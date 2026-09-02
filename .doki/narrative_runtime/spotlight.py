"""Spotlight Balancer: deterministic narrator selection.

The Composite Hash remains the source of determinism.
Spotlight modifies candidate weights, not the algorithm.

Selection path:
    candidate_score × balance_modifier × social_modifier → normalized weights
    → deterministic_random(composite_hash) → Weighted Choice → NARRATOR

The hash is the selection engine (Weighted Choice), not a multiplier.

Rules:
- Spotlight balance may only limitedly influence natural selection
- No character may be deterministically favored or excluded
- Social modifier stays small (max ±15% of weights)
- The hash remains the ultimate arbiter
"""

from __future__ import annotations

import hashlib
import random
from dataclasses import dataclass, field
from typing import Any

from .personality import get_personality, all_personalities


# ─── Configuration ──────────────────────────────────────────────

# Initial bounds for balance modifier (kalibrierbar)
BALANCE_LOWER: float = 0.85
BALANCE_UPPER: float = 1.15

# Social modifier is even smaller
SOCIAL_LOWER: float = 0.92
SOCIAL_UPPER: float = 1.08

# Minimum weight floor (no character gets 0)
MIN_WEIGHT: float = 0.05

# Maximum weight ceiling (no character dominates)
MAX_WEIGHT: float = 0.30


@dataclass
class SpotlightCandidate:
    """One narrator's candidacy for selection."""
    name: str
    base_score: float = 1.0        # from composite hash (natural randomness)
    balance_modifier: float = 1.0  # from opportunity analysis
    social_modifier: float = 1.0   # from public state
    final_weight: float = 1.0      # after all modifiers
    breakdown: dict[str, Any] = field(default_factory=dict)  # explainability

    def as_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "base_score": round(self.base_score, 6),
            "balance_modifier": round(self.balance_modifier, 6),
            "social_modifier": round(self.social_modifier, 6),
            "final_weight": round(self.final_weight, 6),
        }


def _deterministic_random(seed: int) -> float:
    """Deterministic float [0, 1) from a seed.

    Uses the hash directly as a PRNG seed, giving us:
    - Same seed → same result (determinism)
    - Good distribution (hash mixing)
    """
    rng = random.Random(seed)
    return rng.random()


def _hash_seed(composite: str, extra: str = "") -> int:
    """Create a deterministic seed from composite + optional extra.

    The composite is the PRIMARY source. Extra data (like balance state)
    influences weights but does NOT change the hash itself.

    SQLite INTEGER max is 2^63-1. We use 8 hex chars (32 bits) to stay safe.
    """
    raw = f"{composite}|{extra}".encode("utf-8")
    digest = hashlib.sha256(raw).hexdigest()
    return int(digest[:8], 16)


def _compute_balance_modifier(
    narrator: str,
    history: list[dict[str, Any]],
    current_seq: int,
) -> float:
    """Compute balance modifier based on opportunity analysis.

    Factors:
    - recency: how long since this narrator last appeared
    - opportunity_gap: how many chances missed
    - underrepresentation: systematic underuse
    """
    # Count appearances in recent history
    recent_window = 20
    recent = [h for h in history if int(h.get("seq", 0)) > current_seq - recent_window]
    appearances = sum(1 for h in recent if h.get("narrator") == narrator)

    # Recency: more steps since last appearance → higher modifier
    last_appearance = 0
    for h in reversed(history):
        if h.get("narrator") == narrator:
            last_appearance = int(h.get("seq", 0))
            break

    steps_since = current_seq - last_appearance
    recency_factor = min(1.0, steps_since / 10.0)  # caps at 10 steps

    # Opportunity gap: expected vs actual
    expected_ratio = 1.0 / 14.0  # uniform distribution
    actual_ratio = appearances / max(1, len(recent))
    gap = expected_ratio - actual_ratio

    # Underrepresentation: persistent deficit
    total_history = len(history)
    total_appearances = sum(1 for h in history if h.get("narrator") == narrator)
    overall_ratio = total_appearances / max(1, total_history)
    underrep = max(0.0, expected_ratio - overall_ratio)

    # Combine: small effects, bounded
    modifier = 1.0
    modifier += recency_factor * 0.05      # max +5%
    modifier += max(0, gap) * 0.03         # max +3%
    modifier += underrep * 0.02            # max +2%

    # Clamp to bounds
    clamped = max(BALANCE_LOWER, min(BALANCE_UPPER, modifier))
    return {
        "modifier": round(clamped, 6),
        "recency_factor": round(recency_factor, 6),
        "opportunity_gap": round(max(0.0, gap), 6),
        "underrepresentation": round(underrep, 6),
    }


def _compute_social_modifier(
    narrator: str,
    public_state: dict[str, dict[str, float]],
) -> float:
    """Compute social modifier from public state.

    Rule: Social influence stays small. Max ±8% of weights.
    """
    if narrator not in public_state:
        return {"modifier": 1.0, "visibility": 0.5, "hype": 0.5, "reputation": 0.5, "controversy": 0.5}

    state = public_state[narrator]
    visibility = state.get("visibility", 0.5)
    hype = state.get("hype", 0.5)
    reputation = state.get("reputation", 0.5)

    # Small positive modifiers for high visibility/hype/reputation
    modifier = 1.0
    modifier += (visibility - 0.5) * 0.04   # max ±2%
    modifier += (hype - 0.5) * 0.04         # max ±2%
    modifier += (reputation - 0.5) * 0.04   # max ±2%

    # Controversy is a double-edged sword
    controversy = state.get("controversy", 0.5)
    modifier += (controversy - 0.5) * 0.02  # max ±1%

    clamped = max(SOCIAL_LOWER, min(SOCIAL_UPPER, modifier))
    return {
        "modifier": round(clamped, 6),
        "visibility": round(visibility, 6),
        "hype": round(hype, 6),
        "reputation": round(reputation, 6),
        "controversy": round(controversy, 6),
    }


