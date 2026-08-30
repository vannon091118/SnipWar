"""
Preflight Runner
================

Main entry point for the Python preflight CLI.
Orchestrates: Snapshot → Inventory → Scope → Constraints → Evidence → Verdict
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

from .inventory import RepositoryInventory, RepositorySnapshot
from .constraints import (
    ConstraintRegistry, ConstraintType, ConstraintPhase,
    PreflightContext, PureConstraint, ConstraintResult,
)
from .scope import ScopeResolver
from .cache import FileCache, ConstraintCache
from .report import ReportGenerator, print_summary


class PreflightRunner:
    """Main preflight execution engine."""

    def __init__(self, repo_root: Path | None = None, verbose: bool = False,
                 fail_fast: bool = False, godot_binary: str | None = None):
        self.repo_root = repo_root or Path.cwd()
        self.verbose = verbose
        self.fail_fast = fail_fast
        self.godot_binary = godot_binary

        # Initialize components
        self.inventory = RepositoryInventory(self.repo_root)
        self.registry = ConstraintRegistry()
        self.scope_resolver = ScopeResolver(self.repo_root)
        self.file_cache = FileCache(self.repo_root / ".preflight_cache")
        self.constraint_cache = ConstraintCache(self.file_cache)
        self.report_generator = ReportGenerator(verbose)

        # Execution state
        self.snapshot: RepositorySnapshot | None = None
        self.scope_resolution = None
        self.context: PreflightContext | None = None
        self.results: list[ConstraintResult] = []
        self.start_time: float = 0

    def run(self,
            constraint_ids: list[str] | None = None,
            scope_file: Path | None = None,
            changed_only: bool = False,
            full: bool = False,
            constraint_type: ConstraintType | None = None,
            phase: ConstraintPhase | None = None,
            explain_id: str | None = None) -> int:
        """Execute preflight and return exit code."""
        self.start_time = time.time()

        if explain_id:
            return self._explain_constraint(explain_id)

        # 1. Capture repository snapshot
        self.snapshot = self.inventory.capture()

        if self.verbose:
            print(f"[preflight] Repository: {self.repo_root}")
            print(f"[preflight] Branch: {self.snapshot.branch}")
            print(f"[preflight] HEAD: {self.snapshot.head_commit[:8]}")
            print(f"[preflight] Changed files: {len(self.snapshot.changes)}")

        # 2. Resolve scope
        if scope_file:
            self.scope_resolution = self.scope_resolver.resolve_from_manifest(scope_file)
        elif changed_only:
            changed_files = self.inventory.get_changed_files(staged_only=False)
            self.scope_resolution = self.scope_resolver.resolve(changed_files)
        elif full or constraint_ids:
            # Full mode or explicit constraints
            self.scope_resolution = self._resolve_explicit(constraint_ids)
        else:
            # Default: changed files only
            changed_files = self.inventory.get_changed_files(staged_only=False)
            self.scope_resolution = self.scope_resolver.resolve(changed_files)

        if not self.scope_resolution.ok:
            for error in self.scope_resolution.errors:
                print(f"[preflight] ERROR: {error}", file=sys.stderr)
            return 1

        if self.scope_resolution.is_empty:
            print("[preflight] No constraints to run (empty scope)")
            return 0

        if self.verbose:
            print(f"[preflight] Scope: {len(self.scope_resolution.constraint_ids)} constraints")
            print(f"[preflight] Contracts: {', '.join(self.scope_resolution.contract_ids)}")
            for path, contracts in self.scope_resolution.path_mappings.items():
                print(f"[preflight]   {path} -> {', '.join(contracts)}")

        # 3. Filter by type/phase if specified
        pipeline = self._build_pipeline(constraint_type, phase)

        # 4. Create execution context
        self.context = PreflightContext(
            repo_root=self.repo_root,
            snapshot=self.snapshot,
            inventory=self.inventory,
            cache=self.file_cache,
            verbose=self.verbose,
            fail_fast=self.fail_fast,
            godot_available=self.godot_binary is not None,
            godot_binary=self.godot_binary,
        )

        # 5. Execute constraints
        self.results = self._execute_pipeline(pipeline)

        # 6. Generate reports
        total_duration_ms = (time.time() - self.start_time) * 1000
        exit_code = self._generate_reports(total_duration_ms)

        return exit_code

    def _resolve_explicit(self, constraint_ids: list[str] | None) -> "ScopeResolution":
        """Resolve explicitly specified constraint IDs."""
        from .scope import ScopeResolution
        if constraint_ids:
            # Validate all IDs exist
            all_known = set(self.registry.get_all_metadata())
            known_ids = {c.id for c in all_known}
            unknown = [cid for cid in constraint_ids if cid not in known_ids]
            if unknown:
                return ScopeResolution(
                    constraint_ids=[],
                    contract_ids=[],
                    path_mappings={},
                    errors=[f"Unknown constraint IDs: {', '.join(unknown)}"],
                )
            return ScopeResolution(
                constraint_ids=constraint_ids,
                contract_ids=[],  # Would need reverse lookup
                path_mappings={},
            )
        # Full mode - all constraints
        all_ids = [c.metadata.id for c in self.registry.get_all()]
        return ScopeResolution(
            constraint_ids=all_ids,
            contract_ids=list(_CONTRACT_CONSTRAINTS.keys()),
            path_mappings={},
        )

    def _build_pipeline(self, constraint_type: ConstraintType | None,
                        phase: ConstraintPhase | None) -> list:
        """Build ordered constraint pipeline."""
        pipeline = self.registry.get_pipeline(
            constraint_ids=self.scope_resolution.constraint_ids,
            constraint_type=constraint_type,
            phase=phase,
        )

        # Filter to only runnable constraints (Python-only unless Godot available)
        runnable = []
        for constraint in pipeline:
            if constraint.can_run_in_python() or self.context.godot_available:
                runnable.append(constraint)
            elif self.verbose:
                print(f"[preflight] SKIP (requires Godot): {constraint.metadata.id}")

        return runnable

    def _execute_pipeline(self, pipeline: list) -> list[ConstraintResult]:
        """Execute all constraints in pipeline."""
        results = []

        for constraint in pipeline:
            if self.verbose:
                print(f"[preflight] Running: {constraint.metadata.id} ({constraint.metadata.phase.name})")

            constraint_start = time.time()

            # Check cache first
            snapshot_hash = self.constraint_cache.get_snapshot_hash(self.snapshot)
            cached = self.constraint_cache.get_constraint_result(
                constraint.metadata.id, snapshot_hash
            )
            if cached is not None:
                if self.verbose:
                    print(f"[preflight]   CACHED: {constraint.metadata.id}")
                results.append(cached)
                continue

            # Run constraint
            try:
                result = constraint.run(self.context)
            except Exception as e:
                result = ConstraintResult(
                    constraint_id=constraint.metadata.id,
                    passed=False,
                    duration_ms=(time.time() - constraint_start) * 1000,
                    errors=[f"Constraint crashed: {type(e).__name__}: {e}"],
                )

            result.duration_ms = (time.time() - constraint_start) * 1000
            results.append(result)
            self.context.add_result(result)

            # Cache result
            self.constraint_cache.set_constraint_result(
                constraint.metadata.id, snapshot_hash, result
            )

            # Print result
            status = "PASS" if result.passed else "FAIL"
            print(f"[preflight] {status} {constraint.metadata.id} ({result.duration_ms:.1f} ms, {result.checks_run} checks)")

            if self.fail_fast and not result.passed:
                if self.verbose:
                    print(f"[preflight] Fail-fast triggered after {constraint.metadata.id}")
                break

        return results

    def _generate_reports(self, total_duration_ms: float) -> int:
        """Generate and output reports."""
        passed = sum(1 for r in self.results if r.passed)
        failed = sum(1 for r in self.results if not r.passed)
        exit_code = 0 if failed == 0 else 1

        # Human report
        human_report = self.report_generator.generate_human(
            self.snapshot, self.results, total_duration_ms, exit_code
        )
        print(human_report)

        # JSON report (if requested via --json flag, handled by CLI)
        return exit_code

    def _explain_constraint(self, constraint_id: str) -> int:
        """Explain why a constraint is required."""
        explanation = self.scope_resolver.explain(constraint_id)
        print(json.dumps(explanation, indent=2))
        return 0


# Import for _resolve_explicit
from .scope import ScopeResolution
from .scope import _CONTRACT_CONSTRAINTS


def main() -> int:
    """Main CLI entry point."""
    parser = argparse.ArgumentParser(
        prog="python -m preflight",
        description="SnipWar Python Preflight - Static verification without Godot",
    )

    parser.add_argument(
        "--root", type=Path, default=Path.cwd(),
        help="Repository root directory"
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="Verbose output"
    )
    parser.add_argument(
        "-x", "--fail-fast", action="store_true",
        help="Abort on first failure"
    )
    parser.add_argument(
        "--godot", type=str, default=None,
        help="Path to Godot binary for runtime constraints"
    )

    # Scope selection
    scope_group = parser.add_mutually_exclusive_group()
    scope_group.add_argument(
        "--changed-only", action="store_true",
        help="Run only constraints affected by changed files (default)"
    )
    scope_group.add_argument(
        "--full", action="store_true",
        help="Run all constraints (full preflight)"
    )
    scope_group.add_argument(
        "--scope", type=Path, default=None,
        help="Scope manifest file (JSON with 'constraints' array)"
    )
    scope_group.add_argument(
        "--constraint", type=str, action="append", default=[],
        help="Specific constraint ID to run (can be used multiple times)"
    )

    # Filtering
    parser.add_argument(
        "--type", type=str, choices=["pure", "godot", "hybrid"],
        help="Filter by constraint type"
    )
    parser.add_argument(
        "--phase", type=str, choices=[p.name.lower() for p in ConstraintPhase],
        help="Filter by execution phase"
    )

    # Output
    parser.add_argument(
        "--json", type=Path, default=None,
        help="Write JSON report to file"
    )
    parser.add_argument(
        "--explain", type=str, default=None,
        help="Explain why a constraint is required"
    )
    parser.add_argument(
        "--list", action="store_true",
        help="List all available constraints"
    )

    args = parser.parse_args()

    runner = PreflightRunner(
        repo_root=args.root,
        verbose=args.verbose,
        fail_fast=args.fail_fast,
        godot_binary=args.godot,
    )

    if args.list:
        print("Available constraints:")
        for meta in runner.registry.get_all_metadata():
            type_tag = f"[{meta.constraint_type.value.upper()}]"
            phase_tag = f"({meta.phase.name})"
            contracts = f"contracts={meta.contracts}" if meta.contracts else ""
            print(f"  {meta.id:<40} {type_tag} {phase_tag} {contracts}")
        return 0

    constraint_type = ConstraintType(args.type) if args.type else None
    phase = ConstraintPhase[args.phase.upper()] if args.phase else None

    exit_code = runner.run(
        constraint_ids=args.constraint if args.constraint else None,
        scope_file=args.scope,
        changed_only=args.changed_only or (not args.full and not args.scope and not args.constraint),
        full=args.full,
        constraint_type=constraint_type,
        phase=phase,
        explain_id=args.explain,
    )

    # Write JSON report if requested
    if args.json and runner.snapshot and runner.results:
        total_duration_ms = (time.time() - runner.start_time) * 1000
        json_report = runner.report_generator.generate_json(
            runner.snapshot, runner.results, total_duration_ms, exit_code
        )
        runner.report_generator.write_json(json_report, args.json)
        print(f"[preflight] JSON report written to {args.json}")

    return exit_code


if __name__ == "__main__":
    sys.exit(main())