@tool
class_name SceneDirector
extends CanvasLayer

## Scene-flow orchestrator (autoload: SceneDirectorService).
##
## Owns the scene registry (menu / world / battle / conquest) and performs
## scene switches through the documented custom-switcher pattern (deferred
## free + add_child + set current_scene) instead of change_scene_to_packed,
## so lifecycle stays deterministic and headless-testable.
##
## Contract: GameCycleManager decides WHEN to switch (game-flow rules);
## SceneDirector executes the switch and the fade transition. Context is
## handed over through GameState (pending battle context / world reconnect),
## never through global variables.

signal scene_requested(scene_id: StringName, context: Resource)
signal transition_started()
signal transition_midpoint()
signal transition_completed()

const SCENE_MENU: PackedScene = preload("res://scenes/main_menu/main_menu.tscn")
const SCENE_WORLD: PackedScene = preload("res://scenes/world/world.tscn")
const SCENE_BATTLE: PackedScene = preload("res://scenes/battle/battle_scene.tscn")
const SCENE_CONQUEST: PackedScene = preload("res://scenes/conquest/conquest_scene.tscn")

const SCENE_ID_MENU: StringName = &"menu"
const SCENE_ID_WORLD: StringName = &"world"
const SCENE_ID_BATTLE: StringName = &"battle"
const SCENE_ID_CONQUEST: StringName = &"conquest"

var _fade_rect: ColorRect
var _is_transitioning: bool = false

func _ready() -> void:
	layer = 95
	_build_ui()

func _build_ui() -> void:
	if _fade_rect != null:
		return
	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeOverlay"
	_fade_rect.color = Color(0.02, 0.02, 0.04, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade_rect)

## Resolves a registered scene id to its PackedScene, or null.
func scene_for_id(scene_id: StringName) -> PackedScene:
	match scene_id:
		SCENE_ID_MENU:
			return SCENE_MENU
		SCENE_ID_WORLD:
			return SCENE_WORLD
		SCENE_ID_BATTLE:
			return SCENE_BATTLE
		SCENE_ID_CONQUEST:
			return SCENE_CONQUEST
	return null

func registered_scene_ids() -> Array[StringName]:
	return [SCENE_ID_MENU, SCENE_ID_WORLD, SCENE_ID_BATTLE, SCENE_ID_CONQUEST]

## Requests a scene switch with a fade. The actual switch happens at the
## transition midpoint via the deferred custom-switcher. Context handover:
## - world: GameState.request_world_reconnect() (rebuild from session seed)
## - battle/conquest: GameState.set_pending_battle_context(context)
func goto_scene(scene_id: StringName, context: Resource = null) -> bool:
	if _is_transitioning:
		return false
	var scene: PackedScene = scene_for_id(scene_id)
	if scene == null:
		return false
	scene_requested.emit(scene_id, context)
	var state: Node = get_node_or_null("/root/GameState")
	if scene_id == SCENE_ID_WORLD:
		if state != null and state.has_method("request_world_reconnect"):
			state.request_world_reconnect()
	elif (scene_id == SCENE_ID_BATTLE or scene_id == SCENE_ID_CONQUEST) and context != null:
		if state != null and state.has_method("set_pending_battle_context"):
			state.set_pending_battle_context(context)
	transition(0.6, func(): _switch_scene(scene))
	return true

func transition(duration: float = 0.4, on_midpoint: Callable = Callable()) -> void:
	if _is_transitioning:
		return
	if _fade_rect == null:
		_build_ui()
	_is_transitioning = true
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	transition_started.emit()

	var half := duration * 0.5
	var tw: Tween = create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		transition_midpoint.emit()
		if on_midpoint.is_valid():
			on_midpoint.call()
	)
	tw.tween_property(_fade_rect, "color:a", 0.0, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_is_transitioning = false
		transition_completed.emit()
	)

func _switch_scene(scene: PackedScene) -> void:
	call_deferred("_deferred_switch_scene", scene)

func _deferred_switch_scene(scene: PackedScene) -> void:
	if scene == null:
		return
	var current: Node = get_tree().current_scene
	if current != null and is_instance_valid(current):
		current.free()
	var instance: Node = scene.instantiate()
	get_tree().root.add_child(instance)
	get_tree().current_scene = instance

## Compatibility wrapper: player-involved battles switch to the battle scene.
func transition_to_layer2(context: BattleContext) -> void:
	if context == null or context.replay == null or _is_transitioning:
		return
	goto_scene(SCENE_ID_BATTLE, context)

## Compatibility wrapper: return to the strategy overworld.
func transition_to_layer1() -> void:
	goto_scene(SCENE_ID_WORLD)

func is_transitioning() -> bool:
	return _is_transitioning
