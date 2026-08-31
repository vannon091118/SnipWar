---
goal: Historical Economy State and Visualization
version: 1.0
date_created: 2026-08-30
last_updated: 2026-08-30
owner: Buffy
status: 'Planned'
tags: [feature, architecture, history, economy, visualization]
---

# Introduction

![Status: Planned](https://img.shields.io/badge/status-Planned-blue)

This plan defines the smallest complete slice for making deterministic economy state observable in the historical simulation, in the historical UI, and in the live in-game economy HUD without changing unrelated gameplay systems.

## 1. Requirements & Constraints

- **REQ-001**: `HistorySimulator` must compute deterministic per-faction economy state from the existing `WorldState.process_economy_turn()` results for every emitted `HistoricalSnapshot`.
- **REQ-002**: `HistoricalSnapshot` must serialize and restore the economy state without mutating simulation data or changing existing snapshot fields.
- **REQ-003**: `HistoricalWorldBootstrap` must update the historical presentation from the currently selected snapshot, not from only the first snapshot.
- **REQ-004**: `HistoricalRenderer` must visibly associate the selected snapshot's economy stock with owned planets while preserving existing ownership and development rendering.
- **REQ-005**: `SimulationOverlay` must display the selected snapshot's faction economy summary and remain valid when the summary is empty.
- **REQ-006**: The live HUD must continue to use the existing `EconomyDomain`/`VaultBar` entry points for current credits and income; no duplicate economy source may be introduced.
- **CON-001**: Reuse `WorldState`, `HistoricalSnapshot`, `HistoricalWorldBootstrap`, `HistoricalRenderer`, `SimulationOverlay`, `EconomyDomain`, and `VaultBar`; do not create a parallel economy model.
- **CON-002**: Preserve deterministic event ordering, seeded simulation behavior, snapshot playback, save/load compatibility, and existing live economy semantics.
- **CON-003**: Do not modify unrelated assets, global preflight behavior, DOKI artifacts, or other slices.
- **GUD-001**: Use typed dictionaries and existing Godot 4.7.2 APIs; keep presentation code free of simulation mutation.
- **PAT-001**: Drive all historical visual updates through `PlaybackController.snapshot_changed` and assert state transitions through headless entry tests.

## 2. Implementation Steps

### Implementation Phase 1

- GOAL-001: Extend the historical data path with deterministic economy state.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-001 | Add `economy_state: Dictionary` to `scripts/history/historical_snapshot.gd`; include it in `to_dict()` and read it in `from_dict()` with an empty-dictionary default for older snapshots. |  |  |
| TASK-002 | In `scripts/history/simulation/history_simulator.gd::_capture_snapshot`, copy `WorldState.factions` economy stock, income, upkeep, net balance, and territory into `snapshot.economy_state` without consuming RNG or mutating `WorldState`. |  |  |
| TASK-003 | Keep `scripts/state/domains/economy_domain.gd`, `scripts/objects/planets/economy_manager.gd`, and `scripts/ui/vault_bar.gd` as the sole live economy path; verify no historical code writes live credits. |  |  |

### Implementation Phase 2

- GOAL-002: Connect selected historical snapshots to their presentation surfaces.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-004 | In `scripts/bootstrap/historical_world_bootstrap.gd::_on_snapshot_changed`, call both `HistoricalRenderer.show_snapshot(snapshot)` and `SimulationOverlay.set_economy_state(snapshot.economy_state)` in the same callback. |  |  |
| TASK-005 | In `scripts/ui/history/historical_renderer.gd::_apply_visual_state`, read the selected owner's economy data and append the stock value to the existing development label while retaining the existing fallback when no economy data exists. |  |  |
| TASK-006 | In `scripts/ui/history/simulation_overlay.gd`, build one `EconomySummary` container, expose `set_economy_state`, replace its contents on update, and clear prior ticker children on year changes. |  |  |

### Implementation Phase 3

- GOAL-003: Prove the real lifecycle and finish the release gate.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-007 | Add `scripts/testing/history_economy_behavior_test.gd` to run `HistorySimulator.simulate_with_snapshots` with multiple factions and planets, assert non-empty economy snapshots, assert stock changes across snapshots, and assert `HistoricalSnapshot.to_dict()/from_dict()` equality for economy data. |  |  |
| TASK-008 | Run the focused behavior test through Godot headless and verify snapshot ordering, empty-input handling, and repeated presentation updates using the existing playback entry points. |  |  |
| TASK-009 | Run `compile_gate.gd`, the focused historical behavior test, relevant historical playback tests, `git diff --check`, and the full preflight; record failures without reclassifying unrelated failures as passing. |  |  |

## 3. Alternatives

- **ALT-001**: Read economy values directly from `GameState` during historical rendering. Rejected because historical presentation must remain snapshot-driven and deterministic.
- **ALT-002**: Add a second history-specific economy simulator. Rejected because `WorldState.process_economy_turn()` already provides the canonical historical balance.

## 4. Dependencies

- **DEP-001**: `WorldState.process_economy_turn()` must continue updating stock, income, and upkeep before snapshot capture.
- **DEP-002**: `PlaybackController.snapshot_changed` must emit the selected `HistoricalSnapshot` in order.
- **DEP-003**: Godot 4.7.2 headless runtime and the repository's existing compile/test scripts must be available.

## 5. Files

- **FILE-001**: `scripts/history/historical_snapshot.gd` — historical economy data model and serialization.
- **FILE-002**: `scripts/history/simulation/history_simulator.gd` — deterministic economy snapshot capture.
- **FILE-003**: `scripts/bootstrap/historical_world_bootstrap.gd` — snapshot-to-presentation synchronization.
- **FILE-004**: `scripts/ui/history/historical_renderer.gd` — planet economy visualization.
- **FILE-005**: `scripts/ui/history/simulation_overlay.gd` — faction economy summary.
- **FILE-006**: `scripts/state/domains/economy_domain.gd` — unchanged live economy source.
- **FILE-007**: `scripts/objects/planets/economy_manager.gd` — unchanged live tick entry point.
- **FILE-008**: `scripts/ui/vault_bar.gd` — unchanged live HUD consumer.
- **FILE-009**: `scripts/testing/history_economy_behavior_test.gd` — focused behavior coverage.

## 6. Testing

- **TEST-001**: A seeded simulation with two owned planets emits ordered snapshots containing economy values for each live faction.
- **TEST-002**: Economy stock differs between an early and late snapshot when `process_economy_turn()` produces a non-zero net balance.
- **TEST-003**: Snapshot serialization round-trips economy values exactly and older dictionaries without `economy_state` load with an empty dictionary.
- **TEST-004**: Playback selection invokes renderer and overlay updates for the same snapshot; no first-snapshot-only state remains.
- **TEST-005**: Empty economy data does not crash overlay or renderer presentation.
- **TEST-006**: Compile, focused historical tests, and formatting checks pass; unrelated full-suite failures remain explicitly reported.

## 7. Risks & Assumptions

- **RISK-001**: Existing historical scene boot may fail independently because of missing assets or chronicle setup; those failures must be reported separately from economy behavior.
- **RISK-002**: Existing headless Godot reload warnings may appear during compile-gate scanning without indicating a source parse failure.
- **ASSUMPTION-001**: The existing snapshot schema version and migration behavior can accept an optional economy dictionary without requiring a save-version bump.
- **ASSUMPTION-002**: `WorldState` remains the canonical historical economy source and is not replaced by live `EconomyDomain` state.

## 8. Related Specifications / Further Reading

- `plan/infrastructure-session-scoped-verification-1.md`
- `scripts/history/simulation/world_state.gd`
- `scripts/history/simulation/history_simulator.gd`
- `scripts/history/historical_snapshot.gd`
- `scripts/history/playback_controller.gd`
- `scripts/ui/history/historical_renderer.gd`
- `scripts/ui/history/simulation_overlay.gd`
