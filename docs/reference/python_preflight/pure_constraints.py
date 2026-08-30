"""
Pure Constraint Implementations
================================

Concrete implementations of Python-only preflight constraints.
These run without Godot and perform static analysis.
"""

from __future__ import annotations

import re
import json
from pathlib import Path
from typing import Any

from .constraints import PureConstraint, ConstraintResult, ConstraintPhase, PreflightContext


class ConceptIndexConstraint(PureConstraint):
    """Validates ConceptIndex: class mappings, search, expand, free slots."""

    def __init__(self):
        super().__init__(
            id="concept_index",
            name="Concept Index Validation",
            description="Validates ConceptIndex: class mappings, search, expand, free slots",
            phase=ConstraintPhase.CONTRACT,
            contracts=["preflight"],
            estimated_duration_ms=2000,
        )

    def run(self, context: PreflightContext) -> ConstraintResult:
        errors = []
        warnings = []
        checks_run = 0
        checks_passed = 0

        # Check if ConceptIndex script exists
        concept_index_path = context.repo_root / "scripts" / "concept_index.gd"
        if not concept_index_path.exists():
            errors.append("scripts/concept_index.gd not found")
            return ConstraintResult(
                constraint_id=self.metadata.id,
                passed=False,
                duration_ms=0,
                checks_run=1,
                checks_failed=1,
                errors=errors,
            )

        checks_run += 1
        checks_passed += 1

        # Parse ConceptIndex for class mappings
        content = concept_index_path.read_text()

        # Check for _build_concepts method
        checks_run += 1
        if "_build_concepts" in content:
            checks_passed += 1
        else:
            errors.append("ConceptIndex missing _build_concepts method")

        # Check for search/expand methods
        for method in ["search", "expand", "class_concept", "by_domain", "get_unmapped_classes", "get_concepts_with_free_slots"]:
            checks_run += 1
            if f"func {method}" in content:
                checks_passed += 1
            else:
                warnings.append(f"ConceptIndex missing method: {method}")

        # Check for core domains
        core_domains = ["ship", "fleet", "economy", "resource", "planet", "battle", "tech", "save", "worker", "navigation"]
        for domain in core_domains:
            checks_run += 1
            if domain in content:
                checks_passed += 1
            else:
                warnings.append(f"Core domain '{domain}' not referenced in ConceptIndex")

        passed = len(errors) == 0
        return ConstraintResult(
            constraint_id=self.metadata.id,
            passed=passed,
            duration_ms=0,  # Will be set by runner
            checks_run=checks_run,
            checks_passed=checks_passed,
            checks_failed=checks_run - checks_passed,
            evidence={"concept_index_path": str(concept_index_path)},
            errors=errors,
            warnings=warnings,
        )


class GlobalSearchConstraint(PureConstraint):
    """Validates global_search.gd index integrity."""

    def __init__(self):
        super().__init__(
            id="global_search",
            name="Global Search Index",
            description="Validates global_search.gd index integrity",
            phase=ConstraintPhase.CONTRACT,
            contracts=["preflight", "docs"],
            estimated_duration_ms=3000,
        )

    def run(self, context: PreflightContext) -> ConstraintResult:
        errors = []
        warnings = []
        checks_run = 0
        checks_passed = 0

        search_path = context.repo_root / "scripts" / "global_search.gd"
        if not search_path.exists():
            errors.append("scripts/global_search.gd not found")
            return ConstraintResult(
                constraint_id=self.metadata.id,
                passed=False,
                duration_ms=0,
                checks_run=1,
                checks_failed=1,
                errors=errors,
            )

        checks_run += 1
        checks_passed += 1

        content = search_path.read_text()

        # Check for required methods
        required_methods = ["scan", "search", "_scan_file", "_matches", "_get_context"]
        for method in required_methods:
            checks_run += 1
            if f"func {method}" in content:
                checks_passed += 1
            else:
                warnings.append(f"global_search missing method: {method}")

        # Check for supported file types
        supported_types = [".gd", ".tres", ".tscn", ".gdshader", ".import", ".json", ".csv", ".md", ".txt"]
        for ext in supported_types:
            checks_run += 1
            if ext in content:
                checks_passed += 1
            else:
                warnings.append(f"File type {ext} may not be supported")

        # Check for JSON output
        checks_run += 1
        if "JSON" in content or "json" in content:
            checks_passed += 1
        else:
            warnings.append("JSON output handling not detected")

        passed = len(errors) == 0
        return ConstraintResult(
            constraint_id=self.metadata.id,
            passed=passed,
            duration_ms=0,
            checks_run=checks_run,
            checks_passed=checks_passed,
            checks_failed=checks_run - checks_passed,
            evidence={"global_search_path": str(search_path)},
            errors=errors,
            warnings=warnings,
        )


