extends SceneTree

## Persistent SnipWar test suite (no GUT). This file is the orchestrator:
## it boots a PreflightContext, parses CLI debugging flags, profiles execution,
## and runs constraint modules with detailed diagnostics and debug failure reports.
## Scene-dependent constraints receive a fresh PreflightFixture; individual checks
## live in scripts/preflight/ and must not rely on another constraint's mutations.

const _Context := preload("res://scripts/preflight/preflight_context.gd")

const CONSTRAINT_REGISTRY: Array[Dictionary] = [
	{
		"id": "game_state_compatibility",
		"script": preload("res://scripts/preflight/constraint_game_state_compatibility.gd"),
		"desc": "GameState facade methods, signatures & callsites",
		"requires_scene": false,
	},
	{
		"id": "effects_and_traits",
		"script": preload("res://scripts/preflight/constraint_effects_and_traits.gd"),
		"desc": "Combat effect math & traits",
		"requires_scene": false,
	},
	{
		"id": "flight_and_dispatch",
		"script": preload("res://scripts/preflight/constraint_flight_and_dispatch.gd"),
		"desc": "Flight duration & cluster dispatch",
		"requires_scene": false,
	},
	{
		"id": "world_generator_scaling",
		"script": preload("res://scripts/preflight/constraint_world_generator_scaling.gd"),
		"desc": "World generator scaling & catalog expansions",
		"requires_scene": false,
	},
	{
		"id": "navigation_growth",
		"script": preload("res://scripts/preflight/constraint_navigation_growth.gd"),
		"desc": "World growth factor & K-nearest graph",
		"requires_scene": false,
	},
	{
		"id": "scene_boot",
		"script": preload("res://scripts/preflight/constraint_scene_boot.gd"),
		"desc": "Scene boot, starfield, viewport & world wiring",
		"requires_scene": false,
	},
	{
		"id": "resources_and_seed",
		"script": preload("res://scripts/preflight/constraint_resources_and_seed.gd"),
		"desc": "Resource deal determinism & layout seeds",
		"requires_scene": true,
	},
	{
		"id": "world_planets_and_dispatch",
		"script": preload("res://scripts/preflight/constraint_world_planets_and_dispatch.gd"),
		"desc": "Planet layouts, dispatch lines & clusters",
		"requires_scene": true,
	},
	{
		"id": "world_details_and_scale",
		"script": preload("res://scripts/preflight/constraint_world_details_and_scale.gd"),
		"desc": "Planet details, scales & visuals",
		"requires_scene": true,
	},
	{
		"id": "upgrade_catalog",
		"script": preload("res://scripts/preflight/constraint_upgrade_catalog.gd"),
		"desc": "Upgrade branches, prerequisites, exclusivity, traits & assets",
		"requires_scene": false,
	},
	{
		"id": "economy_production",
		"script": preload("res://scripts/preflight/constraint_economy_production.gd"),
		"desc": "Upgrade purchases, generation, maintenance & refinery conversion",
		"requires_scene": true,
	},
	{
		"id": "mission_semantics",
		"script": preload("res://scripts/preflight/constraint_mission_semantics.gd"),
		"desc": "Colony, cargo & military mission semantics",
		"requires_scene": true,
	},
	{
		"id": "cpu_dispatch",
		"script": preload("res://scripts/preflight/constraint_cpu_dispatch.gd"),
		"desc": "CPU dispatch AI, worker costs & cluster tier bonuses",
		"requires_scene": true,
	},
	{
		"id": "selection_and_context",
		"script": preload("res://scripts/preflight/constraint_selection_and_context.gd"),
		"desc": "Selection service, aggregated overview & context menu",
		"requires_scene": true,
	},
	{
		"id": "scout_and_discovery",
		"script": preload("res://scripts/preflight/constraint_scout_and_discovery.gd"),
		"desc": "Scout ship, scanning & discovery",
		"requires_scene": true,
	},
	{
		"id": "ship_catalog_and_assembly",
		"script": preload("res://scripts/preflight/constraint_ship_catalog_and_assembly.gd"),
		"desc": "Ship parts, variants, build/disassemble & tech gating",
		"requires_scene": true,
	},
	{
		"id": "ship_transit_and_arrival",
		"script": preload("res://scripts/preflight/constraint_ship_transit_and_arrival.gd"),
		"desc": "ShipBase dispatch, fleet preview & conquest replay",
		"requires_scene": true,
	},
	{
		"id": "colony_milestone",
		"script": preload("res://scripts/preflight/constraint_colony_milestone.gd"),
		"desc": "Colony ship settling & first_colony milestone",
		"requires_scene": true,
	},
	{
		"id": "event_log",
		"script": preload("res://scripts/preflight/constraint_event_log.gd"),
		"desc": "Event log exports & notifications",
		"requires_scene": true,
	},
	{
		"id": "camera_and_input",
		"script": preload("res://scripts/preflight/constraint_camera_and_input.gd"),
		"desc": "Camera navigation & input maps",
		"requires_scene": true,
	},
	{
		"id": "pause_and_context",
		"script": preload("res://scripts/preflight/constraint_pause_and_context.gd"),
		"desc": "Pause menus & context menus",
		"requires_scene": true,
	},
	{
		"id": "layers_2_and_3",
		"script": preload("res://scripts/preflight/constraint_layers_2_and_3.gd"),
		"desc": "Battle/conquest sim & layer 2/3 deterministic replay",
		"requires_scene": true,
	},
	{
		"id": "ingame_player_and_transitions",
		"script": preload("res://scripts/preflight/constraint_ingame_player_and_transitions.gd"),
		"desc": "In-game player controls & transitions",
		"requires_scene": true,
	},
	{
		"id": "sector_classification",
		"script": preload("res://scripts/preflight/constraint_sector_classification.gd"),
		"desc": "Sector density field classification & edge typing",
		"requires_scene": false,
	},
	{
		"id": "grid_system",
		"script": preload("res://scripts/preflight/constraint_grid_system.gd"),
		"desc": "Hex grid, building placement & pathfinding",
		"requires_scene": true,
	},
	{
		"id": "local_resources",
		"script": preload("res://scripts/preflight/constraint_local_resources.gd"),
		"desc": "Local vaults, transfers & trade routes",
		"requires_scene": true,
	},
	{
		"id": "conquest_grid_combat",
		"script": preload("res://scripts/preflight/constraint_conquest_grid_combat.gd"),
		"desc": "Wave-based grid conquest & capture decisions",
		"requires_scene": true,
	},
	{
		"id": "paper_style",
		"script": preload("res://scripts/preflight/constraint_paper_style.gd"),
		"desc": "Paper-comic shaders & style config",
		"requires_scene": false,
	},
	{
		"id": "chunk_expansion",
		"script": preload("res://scripts/preflight/constraint_chunk_expansion.gd"),
		"desc": "Procedural chunk-grid world & composition",
		"requires_scene": false,
	},
]


