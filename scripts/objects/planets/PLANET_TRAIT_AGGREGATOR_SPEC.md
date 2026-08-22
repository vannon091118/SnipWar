# Slice 2: PlanetTraitAggregator — Extraktions-Spezifikation

## Ziel
**Neue Datei:** `scripts/objects/planets/planet_trait_aggregator.gd`
**Typ:** `class_name PlanetTraitAggregator extends RefCounted`
**Pattern:** Static Helper (wie PlanetView)

## Problem
Planet.gd hat 6 Methoden, die alle das gleiche Pattern wiederholen:
```
for up_id in state.get_planet_upgrades(planet_id):
    var def := DEFAULT_UPGRADE_CATALOG.resolve(up_id)
    if def != null and def.trait_definition != null:
        sum += def.trait_definition.FIELD
```

Jede dieser Schleifen iteriert `get_planet_upgrades()` einzeln — N × M Aufrufe pro Frame.

## Methoden-Übersicht (Verschiebung aus planet.gd)

| # | Methode | planet.gd Zeilen | Zeilen | Zweck |
|---|---------|-------------------|--------|-------|
| 1 | `get_build_slot_count(planet)` | L373–L374 | 2 | Base build slots |
| 2 | `get_perimeter_slots(planet)` | L375–L385 | 11 | Base + upgrade bonus |
| 3 | `get_defense_range(planet)` | L386–L397 | 12 | Base 150 + range_bonus |
| 4 | `get_transfer_speed_multiplier(planet)` | L664–L675 | 12 | Multiplicative speed |
| 5 | `get_cluster_tier_bonus(planet)` | L675–L685 | 11 | Additive tier bonus |
| 6 | `_spawn_count(planet)` | L362–L372 | 11 | spawn_count + bonus |
| 7 | `_aggregate_defense_rating(planet)` | L556–L567 | 12 | Defense sum for conquest |
| | **Gesamt verschoben** | | **~71L** | |

## Vollständige Methoden-Signaturen

```gdscript
class_name PlanetTraitAggregator
extends RefCounted

## Aggregiert Upgrade-Trait-Boni für einen Planeten.
## Einmaliger Catalog-Lookup pro Aufruf statt N-Mal-Iterieren.

const DEFAULT_CATALOG: PlanetUpgradeCatalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")

## Liest alle Upgrades und summiert die benötigten Traits in einem Durchlauf.
## Gibt ein Dictionary mit folgenden Keys zurück:
##   "build_slot_count": int
##   "perimeter_slots_bonus": int
##   "defense_rating": int
##   "range_bonus": float
##   "transfer_speed_multiplier": float (multiplikativ, startet bei 1.0)
##   "cluster_tier_bonus": int
##   "worker_spawn_bonus": int
static func aggregate_all_traits(planet: Planet) -> Dictionary:
    var state: Node = GameStateAccess.autoload(planet)
    var result: Dictionary = {
        "build_slot_count": planet.size_profile.build_slot_count if planet.size_profile != null else 1,
        "perimeter_slots_bonus": 0,
        "defense_rating": 0,
        "range_bonus": 0.0,
        "transfer_speed_multiplier": 1.0,
        "cluster_tier_bonus": 0,
        "worker_spawn_bonus": 0,
    }
    if state == null:
        return result
    for up_id in state.get_planet_upgrades(planet.planet_id):
        var def: PlanetUpgradeDefinition = DEFAULT_CATALOG.resolve(up_id)
        if def == null or def.trait_definition == null:
            continue
        var t: TraitDefinition = def.trait_definition
        result["perimeter_slots_bonus"] += t.perimeter_slots_bonus
        result["defense_rating"] += t.defense_rating
        result["range_bonus"] += t.range_bonus
        result["transfer_speed_multiplier"] *= t.transfer_speed_multiplier
        result["cluster_tier_bonus"] += t.cluster_tier_bonus
        result["worker_spawn_bonus"] += t.worker_spawn_bonus
    return result

# --- Einzelne Helper (für Aufrufer die nur EINEN Wert brauchen) ---

static func get_build_slot_count(planet: Planet) -> int:
    var profile: PlanetSizeProfile = planet.get_size_profile()
    return maxi(profile.build_slot_count, 1)

static func get_perimeter_slots(planet: Planet) -> int:
    var traits := aggregate_all_traits(planet)
    return maxi(1, int(traits["build_slot_count"]) + int(traits["perimeter_slots_bonus"]))

static func get_defense_range(planet: Planet) -> float:
    var traits := aggregate_all_traits(planet)
    return maxf(50.0, 150.0 + float(traits["range_bonus"]))

static func get_transfer_speed_multiplier(planet: Planet) -> float:
    var traits := aggregate_all_traits(planet)
    return float(traits["transfer_speed_multiplier"])

static func get_cluster_tier_bonus(planet: Planet) -> int:
    var traits := aggregate_all_traits(planet)
    return maxi(0, int(traits["cluster_tier_bonus"]))

static func get_spawn_count(planet: Planet) -> int:
    var traits := aggregate_all_traits(planet)
    var count: int = planet.get_size_profile().spawn_count + int(traits["worker_spawn_bonus"])
    return mini(count, get_build_slot_count(planet))

static func aggregate_defense_rating(planet: Planet) -> int:
    var traits := aggregate_all_traits(planet)
    return int(traits["defense_rating"])
```

