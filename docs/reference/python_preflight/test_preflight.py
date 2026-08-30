"""
Tests for Python Preflight
===========================

Unit tests for the preflight components.
"""

from __future__ import annotations

import json
import tempfile
import shutil
from pathlib import Path
from unittest.mock import Mock, patch

import pytest

from preflight.inventory import RepositoryInventory, RepositorySnapshot, FileChange
from preflight.constraints import (
    ConstraintRegistry, ConstraintType, ConstraintPhase,
    ConstraintMetadata, ConstraintResult, PreflightContext,
    PureConstraint, GodotConstraint,
)
from preflight.scope import ScopeResolver
from preflight.cache import FileCache, ConstraintCache
from preflight.report import ReportGenerator
from preflight.pure_constraints import (
    ConceptIndexConstraint,
    GlobalSearchConstraint,
    DocsIntegrityConstraint,
    DeadCodeConstraint,
    MechanicCoverageConstraint,
    MCPCaptureContractConstraint,
    GameStateCompatibilityConstraint,
    SaveGameSlotsConstraint,
)


class TestRepositoryInventory:
    """Tests for RepositoryInventory."""

    def test_capture_in_temp_repo(self):
        """Test capturing snapshot in a temporary git repo."""
        with tempfile.TemporaryDirectory() as tmpdir:
            repo_path = Path(tmpdir)

            # Initialize git repo
            import subprocess
            subprocess.run(["git", "init"], cwd=repo_path, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "test@test.com"], cwd=repo_path, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=repo_path, check=True)

            # Create a file and commit
            test_file = repo_path / "test.txt"
            test_file.write_text("hello")
            subprocess.run(["git", "add", "test.txt"], cwd=repo_path, check=True)
            subprocess.run(["git", "commit", "-m", "Initial commit"], cwd=repo_path, check=True)

            # Modify file
            test_file.write_text("hello world")

            # Capture snapshot
            inventory = RepositoryInventory(repo_path)
            snapshot = inventory.capture()

            assert snapshot.branch == "master" or snapshot.branch == "main"
            assert len(snapshot.head_commit) == 40  # SHA1
            assert len(snapshot.changes) == 1
            assert snapshot.changes[0].path == "test.txt"
            assert snapshot.changes[0].status == "M"
            assert snapshot.changes[0].unstaged is True
            assert snapshot.changes[0].staged is False

    def test_staged_changes(self):
        """Test capturing staged changes."""
        with tempfile.TemporaryDirectory() as tmpdir:
            repo_path = Path(tmpdir)

            import subprocess
            subprocess.run(["git", "init"], cwd=repo_path, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "test@test.com"], cwd=repo_path, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=repo_path, check=True)

            test_file = repo_path / "test.txt"
            test_file.write_text("hello")
            subprocess.run(["git", "add", "test.txt"], cwd=repo_path, check=True)
            subprocess.run(["git", "commit", "-m", "Initial"], cwd=repo_path, check=True)

            # Stage a change
            test_file.write_text("hello world")
            subprocess.run(["git", "add", "test.txt"], cwd=repo_path, check=True)

            inventory = RepositoryInventory(repo_path)
            snapshot = inventory.capture()

            assert len(snapshot.changes) == 1
            assert snapshot.changes[0].staged is True
            assert snapshot.changes[0].hash is not None


class TestScopeResolver:
    """Tests for ScopeResolver."""

    def test_resolve_known_paths(self):
        """Test resolving known file paths to constraints."""
        with tempfile.TemporaryDirectory() as tmpdir:
            repo_path = Path(tmpdir)
            resolver = ScopeResolver(repo_path)

            # Test known paths
            changed = ["scripts/state/game_state.gd", "scripts/config/economy_config.gd"]
            result = resolver.resolve(changed)

            assert result.ok
            assert "game_state" in result.contract_ids
            assert "save" in result.contract_ids
            assert "economy" in result.contract_ids
            assert "game_state_compatibility" in result.constraint_ids
            assert "save_game_roundtrip" in result.constraint_ids
            assert "economy_production" in result.constraint_ids

    def test_resolve_unknown_path_fails(self):
        """Test that unknown paths fail closed."""
        with tempfile.TemporaryDirectory() as tmpdir:
            repo_path = Path(tmpdir)
            resolver = ScopeResolver(repo_path)

            changed = ["unknown/path/file.gd"]
            result = resolver.resolve(changed)

            assert not result.ok
            assert len(result.errors) > 0
            assert "Unmapped paths" in result.errors[0]

    def test_resolve_empty_fails(self):
        """Test that empty scope fails."""
        with tempfile.TemporaryDirectory() as tmpdir:
            repo_path = Path(tmpdir)
            resolver = ScopeResolver(repo_path)

            result = resolver.resolve([])

            assert not result.ok
            assert "Empty scope" in result.errors[0]

    def test_explain_constraint(self):
        """Test constraint explanation."""
        with tempfile.TemporaryDirectory() as tmpdir:
            repo_path = Path(tmpdir)
            resolver = ScopeResolver(repo_path)

            explanation = resolver.explain("game_state_compatibility")

            assert explanation["constraint_id"] == "game_state_compatibility"
            assert "game_state" in explanation["contracts"]
            assert "save" in explanation["contracts"]


