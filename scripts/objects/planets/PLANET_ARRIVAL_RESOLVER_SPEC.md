# Slice 1: PlanetArrivalResolver — Extraktions-Spezifikation

## Ziel
**Neue Datei:** `scripts/objects/planets/planet_arrival_resolver.gd`
**Typ:** `class_name PlanetArrivalResolver extends RefCounted`
**Pattern:** Static Helper (wie `PlanetView`, `PlanetProcedural`)

## Methoden-Übersicht (Verschiebung aus planet.gd)

| # | Methode | planet.gd Zeilen | Zeilen-Anzahl | Rückgabe |
|---|---------|-------------------|---------------|----------|
| 1 | `resolve_arrival(planet, source_faction, amount)` | L412–L435 | 24 | `StringName` |
| 2 | `resolve_ship_arrival(planet, arriving_fleet, defender_fleet, battle_seed, conquest_seed, ship_role)` | L465–L489 | 25 | `Dictionary` |
| 3 | `_resolve_ship_vs_fleet(planet, arriving_fleet, defender_fleet, battle_seed, attacking_faction, out)` | L492–L518 | 27 | `Dictionary` |
| 4 | `_resolve_colony_ship_arrival(planet, arriving_fleet, attacking_faction, out)` | L521–L531 | 11 | `Dictionary` |
| 5 | `_resolve_ship_vs_planet(planet, arriving_fleet, conquest_seed, attacking_faction, out)` | L534–L552 | 19 | `Dictionary` |
| 6 | `_conquest_replay_result(planet, conquest)` | L545–L555 | 11 | `CombatReplay` |
| 7 | `_aggregate_defense_rating(planet)` | L556–L567 | 12 | `int` |
| 8 | `resolve_mission(planet, source_faction, amount, mission_type, source_planet_id)` | L567–L575 | 9 | `StringName` |
| 9 | `resolve_military_arrival(planet, source_faction, amount, _source_planet_id, conquest_seed)` | L580–L606 | 27 | `StringName` |
| 10 | `_resolve_colony(planet, source_faction, amount)` | L611–L621 | 11 | `StringName` |
| 11 | `_resolve_cargo(planet, source_faction, amount)` | L621–L630 | 10 | `StringName` |
| 12 | `_resolve_collect(planet, source_faction, amount, source_planet_id)` | L630–L644 | 15 | `StringName` |
| 13 | `recall_gathering_workers(planet, target_faction, amount)` | L644–L663 | 20 | `int` |
| — | Konstanten: `ARRIVAL_*`, `_CAPTURED_WORKER_PER_SHIP` | L39–L44, L436 | 6 | — |
| | **Gesamt verschoben** | | **~227L** | |

## Konstanten (bleiben in Planet, werden weitergegeben)

```gdscript
# planet.gd behält diese als Public-Konstanten (Preflight + WorkerCluster referenzieren sie):
const ARRIVAL_FRIENDLY := &"friendly"      # L39
const ARRIVAL_REPELLED := &"repelled"     # L40
const ARRIVAL_CAPTURED := &"captured"     # L41
const ARRIVAL_REJECTED := &"rejected"     # L42
const ARRIVAL_SETTLED := &"settled"       # L43
const ARRIVAL_COLLECTED := &"collected"   # L44
# Resolver definiert diese als eigene Kopie oder importiert via Planet.ARRIVAL_*
```

## Callback-Interface (Vermeidet direkten Planet-Zugriff)

Der Resolver greift NICHT direkt auf Planet-Felder zu. Statt dessen:

