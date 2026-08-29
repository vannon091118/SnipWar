extends SceneTree

## Phase 0/1: deterministic infinite-world identity and historical start roster.
## This test uses the existing WorldGenerator/StartRosterGenerator APIs and
## verifies the data contract without selecting a homeworld or mutating gameplay.

const DEFAULT_WORLD_CONFIG: WorldConfig = preload("res://resources/config/world_default.tres")
const DEFAULT_PLANET_CATALOG: PlanetCatalog = preload("res://resources/config/planet_catalog.tres")

var _failures: int = 0
var _checks: int = 0
var _ran := false
var _frame := 0

func _process(_delta: float) -> bool:
	if _ran:
		return false
	_frame += 1
	if _frame < 3:
		return false
	_ran = true
	_run()
	return false

func _check(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("[PASS] " + label)
	else:
		_failures += 1
		print("[FAIL] " + label)

func _run() -> void:
	var config: WorldConfig = DEFAULT_WORLD_CONFIG.duplicate(true) as WorldConfig
	var catalog: PlanetCatalog = WorldGenerator.generate_catalog(config, 424242, 1)
	var seed_a := 424242
	var seed_b := 424243

	var first: Array[Dictionary] = StartRosterGenerator.generate(seed_a, 10, config, catalog)
	var second: Array[Dictionary] = StartRosterGenerator.generate(seed_a, 10, config, catalog)
	_check("default roster has ten candidates", first.size() == 10)
	_check("same seed produces identical roster", _canonical(first) == _canonical(second))
	_check("candidate IDs are unique", _unique_ids(first))
	_check("candidate cells are unique", _unique_cells(first))
	_check("same candidate has stable static identity", _same_candidate(first, second, 0))

	var other_seed: Array[Dictionary] = StartRosterGenerator.generate(seed_b, 10, config, catalog)
	_check("different seeds are not a fixed identical roster", _canonical(first) != _canonical(other_seed))

	# The source generator itself is pure by chunk coordinate and slot. Replaying
	# the slots in three traversal orders must yield the same per-slot records.
	var order_a := _chunk_records(seed_a, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)])
	var order_b := _chunk_records(seed_a, [Vector2i(0, 1), Vector2i(0, 0), Vector2i(1, 0)])
	var order_c := _chunk_records(seed_a, [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 0)])
	_check("chunk traversal order does not change static records", order_a == order_b and order_b == order_c)

	# Re-entry is a fresh pure generation, not mutable-state restoration.
	var reentry_first := _chunk_records(seed_a, [Vector2i.ZERO])
	var reentry_second := _chunk_records(seed_a, [Vector2i.ZERO])
	_check("chunk re-entry preserves static records", reentry_first == reentry_second)

	# Historical input: roster IDs are explicitly carried in the prepared run
	# and must not silently become the alpha/beta/gamma fallback set.
	var state: Node = root.get_node_or_null("GameState")
	if state != null:
		var run_catalog := PlanetCatalog.new()
		state.prepare_start_roster(first)
		state.begin_new_game(run_catalog, &"phase01_test", seed_a, true)
		var received: Array[Dictionary] = state.start_roster_snapshot()
		_check("GameState retains roster after infinite reset", _canonical(received) == _canonical(first))
		_check("roster is separate from ownership", state.faction_planet_snapshot().is_empty())
		var chronicle: Node = root.get_node_or_null("WorldChronicle")
		if chronicle != null:
			var save: ChronicleSaveData = chronicle.get_save() as ChronicleSaveData
			var historical_ids: Dictionary = {}
			if save != null:
				for snapshot in save.historical_snapshots:
					for planet_id in snapshot.get("ownership", {}):
						historical_ids[String(planet_id)] = true
			_check("chronicle receives roster planet IDs", _contains_roster_id(historical_ids, first))
			_check("chronicle does not use synthetic fallback with roster", not historical_ids.has("planet_alpha") and not historical_ids.has("planet_beta") and not historical_ids.has("planet_gamma"))

	_print_result()

func _chunk_records(layout_seed: int, order: Array[Vector2i]) -> Dictionary:
	var result := {}
	var chunk_size: int = DEFAULT_WORLD_CONFIG.chunk_size
	for coord in order:
		var chunk_seed_value := WorldGenerator.chunk_seed(layout_seed, coord.x, coord.y)
		var definitions := WorldGenerator.generate_chunk_planets(WorldGenerator.generate_catalog(DEFAULT_WORLD_CONFIG, layout_seed, 1), coord.x, coord.y, chunk_seed_value, chunk_size, DEFAULT_WORLD_CONFIG, &"xl")
		for slot in definitions.size():
			var definition: PlanetDefinition = definitions[slot]
			var key := "%d:%d:%d" % [coord.x, coord.y, slot]
			result[key] = {
				"planet_id": String(definition.planet_id),
				"cell": [coord.x * chunk_size + slot % chunk_size, coord.y * chunk_size + int(slot / float(chunk_size))],
				"display_name": definition.display_name,
				"composition": str(definition.composition_base_texture) + str(definition.composition_tint) + str(definition.composition_decal_textures),
				"position": WorldGenerator.deterministic_chunk_position(DEFAULT_WORLD_CONFIG, layout_seed, coord.x, coord.y, slot, chunk_size),
			}
	return result

func _same_candidate(a: Array[Dictionary], b: Array[Dictionary], index: int) -> bool:
	return index < a.size() and index < b.size() and a[index].get("planet_id") == b[index].get("planet_id") and a[index].get("cell") == b[index].get("cell") and a[index].get("position") == b[index].get("position") and a[index].get("display_name") == b[index].get("display_name")

func _unique_ids(roster: Array[Dictionary]) -> bool:
	var seen := {}
	for candidate in roster:
		var id: String = String(candidate.get("planet_id", ""))
		if id.is_empty() or seen.has(id):
			return false
		seen[id] = true
	return true

func _unique_cells(roster: Array[Dictionary]) -> bool:
	var seen := {}
	for candidate in roster:
		var cell: Vector2i = candidate.get("cell", Vector2i(-999999, -999999))
		if seen.has(cell):
			return false
		seen[cell] = true
	return true

func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", false)

func _contains_roster_id(ids: Dictionary, roster: Array[Dictionary]) -> bool:
	for candidate in roster:
		if ids.has(String(candidate.get("planet_id", ""))):
			return true
	return false

func _print_result() -> void:
	print("Checks: %d, Failures: %d" % [_checks, _failures])
	if _failures == 0:
		print("RESULT: PASSED")
		quit(0)
	else:
		print("RESULT: FAILED")
		quit(1)
