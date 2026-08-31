
- **Commits:** Immer nach Beendigung der Aufgabe committen, wenn Änderungen vorhanden sind. Kein `git add -A`, kein `git commit -m`, kein `--no-verify`. Feature-Branches: lokalen Stand auf Main cherry-picken und von Main aus committen (nicht direkt auf Feature-Branch committen). Pushes laufen automatisiert über DOKI (by Design: jeder Commit ist durch mehrere Systeme abgesichert und reviewbar). PRs nur mit ausdrücklichem Auftrag.
- Save-Slot 0 ist echter Spielstand und darf nie von Tests gelöscht werden; Slots 1–7 sind Test-Slots.
- Kein Commit ohne aktiven AgentGate-Check-In, der alle staged Dateien abdeckt; `--no-verify` ist unzulässig.

## CHECK-IN / CHECK-OUT
Nach VERIFY: `bash scripts/agent_activity.sh check-in --agent "$AGENT_NAME" --task "..." --scope-from-staged`; danach `export AGENT_ACTIVITY_SEED="$(bash scripts/agent_activity.sh seed "$AGENT_NAME")"` vor DOKI prepare. Das Stage-Set ist die Coverage-Quelle; manuelle 166-Datei-Listen sind nicht zulässig.
Vor RE-AUDIT: `bash scripts/agent_activity.sh check-out --force` nach Abschluss von DOKI finalize; anschließend `prune --force` für stale Agenten. Takeover ist nur bei stale/NO-OUT und ohne ACTIVE-Kollision erlaubt.

Verifikations-SSOT: Der Hook führt AgentGate einmal aus. `agent_activity` im Preflight ist nur ein delegierter PASS und startet keinen zweiten Gate-Prozess. Python-only Stage-Sets nutzen den Cheap-Path ohne Scene-Preflight; Code-Änderungen nutzen den DOKI-Scope/full Preflight. Timeouts sind standardmäßig deaktiviert. Ein Abbruch-Watchdog ist ausschließlich opt-in über `PREFLIGHT_WATCHDOG_SECONDS`/`--watchdog=<sek>` bzw. `COMPILE_GATE_WATCHDOG_SECONDS`; `TEST_ALL_TIMEOUT` ist ebenfalls optional (`0` = kein Timeout).

## Verbindliche Werkzeuge und Workflow
```bash
export GODOT_BIN="C:/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe"
export AGENT_NAME="buffy"
# Suche: concept_search.gd für Architektur; global_search.gd für Volltext und Kontext.
# Python-Godot Parity (falls Godot Binary nicht verfügbar):
#   python -m narrative_runtime.gate_cli --root .
#   python -m docs.reference.python_preflight --full
```

### Git Hook Installation (once per clone)
```bash
bash scripts/doki/install_hooks.sh
```
This symlinks `.githooks/*` to `.git/hooks/` and sets `core.hooksPath`.
Hooks require `GODOT_BIN` to be set and executable.

1. **SELECT:** `cat ROADMAP.md` lesen, höchsten nicht blockierten Slice wählen.
2. **VERIFY:** betroffene Dateien und Abhängigkeiten lesen; nicht raten.
3. **IMPLEMENT:** minimale atomare Änderung; neue `class_name` mit Editor-Scan und `.uid`-Sidecar.
4. **GATE:**
```bash
# Unified Check: ein Befehl, scope-kontrolliert.
# Scope wird aus staged files bestimmt; jede Datei außerhalb
# muss über --takeover begründet werden.
$GODOT_BIN --headless --path . --script res://scripts/check.gd -x
```
   Äquivalent zu compile_gate + test_all + preflight in einem Durchlauf.
   Für isolierte Phasen:
```bash
$GODOT_BIN --headless --path . --script res://scripts/check.gd --skip-tests --skip-preflight -x  # nur compile
$GODOT_BIN --headless --path . --script res://scripts/check.gd --scope-report                    # nur scope-analyse
$GODOT_BIN --headless --path . --script res://scripts/check.gd --full -x                        # voll-lauf
```
   Pflicht: `RESULT: ALL PASSED`; Headless-Rauschen am Ende ignorieren, echte Fehler beheben.
   **Fallback (ohne Godot Binary):**
```bash
python -m narrative_runtime.gate_cli --root .
python -m docs.reference.python_preflight --full
```
5. **DOCS:** ROADMAP/FINDINGS synchron halten; neue Befunde dokumentieren.
6. **DOKI:**
```bash
git add <konkrete-dateien>
$GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- prepare "<impuls>"
# .doki/narrator_body.md als Fließtext in der gezogenen Rolle schreiben
$GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- finish --body-file .doki/narrator_body.md
git commit -F .commit_msg.txt
```
   `finish` schreibt/staged `change_index.json` und `CHANGELOG.md`; `finalize` schreibt/staged danach `narrative_chain.json` und `arcs.json` für den nächsten Commit.
