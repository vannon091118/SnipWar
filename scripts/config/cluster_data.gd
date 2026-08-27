class_name ClusterData
extends RefCounted

## Lightweight data for a generated cluster (not a Node).
## Each cluster contains planets and a central sun.

var cluster_id: StringName
var center_position: Vector2
var sun: RefCounted  # SunData inner instance
var planet_count: int
var planet_slots: Array = []  # Array[Vector2] — local positions within cluster
var resource_bias: StringName = &"neutral"  # cpu, neural, uninhabited, neutral, player
var radius: float
var density_multiplier: float = 1.0

func _init() -> void:
	sun = SunData.new()

func get_world_planet_positions() -> Array:
	var result: Array = []
	for local_pos in planet_slots:
		result.append(center_position + local_pos)
	return result

func contains_point(point: Vector2) -> bool:
	return center_position.distance_to(point) <= radius

func is_void() -> bool:
	return planet_count == 0

func get_cluster_type() -> StringName:
	return resource_bias


class SunData:
	extends RefCounted

	## Visual and physical properties of a cluster's central sun.
	## Mass determines gravity influence, glow determines visual radius.

	var position: Vector2
	var mass: float = 1.0
	var glow_radius: float = 50.0
	var color: Color = Color(1.0, 0.9, 0.7)  # Warm yellow-white
	var cluster_id: StringName
	var temperature: float = 5778.0  # Kelvin (solar-like)

	func get_scale() -> float:
		return sqrt(mass)

	func get_gravity_influence() -> float:
		return glow_radius * 2.0

	func get_visual_color() -> Color:
		if temperature < 3500.0:
			return Color(1.0, 0.6, 0.4)  # Red dwarf
		elif temperature < 5000.0:
			return Color(1.0, 0.8, 0.6)  # Orange
		elif temperature < 6000.0:
			return Color(1.0, 0.95, 0.8)  # Yellow-white
		elif temperature < 10000.0:
			return Color(0.8, 0.9, 1.0)  # Blue-white
		else:
			return Color(0.6, 0.7, 1.0)  # Blue giant


class ResourceDistribution:
	extends RefCounted

	## Resource distribution for a cluster
	var cpu_planets: int = 0
	var neural_planets: int = 0
	var uninhabited_planets: int = 0
	var player_planets: int = 0
	var neutral_planets: int = 0

	func total() -> int:
		return cpu_planets + neural_planets + uninhabited_planets + player_planets + neutral_planets

	func get_bias() -> StringName:
		if cpu_planets > 0:
			return &"cpu"
		elif neural_planets > 0:
			return &"neural"
		elif uninhabited_planets > 0:
			return &"uninhabited"
		return &"neutral"

	func distribute(total_planets: int, ratios: Dictionary, cluster_seed: int = 0) -> void:
		## Distribute planets across resource types based on ratio dictionary.
		## cluster_seed ensures different clusters with the same planet count
		## still get different resource distributions.
		var rng := RandomNumberGenerator.new()
		rng.seed = cluster_seed ^ hash(total_planets)

		if total_planets > 0:
			player_planets = 1
			total_planets -= 1

		for _i in total_planets:
			var roll := rng.randf()
			var cpu_r: float = ratios.get("cpu", 0.3)
			var neural_r: float = ratios.get("neural", 0.1)
			var uninhabited_r: float = ratios.get("uninhabited", 0.2)
			if roll < cpu_r:
				cpu_planets += 1
			elif roll < cpu_r + neural_r:
				neural_planets += 1
			elif roll < cpu_r + neural_r + uninhabited_r:
				uninhabited_planets += 1
			else:
				neutral_planets += 1
