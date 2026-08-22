# SnipWar Agent Notes

## Godot & Headless Verifikation
- Godot ist nicht auf dem globalen PATH; Headless-Kommandos über die Console-Binary ausführen und `GODOT_BIN` darauf setzen (oder `godot`/`godot4` auf den PATH legen).
- Gefundene Console-Binary: `C:\Users\Vannon\Desktop\godu\Godot_v4.7.2-stable_win64_console.exe` — liegt weder auf dem PATH noch in `$LOCALAPPDATA/Programs`; per `export GODOT_BIN="…"` setzen.
- `--headless --path . --quit-after 2` = Main-Scene-Smoke-Test; `--headless --path . --script res://scripts/preflight.gd` = persistente Testsuite (kein externes GUT). Temporäre Lifecycle-Checks nutzen `res://.tmp_*.gd` und müssen nach Abschluss restlos entfernt werden (inklusive generiertem `.tmp_*.gd.uid`-Sidecar).
- Preflight gibt am Ende `ERROR: …RID allocations… leaked at exit` / `ObjectDB instances leaked` aus — das ist normales Teardown-Rauschen des Dummy-Renderers im Headless-Modus. Verbindlich ist die Zeile `RESULT: PASSED`.
- Der Headless-Modus nutzt den Dummy-Renderer, daher ist `Window.get_texture()` null; visuelle Screenshots/Captures benötigen den Desktop Compatibility/OpenGL-Renderer, und `Window.size` muss nach Szenen-Initialisierung explizit gesetzt werden.
- Ein Headless-Editor-Scan kann mit Exit-Code 0 enden, selbst wenn ein `EditorFileServer` Port-6010-Konflikt den Scan-Thread abbricht. Verlässlicher Maßstab sind Preflight + Smoke-Test. Render-Budget-Assertions schätzen CanvasItem-Submissions, nicht GPU-Framezeiten.

## Preflight-Suite Architektur & Verträge
- **Preflight ist modular aufgebaut:** `scripts/preflight.gd` ist der Orchestrator. Er instanziiert einen `PreflightContext` sowie eine `PreflightFixture` und führt die Module aus `CONSTRAINT_REGISTRY` aus.
- **Registrierung:** Neue Constraints werden als eigene `PreflightConstraintX`-Klasse mit `constraint_name() -> String` und `run(ctx: PreflightContext) -> bool` implementiert und in `CONSTRAINT_REGISTRY` in `scripts/preflight.gd` registriert (`{"id": "...", "script": preload("..."), "desc": "...", "requires_scene": bool}`).
- **Fixture-Isolation:** Szenenabhängige Constraints (`requires_scene: true`) erhalten über `ctx.fixture.boot_default(ctx)` eine isolierte Szenen-Fixture. Jeder Boot räumt die vorherige Szene auf und setzt `GameState` aus dem aktiven Katalog zurück. Constraints dürfen sich nicht auf Mutationen vorheriger Constraints verlassen; eine Ausführung in umgekehrter Reihenfolge (`--reverse`) ist explizit unterstützt.
- **Deterministischer Test-Seed:** Das Live-Szenario randomisiert den Seed (`randomize_layout_seed = true`), aber die Preflight-Fixture erzwingt intern `PREFLIGHT_LAYOUT_SEED = 424242`. Dadurch sind Planetenpositionen, Nachbarschaftsgraph und Ressourcen-Deals im Preflight 100 % deterministisch und stabil.
- **CLI-Optionen:** Die Preflight-Suite unterstützt `--verbose` / `-v` (Detail-Assertions), `--fail-fast` / `-x` (sofortiger Abbruch bei erstem Fehler), `--filter=<name>` / `-f=...` (gezielte Constraint-Filterung mit automatischem Scene-Boot falls nötig), `--reverse` (Reverse-Execution) und `--list` / `-l` (Übersicht aller 33 Constraints).
- **Kompatibilitätsprüfung:** `constraint_game_state_compatibility.gd` läuft als erste Constraint und scannt Reflection-Signaturen sowie Regex-Receiver-Aliase unter `res://scripts`. Neue oder umbenannte Fassaden-Methoden müssen in `REQUIRED_FACADE_METHODS` bzw. `SIGNATURE_CONTRACTS` gepflegt werden.
- **Boot-Kosten & Soft-Reset-Antipattern:** Die Full-Suite braucht ~80–90 s (33 Constraints); jeder `requires_scene`-Constraint kostet ~3,5 s, dominiert von Planeten-Re-Instanziierung + `NavigationField`-Rebuild — nicht von Szenen-Teardown oder Chunk-Regeneration. Szene/Chunk-Cache wiederverwenden (Soft-Reset) hilft daher nicht und schwächt die Fixture-Isolation; Monster-Constraints aufteilen lohnt nur für Fehlerlokalisierung, nie für Speed. Dev-Loop über `--filter`/`--group` beschleunigen.
- **Scout- & Collect-Gating im Test:** Collect-Missionen erfordern gescannte, neutrale Planeten (`FACTION_NEUTRAL`). Preflight-Szenarien filtern Scout-Ziele daher strikt nach Fraktion, um Flakiness durch benachbarte gegnerische Homeworlds zu verhindern.

