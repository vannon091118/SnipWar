# AUDIT 3 — Historische Reproduzierbarkeit & unveränderliche Provenienz

**Datum:** 2026-08-29 · **Modus:** READ-ONLY · **Repo:** `github.com/vannon091118/SnipWar`
**Scope:** DOKI CommitLayer (`scripts/doki/`), `narrative_chain.json`, `change_index.json`, `arcs.json`, `docs/METRICS_TRACKER.md`, Git-Historie.

Alle Replay-Ergebnisse dieses Dokuments sind **empirisch** erzeugt: Die Composite-Reproduktion
lief sowohl über eine Python-Portierung des RNG als auch über die **echte**
`DOKI_RngEngine`/`DOKI_XorShift128` per headless Godot. Beide sind **byte-genau identisch**
(liefern für dieselben Inputs exakt dieselben 10 Seeds), wodurch die Portierung verifiziert ist.

---

## 0. Kurzbefund (TL;DR)

- Der DOKI-Composite ist **deterministisch** (gleiche Inputs → gleiches Ergebnis, nachgewiesen).
- Er ist für **keinen** historischen Eintrag **reproduzierbar** (nachgewiesen, siehe §3).
- Provenienz ist **stark**: Jeder Entry ist fest an einen Git-Commit gebunden
  (`hash`, Tree, `[COMPOSITE:]`/`[IMPULSE:]` im Commit-Body).
- Die bestimmenden RNG-Inputs (`tree_hash`, `diff_hash`, `limits`, `mood_pool`) liegen **ausschließlich**
  in der transienten, gitignored Session (`.doki/session.json`), die nach jedem `finalize` verworfen wird.
- **→ HISTORICALLY NON-REPLAYABLE.**

---

## 1. DOKI INPUT GRAPH

Rekonstruiert **aus dem Code** (`prepare_flow.gd`, `commit_orchestrator.gd`, `rng_engine.gd`,
`xorshift128.gd`, `session_builder.gd`, `finish_flow.gd`, `finalize_flow.gd`, `git_helper.gd`,
`arc_engine.gd`, `relationship_engine.gd`, `sideplot_engine.gd`, `change_index_engine.gd`,
`metrics_updater.gd`).

### 1.1 Berechnungskette