**Hinweis:** `aggregate_all_traits()` wird intern von den Einzel-Helper aufgerufen. Für Hot-Paths die mehrere Werte brauchen (z.B. `resolve_arrival` + `resolve_ship_arrival`), kann der Caller `aggregate_all_traits()` einmal aufrufen und die Werte direkt entnehmen.

## planet.gd — Übergangsdelegationen

```gdscript
# In planet.gd — bestehende public Methoden bleiben:

func get_build_slot_count() -> int:
    return PlanetTraitAggregator.get_build_slot_count(self)

func get_perimeter_slots() -> int:
    return PlanetTraitAggregator.get_perimeter_slots(self)

func get_defense_range() -> float:
    return PlanetTraitAggregator.get_defense_range(self)

func get_transfer_speed_multiplier() -> float:
    return PlanetTraitAggregator.get_transfer_speed_multiplier(self)

func get_cluster_tier_bonus() -> int:
    return PlanetTraitAggregator.get_cluster_tier_bonus(self)
```

**`_spawn_count()` und `_aggregate_defense_rating()`** sind private in Planet und werden NICHT als Wrapper gebraucht — sie werden direkt im Planet-Body durch den jeweiligen Helper ersetzt.

## Caller-Referenzen (ALLE stabil — planet.method() Signatur gleich)

### Preflight

| Datei | Zeile | Aufruf |
|-------|-------|--------|
| `constraint_layers_2_and_3.gd` | L15 | `test_planet.get_perimeter_slots()` |
| `constraint_layers_2_and_3.gd` | L17 | `test_planet.get_defense_range()` |
| `constraint_cpu_dispatch.gd` | L65 | `upgrade_planet.get_cluster_tier_bonus()` |
| `constraint_cpu_dispatch.gd` | L73 | `upgrade_planet.get_cluster_tier_bonus()` |

### Game-Code

| Datei | Zeile | Aufruf |
|-------|-------|--------|
| `worker_manager.gd` | L38 | `source.get_cluster_tier_bonus()` |
| `worker_manager.gd` | L41 | `source.get_transfer_speed_multiplier()` |
| `planet_network.gd` | L516 | `(_active_planet as Planet).get_transfer_speed_multiplier()` |
| `planet_panel.gd` | L272 | `selected_planet.get_perimeter_slots()` |
| `planet_panel.gd` | L273 | `selected_planet.get_defense_range()` |
| `planet_panel.gd` | L285 | `selected_planet.get_perimeter_slots()` |
| `planet_panel.gd` | L286 | `selected_planet.get_defense_range()` |

## planet.gd — Zeilen die ENTFERNT werden

| Zeilen | Inhalt | Zeilen |
|--------|--------|--------|
| L362–L372 | `_spawn_count()` Body | 11 |
| L373–L374 | `get_build_slot_count()` Body | 2 |
| L375–L385 | `get_perimeter_slots()` Body | 11 |
| L386–L397 | `get_defense_range()` Body | 12 |
| L556–L567 | `_aggregate_defense_rating()` Body | 12 |
| L664–L675 | `get_transfer_speed_multiplier()` Body | 12 |
| L675–L685 | `get_cluster_tier_bonus()` Body | 11 |
| **Gesamt** | | **~71 Zeilen entfernt** |

## planet.gd — Zeilen die HINZUGEFÜGT werden

| Inhalt | Zeilen |
|--------|--------|
| 5 Thin-Wrapper (get_build_slot_count, get_perimeter_slots, get_defense_range, get_transfer_speed_multiplier, get_cluster_tier_bonus) | ~15 |
| `aggregate_all_traits()` Aufruf in `_spawn_count()` und `resolve_arrival()` | ~4 |
| **Netto-Änderung** | **−52 Zeilen (846 → ~794 nach Slice 1+2: ~591)** |

## Kombination Slice 1 + Slice 2

```
planet.gd VORHER:   846L
planet.gd NACHHER: ~591L  (−255L, −30%)

Aufteilung:
├── planet.gd:                 ~591L  (Core State, Input, Fog, Signals, Drawing, Delegationen)
├── planet_arrival_resolver.gd: ~227L  (Arrival/Combat-Logik)
├── planet_trait_aggregator.gd:  ~100L  (Upgrade-Trait-Aggregation + Helper)
├── planet_view.gd:              ~63L   (✅ bereits vorhanden)
└── planet_procedural.gd:        ~55L   (✅ bereits vorhanden)
```

## Godot-spezifische Safety-Checks

1. **class_name Registrierung:** Headless-Editor-Scan nach Erstellen.
2. **Kein `@tool`:** Reiner GDScript-Helper.
3. **`GameStateAccess.autoload(planet)`:** Gleicher Zugriffsweg wie in Planet.
4. **`DEFAULT_CATALOG` Konstante:** Wird aus `Planet.DEFAULT_UPGRADE_CATALOG` übernommen.
5. **`size_profile` Zugriff:** `planet.size_profile` ist ein `@export` — lesbar von außen.
6. **Preflight-Stabilität:** Alle öffentlichen Methoden bleiben auf Planet mit gleicher Signatur.