```gdscript
## Callback-Interface für Planet-Zustandszugriffe.
## Jeder Planet übergibt sich selbst als erstes Argument.
class_name PlanetArrivalResolver

# Planet-Zugriff via statische Helper mit Planet-Referenz:
static func get_worker_count(planet: Planet) -> int:
    return planet.worker_count

static func get_planet_id(planet: Planet) -> StringName:
    return planet.planet_id

static func get_faction(planet: Planet) -> StringName:
    return planet.get_faction()

static func get_display_name(planet: Planet) -> String:
    return planet.display_name

static func get_planet_texture(planet: Planet) -> Texture2D:
    return planet.planet_texture

static func get_perimeter_slots(planet: Planet) -> int:
    return planet.get_perimeter_slots()

static func get_defense_range(planet: Planet) -> float:
    return planet.get_defense_range()

# Mutations-Delegation (Resolver ruft Planet-METHODEN, nicht direkte Felder):
static func set_faction(planet: Planet, value: StringName) -> void:
    planet.set_faction(value)

static func register_workers(planet: Planet, amount: int) -> void:
    planet.register_workers(amount)

static func unregister_workers(planet: Planet, amount: int) -> void:
    planet.unregister_workers(amount)
```

## Vollständige Methoden-Signaturen (neue Datei)

```gdscript
const ARRIVAL_FRIENDLY := &"friendly"
const ARRIVAL_REPELLED := &"repelled"
const ARRIVAL_CAPTURED := &"captured"
const ARRIVAL_REJECTED := &"rejected"
const ARRIVAL_SETTLED := &"settled"
const ARRIVAL_COLLECTED := &"collected"
const _CAPTURED_WORKER_PER_SHIP := 10

static func resolve_arrival(planet: Planet, source_faction: StringName, amount: int) -> StringName
static func resolve_ship_arrival(
    planet: Planet,
    arriving_fleet: FleetSnapshot,
    defender_fleet: FleetSnapshot = null,
    battle_seed: int = 1337,
    conquest_seed: int = 42,
    ship_role: StringName = &""
) -> Dictionary
static func resolve_mission(
    planet: Planet,
    source_faction: StringName,
    amount: int,
    mission_type: StringName = &"military",
    source_planet_id: StringName = &""
) -> StringName
static func resolve_military_arrival(
    planet: Planet,
    source_faction: StringName,
    amount: int,
    _source_planet_id: StringName = &"",
    conquest_seed: int = 42
) -> StringName
static func recall_gathering_workers(
    planet: Planet,
    target_faction: StringName,
    amount: int
) -> int

# Private Helfer (alle static):
static func _resolve_ship_vs_fleet(...) -> Dictionary
static func _resolve_colony_ship_arrival(...) -> Dictionary
static func _resolve_ship_vs_planet(...) -> Dictionary
static func _conquest_replay_result(planet: Planet, conquest: CombatReplay) -> CombatReplay
static func _aggregate_defense_rating(planet: Planet) -> int
static func _resolve_colony(planet: Planet, source_faction: StringName, amount: int) -> StringName
static func _resolve_cargo(planet: Planet, source_faction: StringName, amount: int) -> StringName
static func _resolve_collect(planet: Planet, source_faction: StringName, amount: int, source_planet_id: StringName = &"") -> StringName
```

## planet.gd — Übergangsdelegationen (bleiben als Thin-Wrappers)

```gdscript
# In planet.gd — bestehende Methoden bleiben als Delegationen:

func resolve_arrival(source_faction: StringName, amount: int) -> StringName:
    return PlanetArrivalResolver.resolve_arrival(self, source_faction, amount)

func resolve_ship_arrival(
    arriving_fleet: FleetSnapshot,
    defender_fleet: FleetSnapshot = null,
    battle_seed: int = 1337,
    conquest_seed: int = 42,
    ship_role: StringName = &""
) -> Dictionary:
    return PlanetArrivalResolver.resolve_ship_arrival(
        self, arriving_fleet, defender_fleet, battle_seed, conquest_seed, ship_role
    )

func resolve_mission(source_faction: StringName, amount: int, mission_type: StringName = &"military", source_planet_id: StringName = &"") -> StringName:
    return PlanetArrivalResolver.resolve_mission(self, source_faction, amount, mission_type, source_planet_id)

func resolve_military_arrival(source_faction: StringName, amount: int, _source_planet_id: StringName = &"", conquest_seed: int = 42) -> StringName:
    return PlanetArrivalResolver.resolve_military_arrival(self, source_faction, amount, _source_planet_id, conquest_seed)

func recall_gathering_workers(target_faction: StringName, amount: int) -> int:
    return PlanetArrivalResolver.recall_gathering_workers(self, target_faction, amount)
```