```
PREPARE (idle → prepared)
  staged          = git diff --cached --name-only
  tree_hash       = git rev-parse HEAD^{tree}          ← HEAD = PARENT des künftigen Commits
  diff_output     = git diff --cached                   (Roh-String des staged Diffs)
  diff_hash       = str( djb2(diff_output) )            ← String des djb2-Ints
  impulse         = Agent-Impuls (CLI-Parameter)
  arc_state       = arcs.json (active arc, arc_count, seen_entities, weight, climax_weight)
  mood_pool       = moods.json["mood_pool"] (Fallback default_pool())
  limits          = {j:99, n:14, a:max(1, arc_count), p: entries.size()+1}
  prev_composite  = letzter Chain-Entry.composite
  prev_mood       = letzter Chain-Entry.mood
  ↓
  seed            = djb2( prev_composite + tree_hash + diff_hash + impulse )     [32-Bit, Codepoints]
  rng             = DOKI_XorShift128(seed)   (init: s1 = seed*1812433253+1, 10×Warmup-_step)
  c               = prev.c + 1  (Sequenz, kein RNG)
  j               = rng.nextInt(1,  99+1)
  n               = rng.nextInt(1,  14+1)
  a               = rng.nextInt(1,  arc_count+1)
  p               = rng.nextInt(1,  p_limit+1)
  mood            = select_mood(j, prev_mood, mood_pool)   (posmod, garantiert ≠ prev_mood)
  ↑ oben entscheidet NUR der Mood-Pool den Label; die Composite-Ziffern c/j/n/a/p sind
    von mood_pool UNABHÄNGIG.
  ↓ Ableitungen (Narrativ-Ebene, deterministisch aus Chain+Diff):
  impulse_class   = VoiceComposer.classify_impulse(impulse)   (Regex-Heuristik)
  tone/structure  = decode_j(j, moods.decoding())
  narrator        = NarratorCatalog.by_index(n)               (narrators.json)
  prev_narrator   = Chain.previous_narrator(narrator) (rückwärts)
  relationship    = RelationshipEngine(prev_narrator, Chain)
  sideplot        = SidePlotEngine (nur bei Merge: MERGE_HEAD/Branch/Commits)
  arc_forecast    = ArcEngine.forecast_weight(arc, entity_ids, merge, impulse_class)
  search_context  = GitHelper.search_context(staged, impulse)
                    (läuft global_search.gd gegen den AKTUELLEN Checkout + ConceptIndex)
  prompt          = VoiceComposer.build_prompts(ctx)   (System+User, enthält search_context)
  session         = {...alle obigen...}                → .doki/session.json  (gitignored)

FINISH (prepared → verified; AGENT schreibt narrativen body)
  message         = MessageBuilder.assemble(session, body, analyze)
                    Subject via build_subject(narrator, impulse, file_count, prev_narrator)
                    [COMPOSITE:], [IMPULSE:], [MODEL:], [PREV_NARRATOR:], Arc-Zeile, Begründungszeilen
  verifier        = 10 Checks (1–6 weich, 7–10 hart); Check 9 replays aus SESSION
  session.body    = body (vom Agent, NICHT deterministisch)

GIT COMMIT (außerhalb DOKI, `git commit -F .commit_msg.txt`)

FINALIZE (verified → idle; idempotent)
  entry           = append_entry(hash, composite, mood, narrator, model_id, summary(body),
                                 subject, prev_narrator, prev_model, data_changes, arc_id,
                                 p_id(seq), c, j, n, a, p)          → narrative_chain.json
  date            = entry_timestamp(seq) = genesis_date-Tag + posmod(seq,24):00:00  (SYNTHETISCH)
  change_index    = link_commit(hash, p_id, composite, c, entity_ids)   → change_index.json
  arc_advance     = ArcEngine.advance(...)  → arcs.json (bei Climax Arc-Wechsel + name vom Agent)
  artifacts       = CHANGELOG.md / change_index.json / arcs.json / narrative_chain.json änderung+stage
  session.reset() ← RNG-Eingaben VERWORFEN  (!!!)
```

### 1.2 Input-Tabelle (für §2)

| # | Input | Erzeugung | ⌕archiviert? |
|---|-------|-----------|--------------|
| G1 | Git HEAD (parent) | `git rev-parse HEAD` | ja, in Git |
| G2 | Parent | entry.hash^ | ja, in Git |
| G3 | Tree (HEAD^{tree}) | prepare | **nein** (nur transient in Session) |
| G4 | Diff (cached) | prepare | **nein** (nur Session) |
| G5 | diff_hash = djb2(diff) | prepare | **nein** (nur Session) |
| G6 | staged scope | prepare | ja (file_snapshot in Session [transient], Diff in Git) |
| G7 | Impulse | CLI | **ja: `[IMPULSE:]` im Commit-Body** |
| G8 | Prompt | prepare | ja (in Session [transient], verworfen) |
| G9 | Such-Kontext | prepare | ja (Session [transient]); Ergebnis läuft __heute gegen anderen Code/Checkout__ → nicht stabil |
| G10 | ConceptIndex-Ergebnis | prepare | ja (in Session/prompt [transient]) |
| G11 | Narrator-Pool | narrators.json | ja (Versioniert, aber keine Version gespeichert) |
| G12 | Mood-Pool | moods.json | **nein** (in Session [transient]) |
| G13 | Arc-State | arcs.json | ja (versioniert), aber kein `a_limit`-Snapshot |
| G14 | RNG-Version | Code | nein, nicht je Entry |
| G15 | RNG-Seed | djb2(...) | **nein** (nur Session [transient]) |
| G16 | RNG-Inputs (prev+tree+diff+impulse) | prepare | **nein** (nur Session) |
| G17 | Gewichte (Arc, Relationship) | Code (Konstanten) | nein, nicht je Entry |
| G18 | Thresholds / Climax | Code | nein |
| G19 | Modell | model_id im CLI (`claude-sonnet-4`) | ja (je Entry) |
| G20 | Commit-Message-Generierung | `build_subject` | **nur der Subject/Volltext des Commits**; die Generierungsfunktion nicht versioniert |
| G21 | Composite-Berechnung | `derive` | Ergebnis ja (je Entry); Methode nicht |
| G22 | Timestamp-Erzeugung | `entry_timestamp` = genesis_date + seq%24 | **synthetisch**; genesis_date ist eine einmalige, ungesicherte Wall-Clock-Input |
| G23 | Change-Index-Daten | `analyze` + `link_commit` | ja (p_id, composite, c, entity_ids je Commit); lines/history ja |
| G24 | Narrative-Chain-Daten | `append_entry` | ja (alle Ausgaben), **nicht die Eingaben** |

