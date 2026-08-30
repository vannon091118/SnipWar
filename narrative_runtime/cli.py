"""Command-line interface for the narrative runtime."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .errors import NarrativeRuntimeError
from .context import ContextUnavailable, build_context
from .observe import SourceSnapshot
from .store import Archive

ROOT = Path(__file__).resolve().parent.parent


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -m narrative_runtime")
    parser.add_argument("command", choices=("import", "rebuild", "verify", "status", "derive", "context", "sandbox"))
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--db", type=Path, default=None)
    parser.add_argument("--chain", type=Path, default=None)
    parser.add_argument("--index", type=Path, default=None)
    # Sandbox nimmt eigene Args — parse_known_args lässt sie durch
    parser.add_argument("sandbox_args", nargs="*", help="Extra-Argumente für sandbox")
    return parser


def _sandbox_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -m narrative_runtime sandbox")
    parser.add_argument("--num-commits", type=int, default=50, help="Anzahl simulierter Commits")
    parser.add_argument("--seed", type=int, default=4242, help="RNG-Seed")
    parser.add_argument("--compare", type=Path, default=None, help="Vergleich mit Referenz-Snapshot")
    parser.add_argument("--output-dir", type=Path, default=None, help="Ausgabe-Verzeichnis für Snapshot")
    return parser


def main(argv: list[str] | None = None) -> int:
    # Für sandbox: eigenen Parser nutzen, da die Args ( --num-commits etc.)
    # nicht zum Hauptparser passen.
    if argv is None:
        argv = sys.argv[1:]
    if argv and argv[0] == "sandbox":
        return _run_sandbox(argv[1:])
    args = _parser().parse_args(argv)
    root = args.root.resolve()
    db_path = (args.db or root / "narrative_runtime" / "state" / "narrative.db").resolve()
    archive = Archive(db_path)
    if args.command == "sandbox":
        return _run_sandbox()
    try:
        if args.command == "status":
            print(json.dumps(archive.status(), ensure_ascii=False, indent=2, sort_keys=True))
            return 0
        chain_path = (args.chain or root / "narrative_chain.json").resolve()
        index_path = (args.index or root / "change_index.json").resolve()
        snapshot = SourceSnapshot.from_paths(chain_path, index_path)
        if args.command == "context":
            try:
                print(json.dumps(build_context(archive, snapshot), ensure_ascii=False, indent=2, sort_keys=True))
            except ContextUnavailable as exc:
                print(json.dumps({"available": False, "reason": str(exc)}, ensure_ascii=False, indent=2, sort_keys=True))
            return 0
        if args.command == "import":
            result = archive.import_snapshot(snapshot)
            print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
            return 0
        if args.command == "rebuild":
            result = archive.rebuild(snapshot)
            print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
            return 0
        if args.command == "derive":
            result = archive.derived_status()
            print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
            return 0
        if args.command == "verify":
            ok = archive.verify(snapshot)
            print("PASS" if ok else "FAIL")
            return 0 if ok else 1
    except NarrativeRuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return exc.exit_code
    except (OSError, ValueError, TypeError) as exc:
        print(f"narrative runtime error: {exc}", file=sys.stderr)
        return 1
    return 1


def _run_sandbox(extra: list[str] | None = None) -> int:
    args = _sandbox_parser().parse_args(extra or [])
    from .sandbox.runner import run_sandbox
    import tempfile
    output_dir = args.output_dir or Path(tempfile.gettempdir()) / "doki_sandbox"
    snapshot = run_sandbox(
        num_commits=args.num_commits,
        seed=args.seed,
        output_dir=output_dir,
    )
    if args.compare:
        with open(args.compare, encoding="utf-8") as f:
            ref = json.load(f)
        diffs = _compare_snapshots(ref, snapshot)
        if diffs:
            print(json.dumps({"match": False, "diffs": diffs}, ensure_ascii=False, indent=2))
            return 1
        print(json.dumps({"match": True}, ensure_ascii=False, indent=2))
        return 0
    print(json.dumps(snapshot["summary"], ensure_ascii=False, indent=2))
    print(f"\nSnapshot written to: {output_dir / 'reference' / 'snapshot.json'}")
    return 0


def _compare_snapshots(ref: dict, actual: dict) -> list[str]:
    diffs: list[str] = []
    ref_s = ref.get("summary", {})
    act_s = actual.get("summary", {})
    for key in ("total_arcs", "avg_arc_length", "avg_climax_weight_at_trigger"):
        if ref_s.get(key) != act_s.get(key):
            diffs.append(f"{key}: ref={ref_s.get(key)} actual={act_s.get(key)}")
    return diffs