## Caller-Referenzen (ES BLEIBT ALLE STABIL)

### Preflight-Aufrufe (bleiben unverändert — planet.method() Signatur gleich)

| Datei | Zeile | Aufruf |
|-------|-------|--------|
| `constraint_world_planets_and_dispatch.gd` | L361 | `destination.resolve_arrival(attack_faction, 2)` |
| `constraint_world_planets_and_dispatch.gd` | L373 | `repel_target.resolve_arrival(attack_faction, 1)` |
| `constraint_mission_semantics.gd` | L38 | `mission_neutral.resolve_mission(GameState.FACTION_PLAYER, 2, GameState.MISSION_COLONY)` |
| `constraint_mission_semantics.gd` | L43 | `mission_neutral.resolve_mission(GameState.FACTION_CPU, 1, GameState.MISSION_COLONY)` |
| `constraint_mission_semantics.gd` | L50 | `mission_source.resolve_mission(GameState.FACTION_PLAYER, 3, GameState.MISSION_CARGO)` |
| `constraint_mission_semantics.gd` | L55 | `mission_cpu.resolve_mission(GameState.FACTION_PLAYER, 3, GameState.MISSION_CARGO)` |
| `constraint_mission_semantics.gd` | L60 | `mission_neutral.resolve_mission(GameState.FACTION_CPU, 4, GameState.MISSION_MILITARY)` |
| `constraint_layers_2_and_3.gd` | L214 | `arrival_planet.resolve_ship_arrival(reinforce)` |
| `constraint_layers_2_and_3.gd` | L245 | `enemy_arrival_planet.resolve_ship_arrival(attacker, defender, 2024)` |
| `constraint_layers_2_and_3.gd` | L273 | `conquest_target.resolve_ship_arrival(attacker_only, null, 0, 1234)` |
| `constraint_layers_2_and_3.gd` | L303 | `rejection_planet.resolve_ship_arrival(null)` |
| `constraint_layers_2_and_3.gd` | L314 | `rejection_planet.resolve_ship_arrival(neutral_snap)` |
| `constraint_layers_2_and_3.gd` | L347 | `draft_target.resolve_military_arrival(draft_source.get_faction(), 4, draft_source_id)` |
| `constraint_layers_2_and_3.gd` | L365 | `fallback_target.resolve_military_arrival(GameState.FACTION_CPU, 4, &"")` |
| `constraint_scout_and_discovery.gd` | L326 | `destination.call("recall_gathering_workers", GameState.FACTION_PLAYER, gatherers_registered)` |

### Game-Code-Aufrufe (bleiben unverändert)

| Datei | Zeile | Aufruf |
|-------|-------|--------|
| `worker_cluster.gd` | L50 | `destination_planet.resolve_mission(source_faction, unit_count, mission_type, source_planet_id)` |
| `ship_manager.gd` | L133 | `destination_planet.resolve_ship_arrival(ship_base.fleet)` |
| `conflict_manager.gd` | L141 | `ship.destination.resolve_ship_arrival(ship.fleet, defender_fleet, 1337, 42, ship.mission_role)` |

### Signal-Emission (bleibt in Planet via callback)

| Signal | Auslöser im Resolver | Planet-Handler |
|--------|----------------------|----------------|
| `conflict_simulated` | `_resolve_ship_vs_fleet`, `_resolve_ship_vs_planet`, `resolve_military_arrival` | Planet.emit via callback |

## planet.gd — Zeilen die ENTFERNT werden

