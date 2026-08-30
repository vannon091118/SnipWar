"""
Report Generator
================

Generates human-readable and JSON reports from preflight execution results.
"""

from __future__ import annotations

import json
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Any

from .constraints import ConstraintResult, ConstraintPhase
from .inventory import RepositorySnapshot


class ReportGenerator:
    """Generates preflight reports in multiple formats."""

    def __init__(self, verbose: bool = False):
        self.verbose = verbose

    def generate_json(self,
                      snapshot: RepositorySnapshot,
                      results: list[ConstraintResult],
                      total_duration_ms: float,
                      exit_code: int) -> dict[str, Any]:
        """Generate machine-readable JSON report."""
        passed = sum(1 for r in results if r.passed)
        failed = sum(1 for r in results if not r.passed)
        total_checks = sum(r.checks_run for r in results)
        passed_checks = sum(r.checks_passed for r in results)
        failed_checks = sum(r.checks_failed for r in results)

        # Group by phase
        by_phase: dict[str, list[dict]] = {}
        for result in results:
            # We need to get phase from constraint registry, but for now use a simple mapping
            phase_name = "unknown"
            # Could look up phase from constraint ID
            phase_key = f"phase_{phase_name}"
            if phase_key not in by_phase:
                by_phase[phase_key] = []
            by_phase[phase_key].append(result.to_dict())

        return {
            "verdict": "PASS" if exit_code == 0 else "FAIL",
            "exit_code": exit_code,
            "timestamp": datetime.now().isoformat(),
            "repository": {
                "root": str(snapshot.repo_root),
                "branch": snapshot.branch,
                "head_commit": snapshot.head_commit,
                "head_message": snapshot.head_message,
                "changed_files": len(snapshot.changes),
            },
            "constraints": {
                "total": len(results),
                "passed": passed,
                "failed": failed,
            },
            "assertions": {
                "run": total_checks,
                "passed": passed_checks,
                "failed": failed_checks,
            },
            "duration_ms": total_duration_ms,
            "constraint_results": [r.to_dict() for r in results],
            "by_phase": by_phase,
        }

    def generate_human(self,
                       snapshot: RepositorySnapshot,
                       results: list[ConstraintResult],
                       total_duration_ms: float,
                       exit_code: int) -> str:
        """Generate human-readable report."""
        lines = []
        passed = sum(1 for r in results if r.passed)
        failed = sum(1 for r in results if not r.passed)
        total_checks = sum(r.checks_run for r in results)
        passed_checks = sum(r.checks_passed for r in results)
        failed_checks = sum(r.checks_failed for r in results)

        lines.append("=" * 60)
        lines.append(" SNIPWAR PYTHON PREFLIGHT REPORT")
        lines.append("=" * 60)
        lines.append(f" Repository: {snapshot.repo_root}")
        lines.append(f" Branch:     {snapshot.branch}")
        lines.append(f" HEAD:       {snapshot.head_commit[:8]} - {snapshot.head_message[:60]}")
        lines.append(f" Changed:    {len(snapshot.changes)} files")
        lines.append("-" * 60)
        lines.append(f" Constraints: {len(results)} total ({passed} passed, {failed} failed)")
        lines.append(f" Assertions:  {total_checks} total ({passed_checks} passed, {failed_checks} failed)")
        lines.append(f" Duration:    {total_duration_ms:.1f} ms")
        lines.append("-" * 60)

        # Group by phase
        phase_results: dict[ConstraintPhase, list[ConstraintResult]] = {}
        for result in results:
            # Look up phase from constraint ID (simplified)
            phase = self._get_phase_for_constraint(result.constraint_id)
            if phase not in phase_results:
                phase_results[phase] = []
            phase_results[phase].append(result)

        for phase in sorted(phase_results.keys()):
            phase_list = phase_results[phase]
            lines.append(f"\n  --- {phase.name} ---")
            for result in phase_list:
                marker = "[PASS]" if result.passed else "[FAIL]"
                duration = f"{result.duration_ms:.1f} ms"
                checks = f"{result.checks_run} checks"
                if result.checks_failed > 0:
                    checks += f" ({result.checks_failed} fail)"
                lines.append(f"  {marker} {result.constraint_id:<40} {duration:>10} ({checks})")

                if self.verbose:
                    for error in result.errors:
                        lines.append(f"       ERROR: {error}")
                    for warning in result.warnings:
                        lines.append(f"       WARN:  {warning}")

        lines.append("\n" + "=" * 60)
        if exit_code == 0:
            lines.append(f" RESULT: PASSED ({passed} constraints in {total_duration_ms:.1f} ms)")
        else:
            lines.append(f" RESULT: FAILED ({failed} constraints failed)")
            lines.append("")
            lines.append(" FAILURES:")
            for result in results:
                if not result.passed:
                    lines.append(f"  [{result.constraint_id}]")
                    for error in result.errors:
                        lines.append(f"    - {error}")
        lines.append("=" * 60)

        return "\n".join(lines)

    def _get_phase_for_constraint(self, constraint_id: str) -> ConstraintPhase:
        """Map constraint ID to phase (simplified mapping)."""
        # Pure constraints
        pure_constraints = {
            "concept_index": ConstraintPhase.CONTRACT,
            "global_search": ConstraintPhase.CONTRACT,
            "docs_integrity": ConstraintPhase.DOCS,
            "dead_code": ConstraintPhase.SEMANTIC,
            "mechanic_coverage": ConstraintPhase.CONTRACT,
            "mcp_capture_contract": ConstraintPhase.CONTRACT,
            "game_state_compatibility": ConstraintPhase.CONTRACT,
            "save_game_slots": ConstraintPhase.CONTRACT,
            "save_game_roundtrip": ConstraintPhase.INTEGRATION,
        }

        if constraint_id in pure_constraints:
            return pure_constraints[constraint_id]

        # Godot constraints - map by prefix
        if constraint_id.startswith("scene_"):
            return ConstraintPhase.INTEGRATION
        elif constraint_id.startswith("world_"):
            return ConstraintPhase.RUNTIME
        elif constraint_id.startswith("chunk_") or constraint_id.startswith("cluster_") or constraint_id.startswith("grid_"):
            return ConstraintPhase.RUNTIME
        elif constraint_id.startswith("sector_"):
            return ConstraintPhase.RUNTIME
        elif constraint_id.startswith("economy_") or constraint_id.startswith("local_") or constraint_id.startswith("resources_") or constraint_id.startswith("upgrade_") or constraint_id.startswith("mission_"):
            return ConstraintPhase.RUNTIME
        elif constraint_id.startswith("ship_") or constraint_id.startswith("research_") or constraint_id.startswith("module_") or constraint_id.startswith("effects_"):
            return ConstraintPhase.RUNTIME
        elif constraint_id.startswith("flight_") or constraint_id.startswith("cpu_") or constraint_id.startswith("conquest_") or constraint_id.startswith("layers_"):
            return ConstraintPhase.RUNTIME
        elif constraint_id.startswith("main_") or constraint_id.startswith("pause_") or constraint_id.startswith("ingame_") or constraint_id.startswith("selection_") or constraint_id.startswith("camera_") or constraint_id.startswith("paper_") or constraint_id.startswith("layer_") or constraint_id.startswith("context_") or constraint_id.startswith("colony_"):
            return ConstraintPhase.RUNTIME
        elif constraint_id.startswith("historical_") or constraint_id.startswith("event_"):
            return ConstraintPhase.RUNTIME
        elif constraint_id.startswith("narrative_"):
            return ConstraintPhase.CONTRACT

        return ConstraintPhase.INTEGRATION

    def write_json(self, report: dict[str, Any], output_path: Path) -> None:
        """Write JSON report to file."""
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w") as f:
            json.dump(report, f, indent=2, sort_keys=True)

    def write_human(self, report: str, output_path: Path) -> None:
        """Write human report to file."""
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w") as f:
            f.write(report)


def print_summary(exit_code: int, passed: int, failed: int, duration_ms: float) -> None:
    """Print a one-line summary to stdout."""
    status = "PASSED" if exit_code == 0 else "FAILED"
    print(f"Preflight {status}: {passed} passed, {failed} failed in {duration_ms:.1f} ms")