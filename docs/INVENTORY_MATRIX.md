# INVENTORY MATRIX — SnipWar Systemkarte (Stand: nach Modularisierung Phasen 1–9)

> **Zweck:** LLM-freundliche, maschinenlesbare Systemkarte. Jede Zeile:
> System/Domäne → Datei → öffentliche Klasse → Kern-API → Zustand.
> Diese Matrix ist die **Anti-Rate-Quelle**: Wer eine Klasse sucht, findet sie
> hier in einem Tool-Call (global_search findet diese Datei als .md).
>
> **Pflege:** Neue Klassen hier eintragen. Preflight `concept_index` prüft
> Klassen-Verfügbarkeit gegen diese Struktur.

---

## A. Autoloads (project.godot [autoload], Reihenfolge = Lade-Reihenfolge)

| # | Autoload | Datei | Rolle | Zustand |
|---|----------|-------|-------|---------|
| 1 | `EventBus` | `scripts/state/event_bus.gd` | Einzige Cross-Domain-Event-Grenze (`game_event(type, data)`) | Runtime |
| 2 | `GameState` | `scripts/state/game_state.gd` | Compatibility-Facade + Orchestrator über 4 Domänen | Runtime + Save |
| 3 | `WorldChronicle` | `scripts/history/world_chronicle.gd` | Weltgeschichts-Simulation (Backstory), EventBus-Konsument | Runtime + Save (ChronicleSaveData) |
| 4 | `GameCycleManager` | `scripts/game_cycle_manager.gd` | Run-Lifecycle, Scene-Wechsel | Runtime |
| 5 | `SceneDirectorService` | `scripts/ui/scene_director.gd` | Szenen-Navigation | Runtime |
| 6 | `SaveGameService` | `scripts/state/save_game_service.gd` | Persistenz-Infrastruktur (Slots 0–7, atomar) | Persistenz |
| 7 | `EventLog` | `scripts/state/event_log.gd` | Spiel-Log, EventBus-Konsument (kein GameState-Fallback) | Runtime |
| 8 | `TouchFeedbackLayer` | — | UI-Feedback | Runtime |
| 9 | `McpRuntime` | `addons/gdscript_mcp/runtime/host/mcp_runtime.gd` | MCP-Server | Runtime |
| 10 | `McpProjectAdapter` | `addons/gdscript_mcp/` | MCP-Projektadapter | Runtime |

## B. Domänen (State Ownership, SSO)

| Domäne | Datei | Klasse | Eigener Zustand | Kern-API |
|--------|-------|--------|-----------------|----------|
| Faction | `scripts/state/domains/faction_domain.gd` | `FactionDomain` | `ownership`, `starting_workers`, `homeworlds`, `known_planets` | `set_faction`, `discover_planet`, `scan_planet`, `is_known`, `homeworld_for` |
| Economy | `scripts/state/domains/economy_domain.gd` | `EconomyDomain` | `faction_vaults`, `planet_resources`, `planet_upgrades`, `gathering_workers` | `add_faction_resource`, `register_gathering_workers_with_domains`, `can_register_trade_route` |
| Technology | `scripts/state/domains/tech_domain.gd` | `TechDomain` | Forschung, Tech-Bäume | `research_technology`, `advance_research`, `has_technology` |
| Ships | `scripts/state/domains/ship_domain.gd` | `ShipDomain` | Schiffe, Flotten, Persistenz | `register_persistent_fleet`, `mark_research_ship_departed` |

**Regel:** GameState orchestriert, dupliziert nicht. UI liest über GameState-Facade (Getter), nie über `domain.*` intern.

## C. Config/Constants

| Datei | Klasse | Zweck |
|-------|--------|-------|
| `scripts/config/game_constants.gd` | `GameConstants` | **Dependency-freie** StringName-Konstanten (Faction/Resource/Mission/Tech) — Config-Resources nutzen NUR diese, nie GameState |
| `scripts/config/ship_part_catalog.gd` | `ShipPartCatalog` | Schiffs-Teile-Katalog |
| `scripts/config/ship_part_definition.gd` | `ShipPartDefinition` | Teil-Definition |
| `scripts/config/technology_definition.gd` | `TechnologyDefinition` | Technologie-Definition |
| `scripts/config/planet_upgrade_definition.gd` | `PlanetUpgradeDefinition` | Upgrade-Definition |
| `scripts/config/ship_config.gd` | `ShipConfig` | Schiffskonfig |
| `scripts/config/transit_record.gd` | `TransitRecord` | Transit-Status-Konstanten (STATUS_*) |

## D. Welt-Systeme