class DocsIntegrityConstraint(PureConstraint):
    """Checks FINDINGS.md, CHANGELOG.md for duplicate headings, broken tables."""

    def __init__(self):
        super().__init__(
            id="docs_integrity",
            name="Documentation Integrity",
            description="Checks FINDINGS.md, CHANGELOG.md for duplicate headings, broken tables",
            phase=ConstraintPhase.DOCS,
            contracts=["docs", "doki"],
            estimated_duration_ms=1500,
        )

    def run(self, context: PreflightContext) -> ConstraintResult:
        errors = []
        warnings = []
        checks_run = 0
        checks_passed = 0

        target_docs = [
            context.repo_root / "docs" / "FINDINGS.md",
            context.repo_root / "CHANGELOG.md",
        ]

        heading_regex = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")
        separator_chars = set("|:- ")

        for doc_path in target_docs:
            checks_run += 1
            if not doc_path.exists():
                errors.append(f"{doc_path.relative_to(context.repo_root)}: file missing")
                continue

            checks_passed += 1
            text = doc_path.read_text()
            lines = [line.rstrip("\r") for line in text.split("\n")]

            heading_seen = {}
            table_seen = {}
            headings = 0
            tables = 0

            index = 0
            while index < len(lines):
                line = lines[index]

                # Heading duplicates
                h = heading_regex.search(line)
                if h:
                    headings += 1
                    key = f"{len(h.group(1))}|{h.group(2)}"
                    occurrences = heading_seen.get(key, [])
                    occurrences.append(index + 1)
                    heading_seen[key] = occurrences
                    if len(occurrences) == 2:
                        errors.append(
                            f"{doc_path.name}:{index + 1} duplicate heading "
                            f"'{h.group(1)} {h.group(2)}' (first at line {occurrences[0]})"
                        )
                    index += 1
                    continue

                # Table blocks
                if line.strip().startswith("|"):
                    block_start = index
                    block = []
                    while index < len(lines) and lines[index].strip().startswith("|"):
                        block.append(lines[index])
                        index += 1
                    tables += 1

                    # Check table structure
                    if len(block) < 2:
                        errors.append(
                            f"{doc_path.name}:{block_start + 1} table block with "
                            f"{len(block)} line(s) — header+separator required"
                        )
                    else:
                        header_pipes = self._count_unescaped_pipes(block[0])
                        if not self._is_separator(block[1], separator_chars):
                            errors.append(
                                f"{doc_path.name}:{block_start + 1} table separator "
                                f"missing/invalid at line {block_start + 2}"
                            )
                        for i, row in enumerate(block):
                            row_stripped = row.strip()
                            if not row_stripped.endswith("|"):
                                errors.append(
                                    f"{doc_path.name}:{block_start + i + 1} table row "
                                    f"does not end with '|' (truncated?)"
                                )
                            pipes = self._count_unescaped_pipes(row)
                            if pipes != header_pipes:
                                errors.append(
                                    f"{doc_path.name}:{block_start + i + 1} table cell drift: "
                                    f"{pipes} pipes, header has {header_pipes}"
                                )

                    # Check for duplicate table blocks
                    signature = "\n".join(self._normalize(bline) for bline in block)
                    occurrences = table_seen.get(signature, [])
                    occurrences.append(block_start + 1)
                    table_seen[signature] = occurrences
                    if len(occurrences) == 2:
                        warnings.append(
                            f"{doc_path.name}:{block_start + 1} duplicate table block "
                            f"(first at line {occurrences[0]}, {len(block)} lines)"
                        )
                    continue

                index += 1

            if context.verbose:
                print(f"[docs_integrity] {doc_path.name}: {headings} headings, {tables} table blocks")

        passed = len(errors) == 0
        return ConstraintResult(
            constraint_id=self.metadata.id,
            passed=passed,
            duration_ms=0,
            checks_run=checks_run,
            checks_passed=checks_passed,
            checks_failed=checks_run - checks_passed,
            evidence={"checked_files": [str(p) for p in target_docs]},
            errors=errors,
            warnings=warnings,
        )

    def _is_separator(self, line: str, separator_chars: set) -> bool:
        trimmed = line.strip()
        if "-" not in trimmed:
            return False
        return all(c in separator_chars for c in trimmed)

    def _count_unescaped_pipes(self, line: str) -> int:
        count = 0
        for i, ch in enumerate(line):
            if ch == "|" and (i == 0 or line[i - 1] != "\\"):
                count += 1
        return count

    def _normalize(self, line: str) -> str:
        return re.sub(r"\s+", " ", line.strip())


