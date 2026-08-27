# DOKI v3 Narrative Runtime — Verbindliche Verträge (Sprint 0, Rev. 2)

> **Status**: Sprint 0 eingefroren (2026-08-27) — dieser Text ist die verbindliche Vertragsgrundlage.
> **Vorgänger**: DOKI CommitLayer v2 (GDScript, Godot Headless) — bleibt unverändert produktiv.
> **Kern-Prinzip**: DOKI erzeugt keine Geschichten. DOKI entdeckt Geschichten, die schon passiert sind.
> **Geltung**: Jede Abweichung von diesem Dokument ist ein Vertragsbruch → Rollback, neuer Beginn, ausnahmslos.

---

## 1. Verantwortungsgrenzen (Drei-Welten-Modell)

| Welt | Enthält | Darf | Darf nicht |
|------|---------|------|------------|
| **Git + DOKI (Wahrheit)** | Git-Historie, `narrative_chain.json`, `change_index.json`, DOKI-Session + Verifier | entscheiden, was historisch passiert ist | von Python, Social oder X abhängig werden; durch Runtime-Fehler blockiert werden |
| **Python + SQLite (abgeleitet)** | ChainObservations, Relationship Events, Character State, Beliefs/Evidence, Memory, Threads, Perspectives, Conflicts, Social Candidates | aus der Chain deterministisch rekonstruieren | als zweite Wahrheit gelten; Git-/DOKI-Dateien schreiben; den Composite neu berechnen |
| **X (downstream)** | Publish, Engagement, Visibility, Community | aus abgeleiteten Kandidaten veröffentlichen | irgendetwas upstream von Push und Narrative-State sein |

**Harte Regel:** Ein Fehler in Python, Social Engine oder X darf einen erfolgreichen Commit niemals ungültig machen, verändern oder blockieren.

**SQLite** ist Gedächtnisarchiv, nicht Quelle: jederzeit löschbar und aus der Chain byte-/semantisch identisch rekonstruierbar.

---

## 2. Schichtmodell 0–7 mit bindender Datenabhängigkeit

```text
0. COMPOSITE            → wählt Narrator (n) + Variation (j). Unverändert. Keine Schicht darf ihn neu berechnen.
1. CHAIN OBSERVATION    → liest: narrative_chain.json, change_index.json. Erzeugt ausschließlich Quellfakten
                          + deterministische Projektionen.
2. RELATIONSHIP EFFECTS → liest: nur Schicht 1 + Regel-Tabelle. Erzeugt unabhängige, gerichtete Deltas.
3. THREAD STATE         → liest: nur Schicht 1 (+ Beobachtungs-Referenzen). Erzeugt Fäden mit Zuständen.
4. PERSPECTIVE / BELIEFS→ liest: Schicht 1 + 3. Evidence verweist auf Beobachtungen, kopiert sie nicht.
5. MEMORY / CHAR STATE  → liest: Schicht 2 + 4. Roh-Events unveränderlich; emotionale Gewichte decays
                          pro Achsenprofil (abgeleitet, nie destruktiv).
6. CONFLICT / RELEVANCE → liest: Schicht 3 + 4 + 5. Erzeugt Widersprüche und erzählerisches Gewicht.
7. NARRATIVE OUTPUT     → liest: alles Obige (read-only). Liefert Kontext an DOKI + getrennte Social Candidates.
```

**Bindende Leseregeln:** Keine Schicht liest „amewsammen" — die Read-Sets oben sind exklusiv. Beobachtungen (1) enthalten nie Interpretation; Deltas (2) enthalten nie Fadenaussagen; Konflikte (6) sind Ableitungen mit Evidence-Refs, nie historische Wahrheit.

