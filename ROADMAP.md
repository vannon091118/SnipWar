# ROADMAP — SnipWar Konsolidierungs-Roadmap (Dependency Graph)

> **Regel:** Dieses Dokument ist die EINZIGE vorwärts denkende Quelle des Repos.
> `CHANGELOG.md` blickt zurück (abgeschlossene Änderungen), `docs/FINDINGS.md`
> beschreibt offenen Schaden, `ROADMAP.md` definiert den verbleibenden Weg.
> Kein anderes Dokument enthält eine parallele Roadmap.
>
> **Status-Legende:** `TODO` · `BLOCKED` · `IN_PROGRESS` · `VERIFIED` · `DEFERRED`
> **Prioritäten:** P0 (blockiert Kohärenz/Runtime) · P1 (hoher Architektur-Effekt) ·
> P2 (relevante Schuld) · P3 (Optimierung) · P4 (optional)
>
> **Stand:** 2026-08-29 · Basis: Forensik-Audit (43/43 Preflight PASS, 61,2 s;
> 313 `.gd` / 60.404 LOC live; 10 Autoloads; 19 Szenen verdrahtet).

---

## 0. Globale Zielstruktur

```
CHANGELOG.md   ← Vergangenheit (DOKI-generiert, kompakt)
docs/FINDINGS.md ← offener Schaden (Status: OPEN/MITIGATED/CLOSED/DEFERRED/WONT_FIX)
ROADMAP.md     ← Zukunft (TODO-Kette mit Dependencies, Acceptance Criteria)
docs/modules/  ← nur echte Modulverträge (API/Datenmodell/Invarianten), keine Kopien
```

**Zyklus:** Finding behoben → FINDINGS `CLOSED` → ROADMAP `VERIFIED` → CHANGELOG-Eintrag.

---

## 1. Aktuelle Wahrheit (FACT, gemessen 2026-08-29)

