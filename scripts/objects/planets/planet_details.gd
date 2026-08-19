@tool
class_name PlanetDetails
extends Node2D

const DEFAULT_PROFILE: PlanetDetailProfile = preload("res://resources/config/planet_details/default.tres")

@export var detail_seed := 0:
	set(value):
		detail_seed = value
		_seed_ready = true
		if is_inside_tree():
			regenerate()

var _seed_ready := false
var _selected_details: Array[StringName] = []

func _ready() -> void:
	if _seed_ready:
		regenerate()

func set_seed(value: int) -> void:
	detail_seed = value

func regenerate() -> void:
	var planet := get_parent() as Planet
	if planet == null:
		return
	for child in get_children():
		child.free()

	var rng := RandomNumberGenerator.new()
	rng.seed = detail_seed
	var profile: PlanetDetailProfile = planet.detail_profile if planet.detail_profile != null else DEFAULT_PROFILE
	_selected_details = _select_details(profile, rng)
	for detail_id in _selected_details:
		var definition := profile.definition_for(detail_id)
		if definition != null:
			_add_definition(definition, rng)

func get_detail_types() -> Array[StringName]:
	return _selected_details.duplicate()

func _select_details(profile: PlanetDetailProfile, rng: RandomNumberGenerator) -> Array[StringName]:
	if profile == null or profile.max_details <= 0:
		return []
	var selected: Array[StringName] = []
	for detail_id in profile.guaranteed_detail_ids:
		if selected.size() >= profile.max_details:
			break
		if not selected.has(detail_id) and profile.definition_for(detail_id) != null:
			selected.append(detail_id)

	var optional: Array[StringName] = profile.optional_detail_ids.duplicate()
	_shuffle(optional, rng)
	var available_slots := profile.max_details - selected.size()
	var optional_max := mini(profile.optional_count_range.y, available_slots)
	var optional_min := mini(profile.optional_count_range.x, optional_max)
	var optional_count := rng.randi_range(optional_min, optional_max) if optional_max > 0 else 0
	for index in optional_count:
		var detail_id: StringName = optional[index]
		if not selected.has(detail_id) and profile.definition_for(detail_id) != null:
			selected.append(detail_id)
	return selected

func _add_definition(definition: PlanetDetailDefinition, rng: RandomNumberGenerator) -> void:
	for index in definition.instance_count:
		if definition.textures.is_empty():
			return
		var texture: Texture2D = definition.textures[rng.randi_range(0, definition.textures.size() - 1)]
		if texture == null:
			continue
		var orbit := PlanetDetailOrbit.new()
		orbit.name = definition.node_name_prefix + ("_%d" % index if definition.instance_count > 1 else "")
		orbit.configure(
			rng.randf_range(definition.orbit_radius_range.x, definition.orbit_radius_range.y),
			rng.randf_range(definition.angular_speed_range.x, definition.angular_speed_range.y),
			rng.randf_range(definition.phase_range.x, definition.phase_range.y)
		)
		orbit.set_sprite(texture, rng.randf_range(definition.sprite_size_range.x, definition.sprite_size_range.y))
		add_child(orbit)

func _shuffle(values: Array[StringName], rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var value: StringName = values[index]
		values[index] = values[swap_index]
		values[swap_index] = value