**Datenabhängigkeits-Reihenfolge Memory/Thread/Perspective (verbindlich):**
1. Threads konsumieren nur Beobachtungen (Dateien/Entitäten/Teilnehmer).
2. Beliefs/Perspektiven konsumieren Beobachtungen + Thread-Kontext; ihre Evidence-Refs zeigen auf `seq`.
3. Memory/Character State konsumiert Relationship Events + Belief-Übergänge; Emotionen decays, Fakten verrotten nie.

---

## 3. Quell-Datenmodell (Ist-Stand, verifiziert am 2026-08-27)

### 3.1 `narrative_chain.json`
```text
Top-Level: anchor{date,hash,subject}, entries[], genesis_composite, genesis_date, genesis_mood, repairs[]
Entry (real): a, arc, c, composite, data_changes[], date, hash, j, model_id, mood, n, narrator,
              p, p_id, prev_narrator (ab seq 2), seeded, seq, subject, summary
              — `impulse_category` und `parent_hashes` sind im aktuellen Bestand nicht vorhanden
data_changes[] (real): [{file, insertions, deletions}]   ← Dateien liegen IN der Chain
repairs[] (real): [{at_hash, note}]  — 2× Re-Anchoring nach rebase/amend/force-push bereits vorhanden
Sequenzen: kontiguierlich 1..44 (Stand: 44 Einträge nach dem genehmigten Sprint-0-Doku-Commit)
```

### 3.2 `change_index.json`
```text
Top-Level: commits{hash → {c, composite, entities[], p_id}}, entities{id → {...}}, version
entities[] (real): id, type ('component'|'file'), name, path, status, first_p, last_p,
                   history[{lines[], p_id}]
```

### 3.3 `classify_impulse` (Deterministischer Port, `voice_composer.gd:255`)
Reihenfolge bindend, erster Treffer gewinnt:
1. `\b(doku|archiv|changelog|readme|plan|comment|docs)\b` → `DOKU`
2. `\b(fix|bug|hotfix|patch|repair|fehler|korr)\b` → `FIX`
3. `\b(restruktur|refactor|cleanup|aufr|umstruktur|moved|verschoben|modular|extract|dedupli)` → `REFACTOR` (kein `\b` am Ende — bewusst 1:1 portiert)
4. `\b(build|commitlayer|commit_layer|author.system|hook|verifier|pipeline|doki)\b` → `BUILD` (`author.system` mit unescaped Punkt — bewusst 1:1)
5. `\b(test|test\w*)\b` → `TEST-ASSET`
6. `len(text) < 12 or Wortzahl ≤ 2` → `TRIVIAL`
7. sonst → `CODE`

---

## 4. ChainObservation-Vertrag (Schicht 1)

### 4.1 Purity-Linie (exakte Vertragsformulierung)

> **Observation enthält Git-/DOKI-Quellfakten plus deterministische, reproduzierbare Projektionen
> dieser Fakten. Keine narrative Interpretation.**

Daraus folgt:
- Erlaubt: `subject_term_flags.repair = true` (deterministische Projektion eines Quellfaktens).
- Verboten in Observations: „Thinker caused a problem", „Buffy is angry", Schuld, Absicht, Emotion, Bewertung.

### 4.2 Feldursprünge (zwei Klassen, zentral deklariert — nicht pro Datensatz)

**Klasse A — Quellfakten** (1:1 aus Chain/Index übernommen):
`seq`, `commit_hash`, `date`, `subject` und `summary` (Rohtexte, unverändert), `narrator`,
`prev_narrator`, `mood`, `composite`, `composite_fields {c,n,j,a,p}`,
`parent_hashes` (falls vorhanden, sonst `[]`), `p_id`, `arc`, `impulse_category` (optional aus
Chain-Eintrag, im aktuellen Bestand `null`), `seeded`, `model_id`, `data_changes[]` (Rohtext),
`entities[]` (aus `change_index.commits[hash].entities`).

**Klasse B — deterministische Projektionen** (jede mit Regelname + Version):

