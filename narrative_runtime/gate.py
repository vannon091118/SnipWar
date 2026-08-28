"""Fail-closed repository gate for the narrative runtime contracts."""
from __future__ import annotations

import ast
from pathlib import Path
from tempfile import TemporaryDirectory

from .observe import OBSERVATION_FIELDS, SourceSnapshot, event_id
from .store import Archive
from .relationships import NARRATORS, RELATIONSHIP_AXES, DECAY, build_relationship_effects, build_relationship_state, classify_events

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


def gate_relationship_structure(snapshot: SourceSnapshot) -> None:
    states = build_relationship_state(snapshot.observations[:1])
    pairs = {(item["source"], item["target"]) for item in states}
    expected = {(source, target) for source in NARRATORS for target in NARRATORS if source != target}
    if pairs != expected:
        raise AssertionError(f"G9 relationship matrix mismatch: {len(pairs)} pairs")
    if any(set(item["values"]) != set(RELATIONSHIP_AXES) for item in states):
        raise AssertionError("G8 relationship axis coverage incomplete")


def gate_relationship_effects(snapshot: SourceSnapshot) -> None:
    effects = build_relationship_effects(snapshot.observations)
    for item in effects:
        if item["axis"] not in RELATIONSHIP_AXES:
            raise AssertionError("G10 unknown relationship axis")
        if not item["event_id"] or not item["effect_id"] or not item["evidence_refs"] or not item["rule_version"]:
            raise AssertionError("G10 relationship effect lacks identity/evidence/version")
    if not set(DECAY) == set(RELATIONSHIP_AXES):
        raise AssertionError("G14 decay profile incomplete")


def gate_no_lookahead(snapshot: SourceSnapshot) -> None:
    for observation in snapshot.observations:
        facts = observation.get("relationship_facts", {})
        if any(key in facts for key in ("future_evidence", "later_refs", "confirmed_by")):
            raise AssertionError("G11 observation contains look-ahead evidence")


def gate_classification_contract(snapshot: SourceSnapshot) -> None:
    events = classify_events(snapshot.observations)
    valid_levels = {"DIRECT_FACT", "DETERMINISTIC_DERIVATION", "CANDIDATE", "CONFIRMED_BY_LATER_EVIDENCE"}
    for event in events:
        if event["evidence_level"] not in valid_levels or not event["evidence_refs"]:
            raise AssertionError("G12 invalid classification evidence")
        if event.get("upgraded_classification") and not event.get("upgrade_evidence_refs"):
            raise AssertionError("G13 classification upgrade lacks evidence")


def gate_state_rebuild_contract(snapshot: SourceSnapshot) -> None:
    first = build_relationship_state(snapshot.observations)
    second = build_relationship_state(snapshot.observations)
    if first != second:
        raise AssertionError("G15 relationship state is not deterministic")
    if len(first) != len(snapshot.observations) * len(NARRATORS) * (len(NARRATORS) - 1):
        raise AssertionError("G15 relationship state is incomplete")


def gate_effect_batch_contract(snapshot: SourceSnapshot) -> None:
    full = build_relationship_effects(snapshot.observations)
    split = build_relationship_effects(snapshot.observations[:1] + snapshot.observations[1:])
    if full != split:
        raise AssertionError("G16 effect output depends on batch split")
    valid_seqs = {int(item["seq"]) for item in snapshot.observations}
    if any(int(ref["seq"]) not in valid_seqs for item in full for ref in item["evidence_refs"]):
        raise AssertionError("G17 effect references unknown observation")


def run_gate(root: Path, chain: Path, index: Path) -> dict[str, str]:
    snapshot = SourceSnapshot.from_paths(chain, index)
    checks = {
        "G1": lambda: gate_stdlib(root),
        "G2": lambda: gate_purity(snapshot),
        "G3": lambda: gate_event_ids(snapshot),
        "G4": lambda: gate_gap(snapshot),
        "G5": lambda: gate_no_truth_writes(root),
        "G6/G7": lambda: gate_archive(snapshot),
        "G8/G9": lambda: gate_relationship_structure(snapshot),
        "G10/G14": lambda: gate_relationship_effects(snapshot),
        "G11": lambda: gate_no_lookahead(snapshot),
        "G12": lambda: gate_classification_contract(snapshot),
        "G13": lambda: gate_classification_contract(snapshot),
        "G14": lambda: gate_relationship_effects(snapshot),
        "G15": lambda: gate_state_rebuild_contract(snapshot),
        "G16": lambda: gate_effect_batch_contract(snapshot),
        "G17": lambda: gate_effect_batch_contract(snapshot),
    }
    result = {}
    for name, check in checks.items():
        check()
        result[name] = "PASS"
    return result
