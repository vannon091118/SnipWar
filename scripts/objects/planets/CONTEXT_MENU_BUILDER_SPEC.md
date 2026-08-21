# Slice 3: ContextMenuBuilder — Extraktions-Spezifikation

## Ziel
**Neue Datei:** `scripts/objects/planets/context_menu_builder.gd`
**Typ:** `class_name ContextMenuBuilder extends RefCounted`
**Pattern:** Static Helper (wie PlanetView)

## Problem
`planet_network.gd` hat ~160 Zeilen Context-Menu-Logik (Bau, Gating, Disable-Reasons) die kein Planet-Network-Verhalten braucht — nur GameState-Reads und Neighbor-Queries.

## Methoden-Übersicht

| # | Methode | planet_network.gd Zeilen | Zeilen | Zweck |
|---|---------|--------------------------|--------|-------|
| 1 | `build_menu(menu, planet, selection_service, game_state, is_neighbor_fn)` | L181–L231 | ~50 | Komplettes Menü aufbauen + Gating |
| 2 | `get_attack_disable_reason(...)` | L295–L308 | 14 | Disable-Text: Angreifen |
| 3 | `get_collect_disable_reason(...)` | L310–L323 | 14 | Disable-Text: Sammeln |
| 4 | `get_colonize_disable_reason(...)` | L325–L338 | 14 | Disable-Text: Kolonisieren |
| | **Gesamt verschoben** | | **~92L** | |

**Nicht verschoben:**
- `_on_planet_context_requested()` (L170–L179) — bleibt in PlanetNetwork (Popup-Auslösung)
- `_on_context_action()` (L257–L282) — bleibt in PlanetNetwork (Action-Dispatch)
- `_show_action_tooltip()` (L284–L289) — bleibt in PlanetNetwork (UI-Zugriff)
- `_on_context_item_focused()` (L249–L255) — bleibt in PlanetNetwork (UI-Zugriff)
- `_create_context_menu()` (L240–L247) — bleibt in PlanetNetwork (Node-Erstellung)

## Vollständige Methoden-Signaturen

```gdscript
class_name ContextMenuBuilder
extends RefCounted

## Baut das Rechtsklick-Kontextmenü für einen Planeten und setzt
## die korrekten Enabled/Disabled-States je nach Spiellogik.

## Speichert Gründe für disabled Aktionen (für Tooltip-Popover).
var disabled_reasons: Dictionary = {}

## Baut das komplette Menü auf.
## is_neighbor_fn: Callable(source: Node2D, target: Node2D) -> bool
static func build_menu(
    menu: PopupMenu,
    planet: Node2D,
    selection_service,  # SelectionService oder null
    game_state,         # GameState-Autoload oder null
    is_neighbor_fn: Callable,
    action_ids: Dictionary  # {OPEN: 0, FOCUS: 1, ATTACK: 3, COLLECT: 4, COLONIZE: 5, CLEAR: 7}
) -> Dictionary:
    # Gibt {disabled_reasons: Dictionary} zurück

static func get_attack_disable_reason(
    player_owns_primary: bool,
    target_faction: StringName,
    primary_planet: Node2D,
    target_planet: Node2D,
    is_neighbor_fn: Callable
) -> String:
    # L295–L308

static func get_collect_disable_reason(
    player_owns_primary: bool,
    target_faction: StringName,
    scanned: bool,
    primary_planet: Node2D,
    target_planet: Node2D,
    is_neighbor_fn: Callable
) -> String:
    # L310–L323

static func get_colonize_disable_reason(
    player_owns_primary: bool,
    target_faction: StringName,
    scanned: bool,
    primary_planet: Node2D,
    target_planet: Node2D,
    is_neighbor_fn: Callable
) -> String:
    # L325–L338
```

## planet_network.gd — Übergangsdelegation

```gdscript
# In planet_network.gd — _build_context_menu_for wird zu:

func _build_context_menu_for(planet: Node2D) -> void:
    if _context_menu == null or not is_instance_valid(_context_menu):
        return
    _context_active_planet = planet
    _context_menu.clear()
    var result: Dictionary = ContextMenuBuilder.build_menu(
        _context_menu,
        planet,
        _selection_service,
        _game_state(),
        _is_neighbor,
        {
            "OPEN": ACTION_OPEN,
            "FOCUS": ACTION_FOCUS,
            "ATTACK": ACTION_ATTACK,
            "COLLECT": ACTION_COLLECT,
            "COLONIZE": ACTION_COLONIZE,
            "CLEAR": ACTION_CLEAR_SELECTION,
        }
    )
    _context_disabled_reasons = result.get("disabled_reasons", {})

# _is_neighbor bleibt als Instance-Methode in PlanetNetwork:
func _is_neighbor(source: Node2D, target: Node2D) -> bool:
    # bestehender Code L340–L345
```

## Caller-Referenzen

### Preflight (bleibt stabil — `network.call("_build_context_menu_for", ...)`)

| Datei | Zeile | Aufruf |
|-------|-------|--------|
| `constraint_selection_and_context.gd` | L78 | `network.call("_build_context_menu_for", stand_ins[0])` |
| `constraint_selection_and_context.gd` | L94 | `network.call("_build_context_menu_for", stand_ins[0])` |
| `constraint_selection_and_context.gd` | L104 | `network.call("_build_context_menu_for", stand_ins[0])` |
| `constraint_pause_and_context.gd` | L71 | `network.call("_build_context_menu_for", source)` |

**Status:** ✅ `_build_context_menu_for` bleibt als öffentliche Methode in PlanetNetwork — Preflight-Code unverändert.

## planet_network.gd — Zeilen die ENTFERNT werden

| Zeilen | Inhalt | Zeilen |
|--------|--------|--------|
| L181–L231 | `_build_context_menu_for()` Body (nur Logik, nicht Signatur) | ~50 |
| L295–L308 | `_attack_disable_reason()` | 14 |
| L310–L323 | `_collect_disable_reason()` | 14 |
| L325–L338 | `_colonize_disable_reason()` | 14 |
| **Gesamt** | | **~92 Zeilen entfernt** |

## planet_network.gd — Zeilen die HINZUGEFÜGT werden

| Inhalt | Zeilen |
|--------|--------|
| `_build_context_menu_for()` Delegation zu `ContextMenuBuilder.build_menu()` | ~20 |
| **Netto-Änderung** | **−72 Zeilen (677 → ~605)** |

## Godot-spezifische Safety-Checks

1. **`PopupMenu` API:** `add_item`, `add_separator`, `set_item_disabled` — statische Aufrufe, kein Node-Lebenszyklus.
2. **`Callable` für `_is_neighbor`:** Wird als Parameter übergeben, kein direkter Netzwerk-Zugriff.
3. **`SelectionService` Referenz:** Wird als Parameter übergeben, kein `@onready`.
4. **`disabled_reasons` Dictionary:** Wird als Rückgabewert übergeben, kein Side-State im Builder.
5. **`class_name` Registrierung:** Headless-Editor-Scan nach Erstellen.
