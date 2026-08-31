"""
Scope Resolver
==============

Resolves changed files to required verification constraints via semantic impact analysis.
Uses the canonical _PATH_CONTRACTS and _CONTRACT_CONSTRAINTS from constraint_scanner.gd.
"""

from __future__ import annotations

import fnmatch
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class ScopeResolution:
    """Result of scope resolution."""
    constraint_ids: list[str]
    contract_ids: list[str]
    path_mappings: dict[str, list[str]]  # path -> contracts
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return len(self.errors) == 0

    @property
    def is_empty(self) -> bool:
        return len(self.constraint_ids) == 0


# Canonical path glob → contract mapping (from constraint_scanner.gd)
_PATH_CONTRACTS: list[dict[str, Any]] = [
    {"glob": "scripts/state/game_state.gd", "contracts": ["game_state", "save"]},
    {"glob": "scripts/state/domains/**", "contracts": ["game_state", "economy"]},
    {"glob": "scripts/state/save_game_service.gd", "contracts": ["save"]},
    {"glob": "scripts/state/run_save_data.gd", "contracts": ["save"]},
    {"glob": "scripts/state/run_session.gd", "contracts": ["save", "ui_flow"]},
    {"glob": "scripts/state/chunk_save_data.gd", "contracts": ["save"]},
    {"glob": "scripts/state/event_bus.gd", "contracts": ["history"]},
    {"glob": "scripts/state/event_log.gd", "contracts": ["history"]},
    {"glob": "scripts/history/**", "contracts": ["history"]},
    {"glob": "scripts/ui/history/**", "contracts": ["history"]},
    {"glob": "resources/config/**", "contracts": ["economy", "ships", "docs"]},
    {"glob": "scripts/agent_activity.sh", "contracts": ["preflight"]},
    {"glob": "scripts/config/ship_*", "contracts": ["ships"]},
    {"glob": "scripts/config/fleet_snapshot.gd", "contracts": ["fleet"]},
    {"glob": "scripts/objects/ships/**", "contracts": ["ships", "fleet"]},
    {"glob": "scripts/objects/workers/**", "contracts": ["ships"]},
    {"glob": "scripts/config/economy_config.gd", "contracts": ["economy"]},
    {"glob": "scripts/config/resource_pool*", "contracts": ["economy"]},
    {"glob": "scripts/config/*upgrade*", "contracts": ["economy", "ships"]},
    {"glob": "scripts/config/effect_*", "contracts": ["ships", "economy"]},
    {"glob": "scripts/config/module_*", "contracts": ["combat"]},
    {"glob": "scripts/config/assault_*", "contracts": ["combat"]},
    {"glob": "scripts/config/navigation_*", "contracts": ["navigation"]},
    {"glob": "scripts/config/cpu_*", "contracts": ["fleet"]},
    {"glob": "scripts/config/*dispatch*", "contracts": ["fleet"]},
    {"glob": "scripts/config/world_*", "contracts": ["world"]},
    {"glob": "scripts/config/cluster_*", "contracts": ["world", "sectors"]},
    {"glob": "scripts/config/sector_*", "contracts": ["sectors"]},
    {"glob": "scripts/config/planet_*", "contracts": ["world"]},
    {"glob": "scripts/config/paper_style*", "contracts": ["ui_flow"]},
    {"glob": "scripts/bootstrap/**", "contracts": ["world", "game_state"]},
    {"glob": "scripts/objects/planets/**", "contracts": ["world", "economy", "navigation"]},
    {"glob": "scripts/objects/meteors/**", "contracts": ["world"]},
    {"glob": "scripts/battle/**", "contracts": ["combat", "mcp"]},
    {"glob": "scripts/conquest/**", "contracts": ["combat", "fleet"]},
    {"glob": "scripts/simulation/**", "contracts": ["combat"]},
    {"glob": "scenes/main_menu/**", "contracts": ["ui_flow"]},
    {"glob": "scenes/ui/**", "contracts": ["ui_flow"]},
    {"glob": "scenes/objects/**", "contracts": ["ui_flow", "ships"]},
    {"glob": "scenes/battle/**", "contracts": ["combat", "mcp"]},
    {"glob": "scenes/conquest/**", "contracts": ["combat"]},
    {"glob": "scenes/world/**", "contracts": ["world", "ui_flow"]},
    {"glob": "scenes/historical_world/**", "contracts": ["history", "ui_flow"]},
    {"glob": "scripts/ui/**", "contracts": ["ui_flow", "history"]},
    {"glob": "scripts/ui/dossier/**", "contracts": ["ships", "economy"]},
    {"glob": "scripts/ui/tech_menu/**", "contracts": ["ships", "economy"]},
    {"glob": "scripts/concept_index.gd", "contracts": ["preflight"]},
    {"glob": "scripts/global_search.gd", "contracts": ["preflight", "docs"]},
    {"glob": "scripts/testing/mechanic_registry.gd", "contracts": ["preflight"]},
    {"glob": "scripts/preflight/**", "contracts": ["preflight"]},
    {"glob": "scripts/preflight_v2/**", "contracts": ["preflight"]},
    {"glob": "scripts/testing/**", "contracts": ["preflight"]},
    {"glob": "scripts/tools/**", "contracts": ["preflight"]},
    {"glob": ".githooks/**", "contracts": ["preflight"]},
    {"glob": ".gitignore", "contracts": ["docs", "preflight"]},
    {"glob": ".gitmodules", "contracts": ["preflight"]},
    {"glob": "**/*.uid", "contracts": ["preflight"]},
    {"glob": "scripts/doki/**", "contracts": ["doki"]},
    {"glob": "narrative_runtime/**", "contracts": ["doki"]},
    {"glob": ".doki/narrative_chain.json", "contracts": ["doki"]},
    {"glob": ".doki/change_index.json", "contracts": ["doki"]},
    {"glob": "narrative_chain.json", "contracts": ["doki"]},
    {"glob": "change_index.json", "contracts": ["doki"]},
    {"glob": "arcs.json", "contracts": ["doki"]},
    {"glob": "addons/gdscript_mcp/**", "contracts": ["mcp"]},
    {"glob": "docs/**", "contracts": ["docs"]},
    {"glob": "*.md", "contracts": ["docs"]},
    {"glob": "*.json", "contracts": ["docs", "doki"]},
    {"glob": "project.godot", "contracts": ["ui_flow", "game_state"]},
    {"glob": "icon.svg", "contracts": ["ui_flow"]},
    {"glob": "plan/**", "contracts": ["docs"]},
    {"glob": "assets/**", "contracts": ["docs", "ui_flow"]},
    {"glob": "ROADMAP.md", "contracts": ["docs"]},
    {"glob": "AGENTS.md", "contracts": ["docs"]},
]