| Zeilen | Inhalt |
|--------|--------|
| L412–L435 | `resolve_arrival()` Body |
| L436–L455 | `_CAPTURED_WORKER_PER_SHIP` + `resolve_ship_arrival()` Docstring |
| L456–L489 | `resolve_ship_arrival()` Body |
| L492–L518 | `_resolve_ship_vs_fleet()` |
| L521–L531 | `_resolve_colony_ship_arrival()` |
| L534–L552 | `_resolve_ship_vs_planet()` |
| L545–L555 | `_conquest_replay_result()` |
| L556–L567 | `_aggregate_defense_rating()` |
| L567–L575 | `resolve_mission()` Body |
| L580–L606 | `resolve_military_arrival()` Body |
| L611–L621 | `_resolve_colony()` |
| L621–L630 | `_resolve_cargo()` |
| L630–L644 | `_resolve_collect()` |
| L644–L663 | `recall_gathering_workers()` Body |
| **Gesamt** | **~227 Zeilen entfernt** |

## planet.gd — Zeilen die HINZUGEFÜGT werden (Delegationen)

| Zeilen (neu) | Inhalt |
|-------------|--------|
| ~24 Zeilen | 5 Thin-Wrapper-Delegationen (resolve_arrival, resolve_ship_arrival, resolve_mission, resolve_military_arrival, recall_gathering_workers) |
| **Netto-Änderung** | **−203 Zeilen (846 → ~643)** |

## Fehlerhafte Referenzen (PRÜFUNG)

| Referenz | Status |
|----------|--------|
| `ARRIVAL_FRIENDLY` in Preflight | ✅ Planet behält Konstanten |
| `Planet.ARRIVAL_*` in AGENTS.md | ✅ Dokumentation, kein Code |
| `conflict_simulated.emit(...)` | ✅ Resolver nutzt `planet.conflict_simulated.emit(...)` via Referenz |
| `GameState.FACTION_NEUTRAL` | ✅ Static Konstante, kein Planet-Zugriff |
| `FleetBattleSimulator.simulate_battle(...)` | ✅ Static, kein Planet-Zugriff |
| `ConquestSimulator.simulate_conquest(...)` | ✅ Static, kein Planet-Zugriff |
| `FloatingText.spawn(...)` | ✅ In `show_arrival_feedback` — bleibt in Planet |
| `DEFAULT_UPGRADE_CATALOG` | ✅ Wird in `_aggregate_defense_rating` gebraucht — aus `Planet.DEFAULT_UPGRADE_CATALOG` via Referenz |

## Godot-spezifische Safety-Checks

1. **class_name Registrierung:** Nach Erstellen der Datei muss ein Headless-Editor-Scan laufen (`--headless --path . --editor --quit`) damit `PlanetArrivalResolver` in `global_script_class_cache.cfg` landet.
2. **Kein `@tool`:** Resolver ist reiner GDScript, kein `@tool` nötig (keine Editor-Interaktion).
3. **Keine `@onready`:** Static Methods brauchen keine Node-Referenzen.
4. **Signal-Weiterleitung:** `conflict_simulated.emit(...)` funktioniert mit `planet.conflict_simulated.emit(...)` — Planet ist der Signal-Eigner, Resolver ruft nur auf.
5. **`_game_state()` Zugriff:** Resolver nutzt `GameStateAccess.autoload(planet)` (gleicher Code wie Planet).
6. **`_on_faction_changed` callback:** Planet-Faction-Setter bleibt in Planet — Resolver ruft `set_faction()` auf.

## Zusammenfassung

```
VORHER (planet.gd: 846L):
├── Input/Click/Long-Press: ~110L
├── Fog-of-War:             ~55L
├── Spawn-Timer:            ~45L
├── Upgrade-Traits:         ~85L   → SLICE 2
├── Arrival/Combat:        ~227L   → SLICE 1 (diese Datei)
├── Signal-Handler:         ~50L
├── Drawing/Groups:         ~55L
└── Core State:            ~274L

NACHHER (planet.gd: ~643L):
├── Input/Click/Long-Press: ~110L
├── Fog-of-War:             ~55L
├── Spawn-Timer:            ~45L
├── Upgrade-Traits:         ~85L   → SLICE 2
├── Delegationen:           ~24L   (5 Wrapper)
├── Signal-Handler:         ~50L
├── Drawing/Groups:         ~55L
└── Core State:            ~219L
```
