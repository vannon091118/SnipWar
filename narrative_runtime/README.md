# Narrative Runtime MVP A

The runtime is a deterministic, stdlib-only projection of the repository's DOKI
chain. It never writes `narrative_chain.json`, `change_index.json`, Git metadata,
or DOKI session files. SQLite under `state/` is disposable and gitignored.

## Commands

From the repository root:

```text
python -m narrative_runtime import
python -m narrative_runtime rebuild
python -m narrative_runtime verify
python -m narrative_runtime status
```

Optional `--root`, `--db`, `--chain`, and `--index` arguments support isolated
fixtures and tests. Exit codes are 0 for success, 1 for other runtime errors, 2
for `HISTORY CHANGED` (rebuild required), and 3 for an invalid or gapped chain.

## MVP A guarantees

- All observations are source facts plus named deterministic projections only.
- Event IDs are reproducible from sequence, commit hash, and schema version.
- Incremental import checks the complete stored prefix, including commit hashes
  and raw-entry digests; amend/rebase rewrites fail closed.
- Imports are transactional and idempotent.
- Rebuild produces the same observation dump and aggregate hash.
- No network, third-party package, X integration, DOKI hook, or Composite change
  is present in this MVP.
