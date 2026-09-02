# SEARCH INDEX — LLM-freundlicher Kontext-Index

> **Zweck:** Flacher, zeilenbasierter Suchindex für LLM-Agenten. Jede Zeile:
> `TERM → Datei : Kontext`. Durchsuchbar mit:
> `global_search.gd "TERM" --type md` oder ConceptIndex.
> Dieser Index ist die **Anti-Rate-Quelle** für „wo ist X?“.

---

## Event-Boundary & Autoloads

- `EventBus → scripts/state/event_bus.gd : signal game_event(type, data); emit_event() — einzige Cross-Domain-Event-Grenze`
- `run_started → scripts/state/game_state.gd:150+ : _dispatch_event(&"run_started", {run_id, layout_seed}) — via EventBus, nicht direkt an Consumer`
- `WorldChronicle → scripts/history/world_chronicle.gd : EventBus-Konsument; _on_game_event → _on_run_started → reset(); KEIN GameState-Signal`
- `EventLog → scripts/state/event_log.gd : EventBus-Konsument; kein GameState-Fallback (Phase 5)`
- `GameStateAccess → scripts/game_state_access.gd : autoload(self) — dokumentierter Autoload-Zugriff (12+ Consumer)`

## Domänen & State Ownership

- `FactionDomain → scripts/state/domains/faction_domain.gd : ownership/starting_workers/homeworlds/known_planets`
- `EconomyDomain → scripts/state/domains/economy_domain.gd : faction_vaults/planet_resources/planet_upgrades/gathering_workers`
- `TechDomain → scripts/state/domains/tech_domain.gd : Technologie-Forschung`
- `ShipDomain → scripts/state/domains/ship_domain.gd : Schiffe/Flotten/persistent_ship_changed`
- `GameState → scripts/state/game_state.gd : Compatibility-Facade; orchestriert 4 Domänen; snapshot_run/restore_run; register_chunk_coordinator/register_economy_manager/get_economy_manager`

## Config & Konstanten

- `GameConstants → scripts/config/game_constants.gd : dependency-freie StringName-Konstanten; Config-Resources nutzen NIE GameState (Compile-Zyklus-Fix, Phase 1)`
- `TransitRecord → scripts/config/transit_record.gd : STATUS_IN_FLIGHT/ENGAGED/ARRIVED/RESOLVED/CANCELLED`
- `ShipPartCatalog → scripts/config/ship_part_catalog.gd : Schiffs-Teile-Katalog`
- `TechnologyDefinition → scripts/config/technology_definition.gd : Tech-Definitionen`

## Welt & Szenen

- `SeededLayout → scripts/objects/seeded_layout.gd : registriert ChunkCoordinator (Z.357) + EconomyManager (Z.153) bei GameState`
- `ChunkCoordinator → scripts/objects/chunk_coordinator.gd : save_state/Restore; chunked unendliche Welt`
- `PlanetEconomyManager → scripts/objects/planets/economy_manager.gd : economy_tick_remaining/restore_timer_remaining`
- `ConflictManager → scripts/objects/conflict_manager.gd : Battle/Conquest-Seeds; emit_event; mark_research_ship_departed via Facade`
- `world.tscn → scenes/world/world.tscn : WorldBootstrap + PlanetField + MeteorField + MapCamera + PauseMenu`
- `battle_scene.tscn → scenes/battle/battle_scene.tscn : FleetBattleSimulator + BattleScene + IngamePlayerControls`
- `conquest_scene.tscn → scenes/conquest/conquest_scene.tscn : ConquestSimulator + ConquestScene`

## History/Chronicle (Phasen 1–9 modularisiert)

- `HistorySimulator → scripts/history/simulation/history_simulator.gd : simulate(initial_factions, initial_planets, seed, years, catalog); simulate_with_snapshots(..., interval) — pure RefCounted, kein UI/SceneTree/Save`
- `HistoricalSnapshot → scripts/history/historical_snapshot.gd : pure data (year/ownership/events); owner_of/faction_planets`
- `PlaybackController → scripts/history/playback_controller.gd : seek/next/prev/play/pause; snapshot_changed(index, snapshot)`
- `HistoricalRenderer → scripts/ui/history/historical_renderer.gd : nur Snapshots; SVG-Wiederverwendung; deterministisches Ring-Layout`
- `WorldChronicle save → scripts/history/chronicle_save_data.gd : Teil von RunSaveData; Roundtrip-Vertrag in constraint_save_game_roundtrip.gd`
- `HistoryEvent → scripts/history/history_event.gd : event_id/year/event_type/actors/target/winner/loser/cause_event_id`
- `HistoryEventFactory → scripts/history/simulation/history_event_factory.gd : erzeugt 10 Event-Typen (alliance/build/colony/conquest/defeat/peace_treaty/research/rivalry/trade/war_declared)`
- `FactionAI → scripts/history/simulation/faction_ai.gd : decide_turn; Kriegs-Logik (SIM-CAUSE-1..6 gefixt)`

