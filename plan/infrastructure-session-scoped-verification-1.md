---
goal: Session-Scoped Verification Contract
date_created: 2026-08-30
last_updated: 2026-08-30
owner: Buffy
status: 'In Progress'
tags: [infrastructure, architecture, process, verification, doki, preflight]
---

# Introduction

![Status: Planned](https://img.shields.io/badge/status-Planned-blue)

This plan introduces one repository-enforced verification contract that maps the actual staged change to semantic impact and required verification. DOKI, the canonical V2 Preflight runner, and Git hooks will consume the same resolved scope; unknown, empty, stale, or under-scoped changes fail closed while full verification remains available.

## 1. Requirements & Constraints

- **REQ-001**: Resolve the actual staged change into affected subsystem and contract identifiers using repository code, not agent-supplied filter guesses.
- **REQ-002**: Resolve each affected contract into the complete required Preflight constraint set, including transitive dependencies.
- **REQ-003**: Preserve `scripts/preflight.gd` V2 shared-fixture, pure/scene split, reset-state, watchdog, isolation, and destructive-reboot behavior.
- **REQ-004**: Keep full mode equivalent to the current 44-constraint baseline and preserve existing CLI compatibility unless a replacement is atomically validated.
- **REQ-005**: Reject empty manifests, unknown paths, unknown contracts, unknown constraints, duplicate IDs, and unresolved impact with nonzero exit status.
- **REQ-006**: Make DOKI distinguish declared file scope from machine-resolved required verification scope.
- **REQ-007**: Bind the prepared staged bytes to immutable content digests and reject any post-prepare staged-byte drift.
- **REQ-008**: Prevent silent scope mixing between concurrent agents in one worktree; use explicit ownership identity and reject conflicting active sessions.
- **REQ-009**: Keep global mandatory integrity checks active for scoped runs: compile, chain manifest, entry validation, DOKI verification, and documented baseline invariants.
- **REQ-010**: Preserve the canonical EconomyConfig source for starting credits and verify relevant ship-part, event/history, save, and reset state through existing architecture rather than adding duplicated constants.
- **REQ-011**: Measure real before/after runtime for representative full and scoped runs; do not publish estimates as guarantees.
- **CON-001**: Do not maintain two competing scope registries or two competing canonical Preflight runners.
- **CON-002**: Do not infer semantic impact from filename-to-test string matching alone.
- **CON-003**: Do not weaken baseline capture, reset safety, watchdogs, isolation checks, MCP verdicts, or failure exit codes in scoped mode.
- **CON-004**: Do not overwrite unrelated staged, unstaged, untracked, or auto-managed changes.
- **CON-005**: Do not auto-normalize or silently rewrite staged bytes during verification.
- **GUD-001**: Reuse `ConstraintScanner`, `PreflightContext`, `PreflightFixture`, `PreflightCodeIndex`, DOKI stores, and existing hook entrypoints.
- **GUD-002**: Prefer explicit contract metadata on existing constraint definitions or their canonical registry over a parallel file-to-test guesser.
- **GUD-003**: Keep pure impact resolution deterministic and testable without scene boot; run scene constraints once through the existing shared fixture.
- **PAT-001**: Use fail-closed result objects with `ok`, stable error codes, resolved scope, and evidence paths.
- **PAT-002**: Treat a prepared scope as a content-addressed snapshot of staged paths and staged bytes, not merely a path list.

## 2. Implementation Steps

### Implementation Phase 1

- GOAL-001: Establish the canonical semantic impact model and validate its completeness against the existing constraint registry.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-001 | Add explicit stable subsystem and contract metadata to the canonical Preflight constraint discovery records in `scripts/preflight_v2/constraint_scanner.gd` and the existing constraint declarations; preserve each current constraint ID and `requires_scene` classification. | ✅ DONE — centralized `_CONTRACT_CONSTRAINTS` + `_PATH_CONTRACTS` in `constraint_scanner.gd` | 2026-08-30 |
| TASK-002 | Add a deterministic staged-path impact resolver in a new existing-architecture module under `scripts/preflight_v2/`; read `git diff --cached --name-status` and reject rename/copy/status forms that are not explicitly mapped instead of guessing. | ✅ DONE — `change_impact_resolver.gd` + `resolve_status` | 2026-08-30 |
| TASK-003 | Define complete contract-to-constraint closure, including transitive contracts for `game_state.gd`, domain files, save/history files, hooks, DOKI files, and Preflight files; reject any changed path with no mapping unless it is explicitly classified as documentation-only or auto-managed. | ✅ DONE — canonical path→contract map, unknown/auto-managed handled | 2026-08-30 |
| TASK-004 | Add machine-readable scope output containing changed paths, affected contracts, required constraint IDs, global mandatory gates, registry version, and deterministic digest; ensure the output is stable for the same staged tree. | 🔵 PARTIAL — resolver outputs paths/contracts/constraints; `.doki/scope.json` manifest | 2026-08-30 |

### Implementation Phase 2

- GOAL-002: Add canonical scoped execution while preserving V2 safety and full-mode behavior.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-005 | Extend `scripts/preflight.gd` with a manifest-based scoped entrypoint that accepts only a generated manifest, validates every constraint ID against `ConstraintScanner`, rejects empty/unknown/duplicate scope, and uses the existing `_run_one`, shared fixture, reset, checkpoint, watchdog, and destructive reboot paths unchanged. | ✅ DONE — `--scope=<manifest|ids>`; empty/unknown/duplicate are FATAL nonzero | 2026-08-30 |
| TASK-006 | Keep `--filter` as a developer convenience only; make it non-authoritative for commit verification and preserve full mode with no scope manifest as the complete registry pipeline. | ✅ DONE — full mode unchanged when no scope manifest | 2026-08-30 |
| TASK-007 | Ensure scoped summaries and `--mcp-json` include resolved scope, omitted constraints, baseline identity, global gates, exit status, and evidence without reporting a zero-constraint run as PASS. | 🔵 PARTIAL — reuses existing summary/MCP; scope failure is fatal-nonzero | 2026-08-30 |
| TASK-008 | Add a canonical scope resolver CLI/library entrypoint used by both DOKI and the hook; prohibit each consumer from independently reconstructing semantic impact. | ✅ DONE — resolver + `.doki/scope.json` consumed by gate + pre-commit hook | 2026-08-30 |

### Implementation Phase 3

- GOAL-003: Bind DOKI preparation, verification, and hook execution to the same staged content and resolved scope.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-009 | Extend `scripts/doki/chain/session_store.gd` session schema with scope manifest digest, staged byte digest, changed-path digest, resolved contract IDs, required constraint IDs, baseline identity, and ownership token; keep old sessions invalid rather than silently upgrading them. | | |
| TASK-010 | In the prepare flow, generate the scope from the actual staged index, persist exact staged path/byte digests and resolved verification scope, and fail before prompt creation when impact is unknown or scope resolution is empty. | | |
| TASK-011 | In `scripts/doki/core/verifier.gd` and gate orchestration, recompute staged path and byte digests and reject any mismatch with the prepared session; validate that the executed Preflight evidence matches the stored required constraint set. | | |
| TASK-012 | Replace the pre-commit hook’s unconditional Preflight invocation with the canonical scope resolver plus scoped Preflight, while always running compile, chain manifest, chain entry, DOKI, and other mandatory global integrity gates. | | |
| TASK-013 | Add explicit single-worktree session ownership checks in DOKI prepare/gate; reject a second active owner unless the current session is idle and its artifacts have been finalized or repaired. | | |
| TASK-014 | Preserve post-commit finalization ordering and push behavior; ensure finalize failure prevents push and does not silently clear a verified session. | | |

### Implementation Phase 4

- GOAL-004: Prove boundary behavior, baseline equivalence, state coverage, and measured performance.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-015 | Add assertion-backed tests under `scripts/testing/` for exact mapping, transitive impact, under-scope rejection, over-scope omission, invalid/empty scope, and deterministic manifest output. | | |
| TASK-016 | Add byte-drift tests that prepare a file, alter staged bytes, and verify DOKI gate rejection without normalizing or rewriting the file. | | |
| TASK-017 | Add parallel-ownership tests for conflicting same-worktree sessions and independent worktree/session identities; ensure ambiguity exits nonzero. | | |
| TASK-018 | Add scoped-baseline tests that compare baseline capture and post-reset state against the existing verified fixture, including credits from EconomyConfig, ship-part state, event/history state, save state, and reset state. | | |
| TASK-019 | Add full-mode regression checks for `--filter`, reverse order, fail-fast, destructive constraints, watchdog, MCP JSON, discovery failure, reset failure, and unchanged 44-constraint coverage. | | |
| TASK-020 | Measure representative full and scoped runs with real wall-clock timing, record `before_ms`, `after_ms`, `saved_ms`, and `saved_percent` in the affected metrics documentation, and label hardware/environment conditions. | | |

### Implementation Phase 5

- GOAL-005: Synchronize documentation and complete the release gate.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-021 | Update `AGENTS.md`, `ARCHITECTURE.md`, `DESIGN.md`, `docs/README.md`, `scripts/doki/README.md`, and relevant runner help text so canonical runner, scope resolution, baseline, hook behavior, ownership, and full/scoped invocation are identical to the implementation. | | |
| TASK-022 | Update `ROADMAP.md`, `docs/FINDINGS.md`, `CHANGELOG.md`, `change_index.json`, `narrative_chain.json`, and metrics only through the normal DOKI flow; do not hand-edit auto-managed DOKI artifacts outside that flow. | | |
| TASK-023 | Run compile, focused scope tests, full Preflight, DOKI selfcheck, chain manifest, chain entry, relevant save/history/ship tests, and the complete regression suite; record exit codes and machine-readable evidence. | | |
| TASK-024 | Review the final staged diff for unrelated contamination, verify prepared bytes equal staged bytes and commit bytes, run the configured DOKI gates, create the local commit, and push only after all required gates pass. | | |

## 3. Alternatives

- **ALT-001**: Maintain a standalone path-to-constraint JSON registry. Rejected because it creates a second semantic authority beside constraint metadata and will drift when files or contracts change.
- **ALT-002**: Continue using `--filter` strings selected by agents. Rejected because filters are not deterministic semantic impact resolution and can silently under-scope a commit.
- **ALT-003**: Run all 44 constraints for every commit. Rejected because it preserves safety but fails the requested session-scoped performance objective and does not encode semantic impact.

## 4. Dependencies

- **DEP-001**: Existing `ConstraintScanner` registry and `requires_scene` classification in `scripts/preflight_v2/constraint_scanner.gd`.
- **DEP-002**: Existing V2 `PreflightContext`, `PreflightFixture`, shared baseline, reset, checkpoint, watchdog, and full-reboot behavior.
- **DEP-003**: Existing DOKI session, chain, verifier, orchestration, and artifact stores under `scripts/doki/`.
- **DEP-004**: Git index and `git diff --cached` as the authoritative staged-change source.
- **DEP-005**: Existing Godot 4.7.2 headless executable and repository test infrastructure.
- **DEP-006**: Existing canonical EconomyConfig, ShipPart catalog, EventBus/History, SaveGameService, and related constraints.

## 5. Files

- **FILE-001**: `scripts/preflight.gd` — canonical full/scoped CLI and fail-closed scope execution.
- **FILE-002**: `scripts/preflight_v2/constraint_scanner.gd` — canonical constraint metadata and registry validation.
- **FILE-003**: `scripts/preflight_v2/` scope-resolution module — deterministic staged-change impact and manifest generation.
- **FILE-004**: `scripts/doki/chain/session_store.gd` — prepared scope, byte digests, ownership, and baseline metadata.
- **FILE-005**: `scripts/doki/core/verifier.gd` — prepared/staged scope and byte-lock validation.
- **FILE-006**: `scripts/doki/orchestration/` flow modules — shared scope resolution, gate evidence, and lifecycle integration.
- **FILE-007**: `.githooks/pre-commit`, `.githooks/commit-msg`, `.githooks/post-commit` — scoped verification and ownership enforcement.
- **FILE-008**: `scripts/testing/` — assertion-backed contract, drift, ownership, baseline, regression, and timing tests.
- **FILE-009**: `AGENTS.md`, `ARCHITECTURE.md`, `DESIGN.md`, `docs/README.md`, `scripts/doki/README.md` — synchronized operational documentation.
- **FILE-010**: `ROADMAP.md`, `docs/FINDINGS.md`, `CHANGELOG.md`, `change_index.json`, `narrative_chain.json`, and metrics artifacts — lifecycle documentation updated through DOKI.

## 6. Testing

- **TEST-001**: A staged change mapped to contracts X/Y resolves exactly the declared transitive constraint set and emits a deterministic manifest digest.
- **TEST-002**: A declared scope missing a required transitive constraint exits nonzero before any green verification result.
- **TEST-003**: A scope containing an unrelated constraint is rejected or reported as over-scoped according to the canonical policy without omitting required constraints.
- **TEST-004**: Missing, malformed, empty, duplicate, and unknown scope manifests all exit nonzero.
- **TEST-005**: Changing staged bytes after prepare causes DOKI gate failure with a digest mismatch and leaves file bytes unchanged.
- **TEST-006**: A second active owner in the same worktree is rejected; independent worktree identities do not collide.
- **TEST-007**: Scoped execution uses the same verified baseline, shared fixture, reset, isolation, watchdog, MCP verdict, and mandatory global gates as full execution.
- **TEST-008**: Full mode still discovers and executes all 44 constraints with the existing V2 one-boot/shared-fixture behavior.
- **TEST-009**: Full regression covers filter, reverse, fail-fast, destructive reboot, discovery failure, reset failure, watchdog, compile, chain manifest, and chain entry behavior.
- **TEST-010**: Timing evidence records real before/after wall-clock values and derives savings only from those measurements.

## 7. Risks & Assumptions

- **RISK-001**: A path may affect a contract not represented in metadata; unresolved impact must block rather than silently pass.
- **RISK-002**: Existing DOKI auto-managed artifacts may be staged before prepare; scope resolution must distinguish user changes from generated lifecycle artifacts without ignoring their byte integrity.
- **RISK-003**: Shared-worktree parallel agents may race on `.doki/session.json`; ownership locking must fail closed and avoid destructive cleanup.
- **RISK-004**: Scoped scene constraints may expose hidden fixture dependencies; the contract must model those dependencies explicitly instead of skipping constraints.
- **RISK-005**: Git filters and Windows line-ending settings may alter worktree bytes; digests must be computed over the exact staged blob representation used by the gate.
- **RISK-006**: Existing leak warnings may remain environmental or pre-existing; they must be triaged against changed code and not silently treated as proof of scope correctness.
- **ASSUMPTION-001**: The existing V2 runner and constraint scanner remain the canonical baseline and can expose stable metadata without duplicating the runner.
- **ASSUMPTION-002**: One active DOKI session per worktree is the supported operational model unless explicit ownership support is implemented.
- **ASSUMPTION-003**: Push is permitted by the configured workflow only after a validated commit; no force-push or destructive Git operation is required.
- **ASSUMPTION-004**: Existing save, economy, ship-part, and history contracts can be referenced by impact metadata without introducing a new save version.

## 8. Related Specifications / Further Reading

- `AGENTS.md` — repository workflow, V2 Preflight, DOKI, and hook contracts.
- `ARCHITECTURE.md` — current V2 runner and subsystem architecture.
- `scripts/doki/README.md` — DOKI state machine, checks, and recovery behavior.
- `docs/AUDIT_3_REPRODUCIBILITY.md` — historical provenance and transient-input limitations.
- `docs/FINDINGS.md` — active QA and architecture findings.