| System | Datei | Klasse | Zustand |
|--------|-------|--------|---------|
| World Generation | `scripts/config/world_generator.gd` | `WorldGenerator` | Statische Seed-Funktionen |
| Chunk World | `scripts/objects/chunk_coordinator.gd` | `ChunkCoordinator` | `save_state`/Restore, registriert bei GameState |
| Layout | `scripts/objects/seeded_layout.gd` | `SeededLayout` | Registriert ChunkCoordinator + EconomyManager bei GameState |
| Navigation | `scripts/objects/planets/navigation_field.gd` | `NavigationField` | Routen-Graph |
| Planet Network | `scripts/objects/planets/planet_network.gd` | `PlanetNetwork` | Planet-UI-Koordination |
| Economy Manager | `scripts/objects/planets/economy_manager.gd` | `PlanetEconomyManager` | Ticks, `economy_tick_remaining`, registriert bei GameState |
| CPU Dispatch | `scripts/objects/planets/cpu_dispatch_ai.gd` | `CpuDispatchAI` | CPU-Aktionen |
| Conflict | `scripts/objects/conflict_manager.gd` | `ConflictManager` | Battle/Conquest-Seeds, EventBus-Emit |

## E. Simulation (L2/L3)

| System | Datei | Klasse |
|--------|-------|--------|
| Flotten-Kampf | `scripts/battle/fleet_battle_simulator.gd` | `FleetBattleSimulator` |
| Eroberung | `scripts/conquest/conquest_simulator.gd` | `ConquestSimulator` |
| Ankunfts-Auflösung | `scripts/objects/planets/arrival/planet_arrival_resolver.gd` | `PlanetArrivalResolver` |

## F. History/Chronicle (Modularisiert in Phasen 1–9)

| System | Datei | Klasse | Boundary |
|--------|-------|--------|----------|
| Weltchronik | `scripts/history/world_chronicle.gd` | `WorldChronicle` | EventBus rein (kein GameState-Signal), GameState-Input nur via expliziter Schnittstelle |
| Simulation | `scripts/history/simulation/history_simulator.gd` | `HistorySimulator` | Pure RefCounted: `simulate(initial_factions, initial_planets, seed, years, catalog)` / `simulate_with_snapshots(..., interval)` |
| Snapshot | `scripts/history/historical_snapshot.gd` | `HistoricalSnapshot` | Pure data: `year`, `ownership`, `events` |
| Playback | `scripts/history/playback_controller.gd` | `PlaybackController` | Nur Snapshots: `seek/next/prev/play/pause`, Signal `snapshot_changed` |
| Renderer | `scripts/ui/history/historical_renderer.gd` | `HistoricalRenderer` | Nur Snapshots, SVG-Wiederverwendung, deterministisches Layout |
| Faction-AI | `scripts/history/simulation/faction_ai.gd` | `FactionAI` | Pure |
| Event-Factory | `scripts/history/simulation/history_event_factory.gd` | `HistoryEventFactory` | Erzeugt 10 Event-Typen (siehe STRING_MATRIX §7) |
| Save | `scripts/history/chronicle_save_data.gd` | `ChronicleSaveData` | Teil von RunSaveData, Roundtrip-Vertrag im Preflight |

## G. Narrative Runtime (Python, stdlib-only, isoliert)

| Datei | Rolle |
|-------|-------|
| `narrative_runtime/observe.py` | Observationen aus Chain |
| `narrative_runtime/relationships.py` | 182er-Matrix, 8 Achsen, Decay |
| `narrative_runtime/beliefs.py` | Beliefs + Memory |
| `narrative_runtime/threads.py` | Threads |
| `narrative_runtime/perspectives.py` | Perspektiven |
| `narrative_runtime/personality.py` | 14 Persönlichkeiten |
| `narrative_runtime/public_state.py` | Visibility/Hype/Reputation |
| `narrative_runtime/spotlight.py` | Auswahl (deterministisch, Composite) |
| `narrative_runtime/store.py` | SQLite-Archiv |
| `narrative_runtime/gate.py` + `gate_cli.py` | G1–G24 Gate (read-only) |
| `scripts/testing/narrative_runtime_gate.gd` | Godot-Entry-Test |
| `scripts/preflight/constraint_narrative_runtime.gd` | **43. Preflight-Constraint** (fail-closed, ~18 s) |

## H. DOKI (Git-gebunden, inward-only)

