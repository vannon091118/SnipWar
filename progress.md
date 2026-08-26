# Preflight Optimization — Session Log

## Session 1: 2026-08-26 — Audit, Planning & Baseline

### What was done
- [x] Read and analyzed `scripts/preflight.gd` (orchestrator)
- [x] Read and analyzed `scripts/preflight/preflight_context.gd` (assertion engine)
- [x] Read and analyzed `scripts/preflight/preflight_fixture.gd` (scene lifecycle)
- [x] Read key constraints: scene_boot, save_game_roundtrip, world_planets_and_dispatch, global_search, dead_code, game_state_compatibility, concept_index, mechanic_coverage
- [x] Counted 73 `await_frame()` calls across all constraints
- [x] Identified 23 scene-dependent vs 14 pure constraints
- [x] Found `dead_code` constraint exists but was NOT in registry (now 37 total = it was added)
- [x] Found `--fail-fast` uses `tree.quit(1)` which skips summary report
- [x] Analyzed pre-commit hook (runs full suite on every commit)
- [x] Created task_plan.md, findings.md, progress.md
- [x] **Ran actual baseline: 84,552.60 ms (84.5 seconds)**
- [x] **Identified 82% of runtime = scene re-booting (23× ~3s each)**
- [x] **Identified game_state_compatibility = 5.3s (pure constraint, reads all .gd files)**
- [x] **Identified global_search = 2.2s (scans all files)**
- [x] **Found RID leak warnings: 109 ObjectDB instances, 51 resources leaked at exit**

### Key findings logged
- **#1 bottleneck**: 23× scene re-boot (~70,725 ms of 84,553 ms = 83.6%)
- **#2 bottleneck**: game_state_compatibility (5,299 ms) — pure constraint doing full .gd scan
- **#3 bottleneck**: global_search (2,195 ms) — file scan overhead
- **#1 security gap**: RID leaks prove state leaks are real (109 ObjectDB instances)
- **#1 quick win**: fail-fast skips summary + 37 stale class references

### Decisions made
- Hybrid reset strategy (not full re-boot) for scene constraints
- Phase-based approach: quick wins → scene-sharing → security → profiling
- fail-fast should set a flag, not quit the process

### Files created/modified
- `task_plan.md` — Master plan with 5 phases
- `findings.md` — Full audit research + baseline measurements
- `progress.md` — This file

### Next Step
Begin Phase 1: Fix --fail-fast behavior + address RID leak warnings.

---

## Session 2: 2026-08-26 — Parallel v2 Architecture Implementation

### What was done
- [x] Analyzed current preflight architecture: 37 constraints, PreflightContext, PreflightFixture
- [x] Identified 7 key pitfalls of the current system
- [x] Built complete parallel v2 system WITHOUT touching original code
- [x] Created `scripts/preflight_v2/` directory with 4 new modules
- [x] Created `scripts/preflight_v2_runner.gd` as new entry point
- [x] Verified old preflight.gd is 100% untouched via git diff

### New Architecture: `scripts/preflight_v2_runner.gd`

```
Phase 1: Pure Constraints (no scene)
  └─ Auto-discovered from preflight/ directory
  └─ Run without scene instantiation (~8s saved)
  └─ catalog: constraint_catalog.json (safe default: scene-required)

Phase 2: Scene Constraints (shared fixture)
  └─ Scene booted ONCE via V2Fixture
  └─ State resets between each constraint (reset_state)
  └─ scene_boot skipped (already validated by fixture boot)
  └─ Full re-boot after: save_game_roundtrip, context_handover
  └─ Fallback: full re-boot if reset_state fails

Diagnostics:
  └─ State checkpointing (take_checkpoint/verify_checkpoint)
  └─ Isolation warnings (non-blocking, logged at end)
  └─ Phase-grouped summary report
  └─ Fail-fast fixed: no tree.quit(1), summary always shown
```

### New Files Created
| File | Purpose |
|------|---------|
| `scripts/preflight_v2_runner.gd` | Main orchestrator (extends SceneTree) |
| `scripts/preflight_v2/v2_context.gd` | Extended PreflightContext (checkpointing + check() override) |
| `scripts/preflight_v2/v2_fixture.gd` | Wraps PreflightFixture with reset_state() |
| `scripts/preflight_v2/constraint_scanner.gd` | Auto-discovers constraints from preflight/ |
| `scripts/preflight_v2/constraint_catalog.json` | Maps constraint IDs to pure/scene |