---

## 2. Historische Replay-Fähigkeit (je Input)

Kategorien: `ARCHIVED` = fest im Repo · `RECONSTRUCTABLE` = aus Git zurückrechenbar ·
`DERIVABLE` = aus anderen archivierten Werten berechenbar · `MISSING` = nirgends erhalten ·
`MUTABLE` = veränderbar, kein Schutz · `AMBIGUOUS` = je nach Code/Zeitpunkt nicht eindeutig.

| Input | Status | Kommentar |
|-------|--------|-----------|
| Git HEAD / Parent / Tree (G1–G3) | **DERIVABLE** | aus commit.hash + `^{tree}`/`^` zurückrechenbar |
| Diff / diff_hash (G4–G5) | **MISSING** | Rohdiff in Git (parent..commit), aber belegte Abweichung zum prepare-`--cached`-String → **HISTORICAL REPLAY GAP** |
| staged scope (G6) | RECONSTRUCTABLE | aus commit-Diff; Reihenfolge/Exaktheit fraglich |
| Impulse (G7) | **ARCHIVED** | `[IMPULSE:]` im Commit-Body |
| Prompt (G8) | MISSING | nur transient |
| Such-Kontext (G9/G10) | MISSING/AMBIGUOUS | transient + heutiger Checkout ≠ historischer → nicht stabil reproduzierbar |
| Narrator-Pool (G11) | AMBIGUOUS | Datei versioniert, Version nicht je Entry |
| Mood-Pool (G12) | MISSING | nur transient |
| Arc-State (G13) | AMBIGUOUS | arcs.json versioniert, a_limit-Snapshot fehlt |
| RNG-Version (G14) | AMBIGUOUS | rng_engine.gd seit `a95a7ee` unverändert; je Entry nicht gespeichert |
| **RNG-Seed (G15)** | **MISSING** | nur transient → **HISTORICAL REPLAY GAP** |
| RNG-Inputs (G16) | MISSING | nur transient → **HISTORICAL REPLAY GAP** |
| Gewichte/Thresholds (G17/G18) | AMBIGUOUS | Code versioniert, nicht je Entry |
| Modell (G19) | ARCHIVED | `model_id` je Entry |
| Commit-MSG-Methode (G20) | AMBIGUOUS | Code versioniert, nicht je Entry |
| Composite-Methode (G21) | AMBIGUOUS | rng unverändert, Aufrufer (`prepare_flow`) verändert |
| Timestamp (G22) | **MUTABLE / synthetisch** | genesis_date einmalig, nicht archiviert als verifizierter Fakt; Stunden = seq%24 (künstlich) |
| Change-Index (G23) | ARCHIVED | je Commit `{p_id, composite, c, entities}` |
| Chain-Daten (G24) | ARCHIVED (Ausgabe), MISSING (Eingabe) | Composite/Narrator/Mood/Arc ja; seed/diff/tree/limits nein |

**Fazit:** Der einzige Verschlusspunkt des Gesamtsystems (der Seed und seine 4 Bestandteile)
ist **nur transient** vorhanden. Über Git ist der Seed **nicht** zurückrechenbar
(§3 empirisch belegt). → **zentrale `HISTORICAL REPLAY GAP`.**

---

## 3. Composite-Replay (empirisch)

Getestet: 16 Einträge. Methode: aktueller `derive` auf die aus Git rekonstruierbaren Inputs
(bzw. für Seeds die vollständig rekonstruierbaren Commit-Daten). Verifiziert via echte
`DOKI_RngEngine` (Godot) UND Python-Port — identische Ergebnisse.

