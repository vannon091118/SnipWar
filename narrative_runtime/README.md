# Narrative Runtime — MVP A + Relationship/Belief/Memory State

The runtime is a deterministic, stdlib-only projection of the repository's DOKI
chain. It never writes `narrative_chain.json`, `change_index.json`, Git metadata,
or DOKI session files. SQLite under `state/` is disposable and gitignored.

## Commands

```text
python -m narrative_runtime import
python -m narrative_runtime rebuild
python -m narrative_runtime verify
python -m narrative_runtime status
python -m narrative_runtime derive
python -m narrative_runtime context
python -m narrative_runtime.gate_cli --root .
```

`derive` reports the derived row counts. Exit codes are 0 for success, 1 for
other runtime errors, 2 for `HISTORY CHANGED` (rebuild required), and 3 for an
invalid or gapped chain.

## Implemented state

- Chain observations and deterministic projections.
- Transactional, idempotent SQLite archive with amend/rebase anchors.
- Evidence-aware directed relationship effects across eight independent axes;
  reverse relationships are never inferred and narrative event IDs are distinct
  from directed effect IDs.
- The relationship state materializes exactly 14 × 13 = 182 directed pairs,
  with every axis clamped to `0.0..1.0` and every snapshot tied to an observation
  sequence and versioned decay rule.
- Relationship classifications remain separate from observations and support
  `REPAIR_AFTER_CHANGE`, `REGRESSION_CONFIRMED`, `DISAGREEMENT`, and
  `EXPLICIT_ADMISSION` when deterministic evidence exists. Later evidence may
  upgrade a classification without mutating the original observation.
- Knowledge state is evidence-bound through `known_traits`, `known_events`,
  `known_beliefs`, `interpretation`, and `expectations`. No look-ahead evidence
  is stored in observations.
- Conservative beliefs: only explicit structural claims are projected, and each
  transition carries an observation evidence sequence.
- Immutable event memory with a derived emotional weight that decays without
  deleting the historical record.
- Bounded character-state axes for future consumers; no state is written back to
  Git/DOKI truth and the Composite is untouched.
- Evidence-bound thread lifecycle with a deterministic merge threshold; weak
  overlap stays split and participant overlap alone never links threads.
- Explicit structured counter-evidence lowers belief confidence; arbitrary
  subject prose never creates a contradiction.

## Current schema additions

`relationship_events`, `relationship_state_history`, `character_state_history`,
`beliefs`, `memory`, `threads`, `thread_events`, `perspectives`, and `conflicts` are rebuilt from the complete observation set in the same
transaction as an import. Existing MVP-A tables remain authoritative for raw
facts. The `context` command exports a read-only `narrative_context/v1` JSON bridge only
when SQLite exactly verifies against the current chain and change index. Missing,
empty, or stale state returns an explicit unavailable response, allowing DOKI to
use its existing fallback without changing Composite or narrator selection.
The local NARRATIVE_RUNTIME_GATE validates G1–G7: stdlib-only imports, observation purity, reproducible IDs, contiguous chains, no source-truth writes, idempotent imports, and rebuild/incremental equality. Run it with `python -m narrative_runtime.gate_cli --root .`.

The runtime does not yet implement social candidates, X, analytics, or community
features. Threads, perspectives, conflict projections, and relationship
classification/effect projections are deterministic local state. The local gate
now validates G1–G17, including eight-axis coverage, 182-pair structure,
evidence-bound effects, no-look-ahead observations, deterministic state, and
batch-independent projections.
