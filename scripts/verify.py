#!/usr/bin/env python3
"""SnipWar verification driver — the single orchestration entry point.

Replaces the in-engine orchestrator (scripts/check.gd): process spawning,
scope resolution, test discovery, and exit-code aggregation live here, not in
Godot. Godot is invoked once per phase (compile / preflight / test), never
spawning Godot itself.

Serialization: an OS-level file lock (msvcrt on Windows, fcntl elsewhere) is
held for the whole run. This replaces the deleted GDScript preflight_lock.gd
after per-run isolation proved impossible (Godot 4.7.2 has no --user-data-dir).

Usage:
  python scripts/verify.py [options]

Options:
  --scope=staged|full|<manifest.json>   Scope source (default: staged)
  --takeover=path1,path2                Add foreign files to the scope
  --full                                Full run (ignore scope)
  --cheap-path                          Pure constraints only, no tests
  --skip-compile / --skip-preflight / --skip-tests
  --fail-fast / -x                      Stop after first failure
  --scope-report                        Only print scope analysis
  --help / -h

Exit: 0 = all green, 1 = failure, 2 = scope unresolvable (fail closed).
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Windows console (cp1252) can't print the box-drawing output — force UTF-8.
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
GODOT_DEFAULT = "C:/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe"
LOCK_PATH = Path(tempfile.gettempdir()) / "snipwar_verify.lock"


def godot_bin() -> str:
    env = os.environ.get("GODOT_BIN", "")
    if env and Path(env).is_file():
        return env
    return GODOT_DEFAULT


# ── OS-level lock (msvcrt / fcntl) ──────────────────────────────────────

class VerifyLock:
    """Exclusive, blocking, self-releasing run mutex held for the whole run."""

    def __init__(self) -> None:
        self._fh = None

    def acquire(self, label: str) -> None:
        LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
        self._fh = open(LOCK_PATH, "a+")
        try:
            import msvcrt
            msvcrt.locking(self._fh.fileno(), msvcrt.LK_LOCK, 1)
        except ImportError:
            import fcntl
            fcntl.flock(self._fh, fcntl.LOCK_EX)
        print(f"[verify] lock acquired by {label}")

    def release(self) -> None:
        if self._fh is None:
            return
        try:
            import msvcrt
            self._fh.seek(0)
            msvcrt.locking(self._fh.fileno(), msvcrt.LK_UNLCK, 1)
        except ImportError:
            import fcntl
            fcntl.flock(self._fh, fcntl.LOCK_UN)
        self._fh.close()
        self._fh = None


# ── Scope resolution via the Godot bridge (ChangeImpactResolver = SSOT) ──

def resolve_scope(paths: list[str]) -> dict:
    """Run the scope_dump bridge and parse its JSON result. Never duplicates
    the path→contract mapping in Python."""
    fd, tmp_name = tempfile.mkstemp(suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(paths, f)
        proc = subprocess.run(
            [godot_bin(), "--headless", "--path", str(REPO_ROOT), "--script",
             "res://scripts/preflight_v2/scope_dump.gd", "--",
             f"--paths-file={tmp_name}"],
            capture_output=True, text=True, timeout=180,
        )
        # Delete after the subprocess has fully exited (Win32 file-handle delay).
        Path(tmp_name).unlink(missing_ok=True)
    except BaseException:
        try:
            Path(tmp_name).unlink(missing_ok=True)
        except OSError:
            pass
        raise
    marker = "@@SCOPE_JSON@@"
    for line in (proc.stdout + proc.stderr).splitlines():
        if line.startswith(marker):
            return json.loads(line[len(marker):])
    return {"ok": False, "error": f"scope_dump produced no {marker} output"}


def staged_paths() -> list[str]:
    proc = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
        cwd=REPO_ROOT, capture_output=True, text=True,
    )
    if proc.returncode != 0:
        return []
    return [line for line in proc.stdout.splitlines() if line.strip()]


# ── Godot phase invocations (one process per phase, never nested) ────────

def run_godot(args: list[str], timeout: int = 3600) -> int:
    proc = subprocess.run(
        [godot_bin(), "--headless", "--path", str(REPO_ROOT)] + args,
        cwd=REPO_ROOT, timeout=timeout,
    )
    return proc.returncode


def run_compile_gate(full: bool, gd_files: list[str]) -> int:
    if full:
        return run_godot(["--script", "res://scripts/testing/compile_gate.gd"])
    # Scope mode: per-file compile via the engine's script loader.
    bad = []
    for p in gd_files:
        code = run_godot(["--check-only", "--script", f"res://{p}"], timeout=120)
        if code != 0:
            bad.append(p)
    if bad:
        print(f"[verify] compile FAIL: {', '.join(bad)}")
        return 1
    print(f"[verify] [PASS] compile ({len(gd_files)} scoped .gd files)")
    return 0


def run_preflight(constraints: list[str], fail_fast: bool, cheap: bool) -> int:
    args = ["--script", "res://scripts/preflight.gd"]
    if fail_fast:
        args.append("-x")
    if cheap:
        args.append("--cheap-path")
    if constraints:
        args.append("--filter=" + ",".join(constraints))
    return run_godot(args)


def discover_tests() -> list[str]:
    d = REPO_ROOT / "scripts" / "testing"
    return sorted(p.name for p in d.glob("*_test.gd")
                  if not p.name.startswith("dbg_"))


def run_tests(contracts: list[str], full: bool, fail_fast: bool) -> int:
    contract_to_substring = {
        "ships": "ship", "economy": "economy", "save": "save",
        "combat": "combat", "navigation": "navigation", "fleet": "navigation",
        "world": "world", "sectors": "sector", "doki": "chain",
        "preflight": "constraint", "mcp": "mcp", "docs": "docs",
        "history": "historical", "game_state": "save", "ui_flow": "r008",
    }
    substrings: list[str] = []
    if not full:
        for c in contracts:
            s = contract_to_substring.get(c, "")
            if s and s not in substrings:
                substrings.append(s)
        if "doki" in contracts:
            for extra in ("narrative_runtime", "chain"):
                if extra not in substrings:
                    substrings.append(extra)
        if not substrings:
            print("[verify] [SKIP] no tests for scope contracts")
            return 0
    tests = discover_tests()
    if substrings:
        tests = [t for t in tests if any(s in t for s in substrings)]
    if not tests:
        print("[verify] [SKIP] no tests matched")
        return 0
    failures = 0
    for t in tests:
        code = run_godot(["--script", f"res://scripts/testing/{t}"],
                         timeout=600)
        if code == 0:
            print(f"[verify] [PASS] {t}")
        else:
            failures += 1
            print(f"[verify] [FAIL] {t} (exit={code})")
            if fail_fast:
                break
    print(f"[verify] tests: {len(tests) - failures}/{len(tests)} passed")
    return 1 if failures else 0


# ── Main ─────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(prog="verify.py")
    ap.add_argument("--scope", default="staged")
    ap.add_argument("--takeover", default="")
    ap.add_argument("--full", action="store_true")
    ap.add_argument("--cheap-path", dest="cheap_path", action="store_true")
    ap.add_argument("--skip-compile", dest="skip_compile", action="store_true")
    ap.add_argument("--skip-preflight", dest="skip_preflight", action="store_true")
    ap.add_argument("--skip-tests", dest="skip_tests", action="store_true")
    ap.add_argument("--fail-fast", "-x", dest="fail_fast", action="store_true")
    ap.add_argument("--scope-report", dest="scope_report", action="store_true")
    args = ap.parse_args()

    print("══════════════════════════════════════════════════")
    print(" SnipWar Verification Driver (scripts/verify.py)")
    print("══════════════════════════════════════════════════")

    # ── Phase 1: scope ──
    if args.full:
        scope = {"ok": True, "full": True, "constraints": [], "contracts": [], "paths": []}
    else:
        paths = staged_paths() if args.scope == "staged" else []
        if args.scope != "staged" and Path(args.scope).is_file():
            manifest = json.loads(Path(args.scope).read_text(encoding="utf-8"))
            paths = list(manifest.get("paths", []))
        if args.takeover:
            paths += [t.strip() for t in args.takeover.split(",") if t.strip()]
        if not paths:
            print("[verify] no staged files — full run")
            scope = {"ok": True, "full": True, "constraints": [], "contracts": [], "paths": []}
        else:
            scope = resolve_scope(paths)
            if not scope.get("ok", False):
                print(f"[verify] FATAL: scope unresolvable — {scope.get('error', 'unknown')}")
                return 2
            print(f"[verify] scope: {len(paths)} files → "
                  f"{len(scope.get('contracts', []))} contracts → "
                  f"{len(scope.get('constraints', []))} constraints")
            if args.scope_report:
                print(json.dumps(scope, indent=2))
                return 0
    if args.scope_report:
        print(" Scope: FULL (all constraints)")
        return 0

    # ── Lock: held for the whole run, after scope resolution ──
    lock = VerifyLock()
    lock.acquire("verify.py")

    failures = 0
    try:
        # ── Phase 2: compile ──
        if not args.skip_compile:
            gd = [p for p in scope.get("paths", []) if p.endswith(".gd")]
            if run_compile_gate(bool(scope.get("full")), gd) != 0:
                failures += 1
                if args.fail_fast:
                    return _finish(failures)

        # ── Phase 3: preflight ──
        if not args.skip_preflight:
            constraints = scope.get("constraints", [])
            print(f"[verify] preflight: {len(constraints) if constraints else 'all'} constraints")
            if run_preflight(constraints, args.fail_fast, args.cheap_path) != 0:
                failures += 1
                if args.fail_fast:
                    return _finish(failures)

        # ── Phase 4: tests ──
        if not args.skip_tests and not args.cheap_path:
            if run_tests(scope.get("contracts", []), bool(scope.get("full")),
                         args.fail_fast) != 0:
                failures += 1
    finally:
        lock.release()

    return _finish(failures)


def _finish(failures: int) -> int:
    print("══════════════════════════════════════════════════")
    if failures == 0:
        print(" RESULT: ALL PASSED")
        return 0
    print(f" RESULT: {failures} FAILURES")
    return 1


if __name__ == "__main__":
    sys.exit(main())
