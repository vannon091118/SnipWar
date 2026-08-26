# SnipWar Agent Notes

---

## 🚀 QUICK START — WAS JEDER AGENT SOFORT WISSEN MUSS

### 1. Godot Binary & Headless
```bash
export GODOT_BIN="C:/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe"
# Alle Headless-Calls: $GODOT_BIN --headless --path . --script res://scripts/...
```

### 2. ZWEI SUCH-TOOLS (statt grep/rg)

| Frage | Tool | Beispiel |
|-------|------|----------|
| **Architektur**: Klassen, Domänen, freie Slots, Synonyme | `concept_search.gd` | `$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd fleet` |
| **Volltext**: String in .tres/.tscn/.md/.json + Kontext | `global_search.gd` | `$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "fleet_supply_bonus" --type tres,json` |

**ConceptIndex CLI** (semantisch):
```bash
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd fleet          # Suche
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --unmapped      # Ungemappte Klassen
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --free-slots    # Freie Slots
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --class ShipManager
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --domain economy
```

**Global Search CLI** (SearchCore-Engine, LLM-JSON-Output, immer mit Abhängigkeiten):
```bash
# Output ist IMMER ein kompaktes JSON (kein --no-json nötig):
#   results[]            Treffer + Kontext
#   classes_available    {ClassName: res://Pfad} — wer ist verfügbar
#   dependency_graph     je Datei: class_name, extends, preloads[], loads[]
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "fleet"
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "assemble_ship" --type gd --context 5
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "runtime_audio|runtime_animation"  # OR-Suche
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "func (_?[a-z_]+)" --regex  # Capture-Groups
# 2 Tool-Calls füralles: Klassen + Abhängigkeiten + Verfügbarkeit in EINEM Output
```

### 3. Preflight (Verbindlicher Qualitäts-Check)
```bash
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd -x   # Full Suite (36 Constraints, ~90s)
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd --filter=concept_index -v  # Einzelne Constraint
```
**Verbindlich:** `RESULT: PASSED` — ERROR-Traces am Ende sind normales Headless-Rauschen.

### 4. Commit-Workflow (Hooks sind aktiv!)
```bash
git add <datei1> <datei2> ...           # NIEMALS git add -A / .
git commit -m "type: kurzer titel" \
  -m "- pfad/datei1: Begründung." \
  -m "- pfad/datei2: Begründung."
# pre-commit führt Preflight aus → bei FAIL: fixen, neu stagen, commit wiederholen
```

---

## 📦 ARCHITEKTUR & SYSTEM-VERTRÄGE (Referenz)

### Szenen-Architektur (3 Spiele, 1 SSO)
| Szene | Layer | Zweck |
|-------|-------|-------|
| `scenes/main_menu/main_menu.tscn` | Einstieg | Neues Spiel / Weiter / Beenden |
| `scenes/world/world.tscn` | 1 (Overworld) | `WorldBootstrap` + `PlanetField` + `MeteorField` + `MapCamera` + `PauseMenu` |
| `scenes/battle/battle_scene.tscn` | 2 (Flotten) | `FleetBattleSimulator` + `BattleScene` + `IngamePlayerControls` |
| `scenes/conquest/conquest_scene.tscn` | 3 (Eroberung) | `ConquestSimulator` + `ConquestScene` |

**SSO:** `GameState` (Autoload) — 4 Domänen: `FactionDomain`, `EconomyDomain`, `TechDomain`, `ShipDomain`.

### Wichtige Konventionen
- **Save Slots:** Slot 0 = echter Spielstand (nie im Preflight löschen!), Slots 1–7 = Test-Slots
- **Seed:** Preflight erzwingt `PREFLIGHT_LAYOUT_SEED = 424242` (deterministisch)
- **Chunk-Welt:** Beide Shipped-Szenarien sind unendlich (`chunk_size > 0`)
- **Sector-System:** Nur visuell (`planet_visual_scale`), nie `set_size_profile` ändern

---

## 🔍 SUCHE & CODE-NAVIGATION (Detail)

