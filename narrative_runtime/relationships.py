"""Deterministic, evidence-aware directed relationship projections."""

from __future__ import annotations

import hashlib
from typing import Any, Iterable

from .observe import canonical_json

RELATIONSHIP_RULE_VERSION = "relationship/v3"
CLASSIFICATION_RULE_VERSION = "classification/v2"
DECAY_RULE_VERSION = "relationship_decay/v1"
NARRATORS = ("Buffy", "Basher", "Thinker", "Vannon", "Squizzle", "Devin", "Argos", "Ghost", "Spark", "Glitch", "Null", "Echo", "Flux", "Sage")
RELATIONSHIP_AXES = ("trust", "respect", "irritation", "affinity", "competence_confidence", "resentment", "curiosity", "defensiveness")
EVIDENCE_LEVELS = ("DIRECT_FACT", "DETERMINISTIC_DERIVATION", "CANDIDATE", "CONFIRMED_BY_LATER_EVIDENCE")
BASELINE = 0.5
DECAY = {"trust": 0.998, "respect": 0.999, "irritation": 0.85, "affinity": 0.999, "competence_confidence": 0.999, "resentment": 0.98, "curiosity": 0.97, "defensiveness": 0.94}


def _id(prefix: str, payload: dict[str, Any]) -> str:
    return prefix + hashlib.sha256(canonical_json(payload).encode("utf-8")).hexdigest()[:16]


def _facts(observation: dict[str, Any]) -> dict[str, Any]:
    facts = dict(observation.get("relationship_facts", {}))
    facts.update(observation.get("subject_term_flags", {}))
    return facts


def _ev(seq: int, kind: str, **extra: Any) -> dict[str, Any]:
    return {"seq": seq, "type": kind, **extra}


