# Preflight Baseline-Messung — Echte Daten

## Datum: 2026-08-26
## Engine: Godot 4.7.2.stable (console build)
## Hardware: FX 6300 / 12 GB RAM / Win11
## Modus: `--headless --path . --script res://scripts/preflight.gd`

---

## Gesamtlaufzeit: 84,552.60 ms (84.5 Sekunden)
## Constraints: 37 total (37 passed, 0 failed)
## Assertions: 2,031 total (2,031 passed, 0 fail)

---

## Per-Constraint Timings (sortiert nach Dauer)

### TOP 10 — Die echten Zeitfresser
| # | Constraint | Dauer (ms) | Checks | Typ | Anteil |
|---|-----------|-----------|--------|-----|--------|
| 1 | **resources_and_seed** | 8,019.31 | 91 | scene | 9.5% |
| 2 | **game_state_compatibility** | 5,299.02 | 322 | **pure** | 6.3% |
| 3 | **world_details_and_scale** | 5,060.31 | 89 | scene | 6.0% |
| 4 | **context_handover** | 4,846.60 | 14 | scene | 5.7% |
| 5 | **world_planets_and_dispatch** | 3,112.08 | 500 | scene | 3.7% |
| 6 | **scene_boot** | 3,075.30 | 37 | scene | 3.6% |
| 7 | **ingame_player_and_transitions** | 3,041.23 | 23 | scene | 3.6% |
| 8 | **ship_catalog_and_assembly** | 2,992.26 | 72 | scene | 3.5% |
| 9 | **grid_system** | 3,038.45 | 12 | scene | 3.6% |
| 10 | **local_resources** | 3,010.35 | 13 | scene | 3.6% |

### Scene-Constraints (alle 23)
| Constraint | Dauer (ms) | Checks |
|-----------|-----------|--------|
| scene_boot | 3,075 | 37 |
| resources_and_seed | 8,019 | 91 |
| world_planets_and_dispatch | 3,112 | 500 |
| world_details_and_scale | 5,060 | 89 |
| economy_production | 3,161 | 27 |
| mission_semantics | 3,227 | 13 |
| cpu_dispatch | 2,866 | 19 |
| selection_and_context | 2,811 | 30 |
| research_ship | 2,658 | 15 |
| ship_catalog_and_assembly | 2,992 | 72 |
| ship_transit_and_arrival | 2,764 | 30 |
| colony_milestone | 2,821 | 14 |
| event_log | 2,911 | 14 |
| camera_and_input | 2,749 | 14 |
| pause_and_context | 2,863 | 19 |
| layers_2_and_3 | 2,921 | 52 |
| ingame_player_and_transitions | 3,041 | 23 |
| grid_system | 3,038 | 12 |
| local_resources | 3,010 | 13 |
| conquest_grid_combat | 2,806 | 9 |
| main_menu_and_flow | 2,842 | 17 |
| context_handover | 4,847 | 14 |
| save_game_roundtrip | 2,849 | 17 |
| **SUMME** | **~70,474 ms** | — |

### Pure-Constraints (14)
| Constraint | Dauer (ms) | Checks |
|-----------|-----------|--------|
| game_state_compatibility | **5,299** | 322 |
| global_search | **2,195** | 9 |
| concept_index | **427** | 21 |
| mechanic_coverage | 20 | 95 |
| save_game_slots | 19 | 14 |
| module_damage_model | 11 | 69 |
| world_generator_scaling | 8 | 58 |
| chunk_expansion | 5 | 126 |
| upgrade_catalog | 5 | 100 |
| navigation_growth | 2 | 26 |
| sector_classification | 1 | 14 |
| effects_and_traits | 0.35 | 15 |
| flight_and_dispatch | 0.3 | 16 |
| paper_style | 0.1 | 5 |
| **SUMME** | **~7,992 ms** | — |

---

## Kritische Beobachtungen

### 1. Scene-Re-Boot: 82% der Laufzeit
- 23 Scene-Constraints × ~3,075 ms (Boot-Kosten) = **~70,725 ms**
- Tatsächliche Constraint-Arbeit: ~15,552 ms
- **82% der Zeit geht für 23× identisches Szenen-Instantiieren drauf**

### 2. game_state_compatibility: 5.3s für einen PURE-Constraint
- Liest ALLE .gd-Dateien und wendet Regex-Pattern an
- 322 Checks = 128 Facade-Methoden + Signature-Contracts + Callsite-Scans
- **Größter einzelner Hotspot bei Pure-Constraints**

### 3. global_search: 2.2s für eine Funktionsprüfung
- Scannt komplett `res://` nach "fleet" in .gd-Dateien
- Dieser Scan läuft beim Preflight UND bei jedem ConceptIndex-Check

### 4. RID-Leak-Warnungen beim Exit
```
ERROR: 3 RID allocations of type 'P11GodotArea2D' were leaked at exit.
ERROR: 1 RID allocation of type 'P12GodotShape2D' were leaked at exit.
ERROR: 14 RID allocations of type 'DummyTexture' were leaked at exit.
WARNING: 21 RIDs of type "CanvasItem" were leaked.
WARNING: 109 ObjectDB instances were leaked at exit.
ERROR: 51 resources still in use at exit.
```
- **109 ObjectDB-Instanzen** = nicht freigegebene Godot-Objekte
- **51 Ressourcen** = nicht freigegebene .tres/.tscn-Instanzen
- **21 CanvasItems** = nicht freigegebene 2D-Objekte
- **Beweis:** Die Fixture-Cleanup ist unvollständig. State-Leaks sind real.

### 5. Ausführungs-Reihenfolge ist suboptimal
- `upgrade_catalog` (pure, 4.54 ms) läuft NACH `world_details_and_scale` (scene, 5,060 ms)
- Alle Pure-Constraints sollten ZUERST laufen, dann die Scene-Constraints

### 6. concept_index: 37 stale class references
- 37 Klassen im Index aber nicht auf Disk (MCP-Remote-Testing Klassen)
- `TutorialDirector` nicht gemappt

### 7. mechanic_coverage: 38 Mechanics ohne Test-Model
- Warnung ist non-blocking, aber zeigt Lücke in der Test-Abdeckung

---

## Engine-Limitationen (Godot 4.7 Headless)

### Was NICHT geht
1. **Kein echtes Threading für GDScript** — WorkerThreadPool existiert (6 Threads), aber GDScript ist single-threaded. Nur C++-Extension-Code kann WorkerThreadPool nutzen.
2. **Kein Parallel-Constraint-Execution** — Constraints sind RefCounted, nicht Thread-safe. Scene-Constraints teilen sich den SceneTree.
3. **class_name-Auflösung braucht Editor-Scan** — Ohne vorherigen `--editor --quit` Scan gibt es Parse-Errors (wie im Test gesehen).
4. **process_frame ist blockierend** — Jeder `await tree.process_frame` wartet den kompletten Tick.
5. **queue_free ist deferred** — Freigabe passiert am Ende des Frames, nicht sofort.

### Was GEHT
1. **GameState-Reset ohne Re-Boot** — `begin_new_game()` resettet den State, Scene bleibt im Tree.
2. **Bedingte Scene-Boots** — Nur Constraints die die Scene-BStruktur testen brauchen Re-Boot.
3. **Batch-Resets** — Mehrere State-Resets in einem Frame möglich.
4. **Preflight-Only Optimization** — Kein Gameplay-Risiko, da nur Test-Infrastruktur betroffen.
