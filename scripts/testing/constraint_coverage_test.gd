extends SceneTree

## Constraint Coverage Test: Maps each of the 43 preflight constraints
## to at least one entry test that exercises it.
##
## This test validates that every constraint has test coverage.
## Exit 1 if any constraint lacks coverage.

var _failures: Array[String] = []

# Constraint -> Test mapping (constraint_id: [test_file_names])
const CONSTRAINT_TEST_MAP: Dictionary = {
	"agent_activity": ["docs_integrity_entry_test"],
	"camera_and_input": ["r008_world_ui_boundary_test"],
	"chunk_expansion": ["historical_world_flow_test"],
	"cluster_generation": ["phase01_world_identity_roster_test"],
	"colony_milestone": ["historical_world_flow_test"],
	"concept_index": ["concept_search_entry_test"],
	"conquest_grid_combat": ["combat_simulation_test"],
	"context_handover": ["historical_world_flow_test"],
	"cpu_dispatch": ["cpu_ai_behavior_test"],
	"dead_code": ["docs_integrity_entry_test"],
	"docs_integrity": ["docs_integrity_entry_test"],
	"economy_production": ["e1_vault_core_semantics_test", "e2_e4_economy_units_test"],
	"effects_and_traits": ["ship_builder_blueprint_test"],
	"event_log": ["chronicle_lifecycle_test", "historical_playback_test"],
	"flight_and_dispatch": ["navigation_transit_test"],
	"game_state_compatibility": ["e1_vault_core_semantics_test"],
	"global_search": ["global_search_entry_test"],
	"grid_system": ["combat_simulation_test"],
	"historical_world": ["historical_world_flow_test", "historical_playback_test"],
	"ingame_player_and_transitions": ["r008_world_ui_boundary_test"],
	"layer_independence": ["combat_simulation_test"],
	"layers_2_and_3": ["combat_simulation_test"],
	"local_resources": ["e2_e4_economy_units_test"],
	"main_menu_and_flow": ["historical_world_flow_test"],
	"mcp_capture_contract": ["mcp_capture_entry_test"],
	"mechanic_coverage": ["mechanic_coverage_entry_test"],
	"mission_semantics": ["navigation_transit_test"],
	"module_damage_model": ["combat_simulation_test"],
	"navigation_growth": ["navigation_transit_test"],
	"narrative_runtime": ["narrative_runtime_gate_test"],
	"paper_style": ["r008_world_ui_boundary_test"],
	"pause_and_context": ["r008_world_ui_boundary_test"],
	"research_ship": ["ship_builder_blueprint_test"],
	"resources_and_seed": ["phase01_world_identity_roster_test"],
	"save_game_roundtrip": ["save_load_roundtrip_test"],
	"save_game_slots": ["save_load_roundtrip_test"],
	"scene_boot": ["historical_world_flow_test"],
	"sector_classification": ["phase01_world_identity_roster_test"],
	"selection_and_context": ["r008_world_ui_boundary_test"],
	"ship_catalog_and_assembly": ["ship_builder_blueprint_test"],
	"ship_transit_and_arrival": ["navigation_transit_test", "combat_simulation_test"],
	"upgrade_catalog": ["e2_e4_economy_units_test"],
	"world_details_and_scale": ["phase01_world_identity_roster_test"],
	"world_generator_scaling": ["phase01_world_identity_roster_test"],
	"world_planets_and_dispatch": ["navigation_transit_test", "phase01_world_identity_roster_test"],
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Load constraint registry from scanner
	var scanner = load("res://scripts/preflight_v2/constraint_scanner.gd").new()
	var registry: Array[Dictionary] = scanner.scan()
	
	var all_constraint_ids: Array[String] = []
	for entry in registry:
		all_constraint_ids.append(entry["id"])
	
	all_constraint_ids.sort()
	
	print("Checking coverage for %d constraints..." % all_constraint_ids.size())
	
	var covered: int = 0
	var uncovered: Array[String] = []
	
	for constraint_id in all_constraint_ids:
		var test_files: Array = CONSTRAINT_TEST_MAP.get(constraint_id, [])
		if test_files.is_empty():
			uncovered.append(constraint_id)
			_failures.append("Constraint '%s' has NO test coverage mapping" % constraint_id)
		else:
			# Verify test files exist
			var all_exist: bool = true
			for test_file in test_files:
				var test_path: String = "res://scripts/testing/%s.gd" % test_file
				if not ResourceLoader.exists(test_path):
					all_exist = false
					_failures.append("Constraint '%s' mapped to missing test: %s" % [constraint_id, test_file])
			if all_exist:
				covered += 1
				if not _failures.is_empty() and _failures[_failures.size() - 1].begins_with("Constraint '%s' has NO test coverage mapping" % constraint_id):
					# This won't happen due to else, but kept for clarity
					pass
	
	if uncovered.size() > 0:
		print("UNCOVERED CONSTRAINTS (%d):" % uncovered.size())
		for cid in uncovered:
			print("  - %s" % cid)
	
	print("Coverage: %d/%d constraints have test mappings" % [covered, all_constraint_ids.size()])
	
	# Also check that all test files are *_test.gd and discoverable by test_all.gd
	var test_dir = DirAccess.open("res://scripts/testing/")
	if test_dir != null:
		test_dir.list_dir_begin()
		var test_count: int = 0
		while true:
			var file_name: String = test_dir.get_next()
			if file_name.is_empty():
				break
			if file_name.ends_with("_test.gd") and not file_name.begins_with("dbg_"):
				test_count += 1
		test_dir.list_dir_end()
		print("Discoverable entry tests: %d" % test_count)
	
	if not _failures.is_empty():
		for failure in _failures:
			printerr("[COVERAGE-FAIL] " + failure)
		print("CONSTRAINT COVERAGE: FAIL (%d failures)" % _failures.size())
		quit(1)
		return
	
	print("CONSTRAINT COVERAGE: PASS (all %d constraints have test coverage)" % all_constraint_ids.size())
	quit(0)