func _init() -> void:
	var args: Dictionary = _parse_cli_arguments()

	if args.get("help", false):
		_print_help()
		quit(0)
		return

	if args.get("list", false):
		_print_list()
		quit(0)
		return

	var ctx: PreflightContext = _Context.new(self)
	ctx.verbose = args.get("verbose", false)
	ctx.fail_fast = args.get("fail_fast", false)

	var filter_query: String = args.get("filter", "")
	var pipeline: Array[Dictionary] = _build_execution_pipeline(filter_query)
	if args.get("reverse", false):
		pipeline = _reverse_execution_pipeline(pipeline)

	if pipeline.is_empty():
		print("[preflight] Warning: No constraints matched filter: '%s'" % filter_query)
		quit(0)
		return

	print("==================================================")
	print(" SnipWar Preflight Suite (Modular Debug Helper)")
	print(" Running %d constraints%s" % [pipeline.size(), (" (Filter: '%s')" % filter_query) if not filter_query.is_empty() else ""])
	if ctx.verbose:
		print(" Mode: Verbose | Fail-Fast: %s" % str(ctx.fail_fast))
	print("==================================================")

	var suite_start_usec: int = Time.get_ticks_usec()
	var constraints_passed: int = 0
	var constraints_failed: int = 0

	for entry in pipeline:
		var constraint_script: Script = entry["script"]
		var constraint: RefCounted = constraint_script.new()
		var c_name: String = constraint.constraint_name()
		ctx.active_constraint = c_name

		var start_checks: int = ctx.checks_run
		var start_failures: int = ctx.failure_count
		var start_usec: int = Time.get_ticks_usec()

		if not ctx.verbose:
			print("[preflight] %s ..." % c_name)
		else:
			print("\n--- [preflight] %s (%s) ---" % [c_name, entry.get("desc", "")])

		var ok: bool = false
		if entry.get("requires_scene", false):
			var fixture_ready: bool = await ctx.fixture.boot_default(ctx)
			if fixture_ready:
				ok = await constraint.run(ctx)
		else:
			ok = await constraint.run(ctx)
		var elapsed_ms: float = (Time.get_ticks_usec() - start_usec) / 1000.0
		var checks_delta: int = ctx.checks_run - start_checks
		var failures_delta: int = ctx.failure_count - start_failures

		var constraint_status: String = "PASS"
		if not ok or failures_delta > 0:
			constraint_status = "FAIL"
			constraints_failed += 1
		else:
			constraints_passed += 1

		ctx.constraint_timings[c_name] = {
			"duration_ms": elapsed_ms,
			"checks": checks_delta,
			"failures": failures_delta,
			"status": constraint_status,
		}

		var status_str := "[PASS]" if constraint_status == "PASS" else "[FAIL]"
		print("%s %s (%.2f ms, %d checks)" % [status_str, c_name, elapsed_ms, checks_delta])

		if ctx.fail_fast and constraint_status == "FAIL":
			break

	var total_suite_ms: float = (Time.get_ticks_usec() - suite_start_usec) / 1000.0

	_print_summary(ctx, pipeline.size(), constraints_passed, constraints_failed, total_suite_ms)
	await ctx.fixture.cleanup()

	if ctx.failure_count > 0 or constraints_failed > 0:
		quit(1)
	else:
		quit(0)


