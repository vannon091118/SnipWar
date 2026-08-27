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
  → XorShift128 (32-Bit-maskiert, 10×Warmup — kein SplitMix) → `cXjXnXaXpX`
- **Narrator** via `n % 14` (1-14), **Mood** via `j % 10` (nie zweimal hintereinander)
- SidePlot-Erkennung bei Merge (`MERGE_HEAD`), Arc-Gewicht + ARC_CLIMAX-Trigger,
  Relationship-Sentiment zum Vorgänger-Narrator
- Schreibt `.doki/prompt.txt` (System + User) für den Agenten

**Arc-Gewicht ist Kategorie-basiert** (`classify_impulse`):
- CODE/FEATURE → volles Gewicht, CLIMAX möglich
- REFACTOR/BUILD → halbes Gewicht, CLIMAX möglich
- FIX/DOKU/TRIVIAL/TEST-ASSET → kein Gewicht, **nie CLIMAX**
  (Prompt: "WARTUNGSABSCHNITT" statt "STAFFELFINALE" via `arc_climax_eligible`)

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
- Nach Erfolg schreibt `finish` nur `.commit_msg.txt` (Fehlschlag = Disk unberührt).
  `CHANGELOG.md`/`change_index.json` entstehen erst in `finalize` NACH dem Commit
  (transaktional — kein Orphan-Eintrag mehr bei gescheitertem Commit)
- `verify-only` (commit-msg Hook) = gleiche Checks, keine Nebenwirkungen; bei
  idle + DOKI-HEAD-Message: chain-verankerter **Amend-Modus** (Checks 1-8)

### 4. `git commit -F .commit_msg.txt`
- **pre-commit:** Preflight-Gate + DOKI-Gate (Session verified? Snapshot-Match?
  `.commit_msg.txt` da? — Rebase/Amend werden erkannt und übersprungen)
- **commit-msg:** `verify-only` re-validiert
- **post-commit:** finalize MUSS gelingen, sonst wird der Push abgebrochen (siehe §5)

**Amend eines DOKI-Commits nach finalize:** `doki amend --body-file <f>` liest die
HEAD-Message, ersetzt nur den Narrator-Body (Subject/Tokens/Arc/Reason-Zeilen
bleiben), verifiziert chain-verankert (Checks 1-8) und schreibt `.commit_msg.txt`.
Danach: `git commit --amend -F .commit_msg.txt`. finalize aktualisiert beim nächsten
Lauf den Entry-Hash (Composite-Abgleich).

> **Hooks ohne `GODOT_BIN` (asymmetrisch):** Fehlt die Godot-Binary (oder ist sie
> nicht ausführbar), blockiert **pre-commit** mit Exit 1 (Preflight + DOKI-Gate
> laufen nicht), während **commit-msg** mit Exit 0 durchlässt (Verifikation
> übersprungen) und **post-commit** finalize überspringt, aber trotzdem pusht.
> `GODOT_BIN` ist also Voraussetzung für das vollständige Commit-Gate.

### 5. `finalize` (post-commit Hook, automatisch)
- Chain-Append: `{seq, hash, composite, mood, narrator, model_id, summary, subject,
  data_changes}` (`summary` = erste Body-Zeile, `subject` = echter Git-Subject
  inkl. „— nach <Vorgänger>" — Grundlage für die Kausalitäts-Analyse)
- ChangeIndex `commits`-Map mit Git-Hash verknüpfen (analysierter Index aus der Session)
- Arc-Advance prüfen (ARC_CLIMAX → Phasenwechsel); der NÄCHSTER-ARC-Vorschlag des
  Narrators („NÄCHSTER ARC: <Name> — <Thema>" im Body-Epilog) wird als Name/Thema
  des neuen Bogens übernommen
- `narrative_chain.json` + `change_index.json` + `scripts/doki/data/arcs.json` +
  `CHANGELOG.md` stagen (reisen mit dem nächsten Commit; CHANGELOG-Eintrag entsteht
  erst HIER — nach dem Commit, kein Orphan)
- `.commit_msg.txt`, `.doki/prompt.txt`, `.doki/narrator_body.md` aufräumen →
  kein Dirty-State. **Idempotent.**

### 6. Determinismus
Gleicher Chain-Zustand + gleicher Impuls + gleicher Diff = gleicher Narrator,
gleicher Mood, gleicher Composite. **Kein** Zeit-/Zufalls-Input in prepare/derive.

## 🔬 Narrative-Qualitäts-Analyse

```bash
$GODOT_BIN --headless --path . --script res://scripts/doki/doki_analyze.gd
```

Prüft die **logische Konsistenz** dessen, was DOKI geschrieben hat:

1. **Narrator-Fussspur** — wer erzählt wann (SEED vs. DOKI getrennt)
2. **Mood-Progression** — Regel „nie zweimal gleich" (Verstoß = ERROR)
3. **Composite-Integrität** — c/p-Folge **lückenlos** (`c == prev+1`, wie Check 9a) +
   strikte Format-Validierung (`^c\d+j\d+n\d+a\d+p\d+$`)
4. **Kausalität** — wird der Vorgänger-Narrator im echten Git-Subject erwähnt?
   (Warnung wenn nicht; liest das `subject`-Feld der Chain, Fallback `summary`)
5. **Arc-Verlauf** — Themen pro Bogen + `arcs.json`-Status (aktiv/completed)
6. **Beziehungs-Matrix** — wer folgt auf wen (Übergänge)
7. **Subject-Stile pro Erzähler** — Stimmen-Konsistenz sichtbar
8. **CHANGELOG-Sync** — Einträge vs. echte DOKI-Commits, **bidirektional**
   (weniger Einträge = Doku hinkt, mehr Einträge = Orphan-Verdacht)

Befunde am Ende: `0 Fehler / N Warnungen` = Stellen für Nachbesserung.

## 🛠 Recovery

| Situation | Lösung |
|-----------|--------|
| Crash zwischen commit und finalize | `doki repair` (holt Chain-Append nach) |
| Abgebrochener prepare | `doki repair` (Session-Reset) |
| rebase/amend/force-push | `doki repair` (Chain-Anker neu verankern) |
| Stale `.commit_msg.txt` | Gate blockt (Snapshot-Mismatch) → `doki prepare` erneut |
| Orphan im CHANGELOG | Analyzer-Modul 8 (mehr Einträge als Commits) → Migration `doki-tools/doki_migrate.py` |

## 🧪 Tests

```bash
# Determinismus-/Verifier-Regressionen (35 Checks, kein Git nötig):
$GODOT_BIN --headless --path . --script res://scripts/doki/doki_selfcheck.gd

# 5-Commits-E2E mit echter Git-Historie (NUR im Test-Worktree, NIEMALS im Haupt-Worktree!):
# Hard-Guard: der Test blockt im Haupt-Worktree (git-dir == <repo>/.git) —
# Ausnahme nur mit Env-Flag DOKI_STORY_TEST_ALLOW=1.
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
| Root | `doki.gd` (CLI), `doki_selfcheck.gd`, `doki_story_test.gd`, `doki_analyze.gd` | Einstieg + Tests + Analyse |