### 3.1 Seeded-Einträge 1–10 (erzeugt durch `init --seed-last 10`)

Alle Eingaben (Subject, Commit-Hash, Commit-Tree, limits) sind **vollständig aus Git vorhanden**.
Trotzdem reproduziert der aktuelle `derive` **keinen** der 10 Composites:

```
 seq  stored         replay (aktuell)
  1   c1j86n14a1p1   c1j12n2a1p1    X
  2   c2j30n8a1p2    c2j74n13a1p1   X
  3   c3j70n14a1p2   c3j53n6a1p1    X
  ... alle 10 X
```

31 plausible Seed-Varianten (andere Reihenfolge, anderer diff_hash, anderes Impulse-Feld)
wurden gebruteforct — **keine** reproduziert irgendeinen Seeded-Composite.
→ Die Seeds wurden von einer **nicht im Repo vorhandenen Methode** erzeugt
(die `DOKI`-Implementierung wurde erst in Commit `a95a7ee` (= Entry 11) eingeführt, die Seeds
entstanden ~12 h früher am 26.08.). Es gibt **keinen historischen Code-Zweig**, der sie erneut
berechnen könnte. **Verdikt: `NOT REPRODUCIBLE`** (Methode fehlt im Repo).

### 3.2 Reale DOKI-Einträge 11–16 (aktueller Flow)

Eingaben rekonstruiert: prev_composite ← Chain, tree = parent^{tree}, impulse ← `[IMPULSE:]`-Token,
diff_hash ← `djb2(git diff parent..commit)`, limits ← p_id. Ergebnis: **kein** Composite reproduziert.

```
 seq  stored         replay(a git)
 11   c11j46n7a1p5   c11j72n8a1p4    X
 12   c12j11n13a1p1  c12j70n4a1p11   X
 ... alle X
```

Ursache: `diff_hash` war bei prepare = `djb2(git diff --cached)`; mein `git diff parent..commit`
ist zwar eine gute Näherung, stimmt aber **nicht byte-genau** (Index vs. Commit-Tree,
Zwischen-Stagings, CRLF/Encoding → exakte Codepoints). Da `diff_hash` (und `tree_hash`,
`limits`, `mood_pool`) **nirgends archiviert** ist, ist **keine unabhängige Reproduktion möglich**.
**Verdikt: `NOT REPRODUCIBLE`.**

### 3.3 Ergebnis je Eintrag

Alle 16 getesteten Einträge: **`NOT REPRODUCIBLE`** (aus Git + heutigem Code).
Kein einziger `REPRODUCED` oder `PARTIALLY REPRODUCED` auf der Composite-Ebene.
Determinismus ist gegeben, Verfügbarkeit der Eingaben fehlt.

---

## 4. Methoden-Versionierung

| Regel | historisch identifizierbar? |
|-------|------------------------------|
| RNG-Algorithmus (djb2/XorShift128) | **Ja, konstant**: byte-identisch seit `a95a7ee`; aber **keine Versionsnummer je Entry** |
| RNG-Version | **nein** je Entry |
| Gewichte (Arc/Relationship/Metrics) | **Δ**: `arc_engine` ändert sich bei `2bc5533` (kategorie-basierter Climax); kein Snapshot |
| Arc-Formeln | **Δ** (siehe oben); `advance`/`forecast_weight` je Entry nicht pinnt |
| Narrator-Pool | Datei versioniert, aber Version nicht je Entry |
| Mood-Pool | kein Snapshot je Entry |
| Keyword-Heuristiken (`classify_impulse`) | **Δ** (die Regex-Liste ist im Code, `historydata`), Version nicht je Entry |
| Tracker-Formeln | einzig `metrics_updater.gd` seit `af3a017`, Konstanten teils „empfohlen“ (weich) — keine Version |
| Prompt-Template | **Δ** (voice_composer), Version nicht je Entry |
| Search-Kontext | läuft __aktuell__ gegen anderen Code/Checkout; **keine fixe Version** |
| Normalisierung / Sortierreihenfolge | `metrics_updater` sortiert mit gdscript `sort_custom` — keine dokumentierte Stabilitätsgarantie |

