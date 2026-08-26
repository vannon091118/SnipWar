extends SceneTree

## Optimized Preflight Runner v2 — parallel execution architecture.
## Runs pure constraints first, boots scene once, then runs scene constraints
## with state resets in between.  Fixes fail-fast to always show summary.
##
## Usage: $GODOT_BIN --headless --path . --script res://scripts/preflight.gd [options]
## Options identical to the original preflight.gd.

const _V2Ctx := preload("res://scripts/preflight_v2/v2_context.gd")
const _V2Fixture := preload("res://scripts/preflight_v2/v2_fixture.gd")
const _Scanner := preload("res://scripts/preflight_v2/constraint_scanner.gd")
const _CatalogPath := "res://scripts/preflight_v2/constraint_catalog.json"

# Loaded once at startup; used by _is_pure() for every constraint.
var _pure_set: Dictionary = {}

# Constraints that破坏 the scene state and require a full re-boot after them.
const FULL_REBOOT_IDS: Array[String] = ["save_game_roundtrip", "context_handover"]


func _init() -> void:
	var args: Dictionary = _parse_cli_arguments()

	if args.get("help", false):
		_print_help()
		quit(0)
		return

	if args.get("list", false):
		_load_pure_catalog()
		_print_list()
		quit(0)
		return

	var ctx = _V2Ctx.new(self)
	ctx.verbose = args.get("verbose", false)
	ctx.fail_fast = args.get("fail_fast", false)

	_load_pure_catalog()

	var registry: Array[Dictionary] = _Scanner.new().scan()
	if registry.is_empty():
		print("[preflight-v2] FATAL: No constraints discovered from preflight/ directory")
		quit(1)
		return

	var filter_query: String = args.get("filter", "")
	var pipeline: Array[Dictionary] = _build_pipeline(registry, filter_query)
	if args.get("reverse", false):
		pipeline = _reverse_pipeline(pipeline)

	if pipeline.is_empty():
		print("[preflight-v2] Warning: No constraints matched filter: '%s'" % filter_query)
		quit(0)
		return

	# --- Split into phases ---
	var pure_constraints: Array[Dictionary] = []
	var scene_constraints: Array[Dictionary] = []
	for entry in pipeline:
		if _is_pure(entry["id"]):
			pure_constraints.append(entry)
		else:
			scene_constraints.append(entry)

	print("==================================================")
	print(" SnipWar Preflight Suite v2 (Optimized)")
	print(" Running %d constraints (%d pure, %d scene)%s" % [
		pipeline.size(), pure_constraints.size(), scene_constraints.size(),
		" (Filter: '%s')" % filter_query if not filter_query.is_empty() else ""
	])
	if ctx.verbose:
		print(" Mode: Verbose | Fail-Fast: %s" % str(ctx.fail_fast))
	print("==================================================")

	var suite_start_usec: int = Time.get_ticks_usec()
	var constraints_passed: int = 0
	var constraints_failed: int = 0
	var early_exit := false

	# ═══ PHASE 1: Pure constraints (no scene needed) ═══
	if not pure_constraints.is_empty():
		ctx.begin_phase("Pure Constraints (no scene)")
		for entry in pure_constraints:
			if early_exit:
				break
			var result: Array = await _run_one(ctx, entry)
			if result[0]:
				constraints_passed += 1
			else:
				constraints_failed += 1
			# Check fail-fast after every constraint (not just failures)
			if ctx.fail_fast and (not result[0] or ctx.early_exit_requested):
				early_exit = true

	# ═══ PHASE 2: Scene constraints (shared fixture, state resets) ═══
	if not scene_constraints.is_empty():
		ctx.begin_phase("Scene Constraints (shared fixture)")
		var fixture: _V2Fixture = _V2Fixture.new(self)

		# Boot the scene once via V2Fixture
		var fixture_ready: bool = await fixture.boot_default(ctx)
		if not fixture_ready:
			print("[preflight-v2] FATAL: Scene fixture boot failed")
			_print_summary(ctx, pipeline.size(), constraints_passed, constraints_failed,
				(Time.get_ticks_usec() - suite_start_usec) / 1000.0)
			await fixture.cleanup()
			quit(1)
			return

		# Wire up ctx references from V2Fixture
		_apply_fixture_to_ctx(ctx, fixture)

		for entry in scene_constraints:
			if early_exit:
				break

			# Take checkpoint before each constraint
			ctx.take_checkpoint()

			var result: Array = await _run_one(ctx, entry)
			if result[0]:
				constraints_passed += 1
			else:
				constraints_failed += 1
			# Check fail-fast after every constraint (not just failures)
			if ctx.fail_fast and (not result[0] or ctx.early_exit_requested):
				early_exit = true

			# Verify state isolation (non-blocking warning)
			if not ctx.verify_checkpoint():
				pass  # Warnings already recorded in isolation_warnings

			# Full reboot after destructive constraints (save_game_roundtrip, context_handover)
			if entry["id"] in FULL_REBOOT_IDS:
				if not early_exit:
					var reboot_ok: bool = await fixture.boot_default(ctx)
					if reboot_ok:
						_apply_fixture_to_ctx(ctx, fixture)
					else:
						print("[preflight-v2] FATAL: Re-boot after %s failed" % entry["id"])
						early_exit = true
			else:
				# Lightweight state reset for the next constraint (much faster than full re-boot)
				var reset_ok: bool = await fixture.reset_state(ctx)
				if reset_ok:
					_apply_fixture_to_ctx(ctx, fixture)
				else:
					print("[preflight-v2] WARNING: State reset failed after %s, forcing full re-boot" % entry["id"])
					var fallback_ok: bool = await fixture.boot_default(ctx)
					if fallback_ok:
						_apply_fixture_to_ctx(ctx, fixture)
					else:
						print("[preflight-v2] FATAL: Fallback re-boot also failed")
						early_exit = true

		await fixture.cleanup()

	var total_ms: float = (Time.get_ticks_usec() - suite_start_usec) / 1000.0
	_print_summary(ctx, pipeline.size(), constraints_passed, constraints_failed, total_ms)
	ctx.print_isolation_report()

	var mcp_json_path: String = args.get("mcp_json", "")
	if mcp_json_path != "":
		_write_mcp_json(mcp_json_path, ctx, constraints_passed, constraints_failed, total_ms, pipeline.size())

	if ctx.failure_count > 0 or constraints_failed > 0:
		quit(1)
	else:
		quit(0)