## Narrative Runtime (Python)

- `narrative_runtime → narrative_runtime/ : stdlib-only, deterministisch; observe→relationships→beliefs→threads→perspectives→public_state→spotlight→store`
- `Gate G1-G24 → narrative_runtime/gate.py + gate_cli.py : read-only-Verify; 43. Preflight-Constraint (constraint_narrative_runtime.gd)`
- `182 Matrix → narrative_runtime/relationships.py : 8 Achsen (trust/respect/irritation/affinity/competence_confidence/resentment/curiosity/defensiveness)`

## DOKI (gepinntes Home, entkoppelt)

- `DOKI CLI → C:/Users/Vannon/Desktop/doki/ : bin/doki prepare|finish|status|gate … (eigenes Projekt + git-Repo, docs/DOKI_PIN.md)`
- `Composite → doki/core im Home : c17j48n14a1p1 — Commit-Counter/Narrator/Jitter/Arc/Plot; deterministisch`
- `14 Narratoren → doki/character im Home : Buffy/Basher/Thinker/Vannon/Squizzle/Devin/Argos/Ghost/Spark/Glitch/Null/Echo/Flux/Sage`
- `Chain → .doki/narrative_chain.json : Git-Wahrheit; ChainStore im Home (doki/chain/chain_store.gd)`

## UI & Presentation

- `EconomyWindow → scripts/ui/economy_window.gd : Manager via GameState.get_economy_manager() — KEIN Szenenbaum-Scan (Phase 6)`
- `PlanetNetworkUI → scripts/objects/planets/planet_network_ui.gd : Manager via Getter; VaultBar/PlanetPanel`
- `MainMenu → scripts/ui/main_menu.gd : Neues Spiel/Weiter/Beenden`
- `SimulationOverlay → scripts/ui/history/simulation_overlay.gd : noch unerreichbar (geplante History-UI)`
- `ChronicleArchiveView → scripts/ui/history/chronicle_archive_view.gd : noch unerreichbar`

## Testing & Preflight

- `Preflight → scripts/preflight.gd : 44 Constraints (19 pure, 25 scene); -x fail-fast; --filter`
- `CompileGate → scripts/testing/compile_gate.gd : 311 Skripte`
- `ChronicleCoreTest → scripts/testing/chronicle_core_test.gd : 22 Checks; Determinismus Seed 424242×2 + 999999`
- `ChronicleLifecycleTest → scripts/testing/chronicle_lifecycle_test.gd : 21 Checks; EventBus-Boundary-Vertrag`
- `HistoricalPlaybackTest → scripts/testing/historical_playback_test.gd : 18 Checks; simulate==with_snapshots`
- `SaveRoundtrip → scripts/preflight/constraint_save_game_roundtrip.gd : Chronicle-Payload-Vertrag (4 Checks)`
- `docs_integrity → scripts/preflight/constraint_docs_integrity.gd : Duplicate-Headings/Table-Checks`

## Suchen & Werkzeuge

- `ConceptIndex → scripts/concept_index.gd : search/expand/class_concept/by_domain; Wartung: _build_concepts()`
- `ConceptSearch CLI → scripts/concept_search.gd : --domain/--class/--free-slots/--list-domains/--unmapped`
- `GlobalSearch → scripts/global_search.gd : Volltext JSON; --type/--context/--regex/--max-files`
- `SearchCore → scripts/search_core.gd : Engine (search/classes_available/dependency_graph)`

## MCP

- `MCP-Doktrin → addons/gdscript_mcp/AGENTS.md : Pflicht-Lektüre vor MCP-Tests`
- `McpRuntime → addons/gdscript_mcp/runtime/host/mcp_runtime.gd : Autoload; async/sync-Dispatch`
- `VisionWorker → addons/gdscript_mcp/client/vision_worker.py : OCR (Tesseract deu)`

## Godot-Pitfalls (kurz)

- `Array.map → typed-Array : Array.map() liefert untyped → Zuweisung an Array[StringName] crasht (489 SCRIPT ERRORS); explizit typisierte Schleife nutzen (Phase 1)`
- `Config→Autoload-Zyklus : Config-Resource → GameState → Config-Resource = Compile-Fehler; Lösung: GameConstants (Phase 1)`
- `UID-Alphabet : Godot-UIDs sind Base32 0-9a-v; ungültige Zeichen (y/x/w) → Editor verwirft Sidecar`
- `@export_enum → String/Integer, nicht StringName`
- `SceneTree.quit() → danach return`
- `get_visible_rect() headless → (0,0)`
- `Node.name → StringName; für String-Ops String(node.name)`
- `class_name als Parametername verboten`
- `func load() verboten → read()`