def classify_events(observations: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    """Create immutable classification history; later evidence only adds upgrades."""
    ordered = sorted(observations, key=lambda x: int(x["seq"]))
    prior: dict[str, list[int]] = {}
    result: list[dict[str, Any]] = []
    stance_history: dict[str, list[tuple[int, str]]] = {}
    for obs in ordered:
        seq = int(obs["seq"])
        facts = _facts(obs)
        keys = [*map(str, obs.get("files", [])), *map(str, obs.get("entities", []))]
        prior_refs = sorted({p for key in keys for p in prior.get(key, [])})
        stance = str(facts.get("stance") or "")
        prior_stances = [item for key in keys for item in stance_history.get(key, [])]
        classification, level = "NONE", "DIRECT_FACT"
        refs = [_ev(seq, "observation")]
        if facts.get("explicit_admission"):
            classification, level = "EXPLICIT_ADMISSION", "DIRECT_FACT"
        elif facts.get("explicit_revert") and prior_refs:
            classification, level = "REGRESSION_CONFIRMED", "CONFIRMED_BY_LATER_EVIDENCE"
            refs.extend(_ev(p, "prior_touch") for p in prior_refs)
        elif facts.get("explicit_disagreement") and prior_stances:
            classification, level = "DISAGREEMENT", "DIRECT_FACT"
            refs.extend(_ev(previous_seq, "prior_stance") for previous_seq, _ in prior_stances)
        elif facts.get("repair") and prior_refs:
            classification, level = "REPAIR_AFTER_CHANGE", "DETERMINISTIC_DERIVATION"
            refs.extend(_ev(p, "prior_touch") for p in prior_refs)
        elif facts.get("stance"):
            classification, level = "STANCE_DIFFERENCE", "DETERMINISTIC_DERIVATION"
        event = {"event_id": _id("evt_", {"seq": seq, "classification": classification, "refs": refs, "rule": CLASSIFICATION_RULE_VERSION}), "origin_observation_seq": seq, "event_type": "classification", "classification": classification, "evidence_level": level, "evidence_refs": refs, "status": "ACTIVE", "rule_version": CLASSIFICATION_RULE_VERSION}
        result.append(event)
        for key in keys:
            prior.setdefault(key, []).append(seq)
            if stance:
                stance_history.setdefault(key, []).append((seq, stance))
    for event in result:
        if event["classification"] != "REPAIR_AFTER_CHANGE":
            continue
        for later in result:
            if int(later["origin_observation_seq"]) > int(event["origin_observation_seq"]) and later["classification"] == "REGRESSION_CONFIRMED":
                event_refs = {int(ref["seq"]) for ref in event["evidence_refs"]}
                later_refs = {int(ref["seq"]) for ref in later["evidence_refs"]}
                if not event_refs & later_refs:
                    continue
                event["upgraded_classification"] = "REGRESSION_CONFIRMED"
                event["upgrade_evidence_refs"] = later["evidence_refs"]
                event["superseded_by"] = later["event_id"]
                break
    return result


def _event_for_seq(events: list[dict[str, Any]], seq: int) -> dict[str, Any]:
    return next(event for event in events if int(event["origin_observation_seq"]) == seq)


def _effect(event: dict[str, Any], source: str, target: str, axis: str, delta: float, reason: str) -> dict[str, Any]:
    classification = event.get("upgraded_classification", event["classification"])
    refs = event.get("upgrade_evidence_refs", event["evidence_refs"])
    payload = {"event_id": event["event_id"], "source": source, "target": target, "axis": axis, "delta": round(delta, 6), "rule": RELATIONSHIP_RULE_VERSION}
    return {"effect_id": _id("eff_", payload), "event_id": event["event_id"], "observation_seq": int(event["origin_observation_seq"]), "source": source, "target": target, "axis": axis, "delta": round(delta, 6), "classification": classification, "evidence_level": event["evidence_level"], "evidence_refs": refs, "reason": reason, "rule_version": RELATIONSHIP_RULE_VERSION}


def build_relationship_effects(observations: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    ordered = sorted(observations, key=lambda x: int(x["seq"]))
    events = classify_events(ordered)
    result: list[dict[str, Any]] = []
    for obs in ordered:
        source, target = str(obs.get("narrator", "")), str(obs.get("prev_narrator") or "")
        if not source or not target or source == target:
            continue
        flags = _facts(obs)
        event = _event_for_seq(events, int(obs["seq"]))
        classification = event.get("upgraded_classification", event["classification"])
        if classification == "REGRESSION_CONFIRMED": effects = (("trust", -0.04, "confirmed regression"), ("competence_confidence", -0.05, "confirmed regression"), ("irritation", 0.02, "confirmed regression"))
        elif classification == "REPAIR_AFTER_CHANGE": effects = (("trust", -0.005, "repair after prior change"), ("irritation", 0.002, "repair after prior change"))
        elif classification == "DISAGREEMENT": effects = (("defensiveness", 0.03, "explicit disagreement"), ("resentment", 0.01, "explicit disagreement"))
        elif classification == "EXPLICIT_ADMISSION": effects = (("resentment", -0.02, "explicit admission"), ("trust", 0.02, "explicit admission"))
        elif flags.get("repair"): effects = (("respect", 0.03, "repair-related observation"), ("competence_confidence", 0.04, "repair-related observation"), ("trust", 0.01, "repair-related observation"))
        elif flags.get("test"): effects = (("respect", 0.015, "test-related observation"), ("curiosity", 0.01, "test-related observation"))
        elif obs.get("is_merge"): effects = (("affinity", 0.02, "merge observation"), ("trust", 0.005, "merge observation"))
        else: effects = (("curiosity", 0.01, "successive narrator observation"),)
        result.extend(_effect(event, source, target, axis, delta, reason) for axis, delta, reason in effects)
    return result


def build_relationship_events(observations: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    """Compatibility entry point for callers expecting relationship effects."""
    return build_relationship_effects(observations)


def initial_relationship() -> dict[str, float]:
    return {axis: BASELINE for axis in RELATIONSHIP_AXES}


def _pairs() -> list[tuple[str, str]]:
    return [(source, target) for source in NARRATORS for target in NARRATORS if source != target]


def _knowledge(states: dict[tuple[str, str], dict[str, float]], observations: list[dict[str, Any]], beliefs: list[dict[str, Any]] | None = None) -> dict[tuple[str, str], dict[str, Any]]:
    result = {pair: {"known_traits": [], "known_events": [], "known_beliefs": [], "interpretation": [], "expectations": []} for pair in states}
    beliefs = beliefs or []
    for obs in observations:
        source, target = str(obs.get("narrator", "")), str(obs.get("prev_narrator") or "")
        if (source, target) not in result:
            continue
        seq = int(obs["seq"])
        entry = result[(source, target)]
        entry["known_events"].append({"seq": seq, "event_type": "observation", "evidence_refs": [seq]})
        if obs.get("mood"):
            entry["known_traits"].append({"trait": "mood", "value": str(obs["mood"]), "evidence_refs": [seq]})
        entry["expectations"].append({"target": target, "evidence_refs": [seq]})
    for belief in beliefs:
        character = str(belief.get("character", ""))
        for source, target in result:
            if source == character:
                result[(source, target)]["known_beliefs"].append({"belief_id": belief["belief_id"], "claim": belief["claim"], "evidence_refs": [int(belief["evidence_seq"])]})
                result[(source, target)]["interpretation"].append({"claim": belief["claim"], "stance": belief["evidence_type"], "evidence_refs": [int(belief["evidence_seq"])]})
    return result


def build_relationship_state(observations: Iterable[dict[str, Any]], beliefs: list[dict[str, Any]] | None = None) -> list[dict[str, Any]]:
    ordered = sorted(observations, key=lambda x: int(x["seq"]))
    states = {(source, target): initial_relationship() for source, target in _pairs()}
    effects = build_relationship_effects(ordered)
    by_seq: dict[int, list[dict[str, Any]]] = {}
    for effect in effects: by_seq.setdefault(int(effect["observation_seq"]), []).append(effect)
    snapshots = []
    for index, obs in enumerate(ordered):
        for values in states.values():
            for axis, factor in DECAY.items(): values[axis] = BASELINE + (values[axis] - BASELINE) * factor
        for effect in by_seq.get(int(obs["seq"]), []):
            values = states[(effect["source"], effect["target"])]
            values[effect["axis"]] = max(0.0, min(1.0, values[effect["axis"]] + float(effect["delta"])))
        knowledge = _knowledge(states, ordered[:index + 1], beliefs)
        for (source, target), values in sorted(states.items()):
            snapshots.append({"observation_seq": int(obs["seq"]), "source": source, "target": target, "values": {axis: round(values[axis], 6) for axis in RELATIONSHIP_AXES}, "knowledge": knowledge[(source, target)], "rule_version": RELATIONSHIP_RULE_VERSION, "decay_rule_version": DECAY_RULE_VERSION})
    return snapshots


def build_relationship_state_history(observations: Iterable[dict[str, Any]], beliefs: list[dict[str, Any]] | None = None) -> list[dict[str, Any]]:
    return build_relationship_state(observations, beliefs)


CHARACTER_STATE_RULE_VERSION = "character_state/v1"
CHARACTER_AXES = ("frustration", "confidence", "embarrassment", "pride", "curiosity", "defensiveness")


def build_character_state(observations: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    states: dict[str, dict[str, float]] = {}
    snapshots: list[dict[str, Any]] = []
    for observation in sorted(observations, key=lambda x: int(x["seq"])):
        character = str(observation.get("narrator", ""))
        if not character:
            continue
        values = states.setdefault(character, {axis: 0.0 for axis in CHARACTER_AXES})
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


def derive_relationships(observations: list[dict[str, Any]], beliefs: list[dict[str, Any]] | None = None) -> dict[str, list[dict[str, Any]]]:
    return {"relationship_events": build_relationship_effects(observations), "relationship_state": build_relationship_state(observations, beliefs), "relationship_state_history": build_relationship_state(observations, beliefs), "relationship_classifications": classify_events(observations), "character_state": build_character_state(observations)}