**→ `METHOD VERSION GAP`:** Ein heutiger Agent kann die aktiv gewesene Regelversion eines
historischen Eintrags **nicht** sicher bestimmen (nur eingrenzen über Commit-Reihenfolge der
Code-Dateien, was für Seeds sogar vollständig scheitert).

---

## 5. Tracker als historische Messung

`metrics_updater.gd` **rechnet den Tracker aus dem aktuellen Chainzustand** (Verteilungen,
Scores, Paarungen, Sentiment-Punkte). Zu einem Eintrag N:

- Historische Zählwerte **sind** aus `chain.slice(≤ N)` + damaliger Formel rekonstruierbar —
  ABER die Formelversion ist nicht je Snapshot gespeichert (§4).
- Die Kopfzeile „Letzte Aktualisierung: `Time.get_datetime_string_from_system()`“ ist
  **Wall-Clock, nicht deterministisch** → exakt nicht reproduzierbar.
- Sortier-/Tie-Break (`sort_custom`) nicht spezifikationssicher.
- `METRICS_TRACKER.md` erst seit `f76388e` (Entry ~72) versorgt; die Vor-Geschichte existiert gar nicht.
- `metrics_updater` läuft als separates Skript (nicht Teil der finalize-Stage-Liste) →
  der Tracker kann sogar mit dem Chain-Inhalt **desynchronisieren** (aktuell: Header nennt `c92`,
  Chain-Datei hat 90 Entries, Session `c93`).

**→ `HISTORICAL METRIC REPLAY GAP` (teilweise):** Zählwerte ja (mit Formel-Audit),
exakte Tracker-Datei nein (Wall-Clock, Sortierinstabilität, Methodversion fehlt).
Verifikation gegen „aktuelle Formel“ zeigt Abweichungen v. a. bei Instabilität und Zeitstempel.

---

## 6. Immutable Evidence — Entwurf minimales Schema

Für vollständiges Replay müsste DOKI **pro Commit** zusätzlich archivieren (Eingaben, die heute
nur in der transienten Session liegen):

```text
commit_sha            — in Git; PROVENIENZ (bereits vorhanden)
parent_sha            — in Git, ableitbar
tree_sha              — ableitbar aus parent^{tree}; nur als Anker speichern (redundant, aber billig)
diff_hash             — NUR transient → MUSS archiviert werden  (KERN)
impulse               — bereits via [IMPULSE:] im Commit-Body (redundant, ok)
rng_algorithm/version — Konstante/Version, MUSS archiviert werden (KERN)
rng_seed              — NUR transient → MUSS archiviert werden  (KERN; wertvoll: 1 Int)
rng_input_hash        — == seed (redundant, entfällt wenn seed gespeichert)
narrator_pool_ver     — MUSS archiviert (oder Hash der Pool-Datei)
mood_pool_version     — MUSS archiviert (oder Hash)
arc_state_version     — MUSS archiviert (oder arcs.json-Hash)
metric_method_version — MUSS archiviert (für Tracker-/Sentiment-Replay)
composite             — bereits archiviert (Ausgabe)
result_hash           — signierte Kette von (prev_composite, seed, composite, pools-ver, method-ver)
                        → MUSS archiviert (NEU): macht Vergangenheit erkennbar-mutiert
```

**Klassifikation:** notwendig + nicht ableitbar = `diff_hash`, `seed`, `limits`(a_limit),
`narrator_pool_ver`, `mood_pool_ver`, `method_version`, `result_hash`. Aus Git ableitbar
(redundant) = `parent_sha`, `tree_sha`. Bereits vorhanden = `commit_sha`, `composite`, `impulse`.
Der **`result_hash`** ist der einzige Schutz gegen stille Mutation der Vergangenheit (§9).

---

## 7. CURRENT_ANCHOR vs HISTORICAL_ROOT (Befund, keine Architektur)

- **CURRENT_ANCHOR** = `chain.anchor` → wird in `repair()` bei rebase/amend/force-push auf
  aktuellen HEAD **neu verankert**. **Befund:** ist **beweglich**. `repairs[]` zeigt 13 solche
  Neu-Verankerungen. Aktuell steht der Anker **18 Commits hinter HEAD** (`f76388e32f` vs
  HEAD `b867cd7`, Entry 90) → der Anker kann sogar <b>veralten</b>/divergieren.