def select_narrator(
    composite: str,
    history: list[dict[str, Any]],
    current_seq: int,
    public_state: dict[str, dict[str, float]] | None = None,
    excluded: list[str] | None = None,
) -> dict[str, Any]:
    """Deterministic narrator selection with spotlight balancing.

    Args:
        composite: The current composite hash (e.g., "c63j36n11a20p19")
        history: List of past observations
        current_seq: Current sequence number
        public_state: Current public state (optional)
        excluded: Narrators to exclude (optional)

    Returns:
        Dict with selected narrator, weights, and audit trail.
    """
    if public_state is None:
        public_state = {}
    if excluded is None:
        excluded = []

    names = [n for n in sorted(all_personalities().keys()) if n not in excluded]

    if not names:
        return {"error": "No valid narrators", "selected": None}

    # 1. Parse composite to get base randomness
    # The n-field from composite gives us the natural selection
    import re
    match = re.fullmatch(r"c(\d+)j(\d+)n(\d+)a(\d+)p(\d+)", composite)
    if not match:
        return {"error": f"Invalid composite: {composite}", "selected": None}

    n_value = int(match.group(3))  # 1-14, maps to narrator index

    # 2. Base scores: uniform, but the hash gives us the tiebreaker
    seed = _hash_seed(composite)

    candidates: list[SpotlightCandidate] = []
    for name in names:
        personality = get_personality(name)

        # Base score from composite (n-field maps to index)
        # This is the deterministic part
        name_index = sorted(all_personalities().keys()).index(name) + 1
        base_match = 1.0 if name_index == n_value else 0.5

        # Add small hash-based variation for tiebreaking
        name_seed = _hash_seed(composite, name)
        hash_bonus = _deterministic_random(name_seed) * 0.1

        base_score = base_match + hash_bonus

        # 3. Balance modifier
        balance = _compute_balance_modifier(name, history, current_seq)

        # 4. Social modifier
        social = _compute_social_modifier(name, public_state)

        # 5. Final weight
        final = base_score * balance["modifier"] * social["modifier"]
        final = max(MIN_WEIGHT, min(MAX_WEIGHT, final))

        candidates.append(SpotlightCandidate(
            name=name,
            base_score=base_score,
            balance_modifier=balance["modifier"],
            social_modifier=social["modifier"],
            final_weight=final,
        ))
        candidates[-1].breakdown = {
            "base_match": round(base_match, 6),
            "hash_bonus": round(hash_bonus, 6),
            "balance": balance,
            "social": social,
        }

    # 6. Weighted random selection using deterministic hash
    total_weight = sum(c.final_weight for c in candidates)
    if total_weight <= 0:
        return {"error": "Total weight is zero", "selected": None}

    # Normalize weights
    for c in candidates:
        c.final_weight /= total_weight

    # Deterministic selection
    random_value = _deterministic_random(seed)

    cumulative = 0.0
    selected = candidates[0]
    selected_threshold = 0.0
    for c in candidates:
        cumulative += c.final_weight
        if random_value <= cumulative:
            selected = c
            selected_threshold = cumulative
            break

    selected_breakdown = {c.name: c.breakdown for c in candidates if c.name == selected.name}
    return {
        "selected": selected.name,
        "composite": composite,
        "seed": seed,
        "random_value": round(random_value, 6),
        "candidates": [c.as_dict() for c in candidates],
        "audit": {
            "n_value": n_value,
            "balance_bounds": [BALANCE_LOWER, BALANCE_UPPER],
            "social_bounds": [SOCIAL_LOWER, SOCIAL_UPPER],
            "min_weight": MIN_WEIGHT,
            "max_weight": MAX_WEIGHT,
            "selection": {
                "random_value": round(random_value, 6),
                "threshold": round(selected_threshold, 6),
                "breakdown": selected_breakdown,
            },
        },
    }


def derive_spotlight(
    observations: list[dict[str, Any]],
    public_state: list[dict[str, Any]] | None = None,
) -> dict[str, list[dict[str, Any]]]:
    """Derive spotlight selection history for all observations.

    Returns one selection result per observation.
    """
    ordered = sorted(observations, key=lambda x: int(x["seq"]))

    # Build public state lookup if provided
    ps_lookup: dict[int, dict[str, dict[str, float]]] = {}
    if public_state:
        for ps in public_state:
            ps_lookup[int(ps["observation_seq"])] = ps.get("public_states", {})

    selections: list[dict[str, Any]] = []

    for obs in ordered:
        seq = int(obs["seq"])
        composite = str(obs.get("composite", ""))

        # History up to this point (exclusive)
        history = [o for o in ordered if int(o["seq"]) < seq]

        # Public state at this point
        ps = ps_lookup.get(seq, {})

        result = select_narrator(
            composite=composite,
            history=history,
            current_seq=seq,
            public_state=ps,
        )

        result["observation_seq"] = seq
        result["actual_narrator"] = str(obs.get("narrator", ""))
        result["match"] = result.get("selected") == result["actual_narrator"]

        selections.append(result)

    return {"spotlight_selections": selections}
