@tool
extends Node2D

@export var planet_id: StringName = &"planet"
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

func _ready() -> void:
	add_to_group("planets")
	_sync_groups()
	_apply_visuals()

func _sync_groups() -> void:
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
