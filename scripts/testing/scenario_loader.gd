class_name ScenarioLoader
extends RefCounted

## READ-Only scenario loader. Loads ScenarioSnapshot resources and applies
## them to GameState. The snapshot resource itself is NEVER mutated.
##
## Usage:
##   var result := ScenarioLoader.load_scenario("res://resources/scenarios/mid_basic.tres")
##   if result.ok:
##       # GameState is now set to the mid-game state
##       run_my_feature_test()
##   else:
##       push_error(result.error)

## --- Load Result ---

class LoadResult extends RefCounted:
	var ok: bool = false
	var error: String = ""
	var snapshot: ScenarioSnapshot = null

	func _init(p_ok: bool = false, p_error: String = "", p_snapshot: ScenarioSnapshot = null) -> void:
		ok = p_ok
		error = p_error
		snapshot = p_snapshot

## --- Static API ---

## Loads a scenario from a resource path and applies it to GameState.
## READ-ONLY: the snapshot resource is never modified.
static func load_scenario(resource_path: String) -> LoadResult:
	var snapshot: ScenarioSnapshot = load(resource_path) as ScenarioSnapshot
	if snapshot == null:
		return LoadResult.new(false, "Cannot load scenario from: " + resource_path)
	return apply_snapshot(snapshot)

## Applies a pre-loaded ScenarioSnapshot to GameState.
## READ-ONLY: the snapshot resource is never modified.
static func apply_snapshot(snapshot: ScenarioSnapshot) -> LoadResult:
	if snapshot == null:
		return LoadResult.new(false, "Snapshot is null")
	if not snapshot.is_valid():
		var errors := snapshot.validate()
		return LoadResult.new(false, "Invalid snapshot: " + "; ".join(errors))

	# 1. Get GameState autoload
	var gs := _get_game_state()
	if gs == null:
		return LoadResult.new(false, "GameState autoload not found")

	# 2. Apply seed override if set
	if snapshot.layout_seed_override >= 0:
		if gs.has_method("set_layout_seed"):
			gs.set_layout_seed(snapshot.layout_seed_override)

	# 3. Restore the snapshot (READ-ONLY: snapshot.save_data is passed by value)
	if snapshot.save_data != null and gs.has_method("restore_run"):
		gs.restore_run(snapshot.save_data)

	return LoadResult.new(true, "", snapshot)

## Lists all available scenario files in the scenarios directory.
static func list_available() -> Array[String]:
	var scenarios: Array[String] = []
	var dir := DirAccess.open("res://resources/scenarios/")
	if dir == null:
		return scenarios
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			scenarios.append("res://resources/scenarios/" + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	return scenarios

## Discovers which mechanics a scenario covers by checking its metadata.
static func mechanic_coverage(snapshot: ScenarioSnapshot) -> Dictionary:
	var registry := MechanicRegistry.new()
	var all_mechanics := registry.get_all()
	var covered: Array[StringName] = []
	var uncovered: Array[StringName] = []
	for mechanic in all_mechanics:
		if snapshot.has_mechanic(mechanic.id):
			covered.append(mechanic.id)
		else:
			uncovered.append(mechanic.id)
	return {
		"covered": covered,
		"uncovered": uncovered,
		"coverage_ratio": float(covered.size()) / float(maxi(1, all_mechanics.size())),
	}

## --- Internal ---

static func _get_game_state() -> Node:
	# Try common autoload paths
	var root: Node = Engine.get_main_loop().root if Engine.get_main_loop() != null else null
	if root == null:
		return null
	return root.get_node_or_null("GameState")
