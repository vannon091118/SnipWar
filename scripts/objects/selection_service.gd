## SelectionService — multi-planet selection state living outside GameState.
##
## Centralizes the "what is currently picked" model so the UI panel, the
## context menu and the aggregated overview can all read from one source. The
## service mirrors Godot's file-explorer convention: a single primary planet
## (focus / "active planet" surrogate) plus a set of additional planets that
## are highlighted but stay secondary.
##
## Modifiers:
##   * shift_pressed / ctrl_pressed / long_press → toggle membership in the
##     active group without changing the primary.
##   * default → clear the secondary group and set primary = planet.
##   * meta_pressed (Cmd) → additive group toggle on macOS, alias for ctrl.
##
## The service intentionally does NOT mutate GameState; ownership/faction/
## vault state remains the SSOT in GameState. This split keeps ownership
## (deterministic, persistent) separate from interaction state (transient,
## per-session).
class_name SelectionService
extends Node

## Emitted whenever the active group changes. The argument is a copy of the
## current selection (primary first) so listeners never have to defensively
## clone.
signal selection_changed(planets: Array[Node2D])

## Emitted when the primary planet changes (including to null on clear).
signal primary_changed(planet: Node2D)

## Emitted after any toggle that changed the multi-selection count. UI uses
## this to refresh the aggregated overview cheaply without diffing planets.
signal selection_count_changed(count: int)

var _primary: Node2D = null
var _secondary: Array[Node2D] = []


func _ready() -> void:
	add_to_group("selection_service")


## Entry point for click/tap events coming from a Planet node.
## `modifiers` may carry: shift_pressed, ctrl_pressed, meta_pressed, long_press.
func handle_request(planet: Node2D, modifiers: Dictionary = {}) -> void:
	if planet == null or not is_instance_valid(planet):
		return
	if modifiers.get("long_press", false) or modifiers.get("shift_pressed", false) or modifiers.get("ctrl_pressed", false) or modifiers.get("meta_pressed", false):
		_toggle_membership(planet)
		return
	# Plain click → primary becomes the new focus; secondary is reset.
	_set_primary(planet)
	_clear_secondary()


func get_primary() -> Node2D:
	if _primary != null and is_instance_valid(_primary):
		return _primary
	return null


func get_selection() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var primary: Node2D = get_primary()
	if primary != null:
		result.append(primary)
	for planet in _secondary:
		if planet != null and is_instance_valid(planet):
			result.append(planet)
	return result


func get_secondary() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for planet in _secondary:
		if planet != null and is_instance_valid(planet):
			result.append(planet)
	return result


func get_selection_count() -> int:
	return get_selection().size()


func is_selected(planet: Node2D) -> bool:
	if planet == null:
		return false
	if planet == get_primary():
		return true
	return _secondary.has(planet)


func clear() -> void:
	var primary_before: Node2D = get_primary()
	var secondary_before: Array[Node2D] = get_secondary()
	if primary_before != null and primary_before.has_method("set_selected"):
		primary_before.set_selected(false)
	for planet in secondary_before:
		if planet != null and is_instance_valid(planet) and planet.has_method("set_selected"):
			planet.set_selected(false)
	_primary = null
	_secondary.clear()
	if primary_before != null:
		primary_changed.emit(null)
	selection_changed.emit(([] as Array[Node2D]))
	selection_count_changed.emit(0)


func _set_primary(planet: Node2D) -> void:
	if planet == _primary:
		return
	var previous: Node2D = get_primary()
	if previous != null and previous.has_method("set_selected"):
		previous.set_selected(false)
	_primary = planet
	if _primary != null and _primary.has_method("set_selected"):
		_primary.set_selected(true)
	primary_changed.emit(_primary)


## A modifier-click on the primary removes it (promoting the first secondary so
## the group still has a stable focus); modifier-clicks on secondaries toggle
## membership; modifier-clicks with no current primary set a new focus.
func _toggle_membership(planet: Node2D) -> void:
	var primary: Node2D = get_primary()
	if planet == primary:
		if _secondary.is_empty():
			clear()
			return
		_promote_first_secondary_to_primary()
	elif _secondary.has(planet):
		_secondary.erase(planet)
		if planet.has_method("set_selected"):
			planet.set_selected(false)
	elif primary == null:
		_set_primary(planet)
	else:
		_secondary.append(planet)
		if planet.has_method("set_selected"):
			planet.set_selected(true)
	selection_changed.emit(get_selection())
	selection_count_changed.emit(get_selection_count())


func _promote_first_secondary_to_primary() -> void:
	var replacement: Node2D = _secondary[0]
	var previous: Node2D = get_primary()
	if previous != null and previous.has_method("set_selected"):
		previous.set_selected(false)
	_primary = replacement
	_secondary = _secondary.slice(1)
	if _primary.has_method("set_selected"):
		_primary.set_selected(true)
	primary_changed.emit(_primary)


func _clear_secondary() -> void:
	for planet in _secondary:
		if planet != null and is_instance_valid(planet) and planet.has_method("set_selected"):
			planet.set_selected(false)
	_secondary.clear()
	selection_changed.emit(get_selection())
	selection_count_changed.emit(get_selection_count())
