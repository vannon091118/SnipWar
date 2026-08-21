class_name PreflightContext
extends RefCounted

## Shared state captured during scene boot and reused by every constraint
## module. Provides rich assertion helpers, failure diagnostics, performance
## profiling, and execution-mode flags (verbose, fail_fast).

var tree: SceneTree
var fixture: PreflightFixture

# Node/Resource references (filled by the isolated preflight fixture).
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

# Execution control & Debug Helper state
var active_constraint := ""
var verbose: bool = false
var fail_fast: bool = false
var checks_run: int = 0
var checks_passed: int = 0
var failure_count: int = 0
var failures: Array[Dictionary] = []
var constraint_timings: Dictionary = {}
var start_timestamp_msec: int = 0


func _init(p_tree: SceneTree) -> void:
	tree = p_tree
	fixture = PreflightFixture.new(p_tree)
	start_timestamp_msec = Time.get_ticks_msec()


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


# --- Core Assertion & Check Engine (Debug Helper) ---

func check(condition: bool, message: String, details: Dictionary = {}) -> bool:
	checks_run += 1
	if condition:
		checks_passed += 1
		if verbose:
			print("    [PASS] " + message)
		return true

	failure_count += 1
	var failure_entry: Dictionary = {
		"constraint": active_constraint,
		"message": message,
		"details": details,
		"time_msec": Time.get_ticks_msec() - start_timestamp_msec,
	}
	failures.append(failure_entry)

	var prefix := ""
	if not active_constraint.is_empty():
		prefix = "[" + active_constraint + "] "
	push_error("FAIL " + prefix + message)
	print("    [FAIL] " + prefix + message)

	if not details.is_empty():
		for key in details:
			print("           * %s: %s" % [key, str(details[key])])

	if fail_fast:
		print("\n[preflight] Aborting immediately due to --fail-fast flag.")
		tree.quit(1)

	return false


func assert_true(condition: bool, message: String) -> bool:
	return check(condition, message, {"expected": true, "actual": condition} if not condition else {})


func assert_false(condition: bool, message: String) -> bool:
	return check(not condition, message, {"expected": false, "actual": condition} if condition else {})


func assert_eq(actual: Variant, expected: Variant, message: String) -> bool:
	var ok: bool = (actual == expected)
	return check(ok, message, {"expected": expected, "actual": actual} if not ok else {})


func assert_ne(actual: Variant, unexpected: Variant, message: String) -> bool:
	var ok: bool = (actual != unexpected)
	return check(ok, message, {"unexpected": unexpected, "actual": actual} if not ok else {})


func assert_approx(actual: float, expected: float, tolerance: float = 0.001, message: String = "") -> bool:
	var diff: float = absf(actual - expected)
	var ok: bool = is_equal_approx(actual, expected) or diff <= tolerance
	return check(ok, message if not message.is_empty() else "Values should be approximately equal", {"expected": expected, "actual": actual, "tolerance": tolerance, "diff": diff} if not ok else {})


func assert_null(val: Variant, message: String) -> bool:
	var ok: bool = (val == null)
	return check(ok, message, {"expected": null, "actual": val} if not ok else {})


func assert_not_null(val: Variant, message: String) -> bool:
	var ok: bool = (val != null)
	return check(ok, message, {"expected": "not null", "actual": val} if not ok else {})


func assert_gt(actual: Variant, min_val: Variant, message: String) -> bool:
	var ok: bool = (actual > min_val)
	return check(ok, message, {"actual": actual, "must_be_greater_than": min_val} if not ok else {})


func assert_ge(actual: Variant, min_val: Variant, message: String) -> bool:
	var ok: bool = (actual >= min_val)
	return check(ok, message, {"actual": actual, "must_be_at_least": min_val} if not ok else {})


func assert_lt(actual: Variant, max_val: Variant, message: String) -> bool:
	var ok: bool = (actual < max_val)
	return check(ok, message, {"actual": actual, "must_be_less_than": max_val} if not ok else {})


func assert_le(actual: Variant, max_val: Variant, message: String) -> bool:
	var ok: bool = (actual <= max_val)
	return check(ok, message, {"actual": actual, "must_be_at_most": max_val} if not ok else {})


func assert_contains(collection: Variant, item: Variant, message: String) -> bool:
	var has_item: bool = false
	if collection is Array or collection is PackedStringArray or collection is PackedInt32Array:
		has_item = (collection as Array).has(item)
	elif collection is Dictionary:
		has_item = (collection as Dictionary).has(item)
	elif collection is String:
		has_item = (collection as String).contains(str(item))
	return check(has_item, message, {"collection": collection, "missing_item": item} if not has_item else {})


# --- Logging & Debugging Utilities ---

func log_info(message: String) -> void:
	print("  [INFO] " + message)


func log_verbose(message: String) -> void:
	if verbose:
		print("  [DEBUG] " + message)


func dump_debug_state() -> Dictionary:
	var state_dump: Dictionary = {
		"active_constraint": active_constraint,
		"uptime_msec": Time.get_ticks_msec() - start_timestamp_msec,
		"failure_count": failure_count,
		"checks_run": checks_run,
	}
	if game_state != null and is_instance_valid(game_state):
		state_dump["game_state_known_planets"] = game_state.get("_known_planets")
		state_dump["game_state_vaults"] = game_state.get("_faction_vaults")
	if field != null and is_instance_valid(field):
		state_dump["planet_count"] = planet_positions(field).size()
	if fixture != null:
		state_dump["fixture_boot_count"] = fixture.boot_count
	return state_dump


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
	var config: WorldConfig = world_config if world_config != null else preload("res://resources/config/world_default.tres")
	return WorldGenerator.generate_catalog(config, original_seed, planet_count)


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
