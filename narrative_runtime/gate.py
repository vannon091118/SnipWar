"""Fail-closed repository gate for the narrative runtime contracts."""
from __future__ import annotations

import ast
from pathlib import Path
from tempfile import TemporaryDirectory

from .observe import OBSERVATION_FIELDS, SourceSnapshot, event_id
from .store import Archive

ALLOWED_STDLIB = {
    "__future__", "argparse", "ast", "dataclasses", "hashlib", "json", "pathlib",
    "re", "sqlite3", "sys", "tempfile", "typing", "unittest",
}


def _runtime_files(root: Path) -> list[Path]:
    return sorted(p for p in (root / "narrative_runtime").rglob("*.py") if "__pycache__" not in p.parts)


def gate_stdlib(root: Path) -> None:
    for path in _runtime_files(root):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                names = [alias.name.split(".")[0] for alias in node.names]
            elif isinstance(node, ast.ImportFrom) and node.module:
                if node.level > 0:
                    continue
                names = [node.module.split(".")[0]]
            else:
                continue
            if any(name not in ALLOWED_STDLIB and name != "narrative_runtime" for name in names):
                raise AssertionError(f"G1 stdlib-only violation in {path}: {names}")


def gate_purity(snapshot: SourceSnapshot) -> None:
    for observation in snapshot.observations:
        if set(observation) - OBSERVATION_FIELDS:
            raise AssertionError("G2 observation contains unknown fields")
        if any(key in observation for key in ("emotion", "blame", "intention", "interpretation")):
            raise AssertionError("G2 observation contains interpretation")


def gate_event_ids(snapshot: SourceSnapshot) -> None:
    seen = set()
    for observation in snapshot.observations:
        value = event_id(int(observation["seq"]), observation["commit_hash"])
        if value in seen or value != event_id(int(observation["seq"]), observation["commit_hash"]):
            raise AssertionError("G3 event ID is not reproducible")
        seen.add(value)


def gate_gap(snapshot: SourceSnapshot) -> None:
    seqs = [int(item["seq"]) for item in snapshot.observations]
    if seqs != list(range(1, len(seqs) + 1)):
        raise AssertionError("G4 chain gap accepted")


def gate_no_truth_writes(root: Path) -> None:
    forbidden = ("narrative_chain.json", "change_index.json", ".doki", ".git")
    for path in _runtime_files(root):
        source = path.read_text(encoding="utf-8")
        tree = ast.parse(source, filename=str(path))
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
                if node.func.attr in {"write_text", "write_bytes", "unlink", "rename", "replace"}:
                    source_segment = ast.get_source_segment(source, node) or ""
                    if any(value in source_segment for value in forbidden):
                        raise AssertionError(f"G5 possible source-truth write in {path}")
                if node.func.attr != "execute":
                    continue
                text = ast.get_source_segment(source, node) or ""
                is_write = any(keyword in text.upper() for keyword in ("INSERT", "UPDATE", "DELETE", "REPLACE"))
                if is_write and any(value in text for value in forbidden):
                    raise AssertionError(f"G5 possible source-truth SQL write in {path}")


def gate_archive(snapshot: SourceSnapshot) -> None:
    with TemporaryDirectory() as temp:
        first = Archive(Path(temp) / "first.db")
        first.import_snapshot(snapshot)
        before = first.status()
        first.import_snapshot(snapshot)
        after = first.status()
        if before != after:
            raise AssertionError("G6 duplicate import changed archive")
        second = Archive(Path(temp) / "second.db")
        second.rebuild(snapshot)
        first_status = first.status()
        second_status = second.status()
        first_status["db_path"] = ""
        second_status["db_path"] = ""
        if first_status != second_status:
            raise AssertionError("G7 incremental and rebuild state differ")


def run_gate(root: Path, chain: Path, index: Path) -> dict[str, str]:
    snapshot = SourceSnapshot.from_paths(chain, index)
    checks = {
        "G1": lambda: gate_stdlib(root),
        "G2": lambda: gate_purity(snapshot),
        "G3": lambda: gate_event_ids(snapshot),
        "G4": lambda: gate_gap(snapshot),
        "G5": lambda: gate_no_truth_writes(root),
        "G6/G7": lambda: gate_archive(snapshot),
    }
    result = {}
    for name, check in checks.items():
        check()
        result[name] = "PASS"
    return result