### ConceptIndex — Semantische Suche (Architektur)
```bash
# Im Code:
ConceptIndex.new().search("fleet")      # → Array[ConceptEntry]
ConceptIndex.new().expand("economy")    # → alle Economy-Konzepte
ConceptIndex.new().class_concept("ShipManager")
ConceptIndex.new().by_domain("ships")
```

**Wartung (neue class_name-Skripte):**
1. In `_build_concepts()` unter passendem Konzept in `class_names` eintragen
2. Datei-Mapping ist **automatisch** (Scan bei nächstem Preflight)
3. Synonyme im `synonyms`-Array ergänzen
4. Preflight prüft: `search()`/`expand()` funktionieren, Stale → nur Warning

### Global Search — Volltext über ALLE Formate
```bash
# Scannt rekursiv res:// — .gd, .tres, .tscn, .gdshader, .import, .json, .csv, .md, .txt, .cs, .glsl, .shader, ...
# Output: JSON mit file, type, matches[{match_line, context[{line, content, is_match}]}]
```

**When-to-use:**
| Frage | Tool |
|-------|------|
| "Welche Klassen für Fleet-Logik? Freie Slots? Domäne?" | **ConceptIndex** |
| "Wo kommt 'fleet_supply_bonus' in .tres/.tscn/.md vor?" | **Global Search** |
| "Gibt es Klasse 'FleetManager'?" | **ConceptIndex --class** |
| "Alle Dateien mit 'worker_transport'" | **Global Search** |
| "Suche nach A oder B (OR-Suche)" | Beide: `"a|b"` mit Pipe-Syntax |
| "Welche Zeilen kommen wie oft vor?" | **Global Search --freq** |
| "Dead-Code-Kandidat? func definiert aber nicht aufgerufen?" | **Global Search --defs** |
| "Capture-Groups extrahieren (z.B. Funktionsnamen)" | **Global Search --regex** |
| "Zu viele Treffer → Timeout" | **Global Search --max-files 500** |

---

## ⚙️ PREFLIGHT-SUITE (Detail)

### CLI-Optionen
| Flag | Zweck |
|------|-------|
| `-v, --verbose` | Detail-Assertions |
| `-x, --fail-fast` | Abbruch bei erstem Fehler |
| `-f, --filter=<name>` | Nur Constraints mit Substring (z.B. `fleet`, `save`) |
| `--reverse` | Reverse-Execution (Testet Isolation) |
| `-l, --list` | Alle 36 Constraints auflisten |

### Constraints (36, atomare Commit-Gruppen beachten!)
- `game_state_compatibility` — Reflection-Signaturen, Fassaden-Methoden
- `concept_index` — **Nur funktional**: search/expand für Kern-Domänen
- `save_game_roundtrip`, `save_game_slots` — Slot-Konvention beachten!
- `mechanic_coverage` — Auto-Erkennung neuer Mechaniken
- ... (siehe `--list`)

---

## 🏗️ ATOMARE COMMIT-GRUPPEN (Change Together)