| Feld | Regel | Version | Definition |
|------|-------|---------|-----------|
| `impulse_category_recomputed` | `classify_impulse/v1` | 1 | Port aus §3.3 auf `subject`, Fallback `summary` |
| `subject_term_flags` | `subject_terms/v1` | 1 | `{repair, doc, refactor, build, test, merge}` — Term-Gruppen 1:1 aus §3.3 (repair=FIX-Gruppe, doc=DOKU-Gruppe, refactor=REFACTOR-Gruppe, build=BUILD-Gruppe, test=TEST-Gruppe, merge=`subject` beginnt mit `merge`) |
| `is_merge` | `merge_rule/v1` | 1 | erstes Token von `subject` (lowercase) == `merge` |
| `sequence_facts` | `sequence_facts/v2` | 2 | nur bereits verarbeitete Sequenzen und frühere Subjects mit Repair-Term; keine Look-ahead-Daten, damit Append-Importe alte Observations nicht rückwirkend ändern |
| `merge_facts` | `merge_facts/v1` | 1 | Merge-Präfix, Elternanzahl und Vorhandensein von `parent_hashes` |
| `sideplot_facts` | `sideplot_facts/v1` | 1 | ausschließlich vorhandene Chain-`repairs[]`-Marker für diesen Hash |
| `files` | `files_rule/v1` | 1 | sortierte, deduplizierte Pfade aus `data_changes[].file` |
| `prior_file_touchers` | `prior_touchers/v1` | 1 | je Pfad: alle früheren `seq` mit gleichem Pfad, absteigend, **Fenster = 5**; fehlt, wenn keine Vorgänger |
| `file_seq_gaps` | `seq_gap/v1` | 1 | je Pfad mit Vorgänger: `seq − letzte_Vorgänger_seq` |
| `shared_entities` | `shared_entities/v1` | 1 | je Entitäts-ID: frühere `seq` mit gleicher Entität, absteigend, **Fenster = 5** |

**Regel:** Ein Feld, das in keiner der beiden Klassen steht, macht die Observation ungültig (Purity-Test erzwingt die Feldmenge strukturell — siehe Gate-Bedingung G2).

### 4.3 Umschlag (Envelope)

```json
{
  "schema": "chain_observation/v1",
  "seq": 43,
  "...": "<Felder nach §4.2>"
}
```

Kanonische Serialisierung (bindend): `json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)` als UTF-8; `observation_digest = sha256(serielle Bytes)`; `observation_output_hash = sha256(kanonisches JSON aller Observations aufsteigend nach seq)`.

### 4.4 Backfill

Backfill = Erzeugung aller Observations über die **komplette** bestehende Chain (aktuell .seq 1..44, allgemein .seq 1..N) mit identischen Regeln wie inkrementell. Gleiche Chain-Eingabe ⇒ identischer `observation_output_hash` (Abnahme Sprint 1).

---

## 5. Event-ID und Seq-Anker (Schichten 1–2, Idempotenz)

### 5.1 Event-ID
```text
event_id = "ev_" + sha256(f"{seq}|{commit_hash}|{schema_version}").hexdigest()[:16]
```
- Reproduzierbar aus Quellfakten; gleiche Eingabe ⇒ gleiche ID; Rewrite desselben `seq` ⇒ andere ID.
- `schema_version` = Runtime-Schema-Version (ganzzahlig, aktuell **1**), nicht die Observation-Envelope-Version.

### 5.2 Chain-Anker (Meta) — **schützt vor rebase/amend/force-push**

Der blinde Start bei `last_processed_chain_seq + 1` reicht nicht: DOKI kennt Amend/Repair/Rebase — dieselbe Sequenz kann später einen **anderen Commit-Hash** tragen (2× bereits in `repairs[]` verzeichnet). Deshalb:

```text
meta:
  schema_version              = 1
  last_processed_chain_seq    = zuletzt verarbeitete Chain-Sequenz
  last_processed_chain_hash   = commit_hash des Chain-Eintrags an last_seq, wie verarbeitet
  last_processed_entry_digest = sha256(kanonisches JSON des ROHEN Chain-Eintrags an last_seq)
  observation_output_hash     = Hash über alle importierten Observations
```

**Import-Entscheidungslogik (fail-closed):**

```text
1. Validierung: Chain-Sequenzen kontiguierlich 1..max — sonst CHAIN_GAP (Exit 3), niemals toleriert.
2. Leere DB            → vollständiger Import ab seq 1.
3. Anker-Check: Eintrag an last_seq muss übereinstimmen in commit_hash UND entry_digest.
   Abweichung          → HISTORY CHANGED (Exit 2): „Rebuild erforderlich" — inkrementeller Import
                         ist verboten, kein stiller Skip, keine Teilverarbeitung.
4. Sonst               → inkrementeller Import aller seq > last_seq in EINER Transaktion.
```

`event_id` allein würde einen Rewrite zwar erkennen, aber der inkrementelle Start würde gar nicht bis zu diesem Event zurückgehen — deshalb ist der Anker mit Hash + Digest Pflicht, nicht optional.

---

## 6. SQLite-Vertrag (Schicht 1/2-Archiv, MVP A)

### 6.1 Grundregeln
- Ein Prozess, ein Zugriff. **Kein WAL** (Default-Journal genügt). Transaktionen trotzdem immer.
- Upserts über eindeutige Event-IDs; Foreign Keys ON.
- Datei: `narrative_runtime/state/narrative.db` (gitignored). Rekonstruierbar, nie zweite Wahrheit.
- Keine API-Abhängigkeit, keine Netz-Zugriffe.

### 6.2 Tabellen jetzt (MVP A)

```sql
meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)                    -- §5.2, keine Uhrzeit-Werte!
observations(seq INTEGER PRIMARY KEY, commit_hash TEXT NOT NULL,
             observation_digest TEXT NOT NULL, observation_json TEXT NOT NULL)
events(event_id TEXT PRIMARY KEY, seq INTEGER NOT NULL UNIQUE,
       commit_hash TEXT NOT NULL, event_type TEXT NOT NULL,        -- 'commit_observed'
       subject TEXT NOT NULL, narrator TEXT NOT NULL, prev_narrator TEXT,
       impulse_category TEXT NOT NULL, entry_digest TEXT NOT NULL, date TEXT)
event_participants(event_id TEXT NOT NULL, participant_type TEXT NOT NULL,   -- 'narrator'|'prev_narrator'
                   participant_id TEXT NOT NULL,
                   PRIMARY KEY(event_id, participant_type, participant_id))
event_evidence(event_id TEXT NOT NULL, evidence_seq INTEGER NOT NULL,
               evidence_type TEXT NOT NULL,                        -- 'observation'
               PRIMARY KEY(event_id, evidence_seq, evidence_type))
file_touches(seq INTEGER NOT NULL, path TEXT NOT NULL, event_id TEXT NOT NULL,
             insertions INTEGER, deletions INTEGER, prior_touch_seqs TEXT,  -- JSON (Projektion)
             PRIMARY KEY(seq, path))
concept_touches(seq INTEGER NOT NULL, entity_id TEXT NOT NULL, event_id TEXT NOT NULL,
                prior_touch_seqs TEXT,                             -- JSON (Projektion)
                PRIMARY KEY(seq, entity_id))
```

### 6.3 Tabellen später (nur per Migration, nie jetzt anlegen)
`relationship_events, beliefs, belief_evidence, threads, thread_events, character_state_history, narrative_snapshots, social_candidates, queue`

### 6.4 Transaktionsvertrag
```text
BEGIN → observations einfügen/aktualisieren → events (+Teilnehmer/Evidence/Touches) → meta-Anker → COMMIT
Fehler irgendwo → ROLLBACK → keine halben Events, Anker unverändert, Exit ≠ 0.
```