7. **RE-AUDIT:** `git status`, `git log --oneline -1`, Regressionen und Artefaktzustand prüfen.

## Atomare Commit-Gruppen — gemeinsam ändern
| Bereich | Verbindliche Dateien |
|---|---|
| Transit & Dispatch | `flight_time.gd`, `dispatch.gd`, `planet_network.gd`, `worker_cluster.*`, `worker_manager.gd`, `game_state.gd`, `preflight.gd` |
| Navigation | `navigation_field.gd`, `navigation_waypoint.gd`, `seeded_layout.gd`, `planet_network.gd`, `worker_manager.gd`, `preflight.gd` |
| Planeten & Katalog | `planet.tscn`, `planet.gd`, `planet_arrival_resolver.gd`, `planet_trait_aggregator.gd`, `planet_view.gd`, `seeded_layout.gd`, Configs/SVGs |
| GameState & Ressourcen | `game_state.gd`, `scripts/state/domains/*`, `resource_pool*.tres`, `bootstrap.gd`, `preflight.gd` |
| Schiffsbau & Forschung | `ship_part_definition.gd`, `ship_blueprint.gd`, `ship_part_catalog.gd+tres`, `technology_definition.gd`, `ship_manager.gd`, Dossier-Views, `preflight.gd` |
| Kampf & Simulation | `fleet_battle_simulator.gd`, `conquest_simulator.gd`, Battle/Conquest-Scene, `composite_ship_view.gd`, `conflict_manager.gd`, `fleet_snapshot.gd`, `preflight.gd` |
| Prozedurale Welt | `world_config.gd`, `world_generator.gd`, `chunk_coordinator.gd`, `planet_procedural.gd`, `navigation_field.gd`, `preflight.gd` |
| SectorSystem | `sector_flavor.gd`, `sector_anchor.gd`, `sector_classifier.gd`, `sector_flavor_catalog.gd`, `world_config.gd`, `seeded_layout.gd`, `preflight.gd` |
| Save/Load | `save_game_service.gd`, `run_save_data.gd`, `game_state.gd`, `scripts/state/domains/*`, `seeded_layout.gd`, Pause/MainMenu, `preflight.gd` |
| ConceptIndex & Suche | `concept_index.gd`, `constraint_concept_index.gd`, `mechanic_registry.gd`, `scenario_loader.gd`, `scenario_snapshot.gd`, `preflight.gd` |
| Global Search | `global_search.gd`, `AGENTS.md` |
| DOKI CommitLayer | `scripts/doki/**`, Chain/Index/CHANGELOG, `.githooks/*`, `AGENTS.md`, `scripts/concept_index.gd` |
| Narrative Runtime | `narrative_runtime/**`, `.gitignore`, `scripts/doki/NARRATIVE_ENGINE_DESIGN.md`, `AGENTS.md` |

## Godot-Fallenstricke
- `@export_enum` ist String/Integer, nicht `StringName`.
- `@tool`-Resources brauchen auch `@tool`; `NavigationWaypoint.configure()` läuft vor `_enter_tree()`.
- `MultiMeshInstance2D`: Mesh vor `instance_count` setzen.
- `Array.map()` liefert untypisiert; bei typisierten Arrays explizit iterieren.
- Config-Resources dürfen keinen `GameState`-Default referenzieren (Autoload-Zyklus); nutze `GameConstants`.
- Neue `class_name` → `$GODOT_BIN --headless --path . --editor --quit`; `.uid`-Sidecars mitcommitten.
- `Node.name` ist `StringName`; vor String-Operationen `String(node.name)` verwenden.
- `SceneTree.quit()` beendet nicht automatisch die Funktion: danach `return`.

## Verträge und Tiefgang
- DOKI-Details, Checks, Composite, Recovery: `scripts/doki/README.md`.
- Narrative Runtime: `scripts/doki/NARRATIVE_ENGINE_DESIGN.md` — Git/DOKI ist Wahrheit, SQLite ist rekonstruierbares Archiv und darf DOKI nicht blockieren.
- Vollständige Suche/Preflight/MCP/Godot-Details: `scripts/docs/AGENTS_REFERENCE.md`.
- Findings: `docs/FINDINGS.md`; Architektur: `ARCHITECTURE.md`, `DESIGN.md`, `VISION.md`.
- MCP-Testregeln: `addons/gdscript_mcp/AGENTS.md`.