| Bereich | Dateien (müssen gemeinsam commitet werden) |
|---------|---------------------------------------------|
| **Transit & Dispatch** | `flight_time.gd`, `dispatch.gd`, `planet_network.gd`, `worker_cluster.*`, `worker_manager.gd`, `game_state.gd`, `preflight.gd` |
| **Navigation** | `navigation_field.gd`, `navigation_waypoint.gd`, `seeded_layout.gd`, `planet_network.gd`, `worker_manager.gd`, `preflight.gd` |
| **Planeten & Katalog** | `planet.tscn`, `planet.gd`, `planet_arrival_resolver.gd`, `planet_trait_aggregator.gd`, `planet_view.gd`, `seeded_layout.gd`, Configs & SVGs |
| **GameState & Ressourcen** | `game_state.gd`, `scripts/state/domains/*`, `resource_pool*.tres`, `bootstrap.gd`, `preflight.gd` |
| **Schiffsbau & Forschung** | `ship_part_definition.gd`, `ship_blueprint.gd`, `ship_part_catalog.gd+tres`, `technology_definition.gd`, `ship_manager.gd`, `dossier/workshop_view.gd`, `dossier/parchment_tech_tree_view.gd`, `preflight.gd` |
| **Kampf & Simulation (L2/3)** | `fleet_battle_simulator.gd`, `conquest_simulator.gd`, `battle_scene.gd`, `conquest_scene.gd`, `composite_ship_view.gd`, `conflict_manager.gd`, `fleet_snapshot.gd`, `preflight.gd` |
| **Prozedurale Welt** | `world_config.gd`, `world_generator.gd`, `chunk_coordinator.gd`, `planet_procedural.gd`, `navigation_field.gd`, `preflight.gd` |
| **SectorSystem** | `sector_flavor.gd`, `sector_anchor.gd`, `sector_classifier.gd`, `sector_flavor_catalog.gd`, `world_config.gd`, `seeded_layout.gd`, `preflight.gd` |
| **Save/Load** | `save_game_service.gd`, `run_save_data.gd`, `game_state.gd`, `scripts/state/domains/*`, `seeded_layout.gd`, `pause_menu.gd`, `main_menu.gd`, `preflight.gd` |
| **ConceptIndex & Suche** | `concept_index.gd`, `constraint_concept_index.gd`, `mechanic_registry.gd`, `scenario_loader.gd`, `scenario_snapshot.gd`, `preflight.gd` |
| **Global Search** | `global_search.gd`, `AGENTS.md` |

---

## 🐛 GODOT-FALLSTRICKE (Kurz)

- `@export_enum` → String/Integer, **nicht** `StringName`
- Resource/Waypoint-Skripte für `@tool` → **auch** `@tool`
- `NavigationWaypoint.configure()` läuft **vor** `_enter_tree()` — kein `@onready`
- `MultiMeshInstance2D` braucht `MultiMesh.mesh` (QuadMesh) **vor** `instance_count`
- `SceneTree.quit()` → **danach `return`** nötig
- `.uid`-Sidecars (`*.gd.uid`) **mitcommitten** (nicht in `.gitignore`)
- Neue `class_name` → Editor-Scan: `$GODOT_BIN --headless --path . --editor --quit`
- `Node.name` = `StringName` → für String-Ops: `String(node.name)`
- `class_name` als Parametername **verboten** (Parser-Fehler) → `cls_name` nutzen
- `is_instance_valid()` unzuverlässig bei gerade `free()` → `v.get_class()` crasht
- `StreamPeerTCP.get_data()` → `Array[Error, Daten]`, nicht `PackedByteArray`
- `RefCounted` hat **kein** `get_node_or_null()` → `Engine.get_main_loop().root.get_node_or_null()`

---

## 📋 WORKFLOW ZUSAMMENFASSUNG

### AM ANFANG (jeder Task)
1. `GODOT_BIN` setzen
2. **ConceptIndex** nutzen: `concept_search.gd --domain <xyz>` / `--class <Name>` / `--free-slots`
3. **Global Search** für Volltext: `global_search.gd "term" --type tres,tscn`
4. Relevante Dateien lesen (`read_file`), **nicht** raten

### ZWISCHENDURCH
- Kleine, atomare Änderungen
- Nach jeder logischen Einheit: `git add <dateien>` + `git commit` mit Begründungszeilen
- Preflight läuft automatisch im Hook

### AM ENDE (nach Arbeit)
1. **Full Preflight**: `$GODOT_BIN --headless --path . --script res://scripts/preflight.gd -x`
2. `git status` / `git diff` prüfen (Headless formatiert .tscn/.tres, injects uids)
3. `.uid`-Sidecars für neue Scripts mitcommitten
4. Push erfolgt via `post-commit` Hook automatisch

---

## 🔗 WEITERE DOKS
- `DESIGN.md` — Feature-Status, Umsetzungsplan
- `VISION.md` — Spielkreislauf, Layer-Details
- `scripts/testing/SCENARIO_LOADER_SPEC.md` — ScenarioLoader API
- `addons/gdscript_mcp/` — MCP-Remote-Testing (E2E, Playthrough-Archiv)