## Architektur & System-Verträge
- **Szenen-Architektur (3 Spiele, 1 SSO):** Das Spiel ist in vier bootbare Szenen getrennt, die sich GameState als SSO teilen und über den `SceneDirectorService`-Autoload wechseln:
  - `scenes/main_menu/main_menu.tscn` (Einstieg; `run/main_scene`): Neues Spiel / Weiter / Beenden.
  - `scenes/world/world.tscn` (Layer 1, Strategie-Overworld): `WorldBootstrap`-Wurzel + `Background`-Renderer + `PlanetField` + `MeteorField` + `MapCamera` + `PauseMenu`.
  - `scenes/battle/battle_scene.tscn` (Layer 2, Flotten-Replay).
  - `scenes/conquest/conquest_scene.tscn` (Layer 3, Eroberungs-Replay).
  - `SceneDirectorService` führt Szenen-Wechsel über den dokumentierten Custom-Switcher aus (deferred free + add_child + `current_scene`), nicht `change_scene_to_packed`. `GameCycleManager` entscheidet WANN gewechselt wird, der Director WIE. Kontext wandert ausschließlich über GameState (`pending_battle_context` / `request_world_reconnect` / `RunSession`).
- **Geteilte WorldConfig:** `WorldBootstrap._enter_tree()` (Wurzel von `world.tscn`) wählt das Szenario, finalisiert `layout_seed` (`_finalize_layout_seed`) und generiert `active_catalog`, bevor `GameState`, `PlanetField` und `MeteorField` initialisiert werden. `Bootstrap._ready()` dealt die Ressourcen mit diesem finalisierten Seed. Der `Background`-Renderer (`starfield_background.gd`) ist reine Optik und berührt weder GameState noch Katalog oder Szenario.
- **Save/Load (Godot-Resource):** `SaveGameService` (Autoload) schreibt `RunSaveData`-Snapshots nach `user://saves/run_<slot>.tres` (atomar via `_tmp.tres` + Rename). `GameState.snapshot_run()`/`restore_run()` erfassen/restaurieren alle vier Domains, Transits, Chunk-Daten und Timer. `load_run()` setzt `_reconnect_requested`, die World bootet danach über `reconnect_world()` mit der gespeicherten Session; `SeededLayout` lädt den Chunk-Payload vor der Instanziierung. Auto-Save bei `NOTIFICATION_WM_CLOSE_REQUEST` — nie im Headless-Modus (`OS.has_feature("headless")`-Guard), sonst schreibt die Preflight-Suite/der pre-commit-Hook Testzustand über echte Spielstände.
- **Slot-Konvention:** Das Spiel nutzt ausschließlich Slot 0 (PauseMenu-Save, MainMenu-Continue, Auto-Save). Die Preflight-Suite darf Slot 0 nie zerstören: `constraint_main_menu_and_flow` sichert/restauriert den echten Save via Backup (backup/restore-Vertrag, empirisch verifiziert), `constraint_save_game_roundtrip` nutzt Test-Slot 7, `constraint_save_game_slots` die Slots 1–2. Neue Save-Tests müssen sich an diese Konvention halten (Slots 1–7 = Test-Slots, Slot 0 = echter Spielstand).
- **Single-Source Weltgenerierung:** `WorldGenerator.generate_catalog(config, active_layout_seed, target_planet_count)` erzeugt den Sektor-Katalog genau einmal (`p0`/`p1` = Homeworlds von Spieler `a` und CPU `b`, `p2`..`p9` = neutrale Welten aus Baustein-Texturen). `SeededLayout` darf den Katalog nicht neu generieren.
- **Homeworld-Separation:** `SeededLayout._separate_homeworlds()` hält die beiden Homeworlds nicht-benachbart, sodass jede mindestens 2 neutrale Nachbarn für Scouts und Expansion besitzt.
- **Raster- & Nachbarschaftsauflösung:** Adjazenz und Dimensionen werden ausschließlich über `WorldConfig.resolved_columns()`, `resolved_size_class_counts()`, `resolved_design_size()` und `resolved_target_planet_count()` bezogen — niemals über rohes `columns`.
- **Planeten-Lebenszyklus & Detail-Profile:** `Planet.layout_size` leitet sich aus `Planet.size_profile` ab. Bauplätze sind profilgesteuert (variable=1, large=2, XL=3). Worker-Spawn-Timer existieren, bleiben aber gestoppt bis `worker_automation` erforscht und eine Worker-Fabrik errichtet wurde.
- **SectorSystem (opt-in Dichte-Feld):** Neue Typen tragen bewusst das Präfix `Sector*` (Namenskollision mit dem Worker-Transit-System `WorkerCluster`/`ClusterTierDefinition`). Aktiv nur bei `WorldConfig.sector_count > 0` (`resolved_sector_count()`); `SectorClassifier` ist ein statischer `RefCounted` und wird von `SeededLayout` (endlicher Pfad) und `ChunkCoordinator` (unendlicher Pfad) aufgerufen.
- **Sector-Größenwirkung ist rein visuell:** Skalierung ausschließlich über `planet_visual_scale`/`resolved_planet_visual_scale()` (0.6 im Shipped-Szenario) in beiden Pfaden — niemals `set_size_profile`, sonst bricht Worker-/Gameplay-Determinismus. Klassifikation landet als `set_meta` (`sector_id`/`sector_role`/`sector_depth`) auf den Planeten.
- **Planet-Modul-Architektur:** `planet.gd` ist der zentrale Knotenpunkt und delegiert spezialisierte Aufgaben:
  - `PlanetArrivalResolver` (`scripts/objects/planets/planet_arrival_resolver.gd`): Deterministische Arrival-, Missions- und Konfliktauflösung.
  - `PlanetTraitAggregator` (`scripts/objects/planets/planet_trait_aggregator.gd`): Aggregation von Upgrade- und Trait-Boni.
  - `PlanetView` (`scripts/objects/planets/view/planet_view.gd`): Reine CanvasItem-Zeichenroutinen (Faction-Ringe, StrengthLabels).
  - `PlanetProcedural` (`scripts/objects/planets/procedural/planet_procedural.gd`): Komposition prozeduraler Planeten.
  - `ContextMenuBuilder` (`scripts/objects/planets/context_menu_builder.gd`): Konstruktion und Gating des Rechtsklick-Kontextmenüs.
