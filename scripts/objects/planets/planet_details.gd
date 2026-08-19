@tool
class_name PlanetDetails
extends Node2D

const MAX_DETAILS := 3
const DETAIL_TYPES: Array[StringName] = [&"satellite", &"asteroid_belt", &"ring"]
const SATELLITE_TEXTURE: Texture2D = preload("res://assets/objects/planets/planet_satellite.svg")
const ASTEROID_TEXTURES: Array[Texture2D] = [
	preload("res://assets/objects/meteors/meteor_01_rock.svg"),
	preload("res://assets/objects/meteors/meteor_03_metal.svg"),
	preload("res://assets/objects/meteors/meteor_05_toxic.svg")
]

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
	_selected_details = _select_details(planet, rng)
	for detail_type in _selected_details:
		match detail_type:
			&"satellite":
				_add_satellite(rng)
			&"asteroid_belt":
				_add_asteroid_belt(rng)
			&"ring":
				_add_ring(planet)

func get_detail_types() -> Array[StringName]:
	return _selected_details.duplicate()

func _select_details(planet: Planet, rng: RandomNumberGenerator) -> Array[StringName]:
	if planet.planet_id == &"toxic":
		var toxic_details: Array[StringName] = [&"satellite", &"asteroid_belt"]
		if rng.randi_range(0, 1) == 1:
			toxic_details.append(&"ring")
		return toxic_details

	var candidates: Array[StringName] = DETAIL_TYPES.duplicate()
	_shuffle(candidates, rng)
	var detail_count := rng.randi_range(0, MAX_DETAILS)
	return candidates.slice(0, detail_count)

func _add_satellite(rng: RandomNumberGenerator) -> void:
	var orbit := PlanetDetailOrbit.new()
	orbit.name = "Satellite"
	orbit.configure(122.0 + rng.randf_range(-8.0, 8.0), 0.18, rng.randf_range(0.0, TAU))
	orbit.set_sprite(SATELLITE_TEXTURE, 13.0)
	add_child(orbit)

func _add_asteroid_belt(rng: RandomNumberGenerator) -> void:
	for index in 5:
		var orbit := PlanetDetailOrbit.new()
		orbit.name = "AsteroidOrbit_%d" % index
		orbit.configure(
			105.0 + rng.randf_range(-12.0, 12.0),
			rng.randf_range(-0.38, 0.38),
			rng.randf_range(0.0, TAU)
		)
		var texture: Texture2D = ASTEROID_TEXTURES[rng.randi_range(0, ASTEROID_TEXTURES.size() - 1)]
		orbit.set_sprite(texture, rng.randf_range(4.0, 7.0))
		add_child(orbit)

func _add_ring(planet: Planet) -> void:
	var ring := PlanetDetailRing.new()
	ring.name = "OrbitalRing"
	ring.z_index = -1
	var color := Color(0.92, 0.34, 0.38, 0.72) if planet.planet_id == &"toxic" else Color(0.48, 0.82, 1.0, 0.58)
	ring.configure(104.0, color)
	add_child(ring)

func _shuffle(values: Array[StringName], rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var value: StringName = values[index]
		values[index] = values[swap_index]
		values[swap_index] = value