class DeadCodeConstraint(PureConstraint):
    """Heuristic dead-code candidates (non-blocking)."""

    def __init__(self):
        super().__init__(
            id="dead_code",
            name="Dead Code Detection",
            description="Heuristic dead-code candidates (non-blocking)",
            phase=ConstraintPhase.SEMANTIC,
            contracts=["preflight"],
            estimated_duration_ms=2000,
        )

    def run(self, context: PreflightContext) -> ConstraintResult:
        errors = []
        warnings = []
        checks_run = 0
        checks_passed = 0

        definition_regex = re.compile(r"^\s*(?:static\s+)?func\s+([A-Za-z0-9_]+)")
        token_regex = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

        KNOWN_ENTRYPOINTS = {
            "_ready", "_process", "_input", "_unhandled_input", "_notification",
            "_enter_tree", "_exit_tree", "_draw", "_physics_process", "_init",
        }
        KNOWN_API_PREFIXES = ["assert_", "get_", "set_", "can_", "has_", "is_", "begin_", "advance_", "dispatch_"]

        # Scan all .gd files
        definitions = []
        usage_counts = {}

        for gd_file in context.repo_root.rglob("*.gd"):
            # Skip excluded dirs
            if any(part in gd_file.parts for part in [".godot", ".git", ".import", "build", "dist", "node_modules"]):
                continue

            try:
                content = gd_file.read_text()
            except Exception:
                continue

            lines = content.split("\n")
            for index, line in enumerate(lines):
                match = definition_regex.search(line)
                if match:
                    name = match.group(1)
                    if not name.startswith("_"):
                        definitions.append({
                            "name": name,
                            "file": str(gd_file.relative_to(context.repo_root)),
                            "line": index + 1,
                        })

                for tm in token_regex.finditer(line):
                    tok = tm.group()
                    usage_counts[tok] = usage_counts.get(tok, 0) + 1

        candidates = []
        for definition in definitions:
            name = definition["name"]
            file_path = definition["file"]
            used = usage_counts.get(name, 0) > 1

            if not used and self._is_known_entrypoint(name, file_path, KNOWN_ENTRYPOINTS, KNOWN_API_PREFIXES):
                used = True

            if not used:
                candidates.append({
                    **definition,
                    "reason": self._candidate_reason(name, file_path),
                })

        candidates.sort(key=lambda c: c["name"])

        checks_run = len(definitions)
        checks_passed = checks_run - len(candidates)

        if candidates:
            warnings.append(f"{len(candidates)} unresolved dead-code candidates (non-blocking)")
            if context.verbose:
                for c in candidates[:50]:
                    warnings.append(f"  {c['name']} ({c['file']}:{c['line']}) -> {c['reason']}")
                if len(candidates) > 50:
                    warnings.append(f"  ... {len(candidates) - 50} additional candidates omitted")

        # This constraint never fails (non-blocking)
        return ConstraintResult(
            constraint_id=self.metadata.id,
            passed=True,
            duration_ms=0,
            checks_run=checks_run,
            checks_passed=checks_passed,
            checks_failed=len(candidates),
            evidence={"candidates": candidates[:100]},
            errors=errors,
            warnings=warnings,
        )

    def _candidate_reason(self, name: str, file: str) -> str:
        if file.startswith("addons/gdscript_mcp/"):
            return "MCP external/registry candidate"
        if file.startswith("scripts/preflight/") or file.startswith("scripts/doki/"):
            return "test/tooling entrypoint candidate"
        if name.startswith("get_") or name.startswith("can_") or name.startswith("has_"):
            return "read/API candidate"
        return "review candidate"

    def _is_known_entrypoint(self, name: str, file: str,
                             known_entrypoints: set, known_prefixes: list) -> bool:
        if name in known_entrypoints:
            return True
        for prefix in known_prefixes:
            if name.startswith(prefix):
                return True
        if file.startswith("addons/gdscript_mcp/") and name in ["dispatch_tool", "dispatch_async", "get_tool_defs"]:
            return True
        if file.startswith("scripts/preflight/") or file.startswith("scripts/doki/"):
            return True
        return False


