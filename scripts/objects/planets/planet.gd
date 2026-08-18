@tool
extends Node2D

signal planet_selected(planet: Node2D)
signal workers_spawn_requested(planet: Node2D, amount: int)

enum WorkerState { IDLE, SPAWNING, PAUSED }

@export var planet_id: StringName = &"planet"
@export_enum("variable", "l", "xl") var layout_size: String = "variable"
@export var faction: StringName = &"neutral":
	set(value):
		if is_inside_tree() and faction != value:
			remove_from_group(_faction_group(faction))
		faction = value
		if is_inside_tree():
			add_to_group(_faction_group(faction))

@export var planet_role: StringName = &"planet":
	set(value):
		if is_inside_tree() and planet_role != value:
			remove_from_group(_role_group(planet_role))
		planet_role = value
		if is_inside_tree():
			add_to_group(_role_group(planet_role))
@export var planet_texture: Texture2D:
	set(value):
		planet_texture = value
		_apply_visuals()

@export_range(0.25, 2.5, 0.05) var visual_scale: float = 1.0:
	set(value):
		visual_scale = value
		_apply_visuals()

@onready var _sprite: Sprite2D = $Sprite2D

var worker_state: WorkerState = WorkerState.IDLE
var worker_count := 0
var _spawn_timer: Timer

func _ready() -> void:
	$ClickArea.input_event.connect(_on_click_area_input_event)
	add_to_group("planets")
	_sync_groups()
	_apply_visuals()
	if not Engine.is_editor_hint():
		_start_spawn_timer.call_deferred()

func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		planet_selected.emit(self)

func _start_spawn_timer() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = _spawn_interval()
	_spawn_timer.timeout.connect(_on_spawn_timer)
	add_child(_spawn_timer)
	_spawn_timer.start()

func _on_spawn_timer() -> void:
	worker_state = WorkerState.SPAWNING
	workers_spawn_requested.emit(self, _spawn_count())
	worker_state = WorkerState.IDLE

func _spawn_interval() -> float:
	match layout_size:
		"xl":
			return 5.0
		"l":
			return 7.0
		_:
			return 10.0

func _spawn_count() -> int:
	match layout_size:
		"xl":
			return 3
		"l":
			return 2
		_:
			return 1

func register_worker(_worker: Node2D) -> void:
	worker_count += 1

func unregister_worker(_worker: Node2D) -> void:
	worker_count = maxi(0, worker_count - 1)

func _sync_groups() -> void:
	add_to_group(StringName("planet_" + String(planet_id)))
	add_to_group(_faction_group(faction))
	add_to_group(_role_group(planet_role))

func _apply_visuals() -> void:
	if not is_instance_valid(_sprite):
		return
	_sprite.texture = planet_texture
	_sprite.scale = Vector2.ONE * visual_scale

func _faction_group(value: StringName) -> StringName:
	return StringName("faction_" + String(value))

func _role_group(value: StringName) -> StringName:
	return StringName("planet_role_" + String(value))

func set_faction(value: StringName) -> void:
	faction = value

func set_planet_role(value: StringName) -> void:
	planet_role = value

func set_group_enabled(enabled: bool) -> void:
	visible = enabled
	process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