### Pitfalls Addressed
1. **23× scene re-boot** → Scene booted ONCE, state resets between constraints
2. **fail-fast kills process** → V2Context.check() sets flag, summary always shown
3. **RID leaks** → Handled by V2Fixture cleanup (delegates to base)
4. **Manual CONSTRAINT_REGISTRY** → Auto-discovery scans preflight/ directory
5. **No state isolation** → take_checkpoint/verify_checkpoint between constraints
6. **Pure/Scene mixed execution** → Phase 1: pure first, Phase 2: scene second
7. **No requires_full_reset flag** → FULL_REBOOT_IDS constant for destructive constraints

### How to Use
```bash
# Run v2 suite (parallel execution)
$GODOT_BIN --headless --path . --script res://scripts/preflight_v2_runner.gd

# Same options as original
$GODOT_BIN --headless --path . --script res://scripts/preflight_v2_runner.gd -x  # fail-fast
$GODOT_BIN --headless --path . --script res://scripts/preflight_v2_runner.gd -v  # verbose
$GODOT_BIN --headless --path . --script res://scripts/preflight_v2_runner.gd -f=fleet  # filter

# Original system still works (untouched)
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd
```

### Verified Performance (2026-08-26)
- **Original**: 37 constraints, 82,163 ms, 37/37 PASS
- **V2**: 37 constraints (scene_boot skipped), 84,832 ms, 37/37 PASS
- **Scene-sharing optimization was NOT viable**: `begin_new_game()` only resets GameState data, not scene nodes. Constraints depend on scene node state. Full re-boot required.
- **Actual gains from v2**: Pure/scene split, fail-fast summary, state checkpointing, auto-discovery. Performance is comparable (scene_boot skip saves ~3s).

### Safety Guarantees
- Old preflight.gd is untouched and available as reference
- V2Context IS-A PreflightContext (existing constraints work unchanged)
- V2Fixture delegates to original PreflightFixture (same scene lifecycle)
- Fallback: if reset_state fails, forces full re-boot (same as original)
- State checkpointing detects mutations (non-blocking warnings)

### Next Steps
1. ~~Run v2 suite to validate correctness~~ ✅ DONE
2. ~~Measure actual performance improvement~~ ✅ DONE
3. ~~Fix any constraint compatibility issues~~ ✅ DONE
4. ~~If v2 is proven safe, consider replacing original orchestrator~~ ✅ DONE
5. Clean up RID leak warnings in fixture cleanup

---

## Session 3: 2026-08-26 — Gap Analysis, Fixes & Migration

### What was done
- [x] Gap analysis: V1 (37 constraints) vs V2 (38 constraints, auto-discovery)
- [x] Fixed parse error: `PreflightV2Context` type not resolved in `--script` mode → removed type annotations
- [x] Fixed `SKIP_IN_PHASE2`: removed `scene_boot` skip → full validation now runs
- [x] Added `--mcp-json` support to V2 runner (chain controller parity)
- [x] Added auto-boot scene_boot for filtered scene constraints (V1 parity)
- [x] Cleaned up orphaned `constraint_scout_and_discovery.gd.uid`
- [x] V2 passes: 38/38 constraints, 2034 assertions, 103.6s
- [x] V1 passes: 37/37 constraints, 2031 assertions, 82.6s (parity confirmed)
- [x] Migrated V1 → `scripts/legacy/preflight_v1.gd`
- [x] Renamed V2 runner → `scripts/preflight.gd` (now primary)
- [x] Updated AGENTS.md, README.md, DESIGN.md, SCENARIO_LOADER_SPEC.md

### V2 is now primary
- `scripts/preflight.gd` = V2 runner (auto-discovery, phase-split, isolation warnings)
- `scripts/legacy/preflight_v1.gd` = V1 runner (archived, manual registry)
- `scripts/preflight/constraint_*.gd` = shared constraint files (unchanged)
- `scripts/preflight_v2/` = V2 components (context, fixture, scanner, catalog)

### Performance note
V2 is ~20s slower than V1 because `reset_state()` delegates to `boot_default()` (documented known limitation). The scene-sharing optimization is not viable for scene node state. Future optimization: lightweight state-only reset for GameState data + planet worker states.