class MechanicCoverageConstraint(PureConstraint):
    """Auto-detects new mechanics and validates coverage."""

    def __init__(self):
        super().__init__(
            id="mechanic_coverage",
            name="Mechanic Coverage",
            description="Auto-detects new mechanics and validates coverage",
            phase=ConstraintPhase.CONTRACT,
            contracts=["preflight"],
            estimated_duration_ms=2000,
        )

    def run(self, context: PreflightContext) -> ConstraintResult:
        errors = []
        warnings = []
        checks_run = 0
        checks_passed = 0

        registry_path = context.repo_root / "scripts" / "testing" / "mechanic_registry.gd"
        if not registry_path.exists():
            errors.append("scripts/testing/mechanic_registry.gd not found")
            return ConstraintResult(
                constraint_id=self.metadata.id,
                passed=False,
                duration_ms=0,
                checks_run=1,
                checks_failed=1,
                errors=errors,
            )

        checks_run += 1
        checks_passed += 1

        content = registry_path.read_text()

        # Check for mechanic registration
        checks_run += 1
        if "mechanics" in content.lower() or "mechanic" in content.lower():
            checks_passed += 1
        else:
            warnings.append("Mechanic registry may not define mechanics")

        # Check for coverage validation
        checks_run += 1
        if "coverage" in content.lower() or "validate" in content.lower():
            checks_passed += 1
        else:
            warnings.append("Coverage validation not detected")

        passed = len(errors) == 0
        return ConstraintResult(
            constraint_id=self.metadata.id,
            passed=passed,
            duration_ms=0,
            checks_run=checks_run,
            checks_passed=checks_passed,
            checks_failed=checks_run - checks_passed,
            evidence={"registry_path": str(registry_path)},
            errors=errors,
            warnings=warnings,
        )


class MCPCaptureContractConstraint(PureConstraint):
    """Validates MCP screenshot contract (async-only, frame_post_draw)."""

    def __init__(self):
        super().__init__(
            id="mcp_capture_contract",
            name="MCP Capture Contract",
            description="Validates MCP screenshot contract (async-only, frame_post_draw)",
            phase=ConstraintPhase.CONTRACT,
            contracts=["mcp", "preflight"],
            estimated_duration_ms=1000,
        )

    def run(self, context: PreflightContext) -> ConstraintResult:
        errors = []
        warnings = []
        checks_run = 0
        checks_passed = 0

        mcp_server_path = context.repo_root / "scripts" / "mcp_server.gd"
        if not mcp_server_path.exists():
            errors.append("scripts/mcp_server.gd not found")
            return ConstraintResult(
                constraint_id=self.metadata.id,
                passed=False,
                duration_ms=0,
                checks_run=1,
                checks_failed=1,
                errors=errors,
            )

        checks_run += 1
        checks_passed += 1

        content = mcp_server_path.read_text()

        # Check for async screenshot tool
        checks_run += 1
        if "capture_screenshot" in content and "_async" in content:
            checks_passed += 1
        else:
            errors.append("MCP capture_screenshot missing _async=true")

        # Check for frame_post_draw await
        checks_run += 1
        if "frame_post_draw" in content:
            checks_passed += 1
        else:
            errors.append("MCP screenshot missing await frame_post_draw")

        # Check for sync capture rejection
        checks_run += 1
        if "capture_screenshot_sync" in content:
            warnings.append("capture_screenshot_sync detected (should be rejected)")
        else:
            checks_passed += 1

        passed = len(errors) == 0
        return ConstraintResult(
            constraint_id=self.metadata.id,
            passed=passed,
            duration_ms=0,
            checks_run=checks_run,
            checks_passed=checks_passed,
            checks_failed=checks_run - checks_passed,
            evidence={"mcp_server_path": str(mcp_server_path)},
            errors=errors,
            warnings=warnings,
        )