| Datei | Rolle |
|-------|-------|
| `scripts/doki/doki.gd` | CLI (init/prepare/finish/amend/verify-only/finalize/repair/status/gate) |
| `scripts/doki/core/` | Rng/Verifier |
| `scripts/doki/chain/` | Stores (Chain/Session/ChangeIndex) |
| `scripts/doki/character/` | 14 Narratoren, Moods |
| `scripts/doki/prompt/` | VoiceComposer, SideplotEngine |
| `scripts/doki/orchestration/` | Flows (prepare/finish/finalize/gate) |
| `scripts/doki/data/arcs.json` | Arc-Definitionen |
| `scripts/doki/metrics_updater.gd` | METRICS_TRACKER.md |

## I. UI (Presentation)

| System | Datei | Klasse |
|--------|-------|--------|
| Main Menu | `scripts/ui/main_menu.gd` | `MainMenu` |
| World UI | `scripts/backgrounds/map_camera.gd` | `MapCamera` |
| Economy UI | `scripts/ui/economy_window.gd` | `EconomyWindow` (Manager via `get_economy_manager()`, kein Baum-Scan) |
| Planet UI | `scripts/objects/planets/planet_network_ui.gd` | `PlanetNetworkUI` (Manager via Getter) |
| Dossier | `scripts/dossier/` | Workshop/Parchment-Views |
| History UI | `scripts/ui/history/` | `SimulationOverlay`, `ChronicleArchiveView`, `HistoricalRenderer` (Renderer verdrahtet, Overlays noch unerreichbar) |

## J. Testing/Validation

| System | Datei | Zweck |
|--------|-------|-------|
| Preflight | `scripts/preflight.gd` | 44 Constraints (19 pure, 25 scene) |
| Compile Gate | `scripts/testing/compile_gate.gd` | 311 Skripte |
| Chronicle Core | `scripts/testing/chronicle_core_test.gd` | 22 Checks |
| Chronicle Lifecycle | `scripts/testing/chronicle_lifecycle_test.gd` | 21 Checks, EventBus-Boundary |
| Historical Playback | `scripts/testing/historical_playback_test.gd` | 18 Checks, Determinismus |
| Narrative Gate | `scripts/testing/narrative_runtime_gate.gd` | Python-Gate |
| MCP Capture | `scripts/testing/mcp_capture_entry_test.gd` | Async-Vertrag |
| Chain Validate | `scripts/testing/chain_validate_entry_test.gd` | Entry-Points |

## K. MCP-Addon

| Datei | Rolle |
|-------|-------|
| `addons/gdscript_mcp/AGENTS.md` | **Pflicht-Lektüre** vor MCP-Tests |
| `addons/gdscript_mcp/runtime/host/mcp_runtime.gd` | Host |
| `addons/gdscript_mcp/client/vision_worker.py` | OCR/Tesseract |
| `addons/gdscript_mcp/.mcp.json` | Transport |

## L. Such-Infrastruktur (LLM-Werkzeuge)

| Tool | Datei | Zweck |
|------|-------|-------|
| ConceptIndex | `scripts/concept_index.gd` | Semantische Klassen-/Domänen-Suche |
| ConceptSearch CLI | `scripts/concept_search.gd` | `--domain/--class/--free-slots/--list-domains` |
| GlobalSearch | `scripts/global_search.gd` | Volltext über .gd/.tres/.tscn/.md/.json, JSON-Output mit dependency_graph |
| SearchCore | `scripts/search_core.gd` | Engine hinter GlobalSearch |
| **Doku-Index** | `docs/STRING_MATRIX.md`, `docs/INVENTORY_MATRIX.md` | Statische LLM-Matrizen (durchsuchbar via global_search) |

## M. Kopplungsknoten (Top, bewusst)

1. **GameState** — Facade über 4 Domänen + Event-Dispatch + Save-Integration (gewollt, §4/§15)
2. **EventBus** — einzige Event-Grenze (EventLog + WorldChronicle hängen nur hier)
3. **GameConstants** — dependency-freie Konstantenquelle (Config-Sicherheit)
4. **SeededLayout** — registriert Welt-Objekte bei GameState (Scene-Boundary)
5. **PreflightContext** — Fixture + CodeIndex für alle Constraints

## N. Bewusst NICHT extrahiert

| System | Grund |
|--------|-------|
| `_find_chunk_coordinator`/`_find_economy_manager`-Fallbacks in GameState | `chronicle_lifecycle_test` läuft ohne Welt-Szene und nutzt sie (dokumentierter Fallback) |
| `SimulationOverlay`/`ChronicleArchiveView` | Geplante History-UI-Grundlage (§14), noch unverdrahtet |
| `narrative_runtime/` (Python) | Vertrag: NICHT nach GDScript portieren |
| `scripts/doki/` | Eigenständig, keine Gameplay-Kopplung |
| `GameStateAccess` | Etablierter Autoload-Helper, 12+ Consumer |