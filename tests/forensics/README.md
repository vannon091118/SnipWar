# 🔬 DOKI — Forensic Instruments (AUDIT 3)

Read-only verification tooling extracted from the AUDIT-3 session (`2026-08-29`).
These are **diagnostic instruments**, not production CI gates: they reproduce the
empirical claims of `docs/AUDIT_3_REPRODUCIBILITY.md` against the live repo and
make the verdict re-checkable by any future agent. They never mutate DOKI logic,
chain files, or the git index.

## Why this directory exists

The audit's central finding is `HISTORICALLY NON-REPLAYABLE`: the RNG-seed inputs
(`tree_hash`, `diff_hash`, `limits`, `mood_pool`) lived only in the transient,
gitignored `.doki/session.json` and were discarded on `finalize`. The instruments
below keep the *evidence* of that finding reproducible — they turn the one-shot
scratch probes that uncovered the verdict into stable, re-runnable checks.

If these instruments were deleted, a future agent could not confirm whether the
finding still holds after DOKI evolves. Keeping them is the audit's own point:
don't destroy the measuring instruments after they surface an uncomfortable truth.

## Instruments

| File | Purpose | Depends on |
|------|---------|-----------|
| `historical_replay.gd` | Replays the 10 **seeded** composites through the **real** `DOKI_RngEngine`. Documents that none are reproducible by current code. | Godot, `DOKI_RngEngine` |
| `chain_history_reconstruction.py` | Reconstructs inputs from **git objects** (`^{tree}`, parent, commit diff, `[IMPULSE:]`) and replays the real DOKI entries (`seq ≥ 11`). | Python 3 (stdlib-only), git |
| `immutability_gate.py` | Verifies that every chain entry's **provenance fields** (`composite`, `mood`, `narrator`, `c/j/n/a/p`, `arc`, `p_id`) are byte-stable across the committed chain history. | Python 3 (stdlib-only), git |

**Deliberately excluded** (AUDIT-3 scratch, not durable):
`audit3_bforce_seed.py` (brute-force seed reconstruction = reverse-engineering lab
equipment, must never become a gate) and `audit3_replay.py` (one-shot duplicate of
the seeded replay already covered by `historical_replay.gd`).

## Run

```bash
# Reproducibility/replay — real Godot engine (Windows path per AGENTS.md)
GODOT_BIN="C:/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT_BIN" --headless --path . --script res://tests/forensics/historical_replay.gd

# Replay from git objects (no Godot needed)
python3 tests/forensics/chain_history_reconstruction.py

# Chain immutability (full coverage, all entries)
python3 tests/forensics/immutability_gate.py
```

All three are pure reads of `narrative_chain.json` + git; they never write.

## Fixed verdict (per AUDIT 3)

- Determinism: `JA` — same inputs → same output (RNG core byte-identical since `a95a7ee`).
- Reproducibility: `NEIN` — RNG-seed inputs were only transient / not archived.
- Provenance: `STARK` — each entry is pinned to a commit (`hash`, tree, `[COMPOSITE:]`).
- Global verdict: `HISTORICALLY NON-REPLAYABLE`.