- **GameState als Domain-Fassade:** `GameState` (/root/GameState) ist der zentrale SSOT für Besitz, Ressourcen, Forschung und Schiffe und delegiert an 4 Sub-Domänen (`scripts/state/domains/`):
  - `FactionDomain`: Besitzverhältnisse, Homeworlds, Discovery, Scan-Intel, Starter-Scout.
  - `EconomyDomain`: Faction-Vaults, Ressourcen-Deals, Upgrades, Worker-Factories, persistente Gatherer.
  - `TechDomain`: Globale & planetare Technologien, Forschungs-Jobs, Voraussetzungen.
  - `ShipDomain`: Teile-Inventare, Schiffsmontage (`assemble_ship`), Zerlegung, Bau-Jobs, FleetSnapshots.
- **Ressourcen & Overdraft-Schutz:** Ressourcen sind unsichtbare `GameResource`-Datenobjekte aus dem `ResourcePool`. `spend_faction_resource()` blockiert bei unzureichendem Guthaben vollständig (kein Overdraft, keine Teilzahlung).
- **Wirtschaft & Sammeltrupps:** Der Economy-Timer (10s) läuft erst nach `worker_automation`. Ein separater Gather-Timer (10s) läuft dauerhaft: `collect`-Missionen registrieren persistente Gatherer in `GameState._gathering_workers`, die pro Tick `workers × resource_base` einbringen.
- **Navigation & Routing:** Pro Nachbarschaftskante existiert ein Moon-/Comet-Waypoint, überlagert von einem K-Nearest-Langstreckengraph (`NavigationField`). `NavigationField.find_route()` liefert den Pfad für Flugvorschau und Transit.
- **Flugzeit & Cluster-Packing:** `FlightTime.seconds_for()` berechnet die Dauer basierend auf Distanz, Einheitenlast und Quell-Transfer-Speed. Worker-Transit packt nach Largest-First (K=1, M=5, L=100); alle Gruppen starten im selben Frame.
- **UI-Stack:**
  - `PlanetNetworkUI` (CanvasLayer 50): Komponiert `VaultBar` (`scenes/ui/vault_bar.tscn`) und `PlanetPanel` (`scenes/ui/planet_panel.tscn`).
  - `TechnologyMenu` (CanvasLayer 60): Unterteilt in `TechResearchView`, `TechScoutView`, `TechShipBuilderView` und `TechPlanetView`. Schließt das PlanetPanel bei Öffnung.
  - `PauseMenu` (CanvasLayer 70): Reagiert auf ESC (`PROCESS_MODE_ALWAYS`), wenn weder PlanetPanel noch TechMenu geöffnet sind. Bietet **SPEICHERN** (→ `SaveGameService.save_run(0)` + EventLog-Toast) und **HAUPTMENÜ** (→ erst unpausen, dann `SceneDirectorService.goto_scene("menu")` — ein Scene-Wechsel im gepausten Baum würde das neue Menü einfrieren). Beide Buttons tragen stabile Namen (`Content/SaveButton`, `Content/MenuButton`) und sind über `constraint_pause_and_context` abgesichert.
  - `MainMenu` (Einstiegsszene, `run/main_scene`): **NEUES SPIEL** (löscht Slot 0, `GameState.request_new_run()`, dann World), **WEITER** (deaktiviert ohne Save; `SaveGameService.load_run(0)` setzt `_reconnect_requested`, dann World), **BEENDEN**. Flow ist über `constraint_main_menu_and_flow` + `constraint_context_handover` abgesichert.
