"""Conservative, deterministic beliefs, counter-evidence, and memory."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Any, Iterable

from .observe import canonical_json

BELIEF_RULE_VERSION = "beliefs/v3"
MEMORY_RULE_VERSION = "memory/v2"

# Basis classes: FACT = directly from observation raw facts, INFERRED = from
# deterministic projections (e.g. counter-evidence), SOCIAL = never produced
# yet (reserved for external social input, which is downstream and excluded).
BELIEF_BASES = ("FACT", "INFERRED", "SOCIAL")
# Status: active (new/unchanged), strengthened (confidence rose), disproven
# (counter-evidence contradicted the claim).
BELIEF_STATUSES = ("active", "strengthened", "disproven")


@dataclass(frozen=True)
class BeliefTransition:
    belief_id: str
    character: str
    subject: str
    claim: str
    confidence: float
    formed_at: int
    last_updated: int
    last_reinforced: int
    evidence_seq: int
    evidence_type: str
    basis: str
    status: str
    impact: float
    rule_version: str = BELIEF_RULE_VERSION

    def as_dict(self) -> dict[str, Any]:
        return self.__dict__.copy()


@dataclass(frozen=True)
class MemoryRecord:
    memory_id: str
    character: str
    event_seq: int
    subject: str
    memory_type: str
    emotional_weight: float
    retention_weight: float
    involved: tuple[str, ...]
    recall_count: int
    last_recalled: int | None
    rule_version: str = MEMORY_RULE_VERSION

    def as_dict(self) -> dict[str, Any]:
        return self.__dict__.copy()


def _belief_id(character: str, subject: str, claim: str) -> str:
    return "belief_" + hashlib.sha256(canonical_json({"character": character, "subject": subject, "claim": claim}).encode()).hexdigest()[:16]


def _memory_id(character: str, seq: int) -> str:
    return "mem_" + hashlib.sha256(f"{character}|{seq}|{MEMORY_RULE_VERSION}".encode()).hexdigest()[:16]


def _claim(observation: dict[str, Any]) -> tuple[str, str, str] | None:
    flags = observation.get("subject_term_flags", {})
    if observation.get("is_merge"):
        return "integration", "A merge was recorded in repository history.", "supports"
    if flags.get("repair"):
        return "change_process", "A repair-related change was recorded.", "supports"
    if flags.get("test"):
        return "change_process", "A test-related change was recorded.", "supports"
    counter = observation.get("counter_evidence")
    if isinstance(counter, dict) and str(counter.get("evidence_type", "")) == "contradicts":
        subject = str(counter.get("subject", ""))
        if subject:
            return subject, "The recorded evidence contradicts an earlier structural claim.", "contradicts"
    subject = str(observation.get("subject", "")).lower()
    if subject.startswith(("feat:", "feature:", "add:", "implement:")):
        return "change_process", "A feature-related change was recorded.", "supports"
    return None


def build_beliefs(observations: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    """Build belief transitions with basis/status/last_reinforced.

    - basis: FACT when the claim rests on raw observation facts; INFERRED when
      it rests on a deterministic projection (counter-evidence); SOCIAL is
      reserved and never produced without external social input.
    - status: active → strengthened (confidence rose) / disproven
      (counter-evidence contradicted the claim).
    - last_reinforced: seq of the most recent supporting evidence.
    """
    states: dict[tuple[str, str, str], BeliefTransition] = {}
    transitions: list[dict[str, Any]] = []
    for observation in sorted(observations, key=lambda item: int(item["seq"])):
        seq = int(observation["seq"])
        character = str(observation.get("narrator", ""))
        claim = _claim(observation)
        if not character or claim is None:
            continue
        subject, text, evidence_type = claim
        key = (character, subject, text)
        previous = states.get(key)
        if evidence_type == "contradicts":
            basis = previous.basis if previous else "INFERRED"
            impact = -0.12
        else:
            basis = "FACT"
            impact = 0.08
        confidence = max(0.0, min(1.0, (previous.confidence if previous else 0.5) + impact))
        if evidence_type == "supports":
            status = "strengthened" if previous and confidence > previous.confidence else "active"
            last_reinforced = seq
        elif previous and previous.status != "disproven":
            status = "disproven"
            last_reinforced = previous.last_reinforced
        else:
            status = "disproven"
            last_reinforced = previous.last_reinforced if previous else seq
        current = BeliefTransition(
            _belief_id(character, subject, text), character, subject, text, confidence,
            previous.formed_at if previous else seq, seq, last_reinforced, seq,
            evidence_type, basis, status, impact,
        )
        states[key] = current
        transitions.append(current.as_dict())
    return transitions


def _recall(memory_observation: dict[str, Any], later: dict[str, Any]) -> bool:
    """A later observation recalls a memory when it shares files or entities.

    Deterministic, event-driven. File overlap alone never creates a conflict;
    it only marks the memory as recalled (recall state, not a new event).
    """
    mem_keys = set(map(str, memory_observation.get("files", []))) | set(map(str, memory_observation.get("entities", [])))
    later_keys = set(map(str, later.get("files", []))) | set(map(str, later.get("entities", [])))
    return bool(mem_keys & later_keys)


def build_memory(observations: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    """Build event-centered memory records with involved + recall state.

    - involved: everyone present in the event (narrator + prev_narrator).
    - recall_count/last_recalled: how often later observations referenced this
      event's files/entities. Recall is derived state; the event itself stays
      unchanged.
    """
    ordered = sorted(observations, key=lambda item: int(item["seq"]))
    if not ordered: return []
    head = int(ordered[-1]["seq"])
    result = []
    for index, observation in enumerate(ordered):
        seq = int(observation["seq"])
        character = str(observation.get("narrator", ""))
        if not character: continue
        flags = observation.get("subject_term_flags", {})
        memory_type = "repair" if flags.get("repair") else "commit"
        emotional_weight = round(max(0.0, min(1.0, 0.65 * (0.92 ** max(0, head - seq)))), 6)
        involved = tuple(sorted({character, str(observation.get("prev_narrator") or "")} - {""}))
        recall_count = 0
        last_recalled = None
        for later in ordered[index + 1:]:
            if _recall(observation, later):
                recall_count += 1
                last_recalled = int(later["seq"])
        result.append(MemoryRecord(
            _memory_id(character, seq), character, seq, str(observation.get("subject", "")),
            memory_type, emotional_weight, 1.0, involved, recall_count, last_recalled,
        ).as_dict())
    return result


def derive_belief_memory(observations: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    beliefs = build_beliefs(observations)
    return {"beliefs": beliefs, "memory": build_memory(observations)}
