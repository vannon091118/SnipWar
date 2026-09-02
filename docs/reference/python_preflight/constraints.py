"""
Constraint Registry
===================

Maps Godot preflight constraints to Python implementations.
Classifies constraints as:
- PURE: Can run without Godot (static analysis, file checks, etc.)
- GODOT: Requires Godot runtime (scene boot, simulation, etc.)
- HYBRID: Has both static and runtime components

Constraints run in order: CHEAP → EXPENSIVE
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class ConstraintType(Enum):
    PURE = "pure"           # Runs entirely in Python, no Godot needed
    GODOT = "godot"         # Requires Godot headless execution
    HYBRID = "hybrid"       # Has both Python and Godot components


class ConstraintPhase(Enum):
    """Execution phase ordering: cheap checks first."""
    SYNTAX = 0          # Syntax, parse, basic structure
    STRUCTURE = 1       # File structure, imports, references
    SEMANTIC = 2        # Semantic analysis, cross-references
    CONTRACT = 3        # Contract validation (ConceptIndex, etc.)
    DOCS = 4            # Documentation integrity
    INTEGRATION = 5     # Integration checks (require Godot)
    RUNTIME = 6         # Full runtime simulation (require Godot)


@dataclass
class ConstraintMetadata:
    """Metadata for a preflight constraint."""
    id: str
    name: str
    description: str
    constraint_type: ConstraintType
    phase: ConstraintPhase
    contracts: list[str] = field(default_factory=list)  # Affected contracts
    requires_scene: bool = False
    destructive: bool = False  # Requires full reboot after
    auto_managed: bool = False  # auto-managed narrative/doc artifacts
    estimated_duration_ms: int = 1000

    def __lt__(self, other: "ConstraintMetadata") -> bool:
        return self.phase.value < other.phase.value


@dataclass
class ConstraintResult:
    """Result of a constraint execution."""
    constraint_id: str
    passed: bool
    duration_ms: float
    checks_run: int = 0
    checks_passed: int = 0
    checks_failed: int = 0
    evidence: dict[str, Any] = field(default_factory=dict)
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "constraint_id": self.constraint_id,
            "passed": self.passed,
            "duration_ms": self.duration_ms,
            "checks_run": self.checks_run,
            "checks_passed": self.checks_passed,
            "checks_failed": self.checks_failed,
            "evidence": self.evidence,
            "errors": self.errors,
            "warnings": self.warnings,
        }


class Constraint(ABC):
    """Base class for all preflight constraints."""

    @property
    @abstractmethod
    def metadata(self) -> ConstraintMetadata:
        """Constraint metadata."""
        pass

    @abstractmethod
    def run(self, context: "PreflightContext") -> ConstraintResult:
        """Execute the constraint."""
        pass

    def can_run_in_python(self) -> bool:
        """Whether this constraint can run without Godot."""
        return self.metadata.constraint_type != ConstraintType.GODOT


@dataclass
class PreflightContext:
    """Execution context passed to constraints."""
    repo_root: Path
    snapshot: "RepositorySnapshot"
    inventory: "RepositoryInventory"
    cache: "FileCache"
    verbose: bool = False
    fail_fast: bool = False

    # Godot-specific (populated when needed)
    godot_available: bool = False
    godot_binary: str | None = None

    # Runtime state (for Godot constraints)
    fixture: Any = None
    game_state: Any = None
    field: Any = None
    network: Any = None

    # Results tracking
    constraint_results: list[ConstraintResult] = field(default_factory=list)
    isolation_warnings: list[dict] = field(default_factory=list)

    def add_result(self, result: ConstraintResult) -> None:
        self.constraint_results.append(result)

    def get_failed_constraints(self) -> list[ConstraintResult]:
        return [r for r in self.constraint_results if not r.passed]


class ConstraintRegistry:
    """Registry of all available constraints."""

    def __init__(self):
        self._constraints: dict[str, Constraint] = {}
        self._metadata: dict[str, ConstraintMetadata] = {}
        self._register_core_constraints()

    def _register_core_constraints(self) -> None:
        """Register all known constraints from Godot preflight."""

        # Import and register pure constraint implementations
        from .pure_constraints import (
            ConceptIndexConstraint,
            GlobalSearchConstraint,
            DocsIntegrityConstraint,
            DeadCodeConstraint,
            MechanicCoverageConstraint,
            MCPCaptureContractConstraint,
            GameStateCompatibilityConstraint,
            SaveGameSlotsConstraint,
        )

        pure_implementations = [
            ConceptIndexConstraint(),
            GlobalSearchConstraint(),
            DocsIntegrityConstraint(),
            DeadCodeConstraint(),
            MechanicCoverageConstraint(),
            MCPCaptureContractConstraint(),
            GameStateCompatibilityConstraint(),
            SaveGameSlotsConstraint(),
        ]

        for constraint in pure_implementations:
            self._register(constraint)

        # GODOT constraints (require Godot runtime)
        godot_constraints = [
            ("scene_boot", "Scene Boot", "Boots world.tscn and validates default scenario", ConstraintPhase.INTEGRATION, ["world", "game_state", "ui_flow"], True, False, 5000),
            ("world_generator_scaling", "World Generator Scaling", "Validates procedural world generation scaling", ConstraintPhase.RUNTIME, ["world"], True, False, 4000),
            ("world_details_and_scale", "World Details and Scale", "Validates world detail levels and planet scale", ConstraintPhase.RUNTIME, ["world"], True, False, 3000),
            ("world_planets_and_dispatch", "World Planets and Dispatch", "Planet network and worker dispatch integration", ConstraintPhase.RUNTIME, ["world", "fleet"], True, False, 4000),
            ("chunk_expansion", "Chunk Expansion", "Validates infinite world chunk expansion", ConstraintPhase.RUNTIME, ["world"], True, False, 4000),
            ("cluster_generation", "Cluster Generation", "Validates planet cluster generation", ConstraintPhase.RUNTIME, ["world", "sectors"], True, False, 3000),
            ("grid_system", "Grid System", "Validates sector grid system", ConstraintPhase.RUNTIME, ["world", "sectors"], True, False, 3000),
            ("sector_classification", "Sector Classification", "Validates sector flavor classification", ConstraintPhase.RUNTIME, ["sectors"], True, False, 2000),
            ("economy_production", "Economy Production", "Validates economy production calculations", ConstraintPhase.RUNTIME, ["economy"], True, False, 3000),
            ("local_resources", "Local Resources", "Validates local resource distribution", ConstraintPhase.RUNTIME, ["economy"], True, False, 2000),
            ("resources_and_seed", "Resources and Seed", "Validates resource assignment with deterministic seed", ConstraintPhase.RUNTIME, ["economy"], True, False, 3000),
            ("upgrade_catalog", "Upgrade Catalog", "Validates planet upgrade catalog", ConstraintPhase.RUNTIME, ["economy", "ships"], True, False, 2000),
            ("mission_semantics", "Mission Semantics", "Validates mission cargo semantics", ConstraintPhase.RUNTIME, ["ships", "combat", "economy"], True, False, 3000),
            ("ship_catalog_and_assembly", "Ship Catalog and Assembly", "Validates ship parts, blueprints, assembly", ConstraintPhase.RUNTIME, ["ships"], True, False, 4000),
            ("ship_transit_and_arrival", "Ship Transit and Arrival", "Validates flight time, transit, arrival", ConstraintPhase.RUNTIME, ["ships", "fleet"], True, False, 3000),
            ("research_ship", "Research Ship", "Validates starter research ship setup", ConstraintPhase.RUNTIME, ["ships"], True, False, 2000),
            ("module_damage_model", "Module Damage Model", "Validates combat module damage", ConstraintPhase.RUNTIME, ["combat", "ships"], True, False, 3000),
            ("effects_and_traits", "Effects and Traits", "Validates ship effects and traits", ConstraintPhase.RUNTIME, ["ships"], True, False, 2000),
            ("flight_and_dispatch", "Flight and Dispatch", "Validates flight time and dispatch logic", ConstraintPhase.RUNTIME, ["fleet"], True, False, 3000),
            ("cpu_dispatch", "CPU Dispatch", "Validates CPU dispatch AI", ConstraintPhase.RUNTIME, ["fleet"], True, False, 3000),
            ("conquest_grid_combat", "Conquest Grid Combat", "Validates conquest grid combat simulation", ConstraintPhase.RUNTIME, ["combat", "fleet"], True, False, 4000),
            ("layers_2_and_3", "Layers 2 and 3", "Validates battle and conquest scene integration", ConstraintPhase.RUNTIME, ["combat", "fleet"], True, False, 4000),
            ("main_menu_and_flow", "Main Menu and Flow", "Validates main menu scene flow", ConstraintPhase.RUNTIME, ["ui_flow"], True, False, 3000),
            ("pause_and_context", "Pause and Context", "Validates pause menu context handling", ConstraintPhase.RUNTIME, ["ui_flow"], True, False, 2000),
            ("ingame_player_and_transitions", "Ingame Player and Transitions", "Validates player controls and scene transitions", ConstraintPhase.RUNTIME, ["ui_flow"], True, False, 3000),
            ("selection_and_context", "Selection and Context", "Validates planet selection and context menus", ConstraintPhase.RUNTIME, ["ui_flow"], True, False, 2000),
            ("camera_and_input", "Camera and Input", "Validates camera controls and input handling", ConstraintPhase.RUNTIME, ["ui_flow"], True, False, 2000),
            ("paper_style", "Paper Style", "Validates papercraft visual style", ConstraintPhase.RUNTIME, ["ui_flow"], True, False, 2000),
            ("layer_independence", "Layer Independence", "Validates layer 1/2/3 independence", ConstraintPhase.RUNTIME, ["ui_flow", "combat"], True, False, 3000),
            ("context_handover", "Context Handover", "Validates world/historical_world context handover", ConstraintPhase.RUNTIME, ["ui_flow", "history"], True, True, 5000),
            ("colony_milestone", "Colony Milestone", "Validates colony milestone progression", ConstraintPhase.RUNTIME, ["ui_flow"], True, False, 2000),
            ("historical_world", "Historical World", "Validates historical world bootstrap and playback", ConstraintPhase.RUNTIME, ["history"], True, False, 4000),
            ("event_log", "Event Log", "Validates event log integrity", ConstraintPhase.RUNTIME, ["history"], True, False, 2000),
            ("save_game_roundtrip", "Save Game Roundtrip", "Save/load roundtrip validation", ConstraintPhase.INTEGRATION, ["save"], True, True, 5000),
            ("navigation_growth", "Navigation Growth", "Validates navigation field growth and waypoint logic", ConstraintPhase.INTEGRATION, ["navigation"], True, False, 3000),
        ]

        for (cid, name, desc, phase, contracts, requires_scene, destructive, duration) in godot_constraints:
            self._register(GodotConstraint(
                id=cid,
                name=name,
                description=desc,
                phase=phase,
                contracts=contracts,
                requires_scene=requires_scene,
                destructive=destructive,
                estimated_duration_ms=duration,
            ))

    def _register(self, constraint: Constraint) -> None:
        self._constraints[constraint.metadata.id] = constraint
        self._metadata[constraint.metadata.id] = constraint.metadata

    def get(self, constraint_id: str) -> Constraint | None:
        return self._constraints.get(constraint_id)

    def get_metadata(self, constraint_id: str) -> ConstraintMetadata | None:
        return self._metadata.get(constraint_id)

    def get_all(self) -> list[Constraint]:
        return list(self._constraints.values())

    def get_all_metadata(self) -> list[ConstraintMetadata]:
        return sorted(self._metadata.values())

    def get_by_type(self, constraint_type: ConstraintType) -> list[Constraint]:
        return [c for c in self._constraints.values() if c.metadata.constraint_type == constraint_type]

    def get_by_phase(self, phase: ConstraintPhase) -> list[Constraint]:
        return [c for c in self._constraints.values() if c.metadata.phase == phase]

    def get_by_contract(self, contract: str) -> list[Constraint]:
        return [c for c in self._constraints.values() if contract in c.metadata.contracts]

    def filter_by_ids(self, ids: list[str]) -> list[Constraint]:
        return [self._constraints[id] for id in ids if id in self._constraints]

    def get_pipeline(self, constraint_ids: list[str] | None = None,
                     constraint_type: ConstraintType | None = None,
                     phase: ConstraintPhase | None = None) -> list[Constraint]:
        """Get ordered pipeline of constraints to run."""
        constraints = self.get_all()

        if constraint_ids:
            constraints = [c for c in constraints if c.metadata.id in constraint_ids]

        if constraint_type:
            constraints = [c for c in constraints if c.metadata.constraint_type == constraint_type]

        if phase:
            constraints = [c for c in constraints if c.metadata.phase == phase]

        # Sort by phase (cheap → expensive)
        constraints.sort(key=lambda c: c.metadata.phase.value)
        return constraints


class PureConstraint(Constraint):
    """Base class for Python-only constraints."""

    def __init__(self, id: str, name: str, description: str, phase: ConstraintPhase,
                 contracts: list[str], estimated_duration_ms: int = 1000):
        self._metadata = ConstraintMetadata(
            id=id,
            name=name,
            description=description,
            constraint_type=ConstraintType.PURE,
            phase=phase,
            contracts=contracts,
            estimated_duration_ms=estimated_duration_ms,
        )

    @property
    def metadata(self) -> ConstraintMetadata:
        return self._metadata

    def run(self, context: PreflightContext) -> ConstraintResult:
        """Override in subclasses."""
        return ConstraintResult(
            constraint_id=self.metadata.id,
            passed=False,
            duration_ms=0,
            errors=["Not implemented"],
        )


class GodotConstraint(Constraint):
    """Constraints that require Godot runtime."""

    def __init__(self, id: str, name: str, description: str, phase: ConstraintPhase,
                 contracts: list[str], requires_scene: bool = True, destructive: bool = False,
                 estimated_duration_ms: int = 3000):
        self._metadata = ConstraintMetadata(
            id=id,
            name=name,
            description=description,
            constraint_type=ConstraintType.GODOT,
            phase=phase,
            contracts=contracts,
            requires_scene=requires_scene,
            destructive=destructive,
            estimated_duration_ms=estimated_duration_ms,
        )

    @property
    def metadata(self) -> ConstraintMetadata:
        return self._metadata

    def run(self, context: PreflightContext) -> ConstraintResult:
        """Override in subclasses - requires Godot context."""
        if not context.godot_available:
            return ConstraintResult(
                constraint_id=self.metadata.id,
                passed=False,
                duration_ms=0,
                errors=[f"Constraint {self.metadata.id} requires Godot runtime"],
            )
        return ConstraintResult(
            constraint_id=self.metadata.id,
            passed=False,
            duration_ms=0,
            errors=["Not implemented - requires Godot execution"],
        )

    def can_run_in_python(self) -> bool:
        return False


# Import Path for context
from pathlib import Path
from .inventory import RepositorySnapshot, RepositoryInventory
from .cache import FileCache