- **Flottenkampf & Eroberung (Layer 2/3):**
  - Layer 2: `FleetBattleSimulator` (deterministischer, getakteter `RefCounted`-Simulator) + `BattleScene` + `IngamePlayerControls`.
  - Layer 3: `ConquestSimulator` (deterministischer `RefCounted`-Simulator für planetare Eroberung) + `ConquestScene`.
  - `ConquestSimulator.simulate_conquest` darf HP/DPS-Konstanten nicht ändern — die bestehenden Layer-2/3-Preflight-Assertions koppeln exakt darauf. Nur `tick`/`max_time`/`variance` parametrisieren.
  - Orchestrierung erfolgt über `ConflictManager` auf `PlanetField` und den `SceneDirector`.
- **Prozedurale Chunk-Welt (Unendlich):**
  - Wird aktiviert, wenn `WorldConfig.chunk_size > 0`. Beide Shipped-Szenarien sind bereits unendlich: `world_default.tres` (`chunk_size = 3`), `world_wide.tres` (`chunk_size = 4`); `chunk_size = 0` wäre der endliche Pfad.
  - Verwaltet durch `ChunkCoordinator` (Lazy-Generierung, Cache, sicheres Cycling) und getestet in Constraint `chunk_expansion`.
  - `SeededLayout.set_layout_seed()` ist im unendlichen Pfad kein billiger Setter, sondern ein Voll-Reset: ruft `GameState.reset_for_infinite_world()` + `reset_for_layout_seed` (leert Chunk-Cache) und deferred `_refresh_chunks` — regeneriert die ganze Chunk-Welt. `constraint_resources_and_seed` ruft das zweimal auf (Seed ±1, dann zurück) und ist deshalb der langsamste Szenen-Constraint (~9–10 s).