# Canonical contract → constraint coverage (from constraint_scanner.gd)
_CONTRACT_CONSTRAINTS: dict[str, list[str]] = {
    "game_state": ["game_state_compatibility"],
    "save": ["save_game_roundtrip", "save_game_slots"],
    "history": ["historical_world", "event_log"],
    "ships": ["ship_catalog_and_assembly", "ship_transit_and_arrival", "research_ship", "module_damage_model", "effects_and_traits"],
    "economy": ["economy_production", "local_resources", "resources_and_seed", "upgrade_catalog", "mission_semantics"],
    "navigation": ["navigation_growth"],
    "fleet": ["flight_and_dispatch", "cpu_dispatch", "conquest_grid_combat", "layers_2_and_3"],
    "world": ["world_generator_scaling", "world_details_and_scale", "world_planets_and_dispatch", "chunk_expansion", "cluster_generation", "grid_system"],
    "sectors": ["sector_classification"],
    "combat": ["module_damage_model", "conquest_grid_combat", "layers_2_and_3", "mission_semantics"],
    "ui_flow": ["main_menu_and_flow", "pause_and_context", "ingame_player_and_transitions", "selection_and_context", "camera_and_input", "scene_boot", "paper_style", "layer_independence", "context_handover", "colony_milestone"],
    "preflight": ["agent_activity", "concept_index", "global_search", "mechanic_coverage", "dead_code", "mcp_capture_contract"],
    "doki": ["narrative_runtime", "docs_integrity"],
    "docs": ["docs_integrity", "global_search"],
    "mcp": ["mcp_capture_contract", "concept_index", "global_search"],
}


