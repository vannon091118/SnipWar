class_name PreflightContext
extends RefCounted

## Shared state captured once during scene boot and reused by every constraint
## module. Constraint modules receive this instance and read/write through it, so
## the per-domain files stay self-contained and failures carry the constraint name.

var tree: SceneTree

# Node/Resource references (filled by the scene-boot constraint).
var background: Node
var field: Node
var network: Node
var manager: Node
var game_state: Node
var world_config: WorldConfig
var planet_catalog: PlanetCatalog
var scenario_catalog: ScenarioCatalog
var upgrade_catalog: PlanetUpgradeCatalog
var original_seed := 0

# Observation state used by the signal-capture helpers.
var observed_planet: Node2D
var observed_state := -1
var observed_amount := -1
var observed_faction_planet: StringName = &""
var observed_old_faction: StringName = &""
var observed_new_faction: StringName = &""

# Name of the constraint currently running, set by the orchestrator so failure
# messages report their location.
var active_constraint := ""

var failure_count := 0


func _init(p_tree: SceneTree) -> void:
	tree = p_tree


# --- SceneTree facades (constraint modules extend RefCounted, not SceneTree) ---

func root() -> Node:
	return tree.root


func get_root() -> Node:
	return tree.root


func await_frame() -> void:
	await tree.process_frame


func wait(seconds: float) -> void:
	await tree.create_timer(seconds).timeout


func nodes_in_group(group: StringName) -> Array[Node]:
	return tree.get_nodes_in_group(group)


func first_node_in_group(group: StringName) -> Node:
	return tree.get_first_node_in_group(group)


# --- Failure reporting ---

func check(condition: bool, message: String) -> bool:
	if condition:
		return true
	failure_count += 1
	var prefix := ""
	if not active_constraint.is_empty():
		prefix = "[" + active_constraint + "] "
	push_error("FAIL " + prefix + message)
	tree.quit(1)
	return false


# --- Signal-capture helpers ---

func capture_spawn(planet: Node2D, amount: int) -> void:
	if planet == observed_planet:
		observed_state = int(planet.worker_state)
		observed_amount = amount


func capture_faction_changed(planet_id: StringName, old_faction: StringName, new_faction: StringName) -> void:
	observed_faction_planet = planet_id
	observed_old_faction = old_faction
	observed_new_faction = new_faction


# --- World/catalog helpers ---

func catalog_for_count(base_catalog: PlanetCatalog, planet_count: int) -> PlanetCatalog:
	return WorldGenerator.expand_catalog(base_catalog, planet_count)


# --- Planet/introspection helpers ---

func planet_positions(field: Node) -> Dictionary:
	var positions: Dictionary = {}
	for child in field.get_children():
		if child is Planet:
			positions[child] = (child as Planet).position
	return positions


func find_planet_with_size(field: Node, size_class: StringName) -> Node:
	for child in field.get_children():
		if child.get("layout_size") != null and StringName(child.get("layout_size")) == size_class:
			return child
	return null


func count_planets_with_size(field: Node, size_class: StringName) -> int:
	var count := 0
	for child in field.get_children():
		if child.get("layout_size") != null and StringName(child.get("layout_size")) == size_class:
			count += 1
	return count


func find_planet_by_id(field: Node, planet_id: StringName) -> Planet:
	for child in field.get_children():
		if child is Planet and (child as Planet).planet_id == planet_id:
			return child as Planet
	return null


func find_timer(planet: Node) -> Timer:
	for child in planet.get_children():
		if child is Timer:
			return child
	return null


# --- Geometry helpers ---

func path_distance(path: Array[Vector2]) -> float:
	return PathUtils.distance(path)


func path_contains_planet(path: Array[Vector2], field: Node, source: Planet, destination: Node2D) -> bool:
	for point_index in range(1, path.size() - 1):
		for child in field.get_children():
			if child is Planet and child != source and child != destination and (child as Planet).global_position.distance_to(path[point_index]) <= 0.05:
				return true
	return false


func offsets_match_shape(actual: Array[Vector2], expected: Array[Vector2], tolerance: float) -> bool:
	if actual.size() != expected.size() or actual.is_empty():
		return false
	var actual_center := Vector2.ZERO
	var expected_center := Vector2.ZERO
	for offset in actual:
		actual_center += offset
	for offset in expected:
		expected_center += offset
	actual_center /= float(actual.size())
	expected_center /= float(expected.size())
	for index in actual.size():
		if (actual[index] - actual_center).distance_to(expected[index] - expected_center) > tolerance:
			return false
	return true


func offsets_have_safe_spacing(offsets: Array[Vector2], minimum: float) -> bool:
	for first_index in offsets.size():
		for second_index in range(first_index + 1, offsets.size()):
			if offsets[first_index].distance_to(offsets[second_index]) < minimum:
				return false
	return true


# --- Formatting helpers ---

func flight_seconds(text: String) -> float:
	return float(text.trim_prefix("Flugzeit: ").trim_suffix(" s"))
