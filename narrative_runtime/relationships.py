"""Deterministic directed relationship and character-state projections."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Any, Iterable

from .observe import canonical_json

RELATIONSHIP_RULE_VERSION = "relationship/v1"
CHARACTER_STATE_RULE_VERSION = "character_state/v1"
RELATIONSHIP_AXES = (
    "trust", "respect", "irritation", "affinity",
    "competence_confidence", "resentment", "curiosity", "defensiveness",
)
CHARACTER_AXES = (
    "frustration", "confidence", "embarrassment", "pride", "curiosity", "defensiveness",
)


@dataclass(frozen=True)
class RelationshipEvent:
    relationship_event_id: str
    observation_seq: int
    source: str
    target: str
    axis: str
    delta: float
    reason: str
    evidence_type: str = "observation"
    rule_version: str = RELATIONSHIP_RULE_VERSION

    def as_dict(self) -> dict[str, Any]:
        return self.__dict__.copy()


def _id(seq: int, source: str, target: str, axis: str, delta: float, reason: str) -> str:
    raw = canonical_json({"seq": seq, "source": source, "target": target, "axis": axis, "delta": delta, "reason": reason, "rule": RELATIONSHIP_RULE_VERSION})
    return "rel_" + hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def _emit(seq: int, source: str, target: str, axis: str, delta: float, reason: str) -> RelationshipEvent:
    if axis not in RELATIONSHIP_AXES:
        raise ValueError(f"unknown relationship axis: {axis}")
    return RelationshipEvent(_id(seq, source, target, axis, delta, reason), seq, source, target, axis, round(delta, 6), reason)


def build_relationship_events(observations: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    """Create sparse, directed effects. No reverse edge is ever inferred."""
    result: list[dict[str, Any]] = []
    for observation in sorted(observations, key=lambda item: int(item["seq"])):
        seq = int(observation["seq"])
        source = str(observation.get("narrator", ""))
        target = str(observation.get("prev_narrator") or "")
        if not source or not target or source == target:
            continue
        flags = observation.get("subject_term_flags", {})
        if flags.get("repair"):
            effects = (("respect", 0.03, "repair-related observation"), ("competence_confidence", 0.04, "repair-related observation"), ("trust", 0.01, "repair-related observation"))
        elif flags.get("test"):
            effects = (("respect", 0.015, "test-related observation"), ("curiosity", 0.01, "test-related observation"))
        elif observation.get("is_merge"):
            effects = (("affinity", 0.02, "merge observation"), ("trust", 0.005, "merge observation"))
        else:
            effects = (("curiosity", 0.01, "successive narrator observation"),)
        result.extend(_emit(seq, source, target, axis, delta, reason).as_dict() for axis, delta, reason in effects)
    return result


def initial_relationship() -> dict[str, float]:
    return {axis: 0.5 for axis in RELATIONSHIP_AXES}


def build_relationship_state(observations: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    states: dict[tuple[str, str], dict[str, float]] = {}
    snapshots: list[dict[str, Any]] = []
    for event in build_relationship_events(observations):
        key = (event["source"], event["target"])
        values = states.setdefault(key, initial_relationship())
        axis = event["axis"]
        values[axis] = max(0.0, min(1.0, values[axis] + float(event["delta"])))
        snapshots.append({
            "observation_seq": event["observation_seq"],
            "source": event["source"],
            "target": event["target"],
            "values": {name: round(values[name], 6) for name in RELATIONSHIP_AXES},
            "rule_version": RELATIONSHIP_RULE_VERSION,
        })
    return snapshots


def initial_character_state() -> dict[str, float]:
    return {axis: 0.0 for axis in CHARACTER_AXES}


def build_character_state(observations: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    states: dict[str, dict[str, float]] = {}
    snapshots: list[dict[str, Any]] = []
    for observation in sorted(observations, key=lambda item: int(item["seq"])):
        character = str(observation.get("narrator", ""))
        if not character:
            continue
        values = states.setdefault(character, initial_character_state())
        flags = observation.get("subject_term_flags", {})
        values["frustration"] *= 0.85
        values["curiosity"] *= 0.97
        values["defensiveness"] *= 0.98
        if flags.get("repair"):
            values["confidence"] = min(1.0, values["confidence"] + 0.04)
            values["pride"] = min(1.0, values["pride"] + 0.02)
        if flags.get("test"):
            values["curiosity"] = min(1.0, values["curiosity"] + 0.03)
        if flags.get("merge"):
            values["defensiveness"] = min(1.0, values["defensiveness"] + 0.02)
        snapshots.append({"observation_seq": int(observation["seq"]), "character": character, "values": {axis: round(values[axis], 6) for axis in CHARACTER_AXES}, "rule_version": CHARACTER_STATE_RULE_VERSION})
    return snapshots


def derive_relationships(observations: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    return {"relationship_events": build_relationship_events(observations), "relationship_state": build_relationship_state(observations), "character_state": build_character_state(observations)}
