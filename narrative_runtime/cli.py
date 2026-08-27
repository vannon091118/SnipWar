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
    parser.add_argument("command", choices=("import", "rebuild", "verify", "status", "derive", "context"))
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--db", type=Path, default=None)
    parser.add_argument("--chain", type=Path, default=None)
    parser.add_argument("--index", type=Path, default=None)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    root = args.root.resolve()
    db_path = (args.db or root / "narrative_runtime" / "state" / "narrative.db").resolve()
    archive = Archive(db_path)
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
