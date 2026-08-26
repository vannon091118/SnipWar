# Preflight System: Performance & Security Audit → Implementierung

## Goal
Transform the SnipWar Preflight Suite from a "works but slow and incomplete" state into a **high-performance, security-guaranteeing CI gate** that runs on an FX 6300 / GTX 1050 / 12GB RAM in under 30 seconds and where "green" truly means "code is clean, all functions work, falsification confirmed, test safety."

## Hardware Context
- CPU: AMD FX 6300 (4C/4T, ~3.5 GHz, weak single-thread) → CPU is the bottleneck
- GPU: GTX 1050 (irrelevant for headless)
- RAM: 12 GB (sufficient for Godot headless)
- OS: Windows 11

## Current State
- 36 registered constraints + 1 unregistered (dead_code)
- ~23 scene-dependent constraints each re-instantiate world.tscn
- 73 `await tree.process_frame` calls (~1.2s overhead)
- No state isolation between constraints (mutation leaks)
- No static/type-check validation
- `--fail-fast` kills process before summary report
- No signal-connection verification

---

## Phase 1: Quick Wins — dead_code registrieren + fail-fast fixen
**Status:** not_started
**Estimated:** 15 min

- [ ] Register `constraint_dead_code.gd` in `CONSTRAINT_REGISTRY` (pure, no scene boot)
- [ ] Fix `--fail-fast`: replace `tree.quit(1)` in `check()` with `ctx.early_exit = true` flag, break in orchestrator after constraint, still run summary
- [ ] Verify with `git diff` that changes are minimal and correct

### Decision: Where to place dead_code in registry
**Chosen:** After `concept_index` (last entry), before end of array. It's the cheapest pure constraint.

---

## Phase 2: Scene-Sharing — Biggest Performance Win
**Status:** not_started
**Estimated:** 2-3 hours
**Target savings:** 18-35 seconds (60-70% of total runtime)

- [ ] Analyze current boot lifecycle in detail (preflight_fixture.gd `boot_default`)
- [ ] Design `reset_state()` method: GameState wipe + selective re-seed without scene destroy/recreate
- [ ] Modify preflight.gd orchestrator:
  - Phase A: Run ALL pure constraints first (14 constraints, no scene needed)
  - Phase B: Boot scene ONCE
  - Phase C: For each scene constraint, call `reset_state()` instead of `boot_default()`
- [ ] Add `reset_state()` to `PreflightFixture`:
  - Call `game_state.call("begin_new_game", ...)` to wipe state
  - Re-deal resources with fixed seed
  - Re-disable automation (economy, cpu_ai)
  - Re-run `_baseline_errors()` as sanity check
- [ ] Handle edge cases: `save_game_roundtrip` calls `request_new_run` at end — ensure this doesn't break the shared fixture
- [ ] Handle `context_handover` which does full scene switching — may need special handling
- [ ] Test: run full suite and compare PASS/FAIL results with baseline

### Decision: Reset strategy
**Options considered:**
1. Full scene re-instantiate (current) — expensive but safe
2. GameState-only reset with scene reuse — fast but risky if scene state leaks
3. Hybrid: reuse scene normally, full re-boot only after save_game_roundtrip and context_handover

**Chosen:** Option 3 (Hybrid). Most constraints can share the scene. Only `save_game_roundtrip` (which does `request_new_run`) and `context_handover` (which does full scene switching) need a fresh boot after them.

---

## Phase 3: State-Checkpointing für bessere Isolation
**Status:** not_started
**Estimated:** 1-2 hours

- [ ] Add `snapshot_state()` to `PreflightContext` — captures key GameState metrics
- [ ] Add `restore_and_verify_state()` — restores from snapshot and verifies integrity
- [ ] Insert checkpoint/restore between each scene constraint in orchestrator
- [ ] Log state delta when restore fails (which constraint mutated state unexpectedly)
- [ ] Add `await_frames(count)` helper method to reduce individual await calls

---

## Phase 4: Security-Audit-Checks erweitern
**Status:** not_started
**Estimated:** 1-2 hours

- [ ] Add signal-connection verification to `scene_boot` constraint:
  - Check critical signals: `faction_changed`, `resource_generated`, `workers_spawn_requested`
- [ ] Add autoload-order validation:
  - Verify GameState, SaveGameService, EventLog, SceneDirectorService are present and in expected order
- [ ] Add GDScript parse-error detection:
  - Scan all `.gd` files for syntax errors using `GDScript.parse()` at suite start
  - Report errors before running any constraint
- [ ] Add `.tres`/`.tscn` integrity verification:
  - For each loaded resource, verify `validate().is_empty()` (most resources already have this)
  - Add to a new `constraint_resource_integrity` or fold into existing `scene_boot`

---

## Phase 5: Performance Profiling & Final Tuning
**Status:** not_started
**Estimated:** 30 min

- [ ] Run full suite before and after all changes, capture timing
- [ ] Compare per-constraint timings to identify remaining hotspots
- [ ] Reduce unnecessary `await_frame()` calls where possible
- [ ] Add `--profile` flag to show timing breakdown in summary
- [ ] Validate that total runtime < 30 seconds on FX 6300

---

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| (none yet) | — | — |

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Hybrid reset (not full re-boot) | ~80% of scene constraints don't break scene state. Only save_roundtrip and context_handover need fresh boot. |
| dead_code goes last in registry | It's a non-blocking heuristic — cheapest pure constraint. |
| fail-fast sets flag, not quit() | Summary report is critical for debugging. Early exit without summary defeats the purpose. |
