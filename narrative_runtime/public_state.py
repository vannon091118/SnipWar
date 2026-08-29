"""Public/Social state for each narrator.

Public state is EXTERNAL observation (SOCIAL truth class).
It never overrides FACT or INFERRED truth.
X/Social metrics come AFTER the narrative system, not before.

Update logic uses Exponentially Weighted Moving averages:
- visibility: slow (0.95 decay)
- hype: fast (0.7 decay)
- reputation: medium (0.9 decay)
- public_confidence: very slow (0.98 decay)
- controversy: medium (0.9 decay)

Rule: ONE EVENT NEVER CHANGES PUBLIC STATE. AGGREGATION ONLY.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Iterable


# ─── Decay factors per axis ──────────────────────────────────────
# Higher decay = slower change (more weight on history)
EWM_DECAY: dict[str, float] = {
    "visibility": 0.95,       # langfristige Präsenz
    "hype": 0.70,             # kurzfristiges Momentum
    "reputation": 0.90,       # mittelfristige Wahrnehmung
    "public_confidence": 0.98, # sehr langsam
    "controversy": 0.90,      # mittelfristig
}

# All axes start at 0.5 (neutral)
BASELINE: float = 0.5

PUBLIC_STATE_RULE_VERSION = "public_state/v2"

AXES = ("visibility", "hype", "reputation", "public_confidence", "controversy")


@dataclass
class PublicState:
    """Current public state for one narrator."""
    character: str
    visibility: float = BASELINE
    hype: float = BASELINE
    reputation: float = BASELINE
    public_confidence: float = BASELINE
    controversy: float = BASELINE

    def as_dict(self) -> dict[str, Any]:
        return {
            "character": self.character,
            "visibility": round(self.visibility, 6),
            "hype": round(self.hype, 6),
            "reputation": round(self.reputation, 6),
            "public_confidence": round(self.public_confidence, 6),
            "controversy": round(self.controversy, 6),
        }

    def snapshot(self) -> dict[str, float]:
        """Return just the values (for diffs)."""
        return {
            "visibility": round(self.visibility, 6),
            "hype": round(self.hype, 6),
            "reputation": round(self.reputation, 6),
            "public_confidence": round(self.public_confidence, 6),
            "controversy": round(self.controversy, 6),
        }


def _ewm_update(current: float, new_signal: float, decay: float) -> float:
    """Exponentially weighted moving average update.

    result = decay * current + (1 - decay) * new_signal

    With decay=0.95, a single event moves the value by 5%.
    With decay=0.70, a single event moves the value by 30%.
    """
    return decay * current + (1.0 - decay) * new_signal


def _clamp(value: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, value))


def _compute_post_signal(observation: dict[str, Any]) -> dict[str, float]:
    """Compute a post-signal from a single observation.

    This is a PLACEHOLDER for future X/social integration.
    For now, we derive signals purely from repository facts.

    Signal rules (deterministic, conservative):
    - Large commit → visibility bump
    - Merge → reputation bump
    - Fix after bug → controversy bump (someone messed up)
    - Clean commit → reputation bump
    - New feature → hype bump
    """
    files = observation.get("files", [])
    entities = observation.get("entities", [])
    subject = str(observation.get("subject", "")).lower()
    flags = observation.get("subject_term_flags", {})

    # Normalize: how significant is this commit?
    significance = min(1.0, (len(files) * 0.1 + len(entities) * 0.05))

    signals = {
        "visibility": 0.0,
        "hype": 0.0,
        "reputation": 0.0,
        "public_confidence": 0.0,
        "controversy": 0.0,
    }

    # Large commits get visibility
    if significance > 0.3:
        signals["visibility"] = significance * 0.3

    # Merges get reputation
    if observation.get("is_merge"):
        signals["reputation"] = 0.2

    # Repairs/fixes get controversy (something went wrong before)
    if flags.get("repair"):
        signals["controversy"] = 0.15
        signals["reputation"] = 0.1  # but fixing is good

    # Clean features get hype
    if flags.get("doc"):
        signals["reputation"] = 0.1
    elif not flags.get("repair") and not flags.get("test"):
        signals["hype"] = significance * 0.2

    # Tests get reputation (responsible)
    if flags.get("test"):
        signals["reputation"] = 0.1

    return signals


def build_public_state(observations: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    """Build public state history from observations.

    Returns a list of snapshots, one per observation.
    Each snapshot is the FULL state for ALL characters at that point, plus an
    audit record for every character whose state changed: previous values,
    deltas, and the input reference (observation seq).
    """
    ordered = sorted(observations, key=lambda x: int(x["seq"]))

    # Initialize all characters
    characters: dict[str, PublicState] = {}
    previous_values: dict[str, dict[str, float]] = {}

    snapshots: list[dict[str, Any]] = []

    for obs in ordered:
        seq = int(obs["seq"])
        narrator = str(obs.get("narrator", ""))

        # Ensure all known characters exist
        for name in _all_narrator_names():
            if name not in characters:
                characters[name] = PublicState(character=name)
                previous_values[name] = characters[name].snapshot()

        # Compute post-signal for this observation
        signals = _compute_post_signal(obs)

        # Update the narrator's public state (EWM)
        if narrator in characters:
            state = characters[narrator]
            state.visibility = _clamp(_ewm_update(state.visibility, signals["visibility"], EWM_DECAY["visibility"]))
            state.hype = _clamp(_ewm_update(state.hype, signals["hype"], EWM_DECAY["hype"]))
            state.reputation = _clamp(_ewm_update(state.reputation, signals["reputation"], EWM_DECAY["reputation"]))
            state.public_confidence = _clamp(_ewm_update(state.public_confidence, signals["public_confidence"], EWM_DECAY["public_confidence"]))
            state.controversy = _clamp(_ewm_update(state.controversy, signals["controversy"], EWM_DECAY["controversy"]))

        # Decay all other characters slightly (they're not in the spotlight)
        for name, state in characters.items():
            if name != narrator:
                # Very gentle decay toward baseline
                for axis in ["visibility", "hype", "controversy"]:
                    current = getattr(state, axis)
                    setattr(state, axis, _clamp(_ewm_update(current, BASELINE, 0.995)))

        # Audit record: previous/delta/new/rule/evidence for every changed character
        updates: dict[str, Any] = {}
        for name, state in characters.items():
            before = previous_values[name]
            after = state.snapshot()
            deltas = {axis: round(after[axis] - before[axis], 6) for axis in AXES}
            if any(deltas.values()):
                updates[name] = {
                    "previous": before,
                    "deltas": deltas,
                    "new": after,
                    "rule": PUBLIC_STATE_RULE_VERSION,
                    "evidence": [seq],
                }
            previous_values[name] = after

        # Record snapshot
        snapshot = {
            "observation_seq": seq,
            "public_states": {name: state.snapshot() for name, state in sorted(characters.items())},
            "updates": updates,
            "rule_version": PUBLIC_STATE_RULE_VERSION,
        }
        snapshots.append(snapshot)

    return snapshots


def current_public_state(observations: Iterable[dict[str, Any]]) -> dict[str, dict[str, float]]:
    """Get the current (latest) public state for all characters."""
    ordered = sorted(observations, key=lambda x: int(x["seq"]))
    if not ordered:
        return {}

    # Build up to the last observation
    snapshots = build_public_state(ordered)
    if not snapshots:
        return {}

    last = snapshots[-1]
    return last["public_states"]


def derive_public_state(observations: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    """Derive public state for the archive."""
    return {"public_state": build_public_state(observations)}


def _all_narrator_names() -> list[str]:
    """All 14 narrator names."""
    return [
        "Argos", "Basher", "Buffy", "Devin", "Echo", "Flux",
        "Ghost", "Glitch", "Null", "Sage", "Spark", "Squizzle",
        "Thinker", "Vannon",
    ]