- **HISTORICAL_ROOT** existiert im Datenmodell **nicht explizit** — es gibt keinen fixen,
  unveränderlichen Wurzel-Anker (außer `genesis_date`/`genesis_composite`, die aber kein Git-Hash sind
  resp. Wall-Clock). **Keine saubere Trennung.**
- `ENTRY_COMMIT` = entry.hash ist fest und stabil; die Einträge selbst sind **immutabel
  (kommittiert)** — aber nur solange niemand `narrative_chain.json` neu schreibt.
- Ein **amended** Commit ändert `entry.hash`-Nachziehen (`_sync_amended_entry_hash`): der Eintrag
  „bleibt“, bekommt aber einen **neuen Hash** am selben Composite → Provenienz-Hash ist dann
  beweglich trotz „gleichem“ Eintrag.

**Befund:** `CURRENT_ANCHOR` darf wechseln (idempotente Recovery), `HISTORICAL_ROOT` wäre
unveränderlich — existiert aber nicht. Ein alter Entry kann erhalten bleiben (append-only),
`repair` verdeckt mit 5 Zeilen Log-Einträgen keine Kette, aber **rebase kann die Bedeutung des
Ankers verändern** (Anker = beweglicher Marker, kein Beweisanker).

---

## 8. Historische Mutation

Vergleich „erster kommittierter Chain-Zustand“ des Eintrags gegen den heutigen (alle 90 Entries):

- **Composite / mood / narrator / c / j / n / a / p / arc / p_id / date / summary: STABLE**
  — über die komplette Chain-Historie keinen Wert gefunden, der später geändert wurde.
- Einzige Änderung: Feld **`subject`** wurde später ergänzt (war `null`/fehlt bei Seq 11–19,
  dann aus dem Commit-Subject befüllt).

**Klassifikation:** `BENIGN MIGRATION` / `NORMALIZATION` (subject ergänzt). Keine
`REPAIR`-Mutation an Beweisfeldern gefunden. `HISTORICAL MUTATION` der Beweisdaten: **nicht
beobachtet** — aber **strukturell möglich** und nicht abgesichert (§9). `UNVERIFIED` = die
Elemente Reihenfolge/Ranking/Timestamp, die nicht kommittiert wurden (Session, recovery_log),
sind nicht auditierbar.

---

## 9. Content-Immutability

Kann ein alter DOKI-Eintrag **heute** verändert werden, ohne den Commit zu verändern?
**JA.** `narrative_chain.json` ist eine normale JSON-Datei ohne inhaltliche Adressierung;
`check_9` (RNG-Replay) prüft **nur die aktuelle Session**, nicht historische Einträge.
`repair`/`finalize` schreiben bei Amends Hashes nach. Migration/Re-seed/Rebuild/manual-edit sind
derzeit **nicht** durch eine Ergebnis-Signatur (`result_hash`) gewehrt. Ein Edit an Entry 17 im
Heute-Worktree würde an keiner Stelle erkannt (erst beim nächsten `append`-Audit liesse sich
allenfalls c-Folge auffinden). **→ Historische Tatsache ist heute still mutierbar; der einzige
Schutz ist, dass die Datei selbst kommittiert wird (append-only entwickelt, aber nicht erzwungen).**

---

## 10. Historical Root Replay

Für die Seeds 1–10: `git log --diff-filter=A` zeigt, dass **kein** Code vor `a95a7ee` existiert,
der die Seeds hätte berechnen können → eine Ausführung „altes Code + alter Zustand“ ist mangels
altern Code **nicht möglich** (die Methode stammt aus dem Vorgänger-System außerhalb des Repos).
Für Einträge 11+: Code vor Eintrag N ist über `git checkout N^` prinzipiell verfügbar, aber
RNG-Eingaben fehlen (§2/§1.2). **→ Historischer Zustand kann mit damaliger Logik nicht erneut
ausgeführt werden (Seeds: keine Logik; Realdoks: keine Eingaben).**

---

## 11. Old Code vs Current Code

