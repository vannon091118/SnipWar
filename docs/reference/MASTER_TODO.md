# MASTER TODO — Konsolidierter Gesamtplan (Single Source of Truth)

> **Regel:** Dieses Dokument ist die EINZIGE operative Aufgabenliste. ROADMAP.md bleibt strategisch, FINDINGS.md dokumentiert Befunde, CHANGELOG.md blickt zurück. Hier wird gearbeitet.
> **Workflow:** Falsifikation → Patch-Plan → Execution → Post-Falsifikation → Global Check → Doku → Audit → Commit → Follow-up

---

## 📊 ÜBERSICHT: ALLE ARBEITSPAKETE

| ID | Quelle | Titel | Priorität | Status | Depends On |
|----|--------|-------|-----------|--------|------------|
| **BRANCH-KONSOLIDIERUNG** |
| C-01 | User | Branch 845 als technischen Basis-Branch prüfen/übernehmen | P0 | TODO | — |
| C-02 | User | Branch 580 Relationship-Fix prüfen/übernehmen | P0 | TODO | — |
| C-03 | User | Relationship-Regression-Tests + Doku ergänzen | P1 | TODO | C-02 |
| **PREFLIGHT / INFRASTRUKTUR** |
| I-01 | F-304 | `reset_state()` / Isolation partiell — partieller Restore, Field-Node-Count-Leak | P0 | 🟡 OFFEN | — |
| I-02 | F-306 | DOKI-Testzählung: "65 Regressionstests" nicht reproduzierbar (14 Funktionen, 79 Checks) | P1 | 🟡 OFFEN | — |
| I-03 | R-013 | Save-Versionierungsaudit (Migration/Versionierung dokumentieren oder implementieren) | P2 | TODO | — |
| I-04 | R-016 | Refinery serialisierbar / mech_frame entscheiden | P3 | TODO | R-007 ✅ |
| I-05 | User | Python-Preflight-Core als eigenständiges CLI bauen (statische Gates ohne Godot) | P1 | TODO | — |
| **SIMULATION / SIM-ENGINE** |
| S-01 | R-SIM-002 | FactionRelationshipEngine — Beziehungsdeltas, Trade-Compatibility | P2 | TODO | R-SIM-001 ✅ |
| S-02 | R-SIM-003 | HistoricalEpochEngine — DOKI-Arc-Mathematik auf Sim-Events | P2 | TODO | R-SIM-001 ✅ |
| S-03 | R-SIM-004 | Trade Window — Ring-Adjazenz, event-getriggerter Cache | P2 | TODO | S-01 |
| S-04 | OFFEN-7 | Plan-Metriken: Kausalitätstiefe (BFS≥3), Dead-End-Rate, State-Consequence-Rate, Character-Agency-Rate, Seed-Diversität | P2 | TODO | S-01, S-02, S-03 |
| **QA / GAMEPLAY** |
| Q-01 | QA2-GAME-3 | NEUES SPIEL-Klick löst keinen Szenenwechsel aus (Main Menu bleibt) | P0 | 🟡 OFFEN | R-050 ✅ |
| Q-02 | QA2-MCP-5 | `runtime_audio_list_streams` → `[]` im Hauptmenü trotz Asset; Welt: nur Master-Bus | P2 | 🟡 OFFEN | — |
| Q-03 | QA2-MCP-6 | Tutorial-Overlay für `runtime_ux_scan` UNSICHTBAR (Controls nicht findbar) | P1 | 🟡 OFFEN | — |
| Q-04 | QA2-GAME-2 | Progressions-Gate "erstes Schiff": Werft nicht gebaut, Tutorial verdeckt Navigation | P1 | 🟡 OFFEN | Q-03 |
| Q-05 | OFFEN-2 | Tutorial-Schritt 2: grüner Ziel-Marker (Home-Planet) sichtbar machen | P1 | 🟡 OFFEN | — |
| Q-06 | OFFEN-5 | Pool-Skalierung messen: `MCP_OCR_POOL=1` vs 4 mit je 8 Jobs | P3 | 🟡 OFFEN | — |
| Q-07 | OFFEN-6 | OCR-Assets (deu.traineddata.gz + Worker-Script) als gepackte Ressource einchecken | P3 | 🟡 OFFEN | — |
| **DOKUMENTATION / SYNC** |
| D-01 | User | ROADMAP.md auf aktuellen Stand bringen (alle VERIFIED, offene TODOs spiegeln) | P0 | TODO | All VERIFIED |
| D-02 | User | ARCHITECTURE.md / Findings / Changelog final synchronisieren | P0 | TODO | D-01 |
| D-03 | R-015 | CHANGELOG-Boilerplate komprimieren (DOKI) | P3 | TODO | — |
| **LORE / WORLD-BUILDING** |
| L-01 | User/LORE.md | `res/lore/world_lore.md` anlegen | P0 | TODO | — |
| L-02 | User/LORE.md | `res/lore/stickman.md` anlegen | P0 | TODO | — |
| L-03 | User/LORE.md | `res/lore/reaper.md` anlegen | P0 | TODO | — |
| L-04 | User/LORE.md | `res/lore/factions_overview.md` anlegen | P0 | TODO | — |
| L-05 | User/LORE_R | Eisen-Grenze kanonisieren: Ursprung, Zweck, Erbauer, historische Bedeutung | P0 | TODO | L-01 |
| L-06 | User/LORE_R | 5 Ressourcen loreseitig erklären: Ursprung, Entstehung, Bedeutung, Nutzung | P0 | TODO | L-01 |
| L-07 | User/LORE_R | Tideborn: Herkunft, Kultur, Motivation, historische Entwicklung | P0 | TODO | L-04 |
| L-08 | User/LORE_R | Reaper: Ursprung, Ideologie, Entwicklung, Verbindung zur Eisen-Grenze | P0 | TODO | L-03, L-05 |
| L-09 | User/LORE_R | Fraktionsbeziehungen: gemeinsame Vergangenheit, Brüche, Feindschaften, Bündnisse | P1 | TODO | L-07, L-08 |
| L-10 | User/LORE_R | Planeten: individuelle Geschichte, Kulturen, Ruinen, Konflikte, Besonderheiten | P1 | TODO | L-01 |
| L-11 | User/LORE_R | Alte Zivilisation: Wer existierte vor heutigen Fraktionen, was ist übrig? | P1 | TODO | L-05 |
| L-12 | User/LORE_R | Sternensystem/Kosmos: Entstehung, Expansion, Grenzen, bekannte Welt begrenzt | P1 | TODO | L-05, L-11 |
| L-13 | User/LORE_R | Historische Ereignisse: zentrale Kriege, Katastrophen, Aufstiege, Untergänge | P1 | TODO | L-09, L-11 |
| L-14 | User/LORE_R | Technologie: Herkunft wichtiger Tech, warum verloren/verboten | P2 | TODO | L-11 |
| L-15 | User/LORE_R | Wirtschaft: Warum Ressourcen knapp, wie Handel/Produktion historisch entstanden | P2 | TODO | L-06, L-09 |
| L-16 | User/LORE_R | Narrative Konsequenzen: Simulationsevents verändern/erzeugen Lore | P1 | TODO | S-02, L-01 |
| L-17 | User/LORE_R | Papercraft-Welt: erklären, warum Welt physisch/ästhetisch Papier-/Modellbau-Logik | P0 | TODO | L-02 |
| L-18 | User/LORE_R | Lore-Kanon: Widersprüche zwischen LORE.md, Dossiers, Simulation, Narrative Runtime beseitigen | P0 | TODO | L-01..L-17 |
| L-19 | User/LORE_R | Lore-Artefakte: fehlende res/lore/*.md erstellen und mit LORE.md synchronisieren | P0 | TODO | L-01..L-04 |
| **GLOBAL CHECKS** |
| G-01 | User | Globale DOKI-/Preflight-Prüfung (44/44 Constraints PASS) | P0 | TODO | All implementation |
| G-02 | User | Alle Branch-Arbeiten auf konsistenten Stand bringen | P0 | TODO | C-01, C-02, C-03 |
| G-03 | User | Finaler Merge auf main | P0 | TODO | G-01, G-02 |
| G-04 | User | Nach Merge: globale Post-Execution-/Divergenz-Prüfung | P0 | TODO | G-03 |

---

## 🔗 DEPENDENCY GRAPH (Kritischer Pfad)

```
CRITICAL PATH (P0 - muss zuerst gelöst werden):
├── C-01 (Branch 845 Basis) ──▶ C-02 (Branch 580 Relationship) ──▶ C-03 (Tests+Doku)
├── I-01 (F-304 reset_state) ──────────────────────────────────────▶ G-01 (Preflight)
├── Q-01 (NEUES SPIEL Flow) ───────────────────────────────────────▶ G-01
├── Q-03 (Tutorial Overlay MCP) ──▶ Q-04 (Progressions-Gate Schiff)
├── Q-05 (Tutorial Marker) ────────────────────────────────────────▶ Q-04
├── L-01..L-04 (Lore-Dateien anlegen) ─────────────────────────────▶ L-05..L-19
├── L-05 (Eisen-Grenze) ───────────────────────────────────────────▶ L-08, L-11, L-12
├── L-06 (Ressourcen-Lore) ────────────────────────────────────────▶ L-15
├── L-07, L-08 (Fraktionen) ───────────────────────────────────────▶ L-09
├── L-16 (Narrative Konsequenzen) ◀──────────────────────────────── S-02 (HistoricalEpochEngine)
└── All P0/P1 ─────────────────────────────────────────────────────▶ G-01 ▶ G-02 ▶ G-03 ▶ G-04

PARALLEL TRACKS (können unabhängig laufen):
├── I-02 (F-306 DOKI-Tests) ──────────────────────────────────────▶ D-03 (CHANGELOG kompakt)
├── I-03 (Save Versioning) ───────────────────────────────────────▶ G-01
├── I-04 (Refinery/mech_frame) ───────────────────────────────────▶ G-01
├── I-05 (Python Preflight CLI) ──────────────────────────────────▶ Independent
├── S-01 (RelationshipEngine) ──▶ S-03 (Trade Window) ────────────▶ S-04 (Metriken)
├── S-02 (EpochEngine) ───────────────────────────────────────────▶ S-04, L-16
├── Q-02 (Audio Streams) ────────────────────────────────────────▶ Independent
├── Q-06, Q-07 (OCR Pool/Assets) ────────────────────────────────▶ Independent
├── D-01 (ROADMAP Sync) ────────────────────────────────────────▶ D-02 (Arch/Findings/Changelog Sync)
└── L-10 (Planeten-Lore) ◀──────────────────────────────────────── L-01, L-11
```

---

## 🎯 FALSIFAKTIONS-WELLE 1: ANALYSE (Aktueller Zustand) — **ABGESCHLOSSEN**

### Was wir WISSEN (Verifiziert):
- ✅ Preflight: 44/44 Constraints PASS (~64s)
- ✅ R-050 HistoricalWorld Lifecycle + Handover VERIFIED
- ✅ R-051 Preflight Constraint historical_world VERIFIED
- ✅ R-052 Jahr-0-Kontext-Übergabe VERIFIED
- ✅ R-007 Economy Domain konsolidiert (E1-E4) VERIFIED
- ✅ R-008 planet_network UI/Logik getrennt VERIFIED
- ✅ R-009 test_all.gd Orchestrator VERIFIED
- ✅ R-010 ConceptIndex unmapped Klassen VERIFIED
- ✅ R-011 MCP Audit Fix VERIFIED
- ✅ R-012 Preflight Cache (narrative_runtime) VERIFIED
- ✅ R-SIM-001 Dynamische Fraktionsprofile VERIFIED
- ✅ Modularisierung Phasen 1-9 abgeschlossen VERIFIED
- ✅ DOKI CommitLayer SO1-SO10 alle VERIFIED
- ✅ Narrative Runtime Design (Sprint 0) eingefroren, Gate fail-closed

### Was KAPUTT / OFFEN ist (Falsifikation) — **ROOT CAUSES IDENTIFIZIERT & PATCHES ERSTELLT**:

| # | Problem | Root Cause | Beweis | Schwere | Status |
|---|---------|------------|--------|---------|--------|
| **F-304** | `reset_state()` partiell: Field-Node-Count leakt | `v2_fixture.gd:reset_state()` restauriert nur GameState-Domänen, NICHT Scene-Nodes. Constraints bauen Field neu auf. Blanket-Restore crasht. | FINDINGS.md F-304; `v2_fixture.gd:84-158` vs `v2_context.gd:169-179` | **P0** | **PATCH 1 ANGEWENDET** ✅ |
| **F-306** | DOKI Selfcheck "65 Tests" nicht reproduzierbar | 14 Test-Funktionen, 79 `_expect` Assertions. Zahl "65" nirgends im Code. | `doki_selfcheck.gd:12-26` (14 Funktionen), 79 `_expect` Aufrufe | **P1** | **PATCH 4 ANGEWENDET** ✅ |
| **QA2-GAME-3** | NEUES SPIEL Klick → Szene bleibt auf main_menu | `SceneDirector._deferred_switch_scene` nutzt `get_tree().current_scene = instance` — in Headless problematisch. Fallback nicht genutzt. | `main_menu.gd:196, 211-216`; `scene_director.gd:124-135` | **P0** | **PATCH 2 ANGEWENDET** ✅ |
| **QA2-MCP-6** | Tutorial Overlay für MCP UNSICHTBAR | `tutorial_director.gd` Overlay Parent-Pfad für MCP UX-Scan nicht findbar. | FINDINGS.md QA2-MCP-6 | **P1** | **PATCH 7 PENDING** |
| **QA2-GAME-2** | "Keine eigene Werft" — Progressions-Gate blockiert | Folge von QA2-MCP-6: Tutorial Overlay verdeckt Navigation. | FINDINGS.md QA2-GAME-2 | **P1** | **PATCH 7 PENDING** |
| **OFFEN-2** | Tutorial Schritt 2: grüner Home-Planet-Marker fehlt | `tutorial_director.gd` Marker-Spawning/Visibility unvollständig. | FINDINGS.md OFFEN-2 | **P1** | **PATCH 7 PENDING** |
| **QA2-MCP-5** | Audio: `runtime_audio_list_streams` leer im Menü, nur Master-Bus in Welt | Audio-Buses nicht verdrahtet oder Tool listet nur MCP-gestartete Streams. | FINDINGS.md QA2-MCP-5 | **P2** | **PENDING** |
| **R-013** | Save-Versionierung nicht dokumentiert/implementiert | `save_game_roundtrip` Constraint existiert aber Migrations-Vertrag nicht belegt. | ROADMAP.md R-013 | **P2** | **TEILWEISE IN BRANCH 845** |
| **R-016** | Refinery serialisierbar / mech_frame entscheiden | `convert_refinery_resources()` hartcodiert, `mech_frame` Tech inert. | ROADMAP.md R-016 | **P3** | **PENDING** |
| **R-SIM-002** | FactionRelationshipEngine fehlt | `WorldState.relationships` mit ressourcengetriebenen Deltas fehlt. | ROADMAP.md | **P2** | **PENDING** |
| **R-SIM-003** | HistoricalEpochEngine fehlt | DOKI-Arc-Mathematik auf Sim-Events anwenden. | ROADMAP.md | **P2** | **PENDING** |
| **R-SIM-004** | Trade Window fehlt | `resource_portfolio` + `resource_demand` in WorldState, Ring-Adjazenz. | ROADMAP.md | **P2** | **PENDING** |
| **L-01..L-04** | 4 Lore-Dateien existieren NICHT | `LORE.md` referenziert Dateien in `res/lore/` — Verzeichnis existierte nicht. | LORE.md + glob check | **P0** | **PATCH 3 ANGEWENDET** ✅ |
| **L-05..L-19** | Komplette Lore-Inhalte fehlen | Nur `LORE_RESEARCH.md` als Planung vorhanden. | LORE_RESEARCH.md | **P0-P2** | **PATCH 3: STRUKTUR ✅, INHALT PENDING** |

### Branch-Analyse (VERIFIZIERT):
- **Branch 845** (`origin/session/agent_8452f79f-3501-408e-a946-c3032e88aa93`, commit `0a501c13`): **4 Commits ahead** — Multi-Branch DOKI Infrastructure (branch-keyed storage, migration, save versioning v1→v2, DOKI config, doc updates). **Clean linear history, no conflicts. SUITABLE AS TECHNICAL BASE BRANCH.**
- **Branch 580** (`origin/session/agent_580dcc7f-004d-4a5d-b01e-88439aebb254`, commit `6b9bba12`): **1 Commit ahead (direct child of main)** — Relationship-Fix für `narrative_runtime/relationships.py`: Regression Classification Logic fix (false positive `REGRESSION_CONFIRMED` → `REGRESSION_CANDIDATE`), CHARACTER_AXES Reordering + fatigue clarification. **Clean fast-forward merge, no conflicts.**

---

## 📋 PATCH-PLÄNE (pro Falsifikation — atomar, minimal, testbar)

### PATCH PLAN 1: F-304 — `reset_state()` Isolation Fix (P0)
**Root Cause:** `v2_fixture.gd:reset_state()` restauriert nur GameState-Domänen (Ownership, Resources, Workers, Techs, Homeworlds, Scan-Status, Research-Ship), NICHT Scene-Nodes. Constraints wie `world_details_and_scale` bauen Field legitim neu auf (`field` Child-Count driftet von 105→106). Blanket-Restore (`queue_free` aller Non-Baseline-Childs) crasht in `selection_and_context` ("previously freed").

**Fix-Strategie:** `reset_state()` muss die Field-Nodes auf Baseline zurücksetzen OHNE Blanket-queue_free. Ansatz:
1. Baseline-Capture erweitert: `_initial_field_children` als Array[Dictionary] mit planet_id, node_type, state
2. In `reset_state()`: Field-Children iterieren, Baseline-konforme Nodes behalten/aktualisieren, überzählige Nodes gezielt `queue_free`, fehlende nicht neu erzeugen (Constraints bauen sie selbst)
3. Node-Count Check in `v2_context.gd:169-179` muss Baseline-Erwartung nutzen, nicht Snapshot

**Betroffene Dateien:**
- `scripts/preflight_v2/v2_fixture.gd` — `_capture_initial_baseline()`, `reset_state()`, `_hard_invariant_check()`
- `scripts/preflight_v2/v2_context.gd` — `take_checkpoint()`, `verify_checkpoint()` (Node-Count Logik)

**Test-Plan:**
- `preflight.gd -f world_details_and_scale -x` → muss stabil bei Baseline 105 bleiben
- `preflight.gd -f selection_and_context -x` → muss nicht crashen ("previously freed")
- Full Preflight `-x` → 44/44 PASS

**Rollback:** `git checkout HEAD -- scripts/preflight_v2/v2_fixture.gd scripts/preflight_v2/v2_context.gd`

---

### PATCH PLAN 2: QA2-GAME-3 — NEUES SPIEL Flow Fix (P0)
**Root Cause:** `main_menu.gd:196` ruft `SceneDirectorService.goto_scene("historical_world")` auf. `SceneDirector._deferred_switch_scene()` nutzt `get_tree().current_scene = instance` — in Godot 4.7 Headless ist `current_scene` setter problematisch. Fallback `change_scene_to_file` in `_goto_historical_world:216` würde funktionieren, aber Director wird priorisiert (gibt `true` zurück).

**Fix-Strategie:** `SceneDirector.goto_scene()` für `SCENE_ID_HISTORICAL_WORLD` muss robust Headless-kompatibel sein. Option A: `change_scene_to_file` als Primärpfad für Historical World (keine Fade-Transition nötig, ist Intro). Option B: `_deferred_switch_scene` Fix mit `call_deferred("set_current_scene", instance)` Pattern.

**Betroffene Dateien:**
- `scripts/ui/scene_director.gd` — `goto_scene()`, `_deferred_switch_scene()` für Historical World Spezialfall
- `scripts/ui/main_menu.gd` — `_goto_historical_world()` kann vereinfacht werden

**Test-Plan:**
- Headless: `$GODOT_BIN --headless --path . --script res://scripts/testing/main_menu_flow_test.gd` (neuer Test)
- MCP: `runtime_ux_scan` nach "NEUES SPIEL" Klick → Historical World Scene aktiv
- OCR: "RAND DER GALAXIE" Titel in Historical World sichtbar

**Rollback:** `git checkout HEAD -- scripts/ui/scene_director.gd scripts/ui/main_menu.gd`

---

### PATCH PLAN 3: L-01..L-04 — Lore-Dateien Struktur anlegen (P0)
**Root Cause:** `LORE.md` referenziert 4 Dateien in `res/lore/` — Verzeichnis existiert nicht.

**Fix-Strategie:**
1. Verzeichnis `res/lore/` anlegen
2. 4 Stub-Dateien mit korrekter Frontmatter-Struktur anlegen (wie LORE.md Stil)
3. LORE.md Links validieren

**Betroffene Dateien:**
- `res/lore/world_lore.md` (neu)
- `res/lore/stickman.md` (neu)
- `res/lore/reaper.md` (neu)
- `res/lore/factions_overview.md` (neu)

**Test-Plan:**
- `glob res/lore/*.md` → 4 Dateien
- `global_search.gd "world_lore\|stickman\|reaper\|factions_overview" --type md` → alle referenzierbar

**Rollback:** `rm -rf res/lore/`

---

### PATCH PLAN 4: F-306 — DOKI Selfcheck Zählung korrigieren (P1)
**Root Cause:** `doki_selfcheck.gd` hat 14 Test-Funktionen, 79 `_expect` Assertions. Die Zahl "65" nirgends im Code.

**Fix-Strategie:**
1. Tatsächliche Zahl zählen und in Output korrigieren: "Selfcheck: 79 Checks, X Fehler"
2. Optional: Tests logisch gruppieren (RNG: 18, Composite: 2, Mood: 2, Decode: 3, Classify: 5, Verifier: 15, Amend: 22, Repair: 8, Voice: 5 = 79)

**Betroffene Dateien:**
- `scripts/doki/doki_selfcheck.gd` — Zeile 29 Output-String

**Test-Plan:**
- `$GODOT_BIN --headless --path . --script res://scripts/doki/doki_selfcheck.gd` → Output zeigt korrekte Zahl

**Rollback:** `git checkout HEAD -- scripts/doki/doki_selfcheck.gd`

---

### PATCH PLAN 5: C-01 — Branch 845 mergen (P0)
**Status:** Clean linear history, 4 commits ahead, no conflicts.
**Action:** `git merge origin/session/agent_8452f79f-3501-408e-a946-c3032e88aa93 --no-ff`
**Verifikation:** Full Preflight nach Merge

---

### PATCH PLAN 6: C-02 — Branch 580 mergen (P0)
**Status:** Clean fast-forward (direct child of main), 1 commit.
**Action:** `git merge origin/session/agent_580dcc7f-004d-4a5d-b01e-88439aebb254`
**Verifikation:** Full Preflight nach Merge

---

### PATCH PLAN 7: QA2-MCP-6 / QA2-GAME-2 / OFFEN-2 — Tutorial Overlay + Marker (P1)
**Root Cause:** `tutorial_director.gd` Overlay Parent-Pfad für MCP UX-Scan nicht findbar. Marker-Spawning für Home-Planet fehlt.
**Analysis needed:** `tutorial_director.gd` lesen, MCP UX-Scan Contract verstehen.

---

### PATCH PLAN 8: R-SIM-002/003/004 — Simulation Engine (P2)
**Nach P0/P1 Fixes** — paralleler Track.

---

### PATCH PLAN 9: L-05..L-19 — Lore Content (P0-P2)
**Nach L-01..L-04** — Inhalte in die 4 Dateien schreiben.

---

### PATCH PLAN 10: I-05 — Python Preflight CLI (Optional, P1)
**Eigenständiges Tool** — nicht Godot-abhängig.

---

## 🚀 EXECUTION WAVES (Aktualisiert mit Patches — **Wave 1 TEILWEIS ABGESCHLOSSEN**)

### Wave 1: Branch-Konsolidierung + P0 Infrastructure (**IN PROGRESS**)
1. **C-01** — Branch 845 mergen (clean, no conflict) — **PENDING (git merge needed)**
2. **C-02** — Branch 580 mergen (fast-forward) — **PENDING (git merge needed)**
3. **C-03** — Relationship-Regression-Tests + Doku (nach C-02) — **PENDING**
4. **PATCH 1** — F-304 `reset_state()` Fix — **✅ CODE ANGEWENDET** (`scripts/preflight_v2/v2_fixture.gd`)
5. **PATCH 2** — QA2-GAME-3 NEUES SPIEL Flow Fix — **✅ CODE ANGEWENDET** (`scripts/ui/scene_director.gd`)
6. **PATCH 3** — L-01..L-04 Lore-Dateien Struktur — **✅ CODE ANGEWENDET** (4 Dateien in `res/lore/`)
7. **PATCH 4** — F-306 DOKI Selfcheck Zählung — **✅ CODE ANGEWENDET** (`scripts/doki/doki_selfcheck.gd`)

### Wave 2: Gameplay/QA Fixes + P1 (**PENDING Wave 1 Merge + Preflight**)
1. **PATCH 7** — Tutorial Overlay + Marker (QA2-MCP-6, QA2-GAME-2, OFFEN-2) — **NEEDS ANALYSIS** (`tutorial_director.gd`)
2. **QA2-MCP-5** — Audio Streams — **PENDING**
3. **OFFEN-5, OFFEN-6** — OCR Pool/Assets — **PENDING**

### Wave 3: Lore Content (Parallel zu Wave 2, **STRUKTUR FERTIG**)
1. **PATCH 9** — L-05..L-19 Lore Inhalte schreiben (in die 4 Dateien) — **PENDING**
2. **L-18** — Kanon-Konsistenz prüfen — **PENDING**

### Wave 4: Simulation Engine (**PENDING**)
1. **S-01** — FactionRelationshipEngine
2. **S-02** — HistoricalEpochEngine
3. **S-03** — Trade Window
4. **S-04** — Plan-Metriken

### Wave 5: Infrastructure Polish (**PENDING**)
1. **I-02** — F-306 DOKI Testzählung (erledigt in Patch 4)
2. **I-03** — Save Versioning (teilweise in Branch 845)
3. **I-04** — Refinery/mech_frame
4. **I-05** — Python Preflight CLI (optional)

### Wave 6: Documentation Sync (**PENDING**)
1. **D-01** — ROADMAP.md aktualisieren
2. **D-02** — ARCHITECTURE/FINDINGS/CHANGELOG sync
3. **D-03** — CHANGELOG Boilerplate komprimieren

### Wave 7: Global Checks & Merge (**PENDING**)
1. **G-01** — Full Preflight 44/44
2. **G-02** — Branch-Konsistenz
3. **G-03** — Merge main
4. **G-04** — Post-Merge Divergenz-Prüfung

---

## ✅ ACCEPTANCE CRITERIA (Definition of Done)

| Aufgabe | DoD |
|---------|-----|
| C-01, C-02 | Branches gemerged, keine Konflikte, Preflight grün |
| C-03 | Relationship-Tests in test_all integriert, DOKI-Doku aktualisiert |
| I-01 | `reset_state()` sauber, keine Node-Leaks, alle Constraints stabil |
| I-02 | DOKI Selfcheck: exakte Zahl dokumentiert, reproduzierbar |
| Q-01 | NEUES SPIEL → historical_world → world.tscn Flow 100% reproduzierbar |
| Q-03 | Tutorial Overlay für `runtime_ux_scan` findbar/schließbar |
| Q-04 | "Erstes Schiff" durchspielbar (Werft bau→ Forschung→ Bau→ Start) |
| Q-05 | Grüner Home-Planet-Marker in Tutorial Schritt 2 sichtbar |
| L-01..L-04 | 4 Dateien in `res/lore/` existieren, LORE.md Links funktionieren |
| L-05..L-19 | Alle Lore-Inhalte geschrieben, intern konsistent, mit Simulation verknüpft |
| S-01 | RelationshipEngine: WorldState.relationships mit Deltas, Trade-Compatibility |
| S-02 | EpochEngine: deterministische Epoch-Transitions, Arc-Math |
| S-03 | Trade Window: Ring-Adjazenz, Events in HistoricalSimulation |
| G-01 | `preflight.gd -x` → RESULT: PASSED (44 Constraints) |
| G-03 | Clean merge auf main, CI grün |
| G-04 | Post-Merge: kein Drift, alle Artefakte konsistent |

---

## 🔄 WORKFLOW-ENFORCEMENT

### JEDER Commit MUSS:
1. **Falsifikation** vorab: Problem reproduziert, Root Cause verstanden
2. **Patch-Plan** geschrieben: Minimal, atomar, testbar
3. **Falsifikation** des Plans: Peer-Review (2 Subagents), Edge-Cases geprüft
4. **Execution**: Implementierung NUR der geplanten Änderungen
5. **Post-Falsifikation**: Tests laufen, Preflight grün, keine Regressionen
6. **DOKI Flow**: `prepare` → `narrator_body.md` schreiben → `finish` → `git commit -F .commit_msg.txt`
7. **Follow-up Falsifikation**: Nach Commit prüfen, ob alles stabil

### VERBOTEN:
- ❌ `git commit -m` ohne DOKI
- ❌ `--no-verify`
- ❌ Mehrere unzusammenhängende Änderungen in einem Commit
- ❌ "Später fixen" — alles wird JETZT root-cause behoben

---

## 📅 NÄCHSTE SOFORT-AKTIONEN

1. **JETZT**: Branch 845 und 580 lokal auschecken und diffen
2. **JETZT**: F-304 (`reset_state` Isolation) tief analysieren — Code in `scripts/preflight_v2/v2_fixture.gd` + `v2_context.gd`
3. **JETZT**: QA2-GAME-3 (NEUES SPIEL Flow) reproduzieren — `main_menu.gd` + `run_preparation.gd` + `historical_world_bootstrap.gd`
4. **JETZT**: Lore-Dateien `res/lore/` anlegen (Verzeichnis existiert nicht!)
5. **PARALLEL**: F-306 DOKI Selfcheck Code lesen (`scripts/doki/doki_selfcheck.gd`)

---

*Erstellt: 2026-08-30 | Basis: ROADMAP.md, FINDINGS.md, LORE.md, LORE_RESEARCH.md, ARCHITECTURE.md, DESIGN.md, User Instructions*
*Dieses Dokument wird bei jedem Commit aktualisiert (DOKI post-commit Hook)*