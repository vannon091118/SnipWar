"""Data classes for sandbox simulation."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class SimCommit:
    """A single simulated commit."""
    seq: int
    impulse: str
    impulse_class: str  # CODE/FIX/DOKU/REFACTOR/TRIVIAL/BUILD
    file_count: int
    entity_ids: list[str]
    is_merge: bool = False


@dataclass
class SimMetrics:
    """Metrics for a single simulated commit."""
    seq: int
    composite: str
    narrator: str
    mood: str
    j: int
    n: int
    arc_id: str
    arc_weight: float
    is_arc_climax: bool
    entities_new: int
    entities_recur: int
    # Aggregated tracking
    narrator_seen: dict[str, int] = field(default_factory=dict)
    mood_seen: dict[str, int] = field(default_factory=dict)
    arc_lengths: dict[str, int] = field(default_factory=dict)
    climax_events: list[dict[str, Any]] = field(default_factory=list)
