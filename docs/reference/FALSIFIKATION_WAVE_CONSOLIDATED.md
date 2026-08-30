# Falsifikation Wave — Consolidated Issue Resolution Strategy

**Total Issues:** 27 (15 Verified Real, 2 False Positives, 10 Already Fixed/No Action)

---

## Consolidated Resolution Table

| ID | Issue | Category | Verified | Root Cause | Resolution Strategy | Priority | Effort |
|----|-------|----------|----------|------------|---------------------|----------|--------|
| **V-001** | Constraint count mismatch (badge 43 vs actual 44) | Doc/Code Sync | ✅ | ARCHITECTURE.md badge says 43, table has 43 entries, actual is 44 (historical_world missing) | 1. Update ARCHITECTURE.md badge to 44<br>2. Add `historical_world` to constraint table<br>3. Fix FINDINGS.md F-201 reference | CRITICAL | Low |
| **V-002** | Narrative Runtime gate count mismatch | Design Contract | ✅ | Design doc §13 says G1-G7, §15 says G1-G17, code has G1-G24 | Update NARRATIVE_ENGINE_DESIGN.md §13 and §15 to G1-G24 | CRITICAL | Low |
| **V-003** | Autoload count (10 in project.godot) | Doc Sync | ✅ | DESIGN.md updated, ARCHITECTURE.md may be stale | Verify ARCHITECTURE.md reflects 10 autoloads | CRITICAL | Low |
| **D-001/D-007** | ARCHITECTURE.md constraint table incomplete | Doc/Code Sync | ✅ | 43 entries, missing `historical_world`, `narrative_runtime` at #27 but count says 43 | Regenerate constraint table to 44 entries with all constraints | CRITICAL | Medium |
| **D-006** | DOKI checks count (9 vs 10) | Doc Sync | ✅ | ARCHITECTURE.md line 317 says "9 Integrity Checks", code has 10 (Check 10 File Limit missing) | Update ARCHITECTURE.md line 317 to "10 Integrity Checks" | CRITICAL | Low |
| **C-002** | Scope resolver auto-managed timing | Code Logic | ✅ | AUTO_MANAGED list correct, but scope manifest timing issue with doki finalize | Add tolerance for auto-managed files appearing in staged set post-manifest in `change_impact_resolver.gd` | MEDIUM | Medium |
| **C-001** | Narrative Runtime G5 gate coverage | Verification | ✅ | Gate checks comprehensive, no violations found | No code fix needed; add audit comment confirming G5 coverage | LOW | None |
| **I-001** | Slot 0 protection in Preflight | Verification | ✅ | Headless guard exists, no test writes to slot 0 | No code fix needed; protection verified working | LOW | None |
| **C-004** | DOKI Check 9 hardcoded limits | Code Quality | ✅ | Check 9 uses magic numbers 99,14,1 instead of config | Add limits to doki config (narrators.json or new limits.json), read in verifier | HIGH | Medium |
| **I-003** | Mood never repeated not in Verifier | Verification Gap | ✅ | Only implicit via RNG replay in Check 9, Analyzer has explicit check | Add explicit Mood uniqueness check to Verifier (Check 4b or new check) | HIGH | Medium |
| **M-001** | Save versioning/migration missing | Architecture | ✅ | SAVE_VERSION=1 exists, NO migration logic, NO migration test | Implement migration system (version bump, migration functions, registry) | HIGH | High |
| **T-001** | Save migration not tested | Test Gap | ✅ | Constraint only tests current-format roundtrip | Add migration test to `constraint_save_game_roundtrip.gd` | HIGH | Medium |
| **M-006** | Tutorial invisible to MCP | QA/Testing | ✅ | TutorialDirector extends Node not Control, not in scan tree | Make TutorialDirector discoverable by `runtime_ux_scan` (extend Control or register) | HIGH | Low |
| **S-004** | V2Fixture reset_state leak | False Positive | ❌ | Stand-ins are tree-less, no leak | No fix needed; mark as resolved false positive | NONE | None |
| **V-004** | Legacy V1 reference in docs | False Positive | ❌ | Accurate reference, legacy removed in ab080dc | No fix needed; documentation correct | NONE | None |