class TestFileCache:
    """Tests for FileCache."""

    def test_basic_cache_operations(self):
        """Test basic cache get/set."""
        with tempfile.TemporaryDirectory() as tmpdir:
            cache = FileCache(Path(tmpdir) / "cache")

            # Set and get
            cache.set("key1", "value1", {"file.txt": "abc123"})
            assert cache.get("key1", {"file.txt": "abc123"}) == "value1"

            # Miss with different hash
            assert cache.get("key1", {"file.txt": "different"}) is None

            # Miss with missing key
            assert cache.get("nonexistent") is None

    def test_cache_invalidation(self):
        """Test cache invalidation on file change."""
        with tempfile.TemporaryDirectory() as tmpdir:
            cache = FileCache(Path(tmpdir) / "cache")

            cache.set("key1", "value1", {"file.txt": "hash1"})
            assert cache.get("key1", {"file.txt": "hash1"}) == "value1"

            # Same hash - should hit
            assert cache.get("key1", {"file.txt": "hash1"}) == "value1"

            # Different hash - should miss
            assert cache.get("key1", {"file.txt": "hash2"}) is None

    def test_file_hashing(self):
        """Test file hash computation."""
        with tempfile.TemporaryDirectory() as tmpdir:
            cache = FileCache(Path(tmpdir) / "cache")
            test_file = Path(tmpdir) / "test.txt"
            test_file.write_text("hello world")

            hash1 = cache.get_file_hash(test_file)
            assert len(hash1) == 16  # Truncated SHA256

            # Same content = same hash
            hash2 = cache.get_file_hash(test_file)
            assert hash1 == hash2

            # Different content = different hash
            test_file.write_text("hello world!")
            hash3 = cache.get_file_hash(test_file)
            assert hash1 != hash3


class TestConstraintRegistry:
    """Tests for ConstraintRegistry."""

    def test_registry_initialization(self):
        """Test registry loads all constraints."""
        registry = ConstraintRegistry()

        all_constraints = registry.get_all()
        assert len(all_constraints) > 40  # Should have all 44+ constraints

        # Check pure constraints exist
        pure = registry.get_by_type(ConstraintType.PURE)
        assert len(pure) >= 8

        # Check godot constraints exist
        godot = registry.get_by_type(ConstraintType.GODOT)
        assert len(godot) >= 30

    def test_pipeline_ordering(self):
        """Test pipeline is ordered by phase (cheap -> expensive)."""
        registry = ConstraintRegistry()
        pipeline = registry.get_pipeline()

        phases = [c.metadata.phase for c in pipeline]
        phase_values = [p.value for p in phases]

        # Should be non-decreasing
        assert phase_values == sorted(phase_values)

    def test_filter_by_type(self):
        """Test filtering by constraint type."""
        registry = ConstraintRegistry()

        pure = registry.get_by_type(ConstraintType.PURE)
        for c in pure:
            assert c.metadata.constraint_type == ConstraintType.PURE

        godot = registry.get_by_type(ConstraintType.GODOT)
        for c in godot:
            assert c.metadata.constraint_type == ConstraintType.GODOT

    def test_filter_by_contract(self):
        """Test filtering by contract."""
        registry = ConstraintRegistry()

        game_state_constraints = registry.get_by_contract("game_state")
        assert len(game_state_constraints) > 0
        for c in game_state_constraints:
            assert "game_state" in c.metadata.contracts