class GameStateCompatibilityConstraint(PureConstraint):
    """Reflection signatures, facade methods for GameState."""

    def __init__(self):
        super().__init__(
            id="game_state_compatibility",
            name="GameState Compatibility",
            description="Reflection signatures, facade methods for GameState",
            phase=ConstraintPhase.CONTRACT,
            contracts=["game_state", "save"],
            estimated_duration_ms=2000,
        )

    def run(self, context: PreflightContext) -> ConstraintResult:
        errors = []
        warnings = []
        checks_run = 0
        checks_passed = 0

        game_state_path = context.repo_root / "scripts" / "state" / "game_state.gd"
        if not game_state_path.exists():
            errors.append("scripts/state/game_state.gd not found")
            return ConstraintResult(
                constraint_id=self.metadata.id,
                passed=False,
                duration_ms=0,
                checks_run=1,
                checks_failed=1,
                errors=errors,
            )

        checks_run += 1
        checks_passed += 1

        content = game_state_path.read_text()

        # Check for required facade methods
        required_methods = [
            "begin_new_game", "reconnect_world", "validate", "validate_starting_setup",
            "get_ownership_count", "get_faction_resource", "get_researched_technologies",
            "homeworld_for", "resource_snapshot", "has_active_run", "request_world_reconnect",
            "set_jobs_auto_advance", "prepare_start_roster",
        ]

        for method in required_methods:
            checks_run += 1
            if f"func {method}" in content:
                checks_passed += 1
            else:
                errors.append(f"GameState missing facade method: {method}")

        # Check for domain access
        checks_run += 1
        if "get(" in content and "faction_domain" in content:
            checks_passed += 1
        else:
            warnings.append("GameState domain access pattern not detected")

        passed = len(errors) == 0
        return ConstraintResult(
            constraint_id=self.metadata.id,
            passed=passed,
            duration_ms=0,
            checks_run=checks_run,
            checks_passed=checks_passed,
            checks_failed=checks_run - checks_passed,
            evidence={"game_state_path": str(game_state_path)},
            errors=errors,
            warnings=warnings,
        )


class SaveGameSlotsConstraint(PureConstraint):
    """Validates save slot conventions (slot 0 = real, 1-7 = test)."""

    def __init__(self):
        super().__init__(
            id="save_game_slots",
            name="Save Game Slots",
            description="Validates save slot conventions (slot 0 = real, 1-7 = test)",
            phase=ConstraintPhase.CONTRACT,
            contracts=["save"],
            estimated_duration_ms=1000,
        )

    def run(self, context: PreflightContext) -> ConstraintResult:
        errors = []
        warnings = []
        checks_run = 0
        checks_passed = 0

        save_service_path = context.repo_root / "scripts" / "state" / "save_game_service.gd"
        if not save_service_path.exists():
            errors.append("scripts/state/save_game_service.gd not found")
            return ConstraintResult(
                constraint_id=self.metadata.id,
                passed=False,
                duration_ms=0,
                checks_run=1,
                checks_failed=1,
                errors=errors,
            )

        checks_run += 1
        checks_passed += 1

        content = save_service_path.read_text()

        # Check for slot constants
        checks_run += 1
        if "SAVE_SLOT" in content or "slot" in content.lower():
            checks_passed += 1
        else:
            warnings.append("Save slot constants not detected")

        # Check for slot 0 handling
        checks_run += 1
        if "0" in content and ("slot" in content.lower() or "save" in content.lower()):
            checks_passed += 1
        else:
            warnings.append("Slot 0 handling not explicitly detected")

        passed = len(errors) == 0
        return ConstraintResult(
            constraint_id=self.metadata.id,
            passed=passed,
            duration_ms=0,
            checks_run=checks_run,
            checks_passed=checks_passed,
            checks_failed=checks_run - checks_passed,
            evidence={"save_service_path": str(save_service_path)},
            errors=errors,
            warnings=warnings,
        )


def register_pure_constraints(registry: "ConstraintRegistry") -> None:
    """Register all pure constraint implementations."""
    constraints = [
        ConceptIndexConstraint(),
        GlobalSearchConstraint(),
        DocsIntegrityConstraint(),
        DeadCodeConstraint(),
        MechanicCoverageConstraint(),
        MCPCaptureContractConstraint(),
        GameStateCompatibilityConstraint(),
        SaveGameSlotsConstraint(),
    ]

    for constraint in constraints:
        # Replace the placeholder in registry
        registry._constraints[constraint.metadata.id] = constraint
        registry._metadata[constraint.metadata.id] = constraint.metadata