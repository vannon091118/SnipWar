"""Deterministic perspectives and evidence-bound conflicts."""

from __future__ import annotations

import hashlib
from typing import Any, Iterable

from .observe import canonical_json

PERSPECTIVE_RULE_VERSION = "perspectives/v1"
CONFLICT_RULE_VERSION = "conflicts/v1"


def _id(prefix: str, payload: dict[str, Any]) -> str:
    return prefix + hashlib.sha256(canonical_json(payload).encode()).hexdigest()[:16]


def build_perspectives(observations: Iterable[dict[str, Any]], beliefs: Iterable[dict[str, Any]], threads: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    topics = {item["thread_id"]: item.get("topic", "") for item in threads}
    result = []
    for belief in sorted(beliefs, key=lambda item: (str(item["character"]), int(item["evidence_seq"]), str(item["claim"]))):
        matching = sorted((tid for tid, topic in topics.items() if topic.endswith(str(belief["subject"])) or topic == str(belief["subject"])))
        thread_id = matching[0] if matching else None
        result.append({
            "perspective_id": _id("persp_", {"character": belief["character"], "belief_id": belief["belief_id"], "thread_id": thread_id, "evidence_seq": belief["evidence_seq"]}),
            "character": belief["character"],
            "thread_id": thread_id,
            "claim": belief["claim"],
            "stance": "supports" if float(belief["confidence"]) >= 0.5 else "uncertain",
            "confidence": float(belief["confidence"]),
            "supporting_evidence": [int(belief["evidence_seq"])] if belief["evidence_type"] == "supports" else [],
            "contradicting_evidence": [int(belief["evidence_seq"])] if belief["evidence_type"] == "contradicts" else [],
            "rule_version": PERSPECTIVE_RULE_VERSION,
        })
    return result


def build_conflicts(perspectives: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[tuple[Any, str], list[dict[str, Any]]] = {}
    for perspective in perspectives:
        key = (perspective.get("thread_id"), str(perspective["claim"]))
        grouped.setdefault(key, []).append(perspective)
    conflicts = []
    for (thread_id, claim), items in sorted(grouped.items(), key=lambda pair: (str(pair[0][0]), pair[0][1])):
        stances = {str(item["stance"]) for item in items}
        if len({item["character"] for item in items}) < 2 or len(stances) < 2:
            continue
        evidence = sorted({seq for item in items for seq in item["supporting_evidence"] + item["contradicting_evidence"]})
        conflicts.append({
            "conflict_id": _id("conflict_", {"thread_id": thread_id, "claim": claim, "evidence": evidence}),
            "thread_id": thread_id,
            "actors": sorted({str(item["character"]) for item in items}),
            "trigger": "incompatible perspective stances",
            "contradiction": claim,
            "intensity": round(min(1.0, sum(abs(float(item["confidence"]) - 0.5) for item in items)), 6),
            "evidence_refs": evidence,
            "rule_version": CONFLICT_RULE_VERSION,
        })
    return conflicts