class TestPureConstraints:
    """Tests for pure constraint implementations."""

    def setup_method(self):
        """Setup test context."""
        self.temp_dir = tempfile.mkdtemp()
        self.repo_root = Path(self.temp_dir)

        # Create minimal repo structure
        (self.repo_root / "scripts").mkdir(parents=True)
        (self.repo_root / "scripts" / "state").mkdir(parents=True)
        (self.repo_root / "scripts" / "testing").mkdir(parents=True)
        (self.repo_root / "docs").mkdir(parents=True)

        # Create minimal required files
        (self.repo_root / "scripts" / "concept_index.gd").write_text("""
class_name ConceptIndex
extends RefCounted

func _build_concepts():
    pass

func search(term):
    return []

func expand(term):
    return []

func class_concept(name):
    return null

func by_domain(domain):
    return []

func get_unmapped_classes():
    return []

func get_concepts_with_free_slots():
    return []
""")

        (self.repo_root / "scripts" / "global_search.gd").write_text("""
class_name GlobalSearch
extends RefCounted

func scan():
    pass

func search(term):
    return []

func _scan_file(path):
    pass

func _matches(line, term):
    return false

func _get_context(lines, index):
    return []
""")

        (self.repo_root / "docs" / "FINDINGS.md").write_text("""# FINDINGS

## Test Heading

| Col1 | Col2 |
|------|------|
| A    | B    |
""")

        (self.repo_root / "CHANGELOG.md").write_text("""# CHANGELOG

## Version 1.0

| Date | Change |
|------|--------|
| 2024-01-01 | Initial |
""")

        (self.repo_root / "scripts" / "state" / "game_state.gd").write_text("""
class_name GameState
extends Node

func begin_new_game():
    pass

func reconnect_world():
    pass

func validate():
    return []

func validate_starting_setup():
    return []

func get_ownership_count(faction):
    return 0

func get_faction_resource(faction, resource):
    return 0

func get_researched_technologies(faction):
    return []

func homeworld_for(faction):
    return ""

func resource_snapshot():
    return {}

func has_active_run():
    return false

func request_world_reconnect():
    pass

func set_jobs_auto_advance(enabled):
    pass

func prepare_start_roster(roster):
    pass
""")

        (self.repo_root / "scripts" / "state" / "save_game_service.gd").write_text("""
class_name SaveGameService
extends RefCounted

const SAVE_SLOT = 0
""")

        (self.repo_root / "scripts" / "testing" / "mechanic_registry.gd").write_text("""
class_name MechanicRegistry
extends RefCounted

var mechanics = {}
""")

        (self.repo_root / "scripts" / "mcp_server.gd").write_text("""
class_name MCPServer
extends RefCounted

func capture_screenshot():
    await get_tree().frame_post_draw
    return {}
""")

    def teardown_method(self):
        """Cleanup."""
        shutil.rmtree(self.temp_dir)

    def _create_context(self):
        """Create a test context."""
        from preflight.inventory import RepositoryInventory, RepositorySnapshot
        from preflight.cache import FileCache

        inventory = RepositoryInventory(self.repo_root)
        snapshot = inventory.capture()
        cache = FileCache(self.repo_root / ".preflight_cache")

        return PreflightContext(
            repo_root=self.repo_root,
            snapshot=snapshot,
            inventory=inventory,
            cache=cache,
            verbose=True,
        )

    def test_concept_index_constraint(self):
        """Test ConceptIndexConstraint."""
        constraint = ConceptIndexConstraint()
        context = self._create_context()

        result = constraint.run(context)

        assert result.passed
        assert result.checks_run > 0
        assert result.checks_passed > 0

    def test_global_search_constraint(self):
        """Test GlobalSearchConstraint."""
        constraint = GlobalSearchConstraint()
        context = self._create_context()

        result = constraint.run(context)

        assert result.passed
        assert result.checks_run > 0

    def test_docs_integrity_constraint(self):
        """Test DocsIntegrityConstraint."""
        constraint = DocsIntegrityConstraint()
        context = self._create_context()

        result = constraint.run(context)

        assert result.passed
        assert result.checks_run > 0

    def test_dead_code_constraint(self):
        """Test DeadCodeConstraint."""
        constraint = DeadCodeConstraint()
        context = self._create_context()

        result = constraint.run(context)

        # Dead code is non-blocking, should always pass
        assert result.passed
        assert result.checks_run > 0

    def test_mechanic_coverage_constraint(self):
        """Test MechanicCoverageConstraint."""
        constraint = MechanicCoverageConstraint()
        context = self._create_context()

        result = constraint.run(context)

        assert result.passed
        assert result.checks_run > 0

    def test_mcp_capture_contract_constraint(self):
        """Test MCPCaptureContractConstraint."""
        constraint = MCPCaptureContractConstraint()
        context = self._create_context()

        result = constraint.run(context)

        assert result.passed
        assert result.checks_run > 0

    def test_game_state_compatibility_constraint(self):
        """Test GameStateCompatibilityConstraint."""
        constraint = GameStateCompatibilityConstraint()
        context = self._create_context()

        result = constraint.run(context)

        assert result.passed
        assert result.checks_run > 0

    def test_save_game_slots_constraint(self):
        """Test SaveGameSlotsConstraint."""
        constraint = SaveGameSlotsConstraint()
        context = self._create_context()

        result = constraint.run(context)

        assert result.passed
        assert result.checks_run > 0


