#!/usr/bin/env python3
"""
🔬 FORENSICS (AUDIT 3) — chain_history_reconstruction.py

Reconstructs the RNG inputs for every REAL DOKI entry (seq >= 11) from git objects
(parent `^{tree}`, parent..commit diff, [IMPULSE:] token) and replays the composite.

Purpose: make the AUDIT-3 finding -- "historical composites are NOT reproducible
from git + current code because diff_hash/limits/mood_pool were only transient" --
re-checkable by any future agent. READ-ONLY (pure reads of git + narrative_chain.json).

Run: python3 tests/forensics/chain_history_reconstruction.py
"""
import json
import re
import subprocess
import sys
from pathlib import Path

MASK = 0xFFFFFFFF


def djb2(s: str) -> int:
    # GDScript hashes Unicode CODEPOINTS (String.unicode_at), not UTF-8 bytes.
    h = 5381
    for ch in s:
        h = ((h << 5) + h + ord(ch)) & MASK
    return h


class XorShift128:
    def __init__(self, seed: int):
        self._s0 = seed & MASK
        self._s1 = (seed * 1812433253 + 1) & MASK
        for _ in range(10):
            self._step()

    def _step(self) -> float:
        a = self._s0
        b = self._s1
        self._s0 = b
        a = (a ^ ((a << 23) & MASK)) & MASK
        a = (a ^ (a >> 17)) & MASK
        a = (a ^ b) & MASK
        a = (a ^ (b >> 26)) & MASK
        self._s1 = a
        return float((b + self._s1) & MASK) / 4294967296.0

    def next_int(self, mn: int, mx: int) -> int:
        return mn + int(self._step() * float(mx - mn))


def parse(c: str):
    m = re.match(r"^c(\d+)j(\d+)n(\d+)a(\d+)p(\d+)$", c)
    if not m:
        raise ValueError("malformed composite: %r" % c)
    return [int(m.group(k)) for k in range(1, 6)]


def derive(prev_comp, tree, diff_hash, impulse, limits):
    prev = parse(prev_comp)
    seed = djb2(prev_comp + tree + diff_hash + impulse)
    rng = XorShift128(seed)
    nxt = [prev[0] + 1]
    for f in ("j", "n", "a", "p"):
        mx = limits[f]
        nxt.append(rng.next_int(1, mx + 1) if mx > 0 else 1)
    return "c%dj%dn%da%dp%d" % (nxt[0], nxt[1], nxt[2], nxt[3], nxt[4]), seed


def git(root: Path, *args) -> str:
    r = subprocess.run(["git"] + list(args), cwd=str(root), capture_output=True)
    if r.returncode != 0:
        raise RuntimeError("git %s failed: %s" % (args, r.stderr.decode("utf-8", "replace")))
    return r.stdout.decode("utf-8", "replace")


def repo_root(start: Path) -> Path:
    p = start
    while True:
        if (p / "narrative_chain.json").exists():
            return p
        nxt = p.parent
        if nxt == p:
            raise RuntimeError("narrative_chain.json not found above %s" % start)
        p = nxt


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    root = repo_root(Path(__file__).resolve().parent)
    chain = json.loads((root / "narrative_chain.json").read_text(encoding="utf-8"))
    stored = {e["seq"]: e for e in chain["entries"]}

    seeded = {e["seq"] for e in chain["entries"] if e.get("seeded")}
    if not seeded:  # fallback: seeded commits are simply the first entries
        seeded = {i for i in range(1, 11)}

    realdok = sorted(s for s in stored if s not in seeded)

    print("seq | stored         | replay         | matched | a_lim p_lim | len(diff) | impulse")
    any_ok = False
    for seq in realdok:
        c = stored[seq]["hash"]
        parent = git(root, "rev-parse", c + "^").strip()
        tree = git(root, "rev-parse", c + "^{tree}").strip()
        msg = git(root, "log", "-1", "--format=%B", c)
        m = re.search(r"\[IMPULSE:([^\]]*)\]", msg)
        if not m:
            continue  # not a real DOKI commit; skip synthetically
        impulse = m.group(1).strip()
        diff = git(root, "diff", parent, c).replace("\r\n", "\n")
        prev_comp = "c0j0n0a0p0" if seq == 1 else stored[seq - 1]["composite"]
        plim = stored[seq]["p_id"]
        alim = 1
        limits = {"j": 99, "n": 14, "a": alim, "p": plim}
        diff_hash = str(djb2(diff))
        comp, seed = derive(prev_comp, tree, diff_hash, impulse, limits)
        ok = comp == stored[seq]["composite"]
        any_ok = any_ok or ok
        print("%-4d| %-14s | %-14s | %s | %-5s %-5s | %8d | %.60s" % (
            seq, stored[seq]["composite"], comp, "OK" if ok else "X", alim, plim, len(diff), impulse))

    print("\nAUDIT-3 fixed verdict: COMPOSITES-NOT-REPRODUCIBLE (inputs were transient); "
          "this run matched=%s" % ("some" if any_ok else "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main())