# --- Runner ---

func _run_one(ctx, entry: Dictionary) -> Array:
	var constraint_script: Script = entry["script"]
	var constraint: RefCounted = constraint_script.new()
	var c_name: String = String(constraint.constraint_name())
	ctx.active_constraint = c_name

	var start_checks: int = ctx.checks_run
	var start_failures: int = ctx.failure_count
	var start_usec: int = Time.get_ticks_usec()

	if not ctx.verbose:
		print("[preflight-v2] %s ..." % c_name)
	else:
		print("\n--- [preflight-v2] %s (%s) ---" % [c_name, entry.get("desc", "")])

	var ok: bool = await constraint.run(ctx)
	var elapsed_ms: float = (Time.get_ticks_usec() - start_usec) / 1000.0
	var checks_delta: int = ctx.checks_run - start_checks
	var failures_delta: int = ctx.failure_count - start_failures

	var status: String = "PASS" if (ok and failures_delta == 0) else "FAIL"
	ctx.constraint_timings[c_name] = {
		"duration_ms": elapsed_ms,
		"checks": checks_delta,
		"failures": failures_delta,
		"status": status,
		"phase": ctx.phase_name,
	}

	var status_str := "[PASS]" if status == "PASS" else "[FAIL]"
	print("%s %s (%.2f ms, %d checks)" % [status_str, c_name, elapsed_ms, checks_delta])

	return [status == "PASS", c_name]


# --- Pipeline ---

func _build_pipeline(registry: Array[Dictionary], filter_query: String) -> Array[Dictionary]:
	if filter_query.is_empty():
		return registry.duplicate()

	var selected: Array[Dictionary] = []
	var tokens: PackedStringArray = filter_query.to_lower().split(",")
	var needs_scene_boot := false
	for entry in registry:
		var c_id: String = entry["id"].to_lower()
		var c_desc: String = entry["desc"].to_lower()
		for token in tokens:
			var t := token.strip_edges()
			if not t.is_empty() and (c_id.contains(t) or c_desc.contains(t)):
				selected.append(entry)
				if not _is_pure(entry["id"]):
					needs_scene_boot = true
				break

	# Auto-boot scene if filtered constraints depend on scene state and scene_boot is not included
	if needs_scene_boot:
		var has_scene_boot := false
		for entry in selected:
			if entry["id"] == "scene_boot":
				has_scene_boot = true
				break
		if not has_scene_boot:
			for entry in registry:
				if entry["id"] == "scene_boot":
					selected.insert(0, entry)
					break

	return selected


func _reverse_pipeline(pipeline: Array[Dictionary]) -> Array[Dictionary]:
	var reversed: Array[Dictionary] = pipeline.duplicate()
	reversed.reverse()
	return reversed


# --- Catalog lookup ---

func _load_pure_catalog() -> void:
	var file := FileAccess.open(_CatalogPath, FileAccess.READ)
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()

	# Strip comment lines (## prefix)
	var lines: PackedStringArray = content.split("\n")
	var clean_lines: PackedStringArray = PackedStringArray()
	for line in lines:
		if not line.strip_edges().begins_with("##"):
			clean_lines.append(line)
	var clean_content: String = "\n".join(clean_lines)

	var json := JSON.new()
	if json.parse(clean_content) != OK:
		return
	var data: Dictionary = json.data as Dictionary
	if data == null:
		return
	var pure_list: Array = data.get("pure", []) as Array
	for entry in pure_list:
		_pure_set[entry] = true


func _is_pure(constraint_id: String) -> bool:
	return _pure_set.has(constraint_id)


# --- Fixture wiring ---