class TestReportGenerator:
    """Tests for ReportGenerator."""

    def test_generate_human_report(self):
        """Test human report generation."""
        with tempfile.TemporaryDirectory() as tmpdir:
            repo_root = Path(tmpdir)

            import subprocess
            subprocess.run(["git", "init"], cwd=repo_root, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "test@test.com"], cwd=repo_root, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=repo_root, check=True)

            inventory = RepositoryInventory(repo_root)
            snapshot = inventory.capture()

            results = [
                ConstraintResult("test1", True, 100.0, 5, 5, 0),
                ConstraintResult("test2", False, 200.0, 3, 1, 2, errors=["Error 1"]),
            ]

            generator = ReportGenerator(verbose=True)
            report = generator.generate_human(snapshot, results, 300.0, 1)

            assert "PREFLIGHT" in report
            assert "PASSED" in report or "FAILED" in report
            assert "test1" in report
            assert "test2" in report
            assert "Error 1" in report

    def test_generate_json_report(self):
        """Test JSON report generation."""
        with tempfile.TemporaryDirectory() as tmpdir:
            repo_root = Path(tmpdir)

            import subprocess
            subprocess.run(["git", "init"], cwd=repo_root, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "test@test.com"], cwd=repo_root, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=repo_root, check=True)

            inventory = RepositoryInventory(repo_root)
            snapshot = inventory.capture()

            results = [
                ConstraintResult("test1", True, 100.0, 5, 5, 0),
                ConstraintResult("test2", False, 200.0, 3, 1, 2, errors=["Error 1"]),
            ]

            generator = ReportGenerator()
            report = generator.generate_json(snapshot, results, 300.0, 1)

            assert report["verdict"] == "FAIL"
            assert report["exit_code"] == 1
            assert report["constraints"]["total"] == 2
            assert report["constraints"]["passed"] == 1
            assert report["constraints"]["failed"] == 1


class TestIntegration:
    """Integration tests for full preflight flow."""

    def test_full_preflight_run(self):
        """Test full preflight run with changed-only scope."""
        with tempfile.TemporaryDirectory() as tmpdir:
            repo_path = Path(tmpdir)

            import subprocess
            subprocess.run(["git", "init"], cwd=repo_path, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "test@test.com"], cwd=repo_path, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=repo_path, check=True)

            # Create minimal structure
            (repo_path / "scripts").mkdir(parents=True)
            (repo_path / "scripts" / "state").mkdir(parents=True)
            (repo_path / "scripts" / "testing").mkdir(parents=True)
            (repo_path / "docs").mkdir(parents=True)

            (repo_path / "scripts" / "concept_index.gd").write_text("""
class_name ConceptIndex
extends RefCounted
func _build_concepts(): pass
func search(term): return []
func expand(term): return []
func class_concept(name): return null
func by_domain(domain): return []
func get_unmapped_classes(): return []
func get_concepts_with_free_slots(): return []
""")

            (repo_path / "scripts" / "global_search.gd").write_text("""
class_name GlobalSearch
extends RefCounted
func scan(): pass
func search(term): return []
func _scan_file(path): pass
func _matches(line, term): return false
func _get_context(lines, index): return []
""")

            (repo_path / "docs" / "FINDINGS.md").write_text("# FINDINGS\n\n## Test\n\n| A | B |\n|---|---|\n| 1 | 2 |\n")

            (repo_path / "CHANGELOG.md").write_text("# CHANGELOG\n\n## v1\n\n| Date | Change |\n|------|--------|\n| 2024 | Init |\n")

            (repo_path / "scripts" / "state" / "game_state.gd").write_text("""
class_name GameState
extends Node
func begin_new_game(): pass
func reconnect_world(): pass
func validate(): return []
func validate_starting_setup(): return []
func get_ownership_count(faction): return 0
func get_faction_resource(faction, resource): return 0
func get_researched_technologies(faction): return []
func homeworld_for(faction): return ""
func resource_snapshot(): return {}
func has_active_run(): return false
func request_world_reconnect(): pass
func set_jobs_auto_advance(enabled): pass
func prepare_start_roster(roster): pass
""")

            (repo_path / "scripts" / "state" / "save_game_service.gd").write_text("""
class_name SaveGameService
extends RefCounted
const SAVE_SLOT = 0
""")

            (repo_path / "scripts" / "testing" / "mechanic_registry.gd").write_text("""
class_name MechanicRegistry
extends RefCounted
var mechanics = {}
""")

            (repo_path / "scripts" / "mcp_server.gd").write_text("""
class_name MCPServer
extends RefCounted
func capture_screenshot():
    await get_tree().frame_post_draw
    return {}
""")

            # Commit initial
            subprocess.run(["git", "add", "."], cwd=repo_path, check=True)
            subprocess.run(["git", "commit", "-m", "Initial"], cwd=repo_path, check=True)

            # Run preflight
            from preflight.core import PreflightRunner

            runner = PreflightRunner(repo_root=repo_path, verbose=False)
            exit_code = runner.run(changed_only=True)

            # Should pass (pure constraints only)
            assert exit_code == 0
            assert len(runner.results) > 0
            assert all(r.passed for r in runner.results)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])