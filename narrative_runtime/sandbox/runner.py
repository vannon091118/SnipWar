"""DOKI Sandbox Runner — simuliert DOKI Commit-Flows ohne echte Git-Commits."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from .generators import generate_commits
from .metrics import SimCommit, SimMetrics

# --- DOKI Konstanten (gespiegelt aus arc_engine.gd) ---
BASE_WEIGHT = 0.5
NEW_ENTITY_WEIGHT = 0.4
RECUR_ENTITY_WEIGHT = 0.2
MERGE_BONUS = 1.0
MIN_COMMITS_FOR_CLIMAX = 2
ENTITY_WINDOW = 50
CLIMAX_WEIGHT_DEFAULT = 5.0

NON_NARRATIVE_CLASSES = {"FIX", "DOKU", "TRIVIAL", "TEST-ASSET"}
MAINTENANCE_CLASSES = {"REFACTOR", "BUILD"}

NARRATORS = [
    "Buffy", "Basher", "Thinker", "Vannon", "Squizzle", "Devin", "Argos",
    "Ghost", "Spark", "Glitch", "Null", "Echo", "Flux", "Sage",
]
MOODS = [
    "sachlich", "sarkastisch", "erschöpft", "triumphierend", "selbstironisch",
    "neugierig", "müde-zufrieden", "alarmiert", "trocken", "warm",
]

GENESIS_COMPOSITE = "c0j0n0a0p0"
GENESIS_MOOD = "genesis"

# --- DOKI RNG Reimplementierung (Djb2 + XorShift128, Python-Port) ---
# Spiegeln exakt scripts/doki/core/xorshift128.gd: zwei 32-bit Zustände
# (s0/s1), zehn Warmup-Schritte und Float-Ausgabe [0,1).


def djb2(s: str) -> int:
    h = 5381
    for c in s:
        h = ((h << 5) + h + ord(c)) & 0xFFFFFFFF
    return h & 0x7FFFFFFF


def posmod(a: int, b: int) -> int:
    return ((a % b) + b) % b


class XorShift128:
    """Exact Python port of DOKI_XorShift128 in xorshift128.gd."""

    MASK = 0xFFFFFFFF

    def __init__(self, seed: int) -> None:
        self.s0 = seed & self.MASK
        self.s1 = (seed * 1812433253 + 1) & self.MASK
        for _ in range(10):
            self._step()

    def _step(self) -> float:
        s1 = self.s0
        s0 = self.s1
        self.s0 = s0
        s1 = (s1 ^ (s1 << 23)) & self.MASK
        s1 = (s1 ^ (s1 >> 17)) & self.MASK
        s1 = (s1 ^ s0) & self.MASK
        s1 = (s1 ^ (s0 >> 26)) & self.MASK
        self.s1 = s1
        return float((s0 + self.s1) & self.MASK) / 4294967296.0

    def next(self) -> float:
        return self._step()

    def next_int(self, minimum: int, maximum: int) -> int:
        return minimum + int(self.next() * float(maximum - minimum))


def derive_composite(prev_composite: str, tree_hash: str, diff_hash: str,
                     subject: str, seq: int, prev_mood: str,
                     arc_count: int, structures_count: int = 7) -> dict[str, Any]:
    """Exact port of DOKI_RngEngine.derive() for sandbox inputs."""
    del structures_count  # Structure decoding is not part of derive().
    fields = _parse_composite(prev_composite)
    seed = djb2(prev_composite + tree_hash + diff_hash + subject)
    rng = XorShift128(seed)
    limits = {"j": 99, "n": 14, "a": max(1, arc_count), "p": max(1, seq)}
    next_fields = {"c": fields["c"] + 1}
    for key in ("j", "n", "a", "p"):
        next_fields[key] = rng.next_int(1, limits[key] + 1)
    j = next_fields["j"]
    mood = MOODS[posmod(j, len(MOODS))]
    if mood == prev_mood and len(MOODS) > 1:
        mood = MOODS[posmod(posmod(j, len(MOODS)) + 1, len(MOODS))]
    narrator = NARRATORS[next_fields["n"] - 1]
    composite = "c%dj%dn%da%dp%d" % tuple(next_fields[key] for key in ("c", "j", "n", "a", "p"))
    return {"composite": composite, "narrator": narrator, "mood": mood, **next_fields, "seed": seed}


def _parse_composite(composite: str) -> dict[str, int]:
    import re
    match = re.fullmatch(r"c(\d+)j(\d+)n(\d+)a(\d+)p(\d+)", composite)
    if not match:
        return {"c": 0, "j": 0, "n": 0, "a": 0, "p": 0}
    return {key: int(value) for key, value in zip(("c", "j", "n", "a", "p"), match.groups())}


def merge_seen(seen: list[str], new_entities: list[str]) -> list[str]:
    merged = list(seen)
    seen_set = set(merged)
    for e in new_entities:
        if e and e not in seen_set:
            seen_set.add(e)
            merged.append(e)
    if len(merged) > ENTITY_WINDOW:
        merged = merged[-ENTITY_WINDOW:]
    return merged


def forecast_weight(arc_weight: float, climax_weight: float, seen_entities: list[str],
                    change_entities: list[str], is_merge: bool,
                    impulse_class: str, commit_count: int) -> dict[str, Any]:
    known = set(seen_entities)
    new_e = 0
    recur_e = 0
    for e in change_entities:
        if e in known:
            recur_e += 1
        else:
            new_e += 1
            known.add(e)
    eligible = True
    base = BASE_WEIGHT
    if impulse_class in NON_NARRATIVE_CLASSES:
        base = 0.0
        eligible = False
    elif impulse_class in MAINTENANCE_CLASSES:
        base = BASE_WEIGHT * 0.5
    weight = arc_weight + base + NEW_ENTITY_WEIGHT * new_e + RECUR_ENTITY_WEIGHT * recur_e
    if is_merge:
        weight += MERGE_BONUS
    climax = eligible and weight >= climax_weight and commit_count >= MIN_COMMITS_FOR_CLIMAX
    return {
        "weight": weight,
        "new_entities": new_e,
        "recur_entities": recur_e,
        "climax": climax,
        "eligible": eligible,
    }


def run_sandbox(num_commits: int = 50, seed: int = 4242,
                output_dir: Path | None = None) -> dict[str, Any]:
    """Simuliert num_commits, trackt Metriken, schreibt Reference-Snapshot."""
    commits = generate_commits(num_commits, seed)

    prev_composite = GENESIS_COMPOSITE
    prev_mood = GENESIS_MOOD
    arc_id = "a1"
    arc_weight = 0.0
    arc_climax_weight = CLIMAX_WEIGHT_DEFAULT
    seen_entities: list[str] = []
    arc_count = 1
    arc_commit_count = 0

    all_metrics: list[dict] = []
    narrator_seen: dict[str, int] = {}
    mood_seen: dict[str, int] = {}
    arc_lengths: dict[str, int] = {}
    climax_events: list[dict] = []

    for commit in commits:
        tree_hash = hashlib.sha1(f"tree_{commit.seq}".encode()).hexdigest()[:12]
        diff_hash = str(djb2(commit.impulse + str(commit.seq)))
        derived = derive_composite(
            prev_composite, tree_hash, diff_hash, commit.impulse,
            commit.seq, prev_mood, arc_count,
        )

        forecast = forecast_weight(
            arc_weight, arc_climax_weight, seen_entities,
            commit.entity_ids, commit.is_merge, commit.impulse_class,
            arc_commit_count,
        )

        arc_weight = forecast["weight"]
        is_climax = forecast["climax"]
        seen_entities = merge_seen(seen_entities, commit.entity_ids)
        arc_commit_count += 1

        narrator = derived["narrator"]
        mood = derived["mood"]
        narrator_seen[narrator] = narrator_seen.get(narrator, 0) + 1
        mood_seen[mood] = mood_seen.get(mood, 0) + 1

        if is_climax:
            climax_events.append({"arc": arc_id, "weight": arc_weight, "seq": commit.seq})
            arc_lengths[arc_id] = arc_commit_count
            arc_id = "a%d" % (int(arc_id[1:]) + 1)
            arc_weight = 0.0
            arc_count += 1
            arc_commit_count = 0
            seen_entities = []

        all_metrics.append({
            "seq": commit.seq,
            "composite": derived["composite"],
            "narrator": narrator,
            "mood": mood,
            "j": derived["j"],
            "n": derived["n"],
            "arc_id": arc_id,
            "arc_weight": round(arc_weight, 2),
            "is_arc_climax": is_climax,
            "entities_new": forecast["new_entities"],
            "entities_recur": forecast["recur_entities"],
            "impulse_class": commit.impulse_class,
            "file_count": commit.file_count,
        })

        prev_composite = derived["composite"]
        prev_mood = mood

    # Letzten Arc abschließen
    if arc_id not in arc_lengths:
        arc_lengths[arc_id] = arc_commit_count

    summary = {
        "total_commits": num_commits,
        "total_arcs": len(arc_lengths),
        "avg_arc_length": round(sum(arc_lengths.values()) / max(1, len(arc_lengths)), 1),
        "narrator_distribution": narrator_seen,
        "mood_distribution": mood_seen,
        "climax_events": climax_events,
        "avg_climax_weight_at_trigger": round(
            sum(e["weight"] for e in climax_events) / max(1, len(climax_events)), 2
        ) if climax_events else 0,
        "entity_window_effect": f"max_seen_entities capped at {ENTITY_WINDOW}",
        "params": {
            "num_commits": num_commits,
            "seed": seed,
            "climax_weight": CLIMAX_WEIGHT_DEFAULT,
            "new_entity_weight": NEW_ENTITY_WEIGHT,
            "recur_entity_weight": RECUR_ENTITY_WEIGHT,
            "min_commits_for_climax": MIN_COMMITS_FOR_CLIMAX,
            "entity_window": ENTITY_WINDOW,
        },
    }

    snapshot = {
        "version": 1,
        "summary": summary,
        "per_commit": all_metrics,
    }

    if output_dir:
        snapshot_path = output_dir / "reference" / "snapshot.json"
        snapshot_path.parent.mkdir(parents=True, exist_ok=True)
        with open(snapshot_path, "w", encoding="utf-8") as f:
            json.dump(snapshot, f, ensure_ascii=False, indent=2)

    return snapshot
