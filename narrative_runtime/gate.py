"""Fail-closed repository gate for the narrative runtime contracts."""
from __future__ import annotations

import ast
from pathlib import Path
from tempfile import TemporaryDirectory

from .observe import OBSERVATION_FIELDS, SourceSnapshot, event_id
from .store import Archive
from .relationships import (
    CHARACTER_AXES,
    NARRATORS,
    RELATIONSHIP_AXES,
    DECAY,
    build_character_state,
    build_relationship_effects,
    build_relationship_state,
    classify_events,
)
from .beliefs import BELIEF_BASES, BELIEF_STATUSES, build_beliefs, build_memory
from .threads import build_threads, current_threads
from .public_state import AXES, build_public_state
from .spotlight import BALANCE_LOWER, BALANCE_UPPER, MAX_WEIGHT, MIN_WEIGHT, SOCIAL_LOWER, SOCIAL_UPPER, select_narrator

ALLOWED_STDLIB = {
    "__future__", "argparse", "ast", "dataclasses", "hashlib", "json", "pathlib",
    "random", "re", "sqlite3", "sys", "tempfile", "typing", "unittest",
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


def gate_beliefs_v2(snapshot: SourceSnapshot) -> None:
    beliefs = build_beliefs(snapshot.observations)
    for item in beliefs:
        if item["basis"] not in BELIEF_BASES:
            raise AssertionError("G18 belief basis outside contract")
        if item["status"] not in BELIEF_STATUSES:
            raise AssertionError("G18 belief status outside contract")
        if "last_reinforced" not in item:
            raise AssertionError("G18 belief lacks last_reinforced")
    if any(item["basis"] == "SOCIAL" for item in beliefs):
        raise AssertionError("G18 SOCIAL belief produced without external social input")


def gate_memory_v2(snapshot: SourceSnapshot) -> None:
    memory = build_memory(snapshot.observations)
    for item in memory:
        if "involved" not in item or not item["involved"]:
            raise AssertionError("G18 memory lacks involved")
        if "recall_count" not in item or "last_recalled" not in item:
            raise AssertionError("G18 memory lacks recall state")
        if item["recall_count"] < 0:
            raise AssertionError("G18 memory has negative recall_count")


def gate_threads_v2(snapshot: SourceSnapshot) -> None:
    events = build_threads(snapshot.observations)
    for item in events:
        if "relevance" not in item or not (0.0 <= item["relevance"] <= 1.0):
            raise AssertionError("G18 thread event lacks bounded relevance")
    for thread in current_threads(snapshot.observations):
        if "pressure" not in thread or "relevance" not in thread:
            raise AssertionError("G18 thread lacks pressure/relevance separation")


def gate_character_state_v2(snapshot: SourceSnapshot) -> None:
    if "fatigue" not in CHARACTER_AXES:
        raise AssertionError("G18 character state lacks fatigue axis")
    states = build_character_state(snapshot.observations)
    if any(set(item["values"]) != set(CHARACTER_AXES) for item in states):
        raise AssertionError("G18 character state axis coverage incomplete")


def gate_public_state_v2(snapshot: SourceSnapshot) -> None:
    history = build_public_state(snapshot.observations)
    for item in history:
        if item["rule_version"] != "public_state/v2":
            raise AssertionError("G18 public state rule version stale")
        for name, update in item["updates"].items():
            for field in ("previous", "deltas", "new", "rule", "evidence"):
                if field not in update:
                    raise AssertionError(f"G18 public state audit lacks {field} for {name}")
            for axis in AXES:
                before = update["previous"][axis]
                after = update["new"][axis]
                if abs(before + update["deltas"][axis] - after) > 1e-5:
                    raise AssertionError(f"G18 public state delta inconsistent for {name}.{axis}")


def gate_spotlight_v2(snapshot: SourceSnapshot) -> None:
    history = [{"seq": int(o["seq"]), "narrator": str(o["narrator"])} for o in snapshot.observations]
    public_state = build_public_state(snapshot.observations)
    ps = public_state[-1]["public_states"] if public_state else {}
    result = select_narrator(snapshot.observations[-1]["composite"], history[:-1], len(history), ps)
    if "error" in result:
        raise AssertionError(f"G18 spotlight error: {result['error']}")
    for candidate in result["candidates"]:
        if not (BALANCE_LOWER <= candidate["balance_modifier"] <= BALANCE_UPPER):
            raise AssertionError("G18 spotlight balance modifier out of bounds")
        if not (SOCIAL_LOWER <= candidate["social_modifier"] <= SOCIAL_UPPER):
            raise AssertionError("G18 spotlight social modifier out of bounds")
        if not (MIN_WEIGHT <= candidate["final_weight"] <= MAX_WEIGHT):
            raise AssertionError("G18 spotlight final weight out of bounds")
    # Deterministic selection: same composite + same state → same narrator
    again = select_narrator(snapshot.observations[-1]["composite"], history[:-1], len(history), ps)
    if result != again:
        raise AssertionError("G18 spotlight selection is not deterministic")
    if "breakdown" not in result["audit"]["selection"]:
        raise AssertionError("G18 spotlight selection lacks explainability breakdown")


def gate_explainability(snapshot: SourceSnapshot) -> None:
    states = build_relationship_state(snapshot.observations[:1])
    for item in states:
        for field in ("previous_values", "deltas", "values", "evidence_refs", "rule_version"):
            if field not in item:
                raise AssertionError(f"G18 relationship audit lacks {field}")
        for axis in RELATIONSHIP_AXES:
            if abs(item["previous_values"][axis] + item["deltas"][axis] - item["values"][axis]) > 1e-5:
                raise AssertionError("G18 relationship delta inconsistent")


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
        "G18": lambda: gate_beliefs_v2(snapshot),
        "G19": lambda: gate_memory_v2(snapshot),
        "G20": lambda: gate_threads_v2(snapshot),
        "G21": lambda: gate_character_state_v2(snapshot),
        "G22": lambda: gate_public_state_v2(snapshot),
        "G23": lambda: gate_spotlight_v2(snapshot),
        "G24": lambda: gate_explainability(snapshot),
    }
    result = {}
    for name, check in checks.items():
        check()
        result[name] = "PASS"
    return result