func _reverse_execution_pipeline(pipeline: Array[Dictionary]) -> Array[Dictionary]:
	var scene_boot: Dictionary = {}
	var reversed: Array[Dictionary] = []
	for entry in pipeline:
		if entry["id"] == "scene_boot":
			scene_boot = entry
		else:
			reversed.append(entry)
	reversed.reverse()
	if not scene_boot.is_empty():
		reversed.insert(0, scene_boot)
	return reversed


func _build_execution_pipeline(filter_query: String) -> Array[Dictionary]:
	if filter_query.is_empty():
		return CONSTRAINT_REGISTRY.duplicate()

	var selected: Array[Dictionary] = []
	var tokens: PackedStringArray = filter_query.to_lower().split(",")
	var needs_scene_boot := false

	for entry in CONSTRAINT_REGISTRY:
		var c_id: String = entry["id"].to_lower()
		var c_desc: String = entry["desc"].to_lower()
		var matches := false
		for token in tokens:
			var t := token.strip_edges()
			if not t.is_empty() and (c_id.contains(t) or c_desc.contains(t)):
				matches = true
				break
		if matches:
			selected.append(entry)
			if entry.get("requires_scene", false):
				needs_scene_boot = true

	# Auto-boot scene if filtered constraints depend on scene state and scene_boot is not included
	if needs_scene_boot:
		var has_scene_boot := false
		for entry in selected:
			if entry["id"] == "scene_boot":
				has_scene_boot = true
				break
		if not has_scene_boot:
			for entry in CONSTRAINT_REGISTRY:
				if entry["id"] == "scene_boot":
					selected.insert(0, entry)
					break

	return selected