### 6.5 CLI (Entry `python -m narrative_runtime`)
```text
import   — inkrementell mit Anker-Prüfung (§5.2)
rebuild  — DB löschen + Komplett-Replay aus der Chain
verify   — Neuberechnung der Observations + Hash-Vergleich gegen Meta (PASS/FAIL)
status   — Anker, Chain-Kopf, DB-Zustand (read-only)
Exit-Codes: 0 ok · 2 HISTORY CHANGED (Rebuild erforderlich) · 3 Chain ungültig/Lücke · 1 sonstiger Fehler
```

---

## 7. Beziehungsmodell RELATIONSHIP[A][B] (Vertrag für Sprint 3, nicht in MVP A implementiert)

- **Gerichtet, ausnahmslos:** `RELATIONSHIP[A][B] ≠ RELATIONSHIP[B][A]`, keine automatische Spiegelung. 14 × 13 = **182 gerichtete Beziehungen** × 8 Achsen = **1.456 relationale State-Werte**.
- **Achsen mit gerichteter Semantik pro Träger:** `trust` („Wie sehr glaube ich ihm?"), `respect` („Wie hoch schätze ich seine Kompetenz?"), `irritation`, `affinity`, `competence_confidence`, `resentment`, `curiosity`, `defensiveness`.
- **Skala intern 0.0–1.0** (nicht 0–10). Prompt-Rendering: 0–100 oder Label („low trust"). Deltas wie `-0.04`, `+0.07` — fein gewichtbar, Social-fest.
- **Events wirken auf einzelne Achsen, keine Achsen-Kopplung.** Die Kombination ergibt die Psychologie. Beispiele (Regel-Beispielfixtures, Kalibrierung in Sprint 3):
  - erfolgreiche Reparatur: `respect +0.03, competence_confidence +0.04, trust +0.01`
  - wiederholte Regression: `trust −0.04, competence_confidence −0.05, irritation +0.02`
  - öffentliche Meinungsverschiedenheit: `defensiveness +0.03, resentment +0.01`
  - eingestandener Fehler: `resentment −0.02, trust +0.02`
- **Ein Event darf beide Richtungen unterschiedlich schreiben** (Fixture c37/c43: Thinker editiert AGENTS.md, Buffy fixt Folgen → `Buffy→Thinker: trust −0.018, competence_confidence −0.022, irritation +0.011`; `Thinker→Buffy: trust +0.002, respect +0.014`).
- **Kein pauschaler Zeit-Decay** („Emotionen dürfen abklingen. Erinnerungen nicht."): `irritation` decayt schnell, `resentment` langsam, `trust`-Schäden bleiben stärker bestehen, Beliefs bleiben mit Evidenz bestehen. Decay-Profil pro Achse, als Projektion — Roh-Events bleiben unveränderlich.
- **Knowledge ebenfalls gerichtet:** `RELATIONSHIP[A][B]` trägt zusätzlich `known_traits / known_events / known_beliefs` (was A über B weiß) und `interpretation` / `expectations`. „Buffy believes: Thinker ignored my warning" vs. „Thinker remembers: Buffy never actually warned me" → Missverständnisse werden modellierbar; genau daraus entstehen Konflikte beiderseitiger Rationalität.
- **Jede Änderung** wird als `relationship_event` mit Begründung + Event-/Observations-Referenz gespeichert. Keine monolithische Gesamtzahl.

---

## 8. Fakt / Interpretation / Stil

| Klasse | Definition | Beispiele |
|--------|-----------|-----------|
| **Fakt** | aus Chain/Git/Index 1:1 oder deterministisch projiziert | `summary`-Text, Datei-Liste, `subject_term_flags.repair=true`, `is_merge=true` |
| **Interpretation** | Ableitung über Fakten hinweg, niemals Chain-Inhalt | „Buffy ist genervt vom Wiederholungsfehler", „Thinker übersah die Referenzen" |
| **Stil** | Narrator-Stimme, Mood, Wortwahl | Composite-/Mood-Overlay, Attitude-Texte |

**Harte Linie:** Interpretation darf nie in Observations oder SQLite-Faktentabellen gelangen. Sie lebt ausschließlich in Schichten 2–7 als abgeleitete, rebuildbare Werte mit Evidence-Refs. Die Engine darf aus Commit-Subjects niemals selbstsichere komplexe Behauptungen als Wahrheit markieren — Beliefs sind Perspektiven, keine Fakten.

---

## 9. Determinismus-Registry

| Kategorie | Werte | Rebuild |
|-----------|-------|---------|
| **Deterministisch aus Chain** | Observations, Projektionen, `event_id`, `observation_output_hash`, Anker-Digests | identisch, byte-geprüft |
| **Abgeleitet / rebuildbar** | Relationship-Deltas, Beliefs, Threads, Perspectives, Conflicts, Candidates, Decay-Gewichte | identisch bei gleicher Regelversion + gleicher Chain |
| **Extern (nie deterministisch)** | Engagement-Metriken, Community-Daten, Uhrzeit | werden importiert, niemals rückprojiziert |

Regel: Abgeleitete Werte tragen eine Regelversion; Regeländerung ⇒ Rebuild mit neuer Version, historische Fakten bleiben unangetastet.

---

## 10. Arc-Kompatibilität

- `scripts/doki/data/arcs.json` (18 Arcs) bleibt **Legacy-/Vergleichsquelle** — Referenzierbarkeit aller 18 Arcs ist Abnahmekriterium der Thread-Migration (Sprint 5).
- `arc_engine.gd` bleibt unangetastet, bis Thread-Backfill validiert ist. Kein blindes Ersetzen.
- **Composite-Narrator-Auswahl bleibt unverändert:** keine Schicht der Runtime berührt `n`, `j` oder den Composite-Hash.
- Bestehende DOKI-Verifier- und Preflight-Verträge dürfen durch Migration nicht brechen (65 Selfchecks bleiben grün).

---

## 11. DOKI-Bridge-Vertrag (Sprint 7, hier nur Vertrag)

Aktueller DOKI-Fluss bleibt exakt: `prepare` (Hash/Narrator/Mood/Prompt) → `finish` (Body-Verifikation, 9 Checks) → `finalize` (Chain-Append, ChangeIndex, Artefakte).

**Bridge liefert zusätzlich** `narrative_context.json` mit: `facts`, `current_character`, `current_state`, `relevant_relationships`, `beliefs`, `memory_refs`, `threads`, `conflicts`, `allowed_interpretations`.

**Regeln:**
- Der Context berechnet den Composite **nie** neu und wählt den Narrator **nie** um.
- Fallback: Context fehlt oder ist veraltet → DOKI funktioniert mit bestehendem Verhalten weiter (frische Klones/fehlende DB = definierter Fallback).
- Context-Fehler blockiert weder `prepare` noch `finish` noch den Commit.

---

## 12. post-commit-Härtung & Recovery (Vertrag, Hooks werden erst mit Runtime-Existenz geändert)

Zielreihenfolge:
```text
post-commit: DOKI finalize → git push → best-effort state update → best-effort candidate generation
```

Recovery-Pflichten der Runtime:
- `last_processed_chain_seq` + `last_processed_chain_hash` + `last_processed_entry_digest` (§5.2),
- idempotente Event-Verarbeitung,
- Rebuild aus der Chain jederzeit,
- Fehlerjournal (append-only, in SQLite-State, nie in Git),
- Retry-/Pending-Status für Social,
- keine Annahme, dass jeder Commit genau einen Candidate erzeugt (0..N).

---

## 13. NARRATIVE_RUNTIME_GATE (fail-closed, Stil: chain_manifest_gate/compile_gate)

Zeitplan: Sprint 1–2 genügt `unittest`. **Bevor die Runtime produktiv in DOKI eingehängt wird (vor Sprint 7), wird daraus ein echtes Repo-Gate.** „Tests liegen irgendwo" ist kein Zustand dieses Repos.

Das Gate schlägt FAIL bei:
```text
G1  stdlib-only verletzt (Fremd-Import in narrative_runtime/)
G2  Observation enthält Interpretation (Feldmenge ≠ Schema §4.2)
G3  Event-ID nicht reproduzierbar (gleiche Eingabe ≠ gleiche ID)
G4  Chain-Lücke akzeptiert (kontiguierliche Seqs verletzt)
G5  State schreibt Git-Wahrheit (Schreibzugriff auf Chain/Index/DOKI-Dateien)
G6  Import nicht idempotent (Doppelimport erzeugt Differenz)
G7  Rebuild ≠ Incremental-Result (Zustandsdifferenz)
```

---

## 14. Invarianten (Risiken 1–12 als prüfbare Sätze)

1. Narrative State ist nie zweite Wahrheit — SQLite jederzeit löschbar, Chain bleibt Quelle.
2. Arc-Migration nicht vorschnell destruktiv — `arcs.json` bleibt referenzierbar (18/18).
3. Der Hash wird nie durch Relevance/Hype ersetzt — Composite-Auswahl unverändert.
4. State aus Chain rekonstruierbar — `rebuild` ist jederzeit Pflicht-weg, nie Best-Effort.
5. Incremental == Full Rebuild — getestet (G7), nicht behauptet.
6. Social erfindet keine Fakten — Candidates nur mit Evidence-Refs.
7. 0..N Candidates pro Commit — kein 1:1-Zwang.
8. Kaputte X-Verbindung berührt Git nicht — X ist rein downstream.
9. Engagement dominiert nicht sofort — Kalibrierung langsam, begrenzt, nie rückwirkend.
10. Community-Daten mit Prompt-Injection-/Moderationsgrenzen — Pflicht vor Sprint 12.
11. Backfill historisch nachvollziehbar und korrigierbar — Anker + Digests + Regelversionen.
12. Alle DOKI-Änderungen erhalten Gates und Selfchecks — 65/65 bleibt grün.

---

## 15. Umsetzungsstand & Fahrplan

**Nach MVP A (dieser Schnitt) existiert:** `narrative_runtime/` (stdlib-only, Python ≥ 3.11) mit
`observe.py` (§4), `store.py` (§5–6), CLI (§6.5), Testsuite (Idempotenz, Anker/Amend, Rebuild-Determinismus, Atomicity, Purity, Gap, Incremental==Rebuild, Smoke gegen Kopie der echten Chain). Die reale Chain umfasst beim Abnahmelauf 44 Einträge.

**Noch nicht implementiert (nur vertraglich):** Relationship-Deltas (§7), Beliefs/Evidence/Memory (Sprint 4), Threads (Sprint 5), Perspectives/Conflicts (Sprint 6), Bridge (§11, Sprint 7), Candidates/Slice Gate/Queue (Sprint 8–9), X (Sprint 10), Analytics (Sprint 11), Community (Sprint 12), Gate-Implementierung (§13, vor Sprint 7).

**Fahrplan (bindende Reihenfolge):** Observation contract ✅ → SQLite archive ✅ → Backfill ✅ → Rebuild/Idempotency-Tests ✅ → Relationship + State-Deltas → Threads → Beliefs/Perspectives/Conflicts → Gate-Implementierung → DOKI context bridge → Social candidates → X adapter → Analytics → Community interactions.

**Der wichtigste erste Erfolg (Abnahme von MVP A):** die bestehende Chain lässt sich in die neue Narrative Runtime importieren, der Zustand lässt sich löschen und identisch wiederherstellen, und DOKI bleibt technisch exakt so zuverlässig wie vorher.