- Preflight: **44/44 PASSED** (63.632 ms; `historical_world`-Gate 7,2 s; top-6 Constraints ≈ 16 s).
- Live-Code: 313 `.gd` / 60.404 LOC (scripts 44.895 + addons/MCP 15.509); `snapshots/` enthält eine 19-MB-Kopie (52.171 LOC, 0 getrackt).
- Autoloads: **10** (EventBus, GameState, WorldChronicle, GameCycleManager, SceneDirectorService, SaveGameService, EventLog, TouchFeedbackLayer, McpRuntime, McpProjectAdapter).
- Doku-Drift: Constraint-Zahlen 34/36/38/39/42 werden in 7 MDs behauptet; DESIGN §17 SO1 nennt 8 Autoloads.
- **P0-Bug (FIXED):** `NEUES SPIEL → Identität → historical_world` bootete mit leerer Chronik — **R-050 schließt** (RunPreparation vor Szenenwechsel; historical_world_flow_test 11/11; historical_world-Constraint 11/11, Preflight 44/44).
- Signal-Heuristik „0 Consumers = tot“ **widerlegt** (F-212): 6/38 GameState-Signale ohne externe `.connect()` — darunter akzeptierte Anker (`mid_game_started`, `transit_changed`, `run_started`, `planet_building_placed/destroyed`). `battle_context_changed` ist Mechanik-Anker der Combat-Mechanik (MechanicRegistry-Reflection + scenarios/*.tres), `run_started`/`ship_launched`/`milestone_reached` sind Compatibility-Facade mit kanonischen EventBus-Zwillingen.
- ConceptIndex: 3 unmapped Klassen (GameConstants, FactionAI, PreflightCodeIndex).
- Kein zentraler Test-Orchestrator; `scripts/history/test_determinism.gd` liegt außerhalb von `scripts/testing/`.

---

## 2. Dependency Graph

```
R-001 Doku-SSOT (ROADMAP/FINDINGS)
  ├─ R-002 Constraint-/Autoload-Zahlen vereinheitlichen
  ├─ R-005 CODEBASE_AUDIT konsolidieren (Stränge → FINDINGS)
  └─ R-011 MCP-Audit-Fix + Session-Docs archivieren
R-050 HistoricalWorld-Lifecycle (P0, unabhängig von R-002)
  ├─ R-051 Preflight-Constraint historical_world (Gate für den Flow)
  └─ R-052 HistoricalWorld-Kontext-Übergabe (Jahr-0-Snapshot → Weltstart)
R-003 Repo-Hygiene (kilo.json/snapshots/tmp) — BLOCKED auf User-Freigabe (destruktiv)
R-006 tote Signale beseitigen (nach R-050, da battle_context_changed im selben Bereich)
R-007 economy_domain konsolidieren (2–3 Kohärenzgrenzen)
R-008 planet_network UI/Logik trennen
R-009 Test-Orchestrator test_all.gd
R-010 ConceptIndex unmapped Klassen mappen
R-012 Preflight-Shared-Inventory + Cheap→Expensive
R-013 Save-Versionierungsaudit
R-014 QA-Stränge (Tutorial→Werft→Neues-Spiel) nach R-050
R-015 CHANGELOG-Boilerplate komprimieren (DOKI)
R-016 Refinery serialisierbar / mech_frame entscheiden
```

---

## 3. Tasks

### R-001 — Doku-SSOT: ROADMAP + FINDINGS etablieren — **P0**
- **WHY:** Keine Roadmap vorhanden; FINDINGS muss die neuen Audit-Befunde tragen.
- **CURRENT:** ROADMAP fehlt; FINDINGS aktuell, aber ohne Konsolidierungs-Befunde.
- **DEPENDS:** — · **BLOCKS:** R-002, R-005, R-011
- **MODULES:** Doku (global)
- **VERIFICATION:** `docs_integrity_entry_test` + Preflight-Constraint `docs_integrity`
- **DoD:** ROADMAP.md existiert mit Dependency-Graph; FINDINGS trägt F-201…F-210; Preflight grün.
- **STATUS:** `VERIFIED` (dieser Commit)

### R-002 — Constraint-/Autoload-Zahlen vereinheitlichen — **P0** ✅ VERIFIED
- **WHY:** 6 verschiedene Constraint-Zahlen (34–43) erzeugten falsche Systemwahrheit für Agents.
- **CURRENT (vor Fix):** ARCHITECTURE.md:349 (38); DESIGN §1 (39)/§14 (34); docs/README (36 ×3); PLAN.md (36); GAME_CYCLE (34); AGENTS (40); DESIGN SO1 (8 Autoloads).
- **DEPENDS:** R-001 · **BLOCKS:** —
- **MODULES:** Doku
- **DoD:** Alle MDs nennen 43 Constraints / 10 Autoloads; historische datierte Lauf-Belege bleiben unangetastet.
- **STATUS:** `VERIFIED`

### R-003 — Repo-Hygiene: kilo.json, snapshots/, tmp_* — **P0**
- **WHY:** `kilo.json` (getrackt, absolute Maschinenpfade), `snapshots/pf_pre_cluster/` (19 MB, 52.171 LOC Kopie), Root-`tmp_*` (ignoriert) verursachen Rauschen/Verwechslung.
- **CURRENT:** Alle klassifiziert (F-206). **DEPENDS:** — · **BLOCKS:** —
- **DoD:** kilo.json entfernt (git rm), snapshots/ + tmp_* gelöscht, Preflight grün.
- **STATUS:** `BLOCKED` — destruktiv, wartet auf User-Freigabe

### R-005 — CODEBASE_AUDIT konsolidieren — **P1**
- **WHY:** `docs/CODEBASE_AUDIT.md` (29.08.) ist durch neueren Code widerlegt („HistoricalWorld fehlt“ — existiert und ist verdrahtet).
- **DEPENDS:** R-001 · **BLOCKS:** —
- **MODULES:** Doku/Chronik
- **DoD:** Einzigartige Inhalte → FINDINGS/Modul-Doku; Rest archiviert.
- **STATUS:** `TODO`

### R-050 — HistoricalWorld-Lifecycle & Handover — **P0** ✅ VERIFIED
- **WHY:** Spielerfluss „NEUES SPIEL“ endete in toter Szene (leere Chronik); Doppel-Simulation drohte (zweites `begin_new_game`).
- **CURRENT (vor Fix):** Reproduziert via Headless-Boot (F-207). Run wurde nicht vorbereitet; Playback startete nie.
- **DEPENDS:** — · **BLOCKS:** R-014, R-051, R-052
- **MODULES:** main_menu, `run_preparation.gd` (neu), historical_world_bootstrap, WorldChronicle, GameState
- **VERIFICATION:** `historical_world_flow_test.gd` 11/11 PASS; `chronicle_lifecycle_test` 21/21; `historical_playback_test` 18/18; `chronicle_core_test` 22/22; compile_gate 315/315; Preflight 43/43 (62,9 s)
- **DoD:** Flow: Run-Prepare → historical_world (gefüllte Chronik, Playback startet) → Jahr 0 → `request_world_reconnect()` → world.tscn reconnected (kein zweites `begin_new_game`); Bootstrap-Fallback statt Dead-End; Preflight grün.
- **STATUS:** `VERIFIED`

### R-051 — Preflight-Constraint historical_world — **P2** ✅ VERIFIED
- **WHY:** Der Flow war von keinem Gate abgedeckt (scene_boot bootet nur world.tscn).
- **DOCH GEPRÜFT:** `constraint_historical_world.gd` (pure, 11 Checks, 7,2 s): RunPreparation(424242) → Szene-Boot → Playback geladen → Snapshots == Chronik → Fallback (leere Chronik → Snapshot-Erzeugung) → Reconnect-Vertrag. Preflight 44/44 (63,6 s), docs 43→44 in allen 6 Stellen vereinheitlicht.
- **DEPENDS:** R-050 · **BLOCKS:** —
- **STATUS:** `VERIFIED`

### R-052 — HistoricalWorld-Kontext-Übergabe (Jahr-0-Snapshot → Weltstart) — **P1**
- **WHY:** Chronik fällt ohne echte Daten auf `_default_planets()` zurück; die Vorstart-Welt ist eine Parallel-Erzählung ohne Rückkopplung in die Spielwelt.
- **DEPENDS:** R-050 · **BLOCKS:** —
- **DoD:** Jahr-0-Ownership/Faction-State wird Basis des Weltstarts; `faction_planet_snapshot()` == Chronik-Endzustand; keine zweite Simulation.
- **STATUS:** `TODO`

### R-006 — Tote-Signal-Befund klassifizieren — **P1** ✅ VERIFIED (revidiert)
- **WHY (ursprünglich):** `battle_context_changed` + `run_started`/`ship_launched`/`milestone_reached` galten als Legacy-Altlasten.
- **ERGEBNIS:** Befund durch Messung **widerlegt** (F-212): 6/38 Signale ohne Consumer, 5 akzeptierte Anker; `battle_context_changed` = einziger Combat-Mechanik-Anker (Entfernung hätte Coverage-Matrix + .tres/Spec inkonsistent gemacht); die übrigen 3 sind Compatibility-Facade mit EventBus-Zwillingen (F-204-Dokumentation bestätigt „Compatibility-Signal bleibt“).
- **ÄNDERUNG:** Kein Signal entfernt; game_state.gd-Kommentar verankert die Klassifikation; FINDINGS F-202/F-204 geschlossen, F-212 neu.
- **VERIFICATION:** repo-weite `.connect()`-Messung (29.08.); mechanic_coverage-Constraint; docs_integrity.
- **STATUS:** `VERIFIED`

### R-007 — economy_domain konsolidieren — **P1**
- **WHY:** 1.282 LOC, ≥5 Verantwortungsgruppen (Vaults/Deals/Upgrades/Worker-Fabriken/Gathering/Refinery/Trade/Transport-Records).
- **DEPENDS:** — · **BLOCKS:** R-016
- **DoD:** 2–3 kohärente Einheiten (Deal/Upgrade · Refinery/Trade · Gathering/Transport); GameState-Fassade unverändert; Preflight + Tests grün.
- **STATUS:** `TODO`

### R-008 — planet_network UI/Logik trennen — **P1**
- **WHY:** 1.017 LOC mischen Routing/Netzwerk mit UI-Aufbau, Tooltips, Tutorial-Spawn, Dispatch-Preview; `planet_network_ui.gd` existiert bereits.
- **DEPENDS:** — · **BLOCKS:** —
- **DoD:** UI-Teil in planet_network_ui; Netzwerk-Logik bleibt; Tests grün.
- **STATUS:** `TODO`

### R-009 — Test-Orchestrator `test_all.gd` — **P2**
- **WHY:** 11 Entry-Tests + Preflight laufen einzeln; `test_determinism.gd` falsch platziert.
- **DEPENDS:** — · **BLOCKS:** —
- **DoD:** Ein Befehl orchestriert alle Gates mit eindeutigem Exit-Code; test_determinism verschoben.
- **STATUS:** `TODO`

### R-010 — ConceptIndex: unmapped Klassen — **P2**
- **WHY:** 3 Klassen (GameConstants, FactionAI, PreflightCodeIndex) unmapped.
- **DEPENDS:** — · **BLOCKS:** —
- **DoD:** `--unmapped` liefert 0; Preflight concept_index grün.
- **STATUS:** `TODO`

### R-011 — MCP-Audit-Fix + Session-Docs archivieren — **P2**
- **WHY:** MCP_AUDIT_REPORT referenziert nicht existentes `scripts/tools_count.gd`; addons/findings.md, progress.md, task_plan.md, mcp_live_test_results.md sind historisch.
- **DEPENDS:** R-001 · **BLOCKS:** —
- **DoD:** Referenzen gefixt; historische Docs archiviert (Inhalte in FINDINGS überführt).
- **STATUS:** `TODO`

### R-012 — Preflight-Shared-Inventory + Cheap→Expensive — **P2**
- **WHY:** top-6 Constraints ≈ 16 s; jeder Scan läuft pro Constraint neu (dead_code 3,5 s, scene_boot 3,5 s, global_search 2,9 s, world_details 2,5 s, context_handover 2,1 s, camera_and_input 1,6 s).
- **DEPENDS:** — · **BLOCKS:** —
- **DoD:** Gleiche Prüfqualität, gemessene Reduktion (vorher/nachher); kein Weakening.
- **STATUS:** `TODO`

### R-013 — Save-Versionierungsaudit — **P2**
- **WHY:** Roundtrip existiert; Versions-/Migrationsvertrag nicht belegt.
- **DEPENDS:** — · **BLOCKS:** —
- **DoD:** Versionierung dokumentiert oder implementiert; Roundtrip-Test deckt Migration ab.
- **STATUS:** `TODO`

### R-014 — QA-Stränge: Tutorial → Werft → Neues-Spiel — **P2**
- **WHY:** FINDINGS QA2-MCP-6 (Tutorial für MCP unsichtbar) blockiert QA2-GAME-2/-3.
- **DEPENDS:** R-050 · **BLOCKS:** —
- **DoD:** Overlay-Pfad für MCP auffindbar; „erstes Schiff“ durchspielbar.
- **STATUS:** `TODO`

### R-015 — CHANGELOG-Boilerplate komprimieren — **P3**
- **WHY:** 1.472 LOC, große DOKI-Boilerplate-Anteile.
- **DEPENDS:** — · **BLOCKS:** —
- **DoD:** Kompaktes Format (Datum, Slice-ID, Änderung, Verification).
- **STATUS:** `TODO`

### R-016 — Refinery serialisierbar / mech_frame entscheiden — **P3**
- **WHY:** Konvertierung hartcodiert in economy_domain; `mech_frame` inert.
- **DEPENDS:** R-007 · **BLOCKS:** —
- **DoD:** ResourceConversionDefinition ODER explizit als Nicht-Ziel dokumentiert.
- **STATUS:** `TODO`

---

## 4. Ausführungsreihenfolge (nächste Slice-Kandidaten)

1. ~~**R-050**~~ ✅ VERIFIED (343cabf) — HistoricalWorld-Lifecycle-Handover
2. ~~**R-002**~~ ✅ VERIFIED — Zahlen vereinheitlichen
3. **R-051** (P2) — Preflight-Gate für den Flow
4. **R-006** (P1) — tote Signale
5. **R-003** (P0, nach User-Freigabe) — Repo-Hygiene
6. **R-009** (P2) — Test-Orchestrator
7. **R-052** (P1) — Kontext-Übergabe Jahr 0
8. **R-010** (P2) — ConceptIndex