- **EventLog:** Autoload `/root/EventLog`. `push()` sendet sichtbare Toasts an das `MessageFeed`, `log_silent()` protokolliert geräuschlos. Export nach `user://player.log` erfolgt erst bei Anwendungsbeendigung (`NOTIFICATION_WM_CLOSE_REQUEST`).

## Atomare Commit-Gruppen (Change Together)
- **Transit & Dispatch:** `flight_time.gd`, `dispatch.gd`, Transit-/Tier-Configs, `planet_network.gd`, `planet_network_ui.gd`, `ui_theme_config.gd`, `worker_cluster.*`, `worker_manager.gd`, `planet.gd`, `game_state.gd`, `preflight.gd`.
- **Navigation:** `navigation_field.gd`, `navigation_waypoint.gd`, `seeded_layout.gd`, `planet_network.gd`, `worker_manager.gd`, `preflight.gd`.
- **Planeten & Katalog:** `planet.tscn`, `planet.gd`, `planet_details.gd`, `planet_arrival_resolver.gd`, `planet_trait_aggregator.gd`, `planet_view.gd`, `planet_procedural.gd`, `seeded_layout.gd`, Welt-/Größen-/Detail-Configs & SVGs.
- **GameState & Ressourcen:** `game_state.gd`, Domänen-Manager (`scripts/state/domains/*`), `planet.gd`, `seeded_layout.gd`, `resource_pool*.tres`, `bootstrap.gd`, `starfield_background.gd`, `preflight.gd`.
- **Wirtschaft & CPU-AI:** `economy_config.gd`+`.tres`, `cpu_dispatch_config.gd`+`.tres`, `economy_manager.gd`, `cpu_dispatch_ai.gd`, `seeded_layout.gd`, `planet.gd`, `worker_manager.gd`, `preflight.gd`.
- **Schiffsbau & Forschung:** `ship_part_definition.gd`, `ship_component_variant.gd`, `ship_blueprint.gd`, `ship_part_catalog.gd`+`.tres`, `technology_definition.gd`, `technology_catalog*.tres`, `ship_manager.gd`, `shipyard_hangar.gd`, `composite_ship_view.gd`, `technology_menu.gd`, Sub-Views (`scripts/ui/tech_menu/*`), `preflight.gd`.
- **Kampf & Simulation (Layer 2/3):** `fleet_battle_simulator.gd`, `conquest_simulator.gd`, `battle_scene.gd`, `conquest_scene.gd`, `composite_ship_view.gd`, `ingame_player_controls.gd`, `scene_director.gd`, `conflict_manager.gd`, `fleet_snapshot.gd`, `preflight.gd`.
- **Prozedurale Welt:** `world_config.gd`, `world_generator.gd`, `chunk_coordinator.gd`, `chunk_save_data.gd`, `planet_procedural.gd`, `navigation_field.gd`, `preflight.gd`.
- **SectorSystem:** `sector_flavor.gd`, `sector_anchor.gd`, `sector_classifier.gd`, `sector_flavor_catalog.gd` + Presets/`sector_flavor_catalog_default.tres`, `world_config.gd`, `seeded_layout.gd`, `chunk_coordinator.gd`, `navigation_field.gd`, `planet.gd`, `preflight.gd`.
- **Grid, Buildings & lokale Ressourcen:** `planet_grid*.gd`, `building_*.gd`, `building_catalog_default.tres` + `resources/config/buildings/*`, `planet.gd`, `economy_domain.gd`, `game_state.gd`, `bootstrap.gd`, `planet_details.gd`, `planet_panel.gd`, `preflight.gd`.
- **Tower-Defense & Capture:** `conquest_simulator.gd`, `battle_event.gd`, `combat_replay.gd`, `planet_arrival_resolver.gd`, `conflict_manager.gd`, `capture_decision_overlay.gd`, `conquest_scene.gd`, `battle_scene.gd`, `preflight.gd`.
- **Szenen-Architektur & Flow:** `scene_director.gd`, `world.tscn`, `world_bootstrap.gd`, `starfield_background.gd`+`.tscn`, `main_menu.gd`+`.tscn`, `conquest_scene.tscn`, `battle_scene.tscn`, `conflict_manager.gd`, `game_cycle_manager.gd`, `project.godot`, `preflight_fixture.gd`, `constraint_scene_boot.gd`, `constraint_world_details_and_scale.gd`, `preflight.gd`.
- **Save/Load:** `save_game_service.gd`, `run_save_data.gd`, `run_session.gd`, `game_state.gd`, Domänen-Manager (`scripts/state/domains/*`), `seeded_layout.gd`, `economy_manager.gd`, `pause_menu.gd`, `main_menu.gd`, `project.godot`, `preflight.gd` (+ `constraint_save_game_*`).