func _parse_cli_arguments() -> Dictionary:
	var parsed: Dictionary = {
		"verbose": false,
		"fail_fast": false,
		"filter": "",
		"list": false,
		"help": false,
		"reverse": false,
	}

	var all_args: PackedStringArray = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())

	for arg in all_args:
		if arg == "--verbose" or arg == "-v":
			parsed["verbose"] = true
		elif arg == "--fail-fast" or arg == "-x":
			parsed["fail_fast"] = true
		elif arg == "--list" or arg == "-l":
			parsed["list"] = true
		elif arg == "--help" or arg == "-h":
			parsed["help"] = true
		elif arg == "--reverse" or arg == "--order=reverse":
			parsed["reverse"] = true
		elif arg.begins_with("--filter="):
			parsed["filter"] = arg.trim_prefix("--filter=")
		elif arg.begins_with("-f="):
			parsed["filter"] = arg.trim_prefix("-f=")
		elif arg.begins_with("--only="):
			parsed["filter"] = arg.trim_prefix("--only=")

	return parsed


func _print_help() -> void:
	print("""
SnipWar Preflight Test Suite (Debug Helper)
===========================================
Usage: godot --headless --path . --script res://scripts/preflight.gd [options]

Options:
  --verbose, -v            Print every individual check and assertion details.
  --fail-fast, -x          Abort immediately on the first assertion failure.
  --filter=<name>, -f=...  Run only constraints matching the given name/pattern.
                           (Auto-boots scene if constraint requires scene state).
  --reverse, --order=reverse
                           Run the selected constraints in reverse order while
                           keeping scene_boot first; scene constraints still get
                           isolated fixtures.
  --list, -l               List all available modular constraints.
  --help, -h               Show this help message.
""")


func _print_list() -> void:
	print("\nAvailable Preflight Constraints:")
	print("--------------------------------")
	var idx := 1
	for entry in CONSTRAINT_REGISTRY:
		var scene_tag := "[scene]" if entry.get("requires_scene", false) else "[pure]"
		print(" %2d. %-30s %-8s %s" % [idx, entry["id"], scene_tag, entry["desc"]])
		idx += 1
	print("")


func _print_summary(ctx: PreflightContext, total_constraints: int, passed_constraints: int, failed_constraints: int, total_ms: float) -> void:
	print("\n==================================================")
	print(" PREFLIGHT SUMMARY REPORT")
	print("==================================================")
	print(" Constraints: %d total (%d passed, %d failed)" % [total_constraints, passed_constraints, failed_constraints])
	print(" Assertions:  %d total (%d passed, %d failed)" % [ctx.checks_run, ctx.checks_passed, ctx.failure_count])
	print(" Total Time:   %.2f ms" % total_ms)
	print("--------------------------------------------------")

	for c_name in ctx.constraint_timings:
		var t: Dictionary = ctx.constraint_timings[c_name]
		var status_marker := "[PASS]" if t["status"] == "PASS" else "[FAIL]"
		print(" %-6s %-32s %7.2f ms (%3d checks, %d fail)" % [status_marker, c_name, t["duration_ms"], t["checks"], t["failures"]])

	if ctx.failures.size() > 0:
		print("==================================================")
		print(" FAILURES DIAGNOSTICS & DEBUGGING INFO (%d total)" % ctx.failures.size())
		print("==================================================")
		var f_idx := 1
		for f in ctx.failures:
			print(" [%d] Constraint: %s (at +%d ms)" % [f_idx, f["constraint"], f["time_msec"]])
			print("     Message:    %s" % f["message"])
			var details: Dictionary = f.get("details", {})
			if not details.is_empty():
				print("     Details:")
				for k in details:
					print("       * %s: %s" % [k, str(details[k])])
			f_idx += 1
		print("==================================================")
		print(" RESULT: FAILED (Blocking CI / Pre-commit)")
	else:
		print("==================================================")
		print(" RESULT: PASSED (%d constraints in %.2f ms)" % [passed_constraints, total_ms])
	print("==================================================\n")
