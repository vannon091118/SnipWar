"""Deterministic thread state derived only from observation facts."""

from __future__ import annotations

import hashlib
import re
from typing import Any, Iterable

from .observe import canonical_json

THREAD_RULE_VERSION = "threads/v3"
DORMANT_AFTER = 5
MERGE_SCORE = 7
OPEN = "OPEN"
DORMANT = "DORMANT"
RESOLVED = "RESOLVED"
REACTIVATED = "REACTIVATED"

_RESOLUTION_RE = re.compile(
    r"\b(resolve|resolved|resolution|close|closed|complete|completed|done|finished|finish|"
    r"abschluss|abgeschlossen|geschlossen|erledigt)\b", re.IGNORECASE,
)


def _thread_id(created_at: int, topic: str) -> str:
    payload = canonical_json({"created_at": created_at, "topic": topic, "rule": THREAD_RULE_VERSION})
    return "thread_" + hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]


def _facts(observation: dict[str, Any]) -> dict[str, Any]:
    return {
        "files": sorted({str(value) for value in observation.get("files", []) if value}),
        "entities": sorted({str(value) for value in observation.get("entities", []) if value}),
        "participants": sorted({str(value) for value in (observation.get("narrator"), observation.get("prev_narrator")) if value}),
        "arc": str(observation.get("arc", "")),
    }


def _topic(facts: dict[str, Any]) -> str:
    if facts["files"]:
        return "file:" + facts["files"][0]
    if facts["entities"]:
        return "entity:" + facts["entities"][0]
    if facts["arc"]:
        return "arc:" + facts["arc"]
    return "observation"


def _resolution(observation: dict[str, Any]) -> bool:
    return _RESOLUTION_RE.search(str(observation.get("subject", ""))) is not None


def _candidate(facts: dict[str, Any], seq: int, thread: dict[str, Any]) -> dict[str, Any] | None:
    shared_files = sorted(set(facts["files"]) & set(thread["files"]))
    shared_entities = sorted(set(facts["entities"]) & set(thread["entities"]))
    evidence: list[dict[str, Any]] = []
    for path in shared_files:
        evidence.append({"type": "shared_file", "key": path, "prior_seq": int(thread["file_last"][path])})
    for entity in shared_entities:
        evidence.append({"type": "shared_entity", "key": entity, "prior_seq": int(thread["entity_last"][entity])})
    score = 4 * len(shared_files) + 3 * len(shared_entities)
    if evidence and score >= MERGE_SCORE:
        return {"thread_id": thread["thread_id"], "score": score, "evidence": evidence, "reactivation_eligible": True}
    if not facts["files"] and not facts["entities"] and not thread["files"] and not thread["entities"] and facts["arc"] and facts["arc"] == thread["arc"] and seq - int(thread["last_activity"]) == 1:
        return {"thread_id": thread["thread_id"], "score": 1, "evidence": [{"type": "arc_continuity", "key": facts["arc"], "prior_seq": int(thread["last_activity"])}], "reactivation_eligible": False}
    return None


def _pressure(unresolved_events: int) -> float:
    return round(min(1.0, unresolved_events / float(unresolved_events + 3)), 6) if unresolved_events > 0 else 0.0


def _new_thread(seq: int, facts: dict[str, Any]) -> dict[str, Any]:
    topic = _topic(facts)
    return {"thread_id": _thread_id(seq, topic), "topic": topic, "participants": set(), "files": set(), "entities": set(), "file_last": {}, "entity_last": {}, "arc": facts["arc"], "created_at": seq, "last_activity": seq, "unresolved_events": 0, "status": OPEN, "linked_threads": set()}


def _derive(observations: Iterable[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    ordered = sorted(observations, key=lambda item: int(item["seq"]))
    working: dict[str, dict[str, Any]] = {}
    thread_events: list[dict[str, Any]] = []
    for observation in ordered:
        seq = int(observation["seq"])
        facts = _facts(observation)
        candidates = [candidate for thread in working.values() if (candidate := _candidate(facts, seq, thread)) is not None]
        candidates.sort(key=lambda item: (-int(item["score"]), int(working[item["thread_id"]]["created_at"]), item["thread_id"]))
        if candidates:
            selected = candidates[0]
            thread = working[selected["thread_id"]]
            linked = [item["thread_id"] for item in candidates[1:]]
            evidence = selected["evidence"]
            evidence_type = "+".join(sorted({str(item["type"]) for item in evidence}))
        else:
            thread = _new_thread(seq, facts)
            working[thread["thread_id"]] = thread
            selected = {"reactivation_eligible": False}
            linked, evidence, evidence_type = [], [], "created"

        gap = seq - int(thread["last_activity"])
        prior_status = DORMANT if gap > DORMANT_AFTER and thread["status"] in (OPEN, REACTIVATED) else str(thread["status"])
        reactivated = False
        if _resolution(observation):
            status, unresolved_events = RESOLVED, 0
        elif prior_status in (DORMANT, RESOLVED) and bool(selected["reactivation_eligible"]):
            status, reactivated, unresolved_events = REACTIVATED, True, int(thread["unresolved_events"]) + 1
        else:
            status, unresolved_events = OPEN, int(thread["unresolved_events"]) + 1

        for linked_id in linked:
            thread["linked_threads"].add(linked_id)
            working[linked_id]["linked_threads"].add(thread["thread_id"])
        thread["participants"].update(facts["participants"])
        thread["files"].update(facts["files"])
        thread["entities"].update(facts["entities"])
        for path in facts["files"]: thread["file_last"][path] = seq
        for entity in facts["entities"]: thread["entity_last"][entity] = seq
        thread["arc"] = thread["arc"] or facts["arc"]
        thread["last_activity"], thread["status"], thread["unresolved_events"] = seq, status, unresolved_events
        refs = sorted({seq} | {int(item["prior_seq"]) for item in evidence})
        thread_events.append({"thread_id": thread["thread_id"], "observation_seq": seq, "status": status, "evidence_type": evidence_type, "evidence_refs": refs, "is_reactivation": reactivated, "rule_version": THREAD_RULE_VERSION})

    head_seq = int(ordered[-1]["seq"]) if ordered else 0
    current = []
    for thread in working.values():
        status = str(thread["status"])
        if status in (OPEN, REACTIVATED) and head_seq - int(thread["last_activity"]) > DORMANT_AFTER: status = DORMANT
        current.append({"thread_id": thread["thread_id"], "topic": thread["topic"], "participants": sorted(thread["participants"]), "pressure": _pressure(int(thread["unresolved_events"]) if status != RESOLVED else 0), "created_at": int(thread["created_at"]), "last_activity": int(thread["last_activity"]), "unresolved_events": int(thread["unresolved_events"]) if status != RESOLVED else 0, "status": status, "linked_threads": sorted(thread["linked_threads"]), "rule_version": THREAD_RULE_VERSION})
    current.sort(key=lambda item: item["thread_id"])
    thread_events.sort(key=lambda item: (int(item["observation_seq"]), item["thread_id"]))
    return current, thread_events


def derive_threads(observations: Iterable[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    current, events = _derive(observations)
    return {"threads": current, "thread_events": events}


def build_threads(observations: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    return derive_threads(observations)["thread_events"]


def current_threads(observations: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    return derive_threads(observations)["threads"]