## Godot-Entwicklungsregeln & Fallstricke
- Godot 4.7 `@export_enum` benötigt String-/Integer-kompatible Typen, nicht `StringName`.
- Resource- und Waypoint-Skripte, die von `@tool`-Skripten genutzt werden, müssen ebenfalls `@tool` sein.
- `NavigationWaypoint.configure()` kann vor `_enter_tree()` laufen; nicht auf `@onready` verlassen und Node vor Zuweisung der globalen Position in den Baum einhängen.
- `MultiMeshInstance2D` erfordert zwingend `MultiMesh.mesh` (z.B. `QuadMesh`) vor dem Setzen von `instance_count`.
- Meteor-Größen sind pixelbasiert; `meteor_field.gd` skaliert über die SVG-Texturbreite.
- `SceneTree.quit()` beendet Funktionen nicht sofort; Testskripte müssen nach `quit()` explizit ein `return` ausführen.
- Headless-Läufe können `.tscn` und `.tres` Dateien formatieren und `uid=` Tags injizieren; vor Commits immer `git status` und `git diff` prüfen.
- `.uid`-Sidecars (`*.gd.uid`, `*.gdshader.uid`) sind versioniert (nicht in `.gitignore`) und müssen bei neuen Scripts/Shadern mitcommittet werden; fehlende Sidecars führen zu Drift/Neuvergabe der UIDs.
- Neue `class_name`-Skripte erfordern einen Editor-Scan (`$GODOT_BIN --headless --path . --editor --quit`), um in `.godot/global_script_class_cache.cfg` registriert zu werden.
- GDScript `:=` Typinferenz schlägt bei `Node`-Kindern und untypisierten Helper-Returns fehl; explizite Casts verwenden (z.B. `(node as Node2D)`).
- `Node.name` liefert `StringName`, nicht `String`. Bei String-Operationen mit `String(node.name)` konvertieren.
- Lokale Variablen und Signal-Parameter dürfen keine Engine-Properties (`visible`, `owner`) oder Instanzfelder shadowen (`SHADOWED_VARIABLE`).
- GDScript kennt kein `sqrtf`/`powf` (C-Namen); Fließkomma-Mathe nutzt `sqrt()`/`pow()` — `sqrtf` erzeugt einen Lookup-/Parse-Fehler.

## Git-Hooks & Commit-Workflow
- `core.hooksPath` ist auf `.githooks` konfiguriert (aktiv und verbindlich):
  - `pre-commit` führt `git diff --cached --check` sowie die vollständige Godot-Preflight-Suite aus.
  - `commit-msg` erzwingt eine aussagekräftige Begründungszeile pro gestagter Datei (`- pfad/datei: Begründung.`).
  - `post-commit` pusht direkt auf `origin HEAD:$branch`.
- Markdown-Hard-Breaks (zwei Leerzeichen am Zeilenende) lassen `git diff --cached --check` im `pre-commit`-Hook fehlschlagen; Doc-Commits vorher mit `sed -i 's/[[:space:]]*$//' <dateien>` bereinigen.
- **Workflow-Schritte:**
  1. `GODOT_BIN` auf die Godot-Console-Binary setzen (`export GODOT_BIN=...` bzw. `$env:GODOT_BIN=...`).
  2. Nur relevante geänderte Dateien stagen via `git add <dateien>` (niemals `git add -A` oder `git add .`).
  3. `git commit` mit Datei-Begründungszeilen ausführen (`- datei: Begründung.`).
  4. Bei Preflight-Fehlern: Ursache beheben, korrigierte Dateien stagen und Commit wiederholen.
