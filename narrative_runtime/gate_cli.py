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
    result = run_gate(root, root / "narrative_chain.json", root / "change_index.json")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
