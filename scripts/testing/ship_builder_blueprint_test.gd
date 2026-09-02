extends SceneTree

## Ship Builder / Blueprint Validation Test: Validates ShipPartCatalog default
## preload, ShipAssembly instantiation, and ShipManager API surface.
##
## Exit 1 on any failure — real assertions, no print-only.

const DEFAULT_CATALOG := preload("res://resources/config/ship_part_catalog_default.tres")

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Test 1: Default ShipPartCatalog loads and is not empty
	var catalog: ShipPartCatalog = DEFAULT_CATALOG
	if catalog == null:
		_failures.append("Default ShipPartCatalog failed to preload")
	else:
		# Test 2: Catalog resolves known part IDs
		var hull: ShipPartDefinition = catalog.resolve(&"hull_t1")
		if hull == null:
			_failures.append("Catalog could not resolve hull_t1_scout")
		else:
			if hull.slot_type != ShipPartDefinition.SLOT_HULL:
				_failures.append("hull_t1_scout slot_type should be hull")

	# Test 3: ShipAssembly instantiation and property roundtrip
	var assembly: ShipAssembly = ShipAssembly.new()
	assembly.ship_id = &"test_ship"
	assembly.hull_id = &"hull_t1_scout"
	assembly.drive_id = &"drive_t1_ion_blue"
	assembly.weapon_id = &"weapon_t1_pulse"
	assembly.shield_id = &"shield_t1_reactive"
	assembly.scanner_id = &"scanner_t1_basic"
	if String(assembly.ship_id) != "test_ship":
		_failures.append("ShipAssembly ship_id roundtrip failed")
	if String(assembly.hull_id) != "hull_t1_scout":
		_failures.append("ShipAssembly hull_id roundtrip failed")

	# Test 4: ShipAssembly copy produces independent instance
	var copy: ShipAssembly = assembly.copy()
	if copy == null or String(copy.ship_id) != "test_ship":
		_failures.append("ShipAssembly copy failed")
	copy.ship_id = &"modified"
	if String(assembly.ship_id) == String(copy.ship_id):
		_failures.append("ShipAssembly copy should be independent")

	# Test 5: FleetSnapshot carries ship assemblies
	var fleet: FleetSnapshot = FleetSnapshot.new()
	fleet.faction = GameState.FACTION_PLAYER
	fleet.ships = [assembly]
	if fleet.ships.size() != 1:
		_failures.append("FleetSnapshot should hold 1 ship")
	if fleet.ships[0] != assembly:
		_failures.append("FleetSnapshot ship reference mismatch")

	# Test 6: ShipManager has the expected public methods
	if not ShipManager.new().has_method("assemble_ship"):
		_failures.append("ShipManager missing assemble_ship")
	if not ShipManager.new().has_method("disassemble_ship"):
		_failures.append("ShipManager missing disassemble_ship")

	# Test 7: FleetSnapshot stats calculation on a catalog-backed ship
	if catalog != null:
		fleet.calculate_stats(catalog)
		if fleet.total_hull_hp <= 0.0:
			_failures.append("FleetSnapshot total_hull_hp should be positive after calculate_stats")

	if not _failures.is_empty():
		for f in _failures:
			printerr("[SHIP-BUILDER-FAIL] " + f)
		print("SHIP BUILDER/BLUEPRINT: FAIL (%d failures)" % _failures.size())
		quit(1)
		return
	print("SHIP BUILDER/BLUEPRINT: PASS (catalog + assembly verified)")
	quit(0)
