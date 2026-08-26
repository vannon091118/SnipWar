# DOKI CommitLayer — Das Commit-Gate

Deterministischer Commit-Narrator für das SnipWar-Repo. Jeder Commit bekommt eine
strukturierte narrative Commit-Message — erzählt von einer von 14 virtuellen Personas
(selektiert via Composite-Hash), mit 10 möglichen Mood-Overlays.

## 🧱 Separation of Concerns (verpflichtend)

**DOKI ist ein reines Commit-Gate.** Es läuft zwar im Repo, hat aber **keinerlei
Kontakt zu MCP, Nipper, Agent-Systemen oder Spiel-Logik**:

- ❌ Keine Imports/Autoloads aus dem Spiel, `addons/`, MCP o. Ä.
- ❌ Keine Signale/Events an andere Systeme
- ✅ Einzige Schnittstellen: **Git-Befehle** (`DOKI_GitHelper`) und **eigene Dateien**
  (`.doki/`, `narrative_chain.json`, `change_index.json`, `CHANGELOG.md`,
  `.commit_msg.txt`, `.githooks/`)
- ✅ Alles liegt unter `scripts/doki/`, Schichten strictly inward-only:

```
core (Rng/Verifier) ← chain (Stores) ← character ← prompt ← orchestration (Flows)
```

`orchestration` darf nur nach innen zeigen. Neue Komponenten müssen diese Schichtung
behalten — sonst ist die Separation gebrochen.

## 🎭 Der 3-Zustands-Flow

```
Idle ── prepare ──▶ Prepared ── finish ──▶ Verified ── git commit ──▶ Idle (finalize)
```

### 1. `prepare "<impuls>"` (idle → prepared)
- Ladet Chain-State aus `narrative_chain.json`
- **Composite** deterministisch: `Djb2(prevComposite + TreeHash + DiffHash + Impuls)`
  → XorShift128 (+ SplitMix-Avalanche, 32-Bit-Maskierung) → `cXjXnXaXpX`
- **Narrator** via `n % 14` (1-14), **Mood** via `j % 10` (nie zweimal hintereinander)
- SidePlot-Erkennung bei Merge (`MERGE_HEAD`), Arc-Gewicht + ARC_CLIMAX-Trigger,
  Relationship-Sentiment zum Vorgänger-Narrator
- Schreibt `.doki/prompt.txt` (System + User) für den Agenten

### 2. Agent schreibt den Body
Der Agent liest `prompt.txt` und schreibt die Commit-Erzählung **in der Rolle des
Charakters** als Fließtext (keine Bullets).

### 3. `finish --body-file <datei>` (prepared → verified)
- **ChangeIndexEngine** extrahiert F-xxx/C-xxx-Entitäten aus `git diff --cached`
  (mit Zeilennummern, stabile IDs über Commits)
- **CommitOrchestrator** baut die Message (`[NARRATOR:]`, `[MODEL:]`, `[IMPULSE:]`,
  `[COMPOSITE:]`, Arc-Block, maschinengenerierte Begründungszeilen je Datei)
- **9 Checks** (1-6 weich, 7-9 HARTER BLOCK):
  1. Pflicht-Tokens + Wortzahl (Charakter-Regeln)
  2. Impuls-Integration im Body
  3. Storytelling (kein Bullet-Überhang, kausale Konnektoren)
  4. Narrator-Token == Composite-n
  5. Composite-Format + Felder == Session
  6. Cross-Narrator (Vorgänger erwähnt)
  7. **Kausalität:** IMPULSE-Anker + Composite ist Ketten-Nachfolger der Session
  8. **DocSync:** CHANGELOG/change_index existieren + keine ungestagten Diffs
  9. **ChainAudit:** c-Folge lückenlos, kein Doppel-Append, **RNG-Replay** == Session
- Erst nach Erfolg: `CHANGELOG.md` + `change_index.json` + `.commit_msg.txt`
  schreiben und stagen
- `verify-only` (commit-msg Hook) = gleiche Checks, keine Nebenwirkungen

### 4. `git commit -F .commit_msg.txt`
- **pre-commit:** Preflight-Gate + DOKI-Gate (Session verified? Snapshot-Match?
  `.commit_msg.txt` da? — Rebase/Amend werden erkannt und übersprungen)
- **commit-msg:** `verify-only` re-validiert

### 5. `finalize` (post-commit Hook, automatisch)
- Chain-Append: `{seq, hash, composite, mood, narrator, model_id, summary, data_changes}`
- ChangeIndex `commits`-Map mit Git-Hash verknüpfen
- Arc-Advance prüfen (ARC_CLIMAX → Phasenwechsel)
- `narrative_chain.json` + `change_index.json` stagen (reisen mit dem nächsten Commit)
- `.commit_msg.txt` aufräumen → kein Dirty-State. **Idempotent.**

### 6. Determinismus
Gleicher Chain-Zustand + gleicher Impuls + gleicher Diff = gleicher Narrator,
gleicher Mood, gleicher Composite. **Kein** Zeit-/Zufalls-Input in prepare/derive.

## 🛠 Recovery

| Situation | Lösung |
|-----------|--------|
| Crash zwischen commit und finalize | `doki repair` (holt Chain-Append nach) |
| Abgebrochener prepare | `doki repair` (Session-Reset) |
| rebase/amend/force-push | `doki repair` (Chain-Anker neu verankern) |
| Stale `.commit_msg.txt` | Gate blockt (Snapshot-Mismatch) → `doki prepare` erneut |

## 🧪 Tests

```bash
# Determinismus-/Verifier-Regressionen (35 Checks, kein Git nötig):
$GODOT_BIN --headless --path . --script res://scripts/doki/doki_selfcheck.gd

# 5-Commits-E2E mit echter Git-Historie (NUR im Test-Worktree, NIEMALS im Haupt-Worktree!):
$GODOT_BIN --headless --path <test-worktree> --script <abs>/doki_story_test.gd --repo <pfad>
```

## 🗂 Dateien

| Bereich | Datei | Zuständigkeit |
|---------|-------|---------------|
| core | `xorshift128.gd`, `rng_engine.gd` | PRNG + Composite-Derivation |
| core | `verifier.gd` | 9 Checks (soft/hard) |
| chain | `chain_store.gd`, `session_store.gd`, `change_index_store.gd` | Persistenz |
| character | `narrator_catalog.gd`, `mood_overlay.gd` | 14 Charaktere × 10 Moods |
| prompt | `voice_composer.gd`, `relationship_engine.gd`, `sideplot_engine.gd`, `arc_engine.gd` | Prompt-Engine |
| orchestration | `commit_orchestrator.gd` (Koordinator), `session_builder.gd`, `message_builder.gd`, `artifact_writer.gd`, `git_helper.gd` | Flow-Wiring |
| orchestration/flows | `prepare_flow.gd`, `finish_flow.gd`, `finalize_flow.gd`, `gate_flow.gd`, `status_flow.gd` | Zustandsübergänge |
| data | `narrators.json`, `moods.json`, `arcs.json` | Charakter-/Mood-Daten |
| Root | `doki.gd` (CLI), `doki_selfcheck.gd`, `doki_story_test.gd` | Einstieg + Tests |