class ScopeResolver:
    """Resolves file changes to required verification constraints."""

    def __init__(self, repo_root: Path):
        self.repo_root = repo_root

    def resolve(self, changed_files: list[str]) -> ScopeResolution:
        """Resolve changed files to constraint IDs."""
        if not changed_files:
            return ScopeResolution(
                constraint_ids=[],
                contract_ids=[],
                path_mappings={},
                errors=["Empty scope: no changed files provided"],
            )

        # Map paths to contracts
        contract_set = set()
        path_mappings = {}
        unknown_paths = []

        for path in changed_files:
            # Normalize path relative to repo root
            try:
                rel_path = str(Path(path).relative_to(self.repo_root))
            except ValueError:
                rel_path = path

            contracts = self._match_path(rel_path)
            if contracts:
                path_mappings[rel_path] = contracts
                contract_set.update(contracts)
            else:
                unknown_paths.append(rel_path)

        if unknown_paths:
            return ScopeResolution(
                constraint_ids=[],
                contract_ids=[],
                path_mappings=path_mappings,
                errors=[f"Unmapped paths (fail-closed): {', '.join(unknown_paths)}"],
            )

        # Resolve contracts to constraints
        constraint_set = set()
        for contract in contract_set:
            constraints = _CONTRACT_CONSTRAINTS.get(contract, [])
            constraint_set.update(constraints)

        # Always include pure constraints that don't require scene
        # (they're fast and catch cross-cutting issues)
        pure_constraints = [
            "concept_index", "global_search", "docs_integrity", "dead_code",
            "mechanic_coverage", "mcp_capture_contract", "game_state_compatibility",
            "save_game_slots",
        ]
        constraint_set.update(pure_constraints)

        return ScopeResolution(
            constraint_ids=sorted(constraint_set),
            contract_ids=sorted(contract_set),
            path_mappings=path_mappings,
        )

    def _match_path(self, path: str) -> list[str]:
        """Match a path against _PATH_CONTRACTS globs."""
        matched_contracts = set()

        for entry in _PATH_CONTRACTS:
            glob_pattern = entry["glob"]
            contracts = entry["contracts"]

            # Handle ** globstar
            if "**" in glob_pattern:
                # Convert to fnmatch pattern
                pattern = glob_pattern.replace("**", "*")
                if fnmatch.fnmatch(path, pattern):
                    matched_contracts.update(contracts)
                # Also check parent directories for ** patterns
                parts = path.split("/")
                for i in range(1, len(parts)):
                    parent_path = "/".join(parts[:i])
                    if fnmatch.fnmatch(parent_path + "/*", pattern):
                        matched_contracts.update(contracts)
                        break
            else:
                # Simple glob matching
                if fnmatch.fnmatch(path, glob_pattern):
                    matched_contracts.update(contracts)

        return list(matched_contracts)

    def resolve_from_manifest(self, manifest_path: Path) -> ScopeResolution:
        """Resolve scope from a JSON manifest file."""
        import json
        with open(manifest_path) as f:
            manifest = json.load(f)

        constraint_ids = manifest.get("constraints", [])
        if not constraint_ids:
            return ScopeResolution(
                constraint_ids=[],
                contract_ids=[],
                path_mappings={},
                errors=["Empty scope manifest: no constraints listed"],
            )

        # Validate all constraint IDs exist
        # (In practice, we'd check against the constraint registry)
        return ScopeResolution(
            constraint_ids=constraint_ids,
            contract_ids=[],  # Would need reverse lookup
            path_mappings={},
        )

    def get_all_constraint_ids(self) -> list[str]:
        """Get all known constraint IDs."""
        all_constraints = set()
        for constraints in _CONTRACT_CONSTRAINTS.values():
            all_constraints.update(constraints)
        return sorted(all_constraints)

    def get_contracts_for_path(self, path: str) -> list[str]:
        """Get contracts affected by a specific path."""
        try:
            rel_path = str(Path(path).relative_to(self.repo_root))
        except ValueError:
            rel_path = path
        return self._match_path(rel_path)

    def explain(self, constraint_id: str) -> dict[str, Any]:
        """Explain why a constraint is required."""
        # Find which contracts include this constraint
        contracts = []
        for contract, constraints in _CONTRACT_CONSTRAINTS.items():
            if constraint_id in constraints:
                contracts.append(contract)

        # Find which paths map to those contracts
        paths = []
        for entry in _PATH_CONTRACTS:
            if any(c in entry["contracts"] for c in contracts):
                paths.append(entry["glob"])

        return {
            "constraint_id": constraint_id,
            "contracts": contracts,
            "path_globs": paths,
            "description": f"Required by contracts: {', '.join(contracts)}",
        }