- `rng_engine.gd` + `xorshift128.gd`: **byte-identisch seit `a95a7ee`** → keine Drift im RNG-Kern.
- Aufrufer `prepare_flow.gd` sich **geändert** (Arc-Forcast, Search-Kontext, Gates) → der
  Input-/Kontextraum driftet.
- Seeds sind **auch mit heutigem Code** nicht reproduzierbar → es ist keine alleinige
  „Heute-Code-auf-alt-Daten“-Ursache, sondern eine **Methode aus dem Vorgänger-System**.
- Realdok-Composites sind **auch mit heutigem-Code-auf-rekonstruierten-Daten** nicht
  reproduzierbar → hier fehlen **archivierte Eingaben**, nicht Code-Drift.

**→ Die Kombination aus beidem = `HISTORICAL METHOD DRIFT` (Seeds) + `HISTORICAL INPUT GAP`
(Realdoks).**

---

## 12. Replay Matrix (16 Einträge)

| Entry | Commit | Hist. Code verfüg. | Inputs archiviert | Method-Version bekannt | Composite-Replay | Narrator-Replay | Mood-Replay | Arc-Replay | Final |
|-------|--------|----|----|----|----|----|----|----|------|
| 1 (Seeded) | 2a43194 | nein (vor DOKI) | ja (Git) | nein | X | X | X | X | `NOT REPRODUCIBLE` |
| 2–10 (Seeded) | ced4704…bbf8763 | nein | ja (Git) | nein | alle X | alle X | alle X | alle X | `NOT REPRODUCIBLE` |
| 11 (Realdok) | a95a7ee | ja | nein (seed/diff/limits) | nein | X | X | X | X | `NOT REPRODUCIBLE` |
| 12 (Realdok) | e186c98 | ja | nein | nein | X | X | X | X | `NOT REPRODUCIBLE` |
| 13–16 (Realdok) | … | ja | nein | nein | alle X | alle X | alle X | alle X | `NOT REPRODUCIBLE` |

---

## 13. Langzeit-Vertrauen (Agent 2030, ohne heutige Doku)

| Frage | Antwort |
|-------|---------|
| 1. Commit finden? | **JA** (hash je Entry, Git intakt) |
| 2. damalige Methode bestimmen? | **NEIN** (Method-Version fehlt; Seeds haben gar keine) |
| 3. Inputs rekonstruieren? | **NEIN** (seed/diff_hash/limits nur transient verworfen) |
| 4. RNG reproduzieren? | **NEIN** (Seed fehlt) |
| 5. Composite reproduzieren? | **NEIN** |
| 6. Narrator reproduzieren? | **NEIN** (hängt an Composite-n) |
| 7. Arc reproduzieren? | **NEIN** (hängt an a_limit/arcs-Snapshot) |
| 8. Tracker-Metrik reproduzieren? | **NEIN** (exakt; Wall-Clock + Methodversion) |
| 9. erkennen, was später verändert wurde? | **NICHT BEWIESEN** (kein `result_hash`; nur in Git-Vergleich möglich, nicht erzwungen) |

---

## 14. Minimaler Beweissatz

Kleinste unveränderliche, **persistierte** Datenmenge pro Entry, die vollständiges Replay
ermöglicht (zusätzlich zu bereits vorhandenem `commit_sha`, `composite`, Impulse im Commit):

1. **`rng_seed`** (1 Int) — rekonstruiert c/j/n/a/p mit fixen Limits.
2. **`limits`-Snapshot** (v. a. `a_limit`, `p_limit`).
3. **`mood_pool` / `narrator_pool`-Version** (oder Hash der Daten-Dateien).
4. **`method_version`** (globale DOKI-Methoden-Version + ggf. Hash der Regeln).
5. **`result_hash`** = signierte Kette `(prev_composite → seed → composite → pools_ver →
   method_ver)` → schützt gegen stille Mutation der Vergangenheit.
6. **fixer `HISTORICAL_ROOT`** (initialer Anker-Hash, nie bewegt) + pro Entry dessen `commit_sha`.

Damit: Seed + Limits + Pools + Methodenversion sind **archiviert**, und `result_hash` macht
Mutationen erkennbar. Kein Rollback des gespeicherten Outputs nötig.