---

## Resolution Execution Order

### Phase 1: Critical Doc/Code Sync (Do First — Blocks Everything)
1. **V-001** → Update ARCHITECTURE.md badge + table + FINDINGS.md
2. **V-002** → Update NARRATIVE_ENGINE_DESIGN.md §13, §15
3. **V-003** → Verify ARCHITECTURE.md autoload count
4. **D-001/D-007** → Regenerate full constraint table (44 entries)
5. **D-006** → Fix DOKI checks count in ARCHITECTURE.md

### Phase 2: High-Priority Code Fixes
6. **C-004** → Add config-driven limits to DOKI Check 9
7. **I-003** → Add explicit Mood uniqueness check to Verifier
8. **M-006** → Make TutorialDirector MCP-discoverable
9. **M-001** → Implement save migration system
10. **T-001** → Add migration test to save constraint

### Phase 3: Medium/Low
11. **C-002** → Fix scope resolver auto-managed tolerance
12. **C-001** → Add audit comment for G5 coverage
13. **I-001** → Add verification comment for Slot 0 protection
14. **S-004** → Mark resolved in FINDINGS.md
15. **V-004** → Mark resolved in FINDINGS.md

---

## Conflict Resolution Strategy

### When Multiple Issues Touch Same File
| File | Conflicting Issues | Resolution |
|------|-------------------|------------|
| `ARCHITECTURE.md` | V-001, V-003, D-001, D-006, D-007 | Single atomic commit updating all affected sections |
| `NARRATIVE_ENGINE_DESIGN.md` | V-002 | Single commit updating §13 and §15 |
| `scripts/doki/doki_verifier.gd` | C-004, I-003 | Single commit adding config + new check |
| `scripts/preflight_v2/constraint_save_game_roundtrip.gd` | M-001, T-001 | Single commit adding migration + test |

### Dependency Graph
```
V-001 → D-001/D-007 (same file, do together)
V-002 (independent)
V-003 (independent)
D-006 (independent)
C-004 + I-003 (same file, do together)
M-001 → T-001 (migration must exist before test)
M-006 (independent)
C-002 (independent, after DOKI flow stable)
```

### Atomic Commit Groups
1. **Group A (Docs):** V-001, V-003, D-001, D-006, D-007, V-002 → 1-2 commits
2. **Group B (DOKI Verifier):** C-004, I-003 → 1 commit
3. **Group C (Save System):** M-001, T-001 → 1-2 commits
4. **Group D (MCP QA):** M-006 → 1 commit
5. **Group E (Scope):** C-002 → 1 commit
6. **Group F (Audit/Close):** C-001, I-001, S-004, V-004 → 1 commit (FINDINGS.md updates)

---

## Verification Gates Per Group

| Group | Pre-Commit Verification |
|-------|------------------------|
| A | `$GODOT_BIN --headless --path . --script res://scripts/preflight.gd -f concept_index` |
| B | `$GODOT_BIN --headless --path . --script res://scripts/doki/doki_selfcheck.gd` |
| C | `$GODOT_BIN --headless --path . --script res://scripts/preflight.gd -f save_game_roundtrip` |
| D | `$GODOT_BIN --headless --path . --script res://scripts/testing/mcp_capture_entry_test.gd` |
| E | `$GODOT_BIN --headless --path . --script res://scripts/preflight.gd -f concept_index --scope=.doki/scope.json` |
| F | `$GODOT_BIN --headless --path . --script res://scripts/doki/doki_analyze.gd` |

---

## Success Criteria

- [ ] All 15 verified issues resolved
- [ ] 2 false positives documented as resolved in FINDINGS.md
- [ ] Preflight passes: `RESULT: PASSED` (44 constraints)
- [ ] DOKI selfcheck passes: 65 tests
- [ ] MCP capture test passes
- [ ] ARCHITECTURE.md badge = 44, table = 44 entries
- [ ] NARRATIVE_ENGINE_DESIGN.md §13/§15 = G1-G24
- [ ] Save migration test exists and passes
- [ ] TutorialDirector discoverable by MCP UX scan