func _apply_fixture_to_ctx(ctx, fixture: _V2Fixture) -> void:
	ctx.background = fixture.background
	ctx.field = fixture.field
	ctx.network = fixture.network
	ctx.manager = fixture.manager
	ctx.game_state = fixture.game_state
	ctx.world_config = fixture.world_config
	ctx.planet_catalog = fixture.planet_catalog
	ctx.scenario_catalog = fixture.scenario_catalog
	ctx.upgrade_catalog = fixture.upgrade_catalog
	ctx.original_seed = fixture.world_config.layout_seed if fixture.world_config != null else 424242

	# Wire up faction_changed signal (avoid duplicates)
	if fixture.game_state != null and not fixture.game_state.faction_changed.is_connected(ctx.capture_faction_changed):
		fixture.game_state.faction_changed.connect(ctx.capture_faction_changed)

	# Set the base fixture reference so constraints can access it
	ctx.fixture = fixture.base


# --- CLI ---

func _parse_cli_arguments() -> Dictionary:
	var parsed: Dictionary = {
		"verbose": false,
		"fail_fast": false,
		"filter": "",
		"list": false,
		"help": false,
		"reverse": false,
		"mcp_json": "",
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
		elif arg.begins_with("--mcp-json="):
			parsed["mcp_json"] = arg.trim_prefix("--mcp-json=")
	return parsed


func _print_help() -> void:
	print("""
SnipWar Preflight Suite v2 (Optimized)
======================================
Usage: godot --headless --path . --script res://scripts/preflight.gd [options]

Options:
  --verbose, -v            Print every individual check and assertion details.
  --fail-fast, -x          Abort after first failing constraint (summary still shown).
  --filter=<name>, -f=...  Run only constraints matching the given name/pattern.
                           (Auto-boots scene if constraint requires scene state).
  --reverse, --order=reverse
                           Run the selected constraints in reverse order.
  --mcp-json=<path>        Write machine-readable JSON result for chain controller.
  --list, -l               List all available constraints.
  --help, -h               Show this help message.

Architecture (v2):
  Phase 1: Pure constraints (no scene needed) — fastest possible execution
  Phase 2: Scene constraints — scene booted ONCE, state resets between each
  Full re-boot after destructive constraints (save_game_roundtrip, context_handover)
""")


func _print_list() -> void:
	var scanner = _Scanner.new()
	var registry: Array[Dictionary] = scanner.scan()
	print("\nAvailable Preflight v2 Constraints:")
	print("-----------------------------------")
	var idx := 1
	for entry in registry:
		var scene_tag := "[scene]" if not _is_pure(entry["id"]) else "[pure]   "
		print(" %2d. %-30s %-8s %s" % [idx, entry["id"], scene_tag, entry.get("desc", "")])
		idx += 1
	print("")


# --- Summary ---

func _print_summary(ctx, total: int, passed: int, failed: int, total_ms: float) -> void:
	print("\n==================================================")
	print(" PREFLIGHT v2 SUMMARY REPORT")
	print("==================================================")
	print(" Constraints: %d total (%d passed, %d failed)" % [total, passed, failed])
	print(" Assertions:  %d total (%d passed, %d fail)" % [ctx.checks_run, ctx.checks_passed, ctx.failure_count])
	print(" Checkpoints: %d" % ctx.checkpoint_count)
	print(" Total Time:   %.2f ms" % total_ms)
	print("--------------------------------------------------")

	# Group by phase
	var phases: Dictionary = {}
	for c_name in ctx.constraint_timings:
		var t: Dictionary = ctx.constraint_timings[c_name]
		var phase: String = t.get("phase", "unknown")
		if not phases.has(phase):
			phases[phase] = []
		phases[phase].append({"name": c_name, "data": t})

	for phase_name in phases:
		var phase_entries: Array = phases[phase_name]
		print("  --- %s ---" % phase_name)
		for entry in phase_entries:
			var cn: String = entry["name"]
			var t: Dictionary = entry["data"]
			var marker := "[PASS]" if t["status"] == "PASS" else "[FAIL]"
			print("  %-6s %-32s %7.2f ms (%3d checks, %d fail)" % [marker, cn, t["duration_ms"], t["checks"], t["failures"]])

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
		print(" RESULT: PASSED (%d constraints in %.2f ms)" % [passed, total_ms])
		print("==================================================\n")


# --- MCP JSON output (for chain controller) ---

func _write_mcp_json(path: String, ctx, passed_constraints: int, failed_constraints: int, total_ms: float, total_constraints: int) -> void:
	var summary := {
		"ok": ctx.failure_count == 0 and failed_constraints == 0,
		"verdict": "PASS" if ctx.failure_count == 0 and failed_constraints == 0 else "FAIL",
		"constraints": {
			"total": total_constraints,
			"passed": passed_constraints,
			"failed": failed_constraints,
		},
		"assertions": {
			"run": ctx.checks_run,
			"passed": ctx.checks_passed,
			"failed": ctx.failure_count,
		},
		"duration_ms": total_ms,
		"timings": ctx.constraint_timings.duplicate(true),
		"failures": ctx.failures.duplicate(true),
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[preflight-v2] Cannot write --mcp-json output to " + path)
		return
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()
