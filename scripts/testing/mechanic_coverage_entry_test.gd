extends SceneTree

## Mechanic Coverage Entry Test: Validates mechanic_registry.gd detects
## all mechanics and validates scenario coverage.

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var registry: MechanicRegistry = MechanicRegistry.new()
	
	# Test 1: Registry loads mechanics
	var mechanics: Array = registry.get_registered_mechanics()
	if mechanics.is_empty():
		_failures.append("MechanicRegistry get_registered_mechanics() empty")
	else:
		print("Registered mechanics: %d" % mechanics.size())
	
	# Test 2: Core mechanics present
	var core_mechanics: Array = [
		"worker_transit",
		"planet_capture",
		"resource_production",
		"research",
		"ship_assembly",
		"fleet_battle",
		"conquest",
		"scout_exploration",
		"upgrade_purchase",
		"cpu_dispatch"
	]
	for mechanic in core_mechanics:
		if not registry.has_mechanic(mechanic):
			_failures.append("Core mechanic missing from registry: %s" % mechanic)
	
	# Test 3: Coverage validation
	var coverage: Dictionary = registry.validate_coverage()
	if not coverage.has("covered") or not coverage.has("uncovered"):
		_failures.append("MechanicRegistry validate_coverage() missing keys")
	else:
		var uncovered: Array = coverage.uncovered
		if uncovered.size() > 0:
			_failures.append("MechanicRegistry uncovered mechanics: %s" % str(uncovered))
	
	# Test 4: Scenario coverage
	var scenario_catalog: ScenarioCatalog = ScenarioCatalog.new()
	scenario_catalog.initialize_default()
	
	var scenarios: Array = scenario_catalog.get_all_scenarios()
	if scenarios.is_empty():
		_failures.append("ScenarioCatalog has no scenarios")
	
	for scenario in scenarios:
		var scenario_coverage: Dictionary = registry.validate_scenario_coverage(scenario.scenario_id)
		if scenario_coverage.uncovered.size() > 0:
			_failures.append("Scenario '%s' uncovered mechanics: %s" % [scenario.scenario_id, str(scenario_coverage.uncovered)])
	
	# Test 5: Mechanic -> scenario mapping
	var mechanic_scenarios: Dictionary = registry.get_mechanic_scenario_map()
	for mechanic in core_mechanics:
		if not mechanic_scenarios.has(mechanic):
			_failures.append("Mechanic '%s' not mapped to any scenario" % mechanic)
		elif mechanic_scenarios[mechanic].is_empty():
			_failures.append("Mechanic '%s' has empty scenario list" % mechanic)
	
	# Test 6: Registry serialization
	var registry_json: String = JSON.stringify(registry.to_dict())
	var restored: MechanicRegistry = MechanicRegistry.new()
	restored.from_dict(JSON.parse_string(registry_json))
	if restored.get_registered_mechanics().size() != mechanics.size():
		_failures.append("MechanicRegistry serialization mismatch")
	
	# Test 7: Entry test discovery (mechanic_coverage constraint should find tests)
	var test_files: Array = _discover_mechanic_tests()
	if test_files.is_empty():
		_failures.append("No mechanic test files discovered")
	
	for test_file in test_files:
		var test_script: Script = load(test_file)
		if test_script == null:
			_failures.append("Failed to load test: %s" % test_file)
	
	if not _failures.is_empty():
		for failure in _failures:
			printerr("[MECHANIC-COVERAGE-FAIL] " + failure)
		print("MECHANIC COVERAGE ENTRY TEST: FAIL (%d failures)" % _failures.size())
		quit(1)
		return
	print("MECHANIC COVERAGE ENTRY TEST: PASS (all checks verified)")
	quit(0)

func _discover_mechanic_tests() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open("res://scripts/testing/")
	if dir == null:
		return result
	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name.is_empty():
			break
		if file_name.ends_with("_test.gd") and not file_name.begins_with("dbg_"):
			result.append("res://scripts/testing/" + file_name)
	dir.list_dir_end()
	return result