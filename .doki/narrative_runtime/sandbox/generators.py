"""Generate fiktive DOKI Commits für Sandbox-Simulation."""

from __future__ import annotations

import random

from .metrics import SimCommit

IMPULSES = [
    ("Implementiere Schiff-Montage für T2-Rümpfe", "CODE"),
    ("Fix: Worker-Transit bricht bei Chunk-Grenze ab", "FIX"),
    ("Refactor: EconomyDomain in Vault/Trade/Worker aufteilen", "REFACTOR"),
    ("Doku: AGENTS.md um Post-Commit-Lifecycle erweitern", "DOKU"),
    ("Build: DOKI Block-Report Generator", "BUILD"),
    ("Fix: Save-Slot-Index verschiebt sich nach Reload", "FIX"),
    ("Feature: Planeten-Sektor-Klassifikation", "CODE"),
    ("Trivial: Tippfehler in README", "TRIVIAL"),
    ("Refactor: NavigationField KNN-Graph extrahieren", "REFACTOR"),
    ("Fix: FleetBattleSimulator berechnet Schilde falsch", "FIX"),
    ("Build: Preflight Scoped-Mode Implementierung", "BUILD"),
    ("Doku: CHANGELOG für Arc a52 dokumentieren", "DOKU"),
    ("Code: ConquestSimulator Tower-Defense Minion-Adapter", "CODE"),
    ("Fix: Audio-Analyser crasht bei leeren OGG", "FIX"),
    ("Refactor: GameState Access-Layer vereinheitlichen", "REFACTOR"),
    ("Feature: Paper-Dossier Planetenansicht", "CODE"),
    ("Trivial: Leerzeichen in project.godot", "TRIVIAL"),
    ("Build: Narrative Runtime Gate Implementierung", "BUILD"),
    ("Fix: ConceptIndex findet neue Klasse nicht", "FIX"),
    ("Code: ChunkCoordinator FoV-Cycling", "CODE"),
]

ENTITY_POOL = [
    "F-001", "F-002", "F-003", "F-004", "F-005",
    "F-006", "F-007", "F-008", "F-009", "F-010",
    "F-011", "F-012", "F-013", "F-014", "F-015",
    "C-001", "C-002", "C-003", "C-004", "C-005",
    "C-006", "C-007", "C-008", "C-009", "C-010",
    "C-011", "C-012", "R-001", "R-002", "R-003",
    "R-004", "R-005", "R-006", "R-007", "R-008",
]


def generate_commits(num_commits: int, seed: int = 4242) -> list[SimCommit]:
    """Generate fiktive Commits mit verteilter Impuls-Klasse."""
    rng = random.Random(seed)
    commits: list[SimCommit] = []
    # Verteilung: 40% CODE, 20% FIX, 15% REFACTOR, 10% DOKU, 10% BUILD, 5% TRIVIAL
    classes = ["CODE"] * 40 + ["FIX"] * 20 + ["REFACTOR"] * 15 + ["DOKU"] * 10 + ["BUILD"] * 10 + ["TRIVIAL"] * 5
    for i in range(1, num_commits + 1):
        impulse, cls = rng.choice(IMPULSES)
        cls = rng.choice(classes)  # Override Klasse für Verteilung
        file_count = rng.randint(1, 15)
        # Entities: 2-6 pro Commit, gemischt neu/rekur
        num_entities = rng.randint(2, 6)
        entities = rng.sample(ENTITY_POOL, min(num_entities, len(ENTITY_POOL)))
        is_merge = rng.random() < 0.05  # 5% Merges
        commits.append(SimCommit(
            seq=i,
            impulse=impulse,
            impulse_class=cls,
            file_count=file_count,
            entity_ids=entities,
            is_merge=is_merge,
        ))
    return commits
