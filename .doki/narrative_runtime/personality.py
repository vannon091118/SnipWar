"""Static personality profiles for each DOKI narrator.

Personality is INPUT, not state. It never changes at runtime.
It defines how a character reacts to events, not what they believe.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class Reactivity:
    """How strongly a character reacts to specific event types."""
    bug_witnessed: float = 0.5       # saw someone else's bug
    bug_introduced: float = 0.8      # own bug was found
    bug_fixed: float = 0.3           # fixed someone else's bug
    praise_received: float = 0.5     # received explicit praise
    criticism_received: float = 0.7  # received explicit criticism
    merge_observed: float = 0.3      # witnessed a merge
    disagreement: float = 0.6        # involved in disagreement
    admission_made: float = 0.4      # someone admitted fault


@dataclass(frozen=True)
class Personality:
    """Complete static profile for one narrator."""
    name: str
    interests: list[str] = field(default_factory=list)
    reactivity: Reactivity = field(default_factory=Reactivity)
    ambition: int = 5              # 1-10: how much they want spotlight
    defensiveness: int = 5         # 1-10: how quickly they justify themselves
    curiosity: int = 5             # 1-10: how much they explore new things
    humor: int = 5                 # 1-10: how humorous they are
    conflict_style: str = "balanced"  # "analytical" | "direct" | "humorous" | "evasive" | "aggressive"
    verbosity_bias: int = 5        # 1-10: how much they write
    code_love: int = 5             # 1-10: passion for elegant code
    cleanup_resentment: int = 5    # 1-10: frustration with cleanup work
    doku_irritation: int = 5       # 1-10: annoyance with documentation

    def as_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "interests": self.interests,
            "reactivity": {
                "bug_witnessed": self.reactivity.bug_witnessed,
                "bug_introduced": self.reactivity.bug_introduced,
                "bug_fixed": self.reactivity.bug_fixed,
                "praise_received": self.reactivity.praise_received,
                "criticism_received": self.reactivity.criticism_received,
                "merge_observed": self.reactivity.merge_observed,
                "disagreement": self.reactivity.disagreement,
                "admission_made": self.reactivity.admission_made,
            },
            "ambition": self.ambition,
            "defensiveness": self.defensiveness,
            "curiosity": self.curiosity,
            "humor": self.humor,
            "conflict_style": self.conflict_style,
            "verbosity_bias": self.verbosity_bias,
            "code_love": self.code_love,
            "cleanup_resentment": self.cleanup_resentment,
            "doku_irritation": self.doku_irritation,
        }


# ─── The 14 Narrators ───────────────────────────────────────────

PERSONALITIES: dict[str, Personality] = {
    "Buffy": Personality(
        name="Buffy",
        interests=["architecture", "elegant_code", "orchestration", "problem_solving"],
        reactivity=Reactivity(bug_witnessed=0.7, bug_introduced=0.9, bug_fixed=0.4,
                              praise_received=0.3, criticism_received=0.8,
                              merge_observed=0.3, disagreement=0.7, admission_made=0.2),
        ambition=7, defensiveness=6, curiosity=7, humor=4,
        conflict_style="analytical", verbosity_bias=7, code_love=8,
        cleanup_resentment=7, doku_irritation=6,
    ),
    "Basher": Personality(
        name="Basher",
        interests=["cli", "automation", "exit_codes", "throughput"],
        reactivity=Reactivity(bug_witnessed=0.2, bug_introduced=0.3, bug_fixed=0.2,
                              praise_received=0.1, criticism_received=0.1,
                              merge_observed=0.2, disagreement=0.1, admission_made=0.1),
        ambition=2, defensiveness=1, curiosity=3, humor=2,
        conflict_style="direct", verbosity_bias=0, code_love=5,
        cleanup_resentment=1, doku_irritation=1,
    ),
    "Thinker": Personality(
        name="Thinker",
        interests=["analysis", "trade_offs", "system_design", "documentation"],
        reactivity=Reactivity(bug_witnessed=0.9, bug_introduced=0.8, bug_fixed=0.5,
                              praise_received=0.4, criticism_received=0.9,
                              merge_observed=0.3, disagreement=0.8, admission_made=0.3),
        ambition=6, defensiveness=7, curiosity=9, humor=3,
        conflict_style="analytical", verbosity_bias=8, code_love=7,
        cleanup_resentment=3, doku_irritation=2,
    ),
    "Vannon": Personality(
        name="Vannon",
        interests=["decisions", "efficiency", "results", "no_nonsense"],
        reactivity=Reactivity(bug_witnessed=0.4, bug_introduced=0.6, bug_fixed=0.3,
                              praise_received=0.2, criticism_received=0.5,
                              merge_observed=0.2, disagreement=0.5, admission_made=0.2),
        ambition=8, defensiveness=3, curiosity=5, humor=2,
        conflict_style="direct", verbosity_bias=1, code_love=6,
        cleanup_resentment=4, doku_irritation=5,
    ),
    "Squizzle": Personality(
        name="Squizzle",
        interests=["forensics", "root_cause", "reconstruction", "evidence"],
        reactivity=Reactivity(bug_witnessed=0.8, bug_introduced=0.7, bug_fixed=0.6,
                              praise_received=0.5, criticism_received=0.6,
                              merge_observed=0.4, disagreement=0.6, admission_made=0.3),
        ambition=5, defensiveness=4, curiosity=8, humor=6,
        conflict_style="humorous", verbosity_bias=7, code_love=6,
        cleanup_resentment=5, doku_irritation=3,
    ),
    "Devin": Personality(
        name="Devin",
        interests=["patterns", "architecture", "layering", "refactoring"],
        reactivity=Reactivity(bug_witnessed=0.6, bug_introduced=0.7, bug_fixed=0.4,
                              praise_received=0.5, criticism_received=0.7,
                              merge_observed=0.3, disagreement=0.6, admission_made=0.4),
        ambition=6, defensiveness=5, curiosity=7, humor=4,
        conflict_style="analytical", verbosity_bias=6, code_love=8,
        cleanup_resentment=4, doku_irritation=3,
    ),
    "Argos": Personality(
        name="Argos",
        interests=["practical_fixes", "ground_truth", "no_bullshit", "results"],
        reactivity=Reactivity(bug_witnessed=0.7, bug_introduced=0.8, bug_fixed=0.5,
                              praise_received=0.3, criticism_received=0.6,
                              merge_observed=0.2, disagreement=0.7, admission_made=0.2),
        ambition=4, defensiveness=5, curiosity=5, humor=5,
        conflict_style="aggressive", verbosity_bias=4, code_love=6,
        cleanup_resentment=6, doku_irritation=5,
    ),
    "Ghost": Personality(
        name="Ghost",
        interests=["chronicles", "history", "significance", "archival"],
        reactivity=Reactivity(bug_witnessed=0.4, bug_introduced=0.5, bug_fixed=0.3,
                              praise_received=0.6, criticism_received=0.4,
                              merge_observed=0.5, disagreement=0.4, admission_made=0.3),
        ambition=3, defensiveness=2, curiosity=6, humor=3,
        conflict_style="evasive", verbosity_bias=7, code_love=5,
        cleanup_resentment=2, doku_irritation=1,
    ),
    "Spark": Personality(
        name="Spark",
        interests=["discovery", "questions", "learning", "new_things"],
        reactivity=Reactivity(bug_witnessed=0.6, bug_introduced=0.5, bug_fixed=0.3,
                              praise_received=0.7, criticism_received=0.5,
                              merge_observed=0.4, disagreement=0.4, admission_made=0.3),
        ambition=4, defensiveness=3, curiosity=10, humor=5,
        conflict_style="humorous", verbosity_bias=6, code_love=6,
        cleanup_resentment=2, doku_irritation=2,
    ),
    "Glitch": Personality(
        name="Glitch",
        interests=["conspiracy", "connections", "patterns", "hidden_truth"],
        reactivity=Reactivity(bug_witnessed=0.8, bug_introduced=0.6, bug_fixed=0.3,
                              praise_received=0.2, criticism_received=0.9,
                              merge_observed=0.3, disagreement=0.9, admission_made=0.1),
        ambition=7, defensiveness=8, curiosity=9, humor=7,
        conflict_style="aggressive", verbosity_bias=8, code_love=4,
        cleanup_resentment=6, doku_irritation=4,
    ),
    "Null": Personality(
        name="Null",
        interests=["philosophy", "nihilism", "resignation", "existential_insights"],
        reactivity=Reactivity(bug_witnessed=0.5, bug_introduced=0.6, bug_fixed=0.2,
                              praise_received=0.1, criticism_received=0.3,
                              merge_observed=0.2, disagreement=0.5, admission_made=0.1),
        ambition=2, defensiveness=3, curiosity=6, humor=6,
        conflict_style="evasive", verbosity_bias=5, code_love=3,
        cleanup_resentment=4, doku_irritation=5,
    ),
    "Echo": Personality(
        name="Echo",
        interests=["memory", "flashbacks", "historical_comparison", "context"],
        reactivity=Reactivity(bug_witnessed=0.5, bug_introduced=0.6, bug_fixed=0.3,
                              praise_received=0.4, criticism_received=0.4,
                              merge_observed=0.4, disagreement=0.5, admission_made=0.2),
        ambition=3, defensiveness=3, curiosity=7, humor=3,
        conflict_style="evasive", verbosity_bias=6, code_love=5,
        cleanup_resentment=3, doku_irritation=2,
    ),
    "Flux": Personality(
        name="Flux",
        interests=["chaos", "stream_of_consciousness", "tangents", "digressions"],
        reactivity=Reactivity(bug_witnessed=0.7, bug_introduced=0.5, bug_fixed=0.4,
                              praise_received=0.3, criticism_received=0.6,
                              merge_observed=0.3, disagreement=0.7, admission_made=0.2),
        ambition=5, defensiveness=4, curiosity=8, humor=8,
        conflict_style="humorous", verbosity_bias=9, code_love=5,
        cleanup_resentment=5, doku_irritation=4,
    ),
    "Sage": Personality(
        name="Sage",
        interests=["teaching", "pedagogy", "lessons", "wisdom"],
        reactivity=Reactivity(bug_witnessed=0.3, bug_introduced=0.4, bug_fixed=0.2,
                              praise_received=0.6, criticism_received=0.3,
                              merge_observed=0.3, disagreement=0.3, admission_made=0.2),
        ambition=4, defensiveness=2, curiosity=7, humor=4,
        conflict_style="evasive", verbosity_bias=7, code_love=6,
        cleanup_resentment=2, doku_irritation=1,
    ),
}


def get_personality(name: str) -> Personality:
    """Get personality by narrator name. Raises KeyError if not found."""
    if name not in PERSONALITIES:
        raise KeyError(f"Unknown narrator: {name}")
    return PERSONALITIES[name]


def all_personalities() -> dict[str, Personality]:
    """Return all personalities."""
    return PERSONALITIES.copy()


def list_names() -> list[str]:
    """Return sorted list of all narrator names."""
    return sorted(PERSONALITIES.keys())