---

## 15. Wichtige Trennung

| Eigenschaft | Befund |
|-------------|--------|
| **Determinismus** (gleiche Inputs → gleiche Ausgabe) | ✅ **JA**, nachgewiesen (identische Seeds in Godot/Python seit `a95a7ee`; Check 9 self-consistent) |
| **Reproduzierbarkeit** (Inputs heute verfügbar) | ❌ **NEIN** — RNG-Eingaben nur transient; Seeds ohne reproduzierbare Methode |
| **Provenienz** (Ergebnis eindeutig Commit zuordenbar) | ✅ **STARK** — entry.hash = commit, Tree, `[IMPULSE:]`/`[COMPOSITE:]`-Tokens im Commit-Body |

DOKI ist also **deterministisch & stark verankert, aber nicht historisch reproduzierbar**.
Diese drei Achsen dürfen **nicht zusammengelegt** werden — Determinismus allein beweist nichts
für die Vergangenheit, solange die Eingaben fehlen.

---

## 16. Finales Urteil

### A — Sind historische DOKI-Composites vollständig reproduzierbar?
**NEIN.** Empirisch: keine der 16 untersuchten Einträge. RNG-Seed & Eingaben nicht archiviert;
Seeds mit nicht-rekonstruierbarer Methode.

### B — Sind die verwendeten Methoden historisch identifizierbar?
**NEIN.** Methodenversion fehlt je Entry; für die Seeds existiert die Methode gar nicht im Repo.
RNG-Kern ist zwar konstant und identifizierbar, die Aufrufer-/Kontext-Regeln jedoch nicht je Entry.

### C — Sind die RNG-Inputs archiviert?
**NEIN / MUTABLE.** Nur transient in der gitignored `.doki/session.json`, nach `finalize`
verworfen. `[IMPULSE:]` im Commit ist die einzige dauerhaft archivierte Eingabe.

### D — Sind Tracker-Metriken historisch reproduzierbar?
**TEILWEISE / eher NEIN.** Zählwerte aus Chain+Formel rekonstruierbar, aber Formelversion,
Wall-Clock-Kopf und Sortierstabilität verhindern die exakte Wiederholung.

### E — Ist die Chain historisch unveränderlich?
**NEIN strukturell; JA de facto.** Kein `result_hash`, kein erzwungenes append-only ⇒ still
mutierbar (§9). Bisher sind die Beweisfelder in Git-Historie stabil (nur `subject` ergänzt).

### F — Ist CURRENT_ANCHOR sauber von HISTORICAL_ROOT getrennt?
**NEIN.** Es gibt keinen expliziten `HISTORICAL_ROOT`; `CURRENT_ANCHOR` ist beweglich
(13 Repair-Reverankerungen) und aktuell **stale** (18 Commits hinter HEAD).

### G — Kann ein fremder Agent die DOKI-Entwicklung ohne Vertrauen in die Dokumentation rekonstruieren?
**NEIN.** Ohne die heutige Doku/`session` ist die Geschichte nur ablesbar, nicht erneut
berechnbar; die Seeds sind unbegründbar.

---

## ABSOLUTE SCHLUSSFRAGE

> Wenn der heutige SnipWar-Entwickler 2035 nicht mehr existiert: Sind im Repo genug unveränderliche
> **Primärdaten** vorhanden, damit ein fremder Agent jeden historischen DOKI-Eintrag **unabhängig
> erneut erzeugen und beweisen** kann?

**NEIN. → `HISTORICALLY NON-REPLAYABLE`**

Begründung: Determinismus ja, Provenienz ja, aber die **Erzeugungs-Eingaben** (RNG-Seed,
diff_hash, tree_hash, limits, pools, Methodenversion) sind nirgends unveränderlich archiviert —
sie lagen nur in der weggeworfenen Session. Eine unabhängige Wiedergabe & Beweisführung ist für
**keinen** historischen Eintrag möglich. Reparatur: den minimalen Beweissatz aus §6/§14 pro
Eintrag ab `HISTORICAL_ROOT` unveränderlich archivieren (Seed + Limits + Pool-/Methodenversion +
`result_hash`).