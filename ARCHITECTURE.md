<div align="center">

# 🏛️ SNIPWAR — SYSTEMARCHITEKTUR & TECHNICAL GROUND TRUTH

**VERBINDLICHE ENGINE-SPEZIFIKATION · DETERMINISTISCHE VERTRÄGE · REPRODUZIERBARE ENGINE-STATE-WELT**

[![Engine: Godot 4.7](https://img.shields.io/badge/Engine-Godot%204.7-478cbf?style=for-the-badge&logo=godotengine&logoColor=white)](https://godotengine.org/)
[![Preflight](https://img.shields.io/badge/Preflight-43%20Constraints%20PASS-2ea44f?style=for-the-badge)](#-automatisierte-preflight-suite-v2-architecture)
[![Sprache: GDScript](https://img.shields.io/badge/GDScript-4.7-blue?style=for-the-badge)](#-architektur--vom-katalog-zum-spielstand)

</div>

---

## 📐 ARCHITEKTUR-PRINZIPIEN & GROUND TRUTH

1. **Code schlägt Dokumentation:** Die Laufzeitverträge im GDScript-Code und in den Preflight-Constraints sind die finale Autorität.
2. **Headless-First & Deterministisch:** Alle Logik-, Math- und Daten-Ketten müssen headless ohne UI-Fenster im Seed-Modus (`PREFLIGHT_LAYOUT_SEED = 424242`) reproduzierbar laufen.
3. **Single Source of Truth (SSO):** Der `GameState`-Autoload verwaltet den weltweiten Spielzustand über 4 separierte Domänen-Manager.
4. **Keine verdeckten Fallbacks:** Es gibt in diesem Repository keine stummen Swallows, leeren Fallbacks oder übergangenen Preflight-Fehler.

---

## ⚙️ ENTWICKLUNGSUMGEBUNG & TERMINAL-COMMANDS

### Engine & Binary
- **Engine:** Godot 4.7 Console-Binary (`Godot_v4.7.2-stable_win64_console.exe`).
- **Binary-Variable:** `export GODOT_BIN="/pfad/zu/godot4_console"` (oder in `PATH`).

```bash
# Smoke-Test (Bootet Hauptszene, beendet nach 2 Sekunden)
$GODOT_BIN --headless --path . --quit-after 2

# Vollständige Preflight-Prüfung (44 Constraints)
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd -x
```

> [!NOTE]
> Der Headless-Lauf meldet am Prozessende Teardown-Warnungen (`ERROR: ...RID allocations...leaked` / `ObjectDB instances leaked`). Das ist normales Dummy-Renderer-Verhalten. Einzig entscheidend ist die Ausgabe `RESULT: PASSED`.

---

## 🔍 CODE-NAVIGATION & DIAGNOSE-TOOLS

Im Repository stehen zwei spezialisierte Headless-Suchwerkzeuge bereit (kein rohes `grep`/`rg`):

### 1. ConceptIndex CLI (`concept_search.gd`) — Semantische Architektur-Suche
Prüft Domänen, freie Class-Slots, Synonyme und Klassenzuordnungen.

```bash
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd fleet
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --unmapped
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --free-slots
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --class ShipManager
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --domain economy
```

### 2. Global Search CLI (`global_search.gd`) — Volltext- & Abhängigkeits-Engine
Scannt rekursiv `.gd`, `.tres`, `.tscn`, `.md`, `.json` mit JSON-Output inklusive Abhängigkeits-Graph (`dependency_graph`) und verfügbarer Klassen-Manifeste (`classes_available`).

```bash
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "fleet_supply_bonus" --type tres,json
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "assemble_ship" --type gd --context 5
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "runtime_audio|runtime_animation"
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "func (_?[a-z_]+)" --regex
```

---

## 🏛️ SZENEN-ARCHITEKTUR & SSO DOMÄNEN-MODELL

SnipWar gliedert das Spiel in 3 bootbare Schichten (Layer) über einem zentralen `GameState`-SSO:

```
MainMenu (scenes/main_menu/main_menu.tscn)
	├── Neues Spiel  →  GameState.request_new_run() + SceneDirector.goto_scene("world")
	└── Weiter       →  SaveGameService.load_run(0) + goto_scene("world")

WorldBootstrap._enter_tree()  (Wurzel von scenes/world/world.tscn)
    ├── Szenarioauswahl (ScenarioCatalog)
    ├── Layout-Seed finalisieren (_finalize_layout_seed)
    ├── WorldGenerator.generate_catalog()  →  aktiver Startkatalog (p0/p1 = Homeworlds)
    ├── ChunkCoordinator  →  weitere Planeten lazy aus Seed und FoV erzeugen
    └── GameState.begin_new_game()/reconnect_world()  →  SSOT für Ownership, Ressourcen, Forschung, Upgrades

Bootstrap._ready()
    └── deal_resources(catalog, pool, seed)  →  deterministischer Ressourcen-Deal

PlanetField._enter_tree()
    └── SeededLayout._enter_tree()  →  Planeten-Nodes erzeugen, Größenprofile, Detail-Seeds
        └── PlanetNetwork._ready()  →  Nachbarschaftsgraph, NavigationField, UI-Aufbau
```

### Die 4 Domänen-Manager von `GameState`

`GameState` ist als Autoload registriert und delegiert intern an vier spezialisierte Domain-Manager:

| Domäne | Skript / Klasse | Verantwortlichkeit & Verträge |
|:---|:---|:---|
| **FactionDomain** | `scripts/state/domains/faction_domain.gd` | Sektor-Ownership, Homeworld-Verwaltung, Discovery-Status, Scan-Intel-Registrierung, Gratis-Starter-Scout. |
| **EconomyDomain** | `scripts/state/domains/economy_domain.gd` | Faction-Vaults, Ressourcen-Deals (`deal_resources`), Upgrade-Käufe (`purchase_upgrade`), Worker-Fabriken, Gatherer-Erträge. |
| **TechDomain** | `scripts/state/domains/tech_domain.gd` | Forschungsfortschritt, Tech-Prerequisites, Freischaltungen für Schiffe/Upgrades, zeitgesteuerte Research-Jobs. |
| **ShipDomain** | `scripts/state/domains/ship_domain.gd` | Schiffs-Montage (`assemble_ship`), Rumpf- & Modulinventar, Bau-Jobs, Generierung von `FleetSnapshot`-Replays. |

---

## 💾 SAVE / LOAD ENGINE & SPEICHER-SLOTS

- **Autoload:** `SaveGameService`
- **Resource-Klasse:** `RunSaveData` (`resources/run_save_data.gd`)
- **Pfad:** `user://saves/run_slot_<N>.tres`

### Slot-Konvention
- **Slot 0:** Live-Spielstand des Nutzers (darf von automatisierten Test-Runs **niemals** überschrieben oder gelöscht werden).
- **Slots 1–7:** Reserviert für automatisierte Preflight-Tests, Szenario-Isolation und Snapshots.

```gdscript
# Atomares Schreiben & Lesen:
SaveGameService.save_run(0) # Schreibt aktuellen GameState in Slot 0
SaveGameService.load_run(0) # Lädt Slot 0 & stellt GameState wieder her
```

---

## 🛤️ MATHEMATISCHE LOGISTIK- & KAMPF-FORMELN

### 1. Flugzeit-Formel (`FlightTime.gd`)

Preview und tatsächlicher Worker-/Schiffs-Transit nutzen identisch:

$$\text{Flugzeit (s)} = \frac{\left(\frac{\text{Distanz}}{100}\right) \times 8.0 \times \left(1.0 + 0.05 \times \sqrt{\max(\text{Einheiten} - 1, 0)}\right)}{\text{SpeedMultiplikator}_{\text{Quelle}}}$$

### 2. Worker-Cluster-Packing (`worker_manager.gd`)

Transits packen Einheiten nach dem *Largest-First*-Prinzip. Die visuellen Tiers unterscheiden sich von der logischen Kapazität:

| Tier | Kapazität (logisch) | Formation | Visuelle Stufe |
|:---:|:---:|:---:|:---:|
| **K** | 1 | Solo | Klein |
| **M** | 5 | V-Formation | Mittel |
| **L** | 100 | Keil | Groß |

*Beispiel:* 7 Worker werden deterministisch aufgeteilt in `1× M (5) + 2× K (1)`.

### 3. CPU Dispatch AI (`CpuDispatchAI.gd`)

Die KI der Fraktion Beta arbeitet mit dynamischer Pacing-Anpassung:

```
decision_interval:       12.0s (Basis)
pacing_decay_rate:       0.02 (pro Intervall)
min_decision_interval:    6.0s (Hard Limit)
reserve_workers:             2 (Garnisons-Reserve)
minimum_source_workers:      3 (Mindestanzahl für Abflug)
dispatch_fraction:         0.5 (50 % der verfügbaren Einheiten)
```

**Prioritäten-Kaskade:**
1. **Kolonisieren:** Nächster gescannter neutraler Planet (`colony`-Mission).
2. **Verstärken:** Eigener Planet mit niedrigster Garnison (`cargo`-Mission).
3. **Angreifen:** Gegnerischer Planet mit schwächerer Garnison (`military`-Mission).

---

## ⚔️ KAMPF-RESOLVE & LAYER-TRANSITIONEN

Der `PlanetArrivalResolver` unterscheidet zwei Ankunftspfade:

### Worker-Military-Ankünfte (`resolve_military_arrival`)
1. **Gleiche Fraktion:** Eintreffende Worker verstärken die Garnison.
2. **Feindliche Fraktion:** Aufruf von `ConquestSimulator.simulate_conquest()`.
   - `captured == true`: Planet wechselt Ownership. Überlebende Angreifer werden neue Garnison.
   - `captured == false`: Angriff abgewehrt. Verluste werden verrechnet.

### Schiffs-Ankünfte (`resolve_ship_arrival`)
1. **Colony-Schiff:** Friedliche Besiedlung gescannter neutraler Planeten (`first_colony`-Milestone).
2. **Militärschiff vs. Verteidiger-Flotte:** Start von Layer 2 (`FleetBattleSimulator`).
3. **Militärschiff vs. Garnison (ohne Verteidiger-Flotte):** Start von Layer 3 (`ConquestSimulator`).

---

## 📱 UI-STACK & CANVASLAYER-HIERARCHIE

Die Benutzeroberfläche nutzt eine strikte CanvasLayer-Kaskade zur Vermeidung von Input-Overlap:

| CanvasLayer | Komponente | Beschreibung & Input-Verhalten |
|:---:|:---|:---|
| **—** | `PlanetNetwork` | World-Space: Planeten, Transitlinien, NavigationField. |
| **40** | `DossierLauncher` | Drei Top-Left Buttons (`PLANET`, `WERKSTATT`, `FORSCHUNG`). |
| **50** | `PlanetNetworkUI` | HUD, VaultBar, PlanetPanel, Dispatch-Preview-Footer. |
| **60** | `TechnologyMenu` | Kompaktes Tech-Overlay (schließt PlanetPanel bei Öffnung). |
| **70** | `PauseMenu` | System-Pause (mit `PROCESS_MODE_ALWAYS`). |
| **80** | `PaperDossier` | Vollbild-Papercraft-Modale. Blockiert `MapCamera` Pan/Zoom. ESC schließt Dossier. |
| **90** | `CaptureDecisionOverlay` | Planeten-Übernahme-Entscheidungsdialog. |
| **100** | `GrainOverlay` | Post-Processing (Paper-Grain & Vignette-Shader). |

---

## 🧪 AUTOMATISIERTE PREFLIGHT-SUITE (V2 ARCHITECTURE)

Die Preflight-Suite in `scripts/preflight.gd` ist ein maßgeschnederter, Headless-Testorchestrator ohne externe Abhängigkeiten.

### CLI-Optionen
- `-v, --verbose`: Ausgabe aller einzelnen Assertions.
- `-x, --fail-fast`: Sofortiger Abbruch bei der ersten fehlgeschlagenen Assertion.
- `-f, --filter=<name>`: Führt nur Constraints aus, die den Substring enthalten.
- `--reverse`: Führt Constraints in umgekehrter Reihenfolge aus (Isolations-Test).
- `--list`: Listet alle registrierten Constraints auf.

### Die 43 Preflight-Constraints

| # | Constraint | Test-Fokus | Execution Mode |
|:---:|:---|:---|:---:|
| 1 | `camera_and_input` | MapCamera Pan/Zoom & Bounds | Scene |
| 2 | `chunk_expansion` | Prozedurale Chunk-Erweiterung & FoV-Cycling | Pure |
| 3 | `cluster_generation` | Cluster-Generierung & Sektor-Flavor | Pure |
| 4 | `colony_milestone` | Friedliche Besiedlung & `first_colony` Milestone | Scene |
| 5 | `concept_index` | Semantischer ConceptIndex & Class-Mapping | Pure |
| 6 | `conquest_grid_combat` | Conquest Grid-Kampf-Simulation | Scene |
| 7 | `context_handover` | SceneDirector Handover & Battle-Kontext | Scene |
| 8 | `cpu_dispatch` | `CpuDispatchAI` Pacing & Reserve-Schwellen | Scene |
| 9 | `dead_code` | Dead-Code-Heuristik (Warning-only) | Pure |
| 10 | `docs_integrity` | Duplicate-Headings & Markdown-Tabellen-Integrität | Pure |
| 11 | `economy_production` | Upgrades, Produktions-Boosts & Raffinerie-Konvertierung | Scene |
| 12 | `effects_and_traits` | Modifikatoren-, Trait- & Effektrechnungen | Pure |
| 13 | `event_log` | Event-Logging, Toasts & Dateiexport | Scene |
| 14 | `flight_and_dispatch` | `FlightTime.seconds_for()` & Cluster-Packing | Pure |
| 15 | `game_state_compatibility` | GameState Fassaden-Methoden & Signal-Signaturen | Scene |
| 16 | `global_search` | Global Search Engine Werkzeug-Test | Pure |
| 17 | `grid_system` | Conquest-Grid & Coordinate Mapping | Scene |
| 18 | `ingame_player_and_transitions` | IngamePlayerControls & FloatingText | Scene |
| 19 | `layers_2_and_3` | Layer-2 & Layer-3 Simulator-Replays | Scene |
| 20 | `layer_independence` | Layer-Isolation & Fixture-Hygiene | Scene |
| 21 | `local_resources` | Lokale Planeten-Ressourcen-Verträge | Scene |
| 22 | `main_menu_and_flow` | Hauptmenü-Flow & Continue-Status | Scene |
| 23 | `mcp_capture_contract` | MCP Capture Vertrag (Async-only, Texture-Ready) | Pure |
| 24 | `mechanic_coverage` | Mechanik-Erkennung & Szenario-Abdeckung | Pure |
| 25 | `mission_semantics` | Military/Colony/Cargo/Collect Missionsregeln | Scene |
| 26 | `module_damage_model` | Modul-Schadensmodell (Konquest) | Pure |
| 27 | `narrative_runtime` | Narrative Runtime Gate G1–G24 (fail-closed, read-only) | Pure |
| 28 | `navigation_growth` | Waypoint-Graphen & KNN-NavigationField | Pure |
| 29 | `paper_style` | Paper-Visuallinie & Asset-Integrität | Pure |
| 30 | `pause_and_context` | Modal-Hierarchie & Pausen-Gating | Scene |
| 31 | `research_ship` | Forschungs-Schiff & Auftragslogik | Scene |
| 32 | `resources_and_seed` | Seed-Invarianz & `deal_resources()` | Scene |
| 33 | `save_game_roundtrip` | Verlustfreier Save/Load Roundtrip **+ Chronicle-Payload-Vertrag** | Scene |
| 34 | `save_game_slots` | Save-Slot Write/Read/Corruption Checks | Pure |
| 35 | `scene_boot` | Bootszenen-Hierarchie & Viewport-Handling | Scene |
| 36 | `sector_classification` | Sektor-Typisierung & Flavor-Zuordnung | Pure |
| 37 | `selection_and_context` | `SelectionService` & Kontextmenü-Gating | Scene |
| 38 | `ship_catalog_and_assembly` | Teile-Katalog, Rumpfmontage & Tech-Gating | Scene |
| 39 | `ship_transit_and_arrival` | ShipBase Transit & Conquest/Battle Triggers | Scene |
| 40 | `upgrade_catalog` | Upgrades, Voraussetzungen & Exklusivitäten | Pure |
| 41 | `world_details_and_scale` | Planeten-Größenprofile & Detail-Seeds | Scene |
| 42 | `world_generator_scaling` | Deterministische Welt- & Katalog-Generierung | Pure |
| 43 | `world_planets_and_dispatch` | Planeten-Netzwerk & Routen-Erstellung | Scene |

> [!NOTE]
> Die Constraints 33 (`save_game_roundtrip`) und 27 (`narrative_runtime`) sind die
> **Modularisierungs-Verträge**: Chronicle-Payload überlebt den Roundtrip
> (4 Checks) und die Narrative Runtime bleibt konform (G1–G24).

---

## 🧱 MODULARISIERUNG & SEPARATION (Phasen 1–9, abgeschlossen)

Adapter-first, contract-preserving: Keine RNG-Reihenfolge, kein Save-Schema,
keine Gameplay-Regel wurde verändert. Details: `docs/FINDINGS.md`
(„Modularisierung & Separation“) und `docs/INVENTORY_MATRIX.md`.

### Verantwortungsgrenzen (real im Code)

```text
Config-Resources → GameConstants (dependency-frei)   [Phase 1]
GameState        → EventBus → EventLog/WorldChronicle [Phase 2]
WorldChronicle   → GameState nur via expliziter Input-Schnittstelle [Phase 3]
Save             → RunSaveData inkl. ChronicleSaveData [Phase 4]
Welt-Objekte     → register_* bei GameState statt Szenenbaum-Scans [Phase 5]
UI               → get_economy_manager() statt Baum-Scans [Phase 6]
Narrative        → narrative_runtime (Python) hinter CLI-Gate [Phase 7]
Presentation     → Snapshot → Playback → Renderer (nur Snapshots) [Phase 8]
Cleanup          → tote Pfade entfernt; Fallbacks dokumentiert [Phase 9]
```

### Neue Dateien (Phase 1–9)

| Datei | Zweck |
|-------|-------|
| `scripts/config/game_constants.gd` | Dependency-freie StringName-Konstanten (Compile-Zyklus-Fix) |
| `scripts/preflight/constraint_narrative_runtime.gd` | 43. Constraint: Narrative Gate fail-closed |
| `scripts/history/historical_snapshot.gd` | Pure Snapshot-Datenklasse |
| `scripts/history/playback_controller.gd` | Snapshot-Playback (nur Snapshots) |
| `scripts/ui/history/historical_renderer.gd` | Snapshot-Renderer (SVG-Wiederverwendung) |
| `scripts/testing/historical_playback_test.gd` | 18 Checks, Determinismus simulate==with_snapshots |
| `docs/STRING_MATRIX.md` | Alle StringName-/Event-Konstanten |
| `docs/INVENTORY_MATRIX.md` | Systemkarte: System → Datei → Klasse → API |
| `docs/SEARCH_INDEX.md` | LLM-freundlicher Flach-Index (global_search-durchsuchbar) |

---

## 🔬 EIGENE DEVELOPER- & AGENTEN-INFRASTRUKTUR

### 📡 S.C.O.U.T. — Model Context Protocol Bridge
- **Pfad:** `addons/gdscript_mcp/`
- **Funktion:** Ermöglicht KI-Agenten die Steuerung und Inspektion des laufenden Spiels (Port 9090 Runtime, Port 9091 Editor).
- **Werkzeug-Umfang:** Over 107 registrierte Tools.
- **Vertrags-Regeln:**
  1. Screenshots dürfen **nur** via Async-Handler nach `frame_post_draw` aufgenommen werden (`mcp_capture_contract`).
  2. Jedes Capture erfordert OCR-/visuellen Beweis (`visual_evidence`).

### 📜 DOKI — Deterministisches Commit-Gate
- **Pfad:** `scripts/doki/`
- **Funktion:** Verhindert rohe Commits (`git commit -m` wird per Hook geblockt). Erzwingt erzählte Commit-Bodys.
- **Composite-Hash-Seed:** `Djb2(prevComposite + TreeHash + DiffHash + Impuls) → XorShift128`.
- **Composite-Format:** `c<count>j<jitter>n<narrator>a<arc>p<plot>` (z. B. `c17j48n14a1p1`).
- **Charaktere (14):** 1. Buffy, 2. Basher, 3. Thinker, 4. Vannon, 5. Squizzle, 6. Devin, 7. Argos, 8. Ghost, 9. Spark, 10. Glitch, 11. Null, 12. Echo, 13. Flux, 14. Sage.
- **9 Integrity Checks:** 1–6 weich (Stil, Tokens, Narrator-Match), 7–9 HART (Kausalität, DocSync, ChainAudit).

---

## 🔄 GIT HOOK PIPELINE & WORKFLOW

Jeder Commit läuft unumgehbar durch folgende Stufen:

```
┌─────────────┐     ┌─────────────┐     ┌──────────────┐
│ pre-commit  │────▶│ commit-msg  │────▶│ post-commit  │
│             │     │             │     │              │
│ whitespace  │     │ DOKI-Flow   │     │ push origin  │
│ + preflight │     │ (Narrator)  │     │ HEAD:main    │
└─────────────┘     └─────────────┘     └──────────────┘
```

1. **`pre-commit`**: Führt Preflight aus. Bei Fehlschlag bricht der Commit ab.
2. **`commit-msg`**: Verifiziert den DOKI-Erzähl-Body (`finish --body-file .doki/narrator_body.md`).
3. **`post-commit`**: Pusht den Commit sofort auf `origin/main`.

---

## 📊 METRIKEN DES CODESTANDS

| Metrik | Stand (Aug 2026) |
|:---|:---|
| GDScript-Dateien | **155** |
| Zeilen GDScript (LOC) | **22.469** |
| Szenen (`.tscn`) | **16** |
| Textur- & Audio-Assets | **419** |
| Engine-Ressourcen (`.tres`) | **91** |
| Preflight Coverage | **44 / 44 Constraints PASS** |

---

<sub>SnipWar Systemarchitektur // Stand: 2026 · Dokumentations-Quelle der Wahrheit</sub>
