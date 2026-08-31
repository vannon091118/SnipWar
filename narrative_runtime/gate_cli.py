from __future__ import annotations

import argparse
import json
from pathlib import Path

from .gate import run_gate


def main() -> int:
    parser = argparse.ArgumentParser(prog="python -m narrative_runtime.gate_cli")
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    # DOKI-Migration: narrative Artefakte liegen seit der Pfad-Migration unter
    # .doki/ (nicht mehr am Repo-Root). Fail-open mit Fallback auf Root, damit
    # der Python-Fallback (ohne Godot) und alter Stand nicht doppelt brechen.
    chain = root / ".doki" / "narrative_chain.json"
    index = root / ".doki" / "change_index.json"
    if not chain.exists():
        chain = root / "narrative_chain.json"
    if not index.exists():
        index = root / "change_index.json"
    result = run_gate(root, chain, index)
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
