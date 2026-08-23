extends SceneTree

## McpTestRunner — Deterministic MCP test orchestrator (like Preflight for MCP tools).
##
## Usage: godot --path . --script res://addons/gdscript_mcp/testing/mcp_test_runner.gd
##        [--mcp-test-filter=<id>] [--mcp-test-verbose] [--mcp-test-list]
##
## Reads enabled scenarios from user://mcp_test_config.cfg,
## boots each target scene, calls MCP tools, and validates expected results.
##
## Requires a real renderer; headless MCP test execution is forbidden.

const SCENARIO_DIR := "res://addons/gdscript_mcp/testing/scenarios/"
const CONFIG_PATH := "user://mcp_test_config.cfg"
const REGISTRY_PATH := "res://addons/gdscript_mcp/runtime/core/mcp_tool_registry.gd"

var _registry: RefCounted = null
var _verbose: bool = false
var _filter: String = ""
var _list_only: bool = false
var _argument_error: bool = false

var _scenarios: Array = []
var _total: int = 0
var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0

func _init() -> void:
	if OS.has_feature("headless") or "--headless" in OS.get_cmdline_args():
		push_error("MCP test runner requires a visible renderer; headless mode is forbidden")
		quit(2)
		return
	_parse_args()
	if _argument_error:
		quit(2)
		return
	if _list_only:
		_list_scenarios()
		quit()
		return
	_run_tests()

func _run_tests() -> void:
	_load_scenarios()
	_filter_scenarios()

	print("==================================================")
	print(" MCP Test Runner — ", _scenarios.size(), " scenario(s)")
	print("==================================================")

	for scenario in _scenarios:
		var sc = scenario
		if not _is_enabled(sc.id):
			_skipped += 1
			print("[SKIP] ", sc.id, " — disabled")
			continue

		print("\n--- ", sc.id, ": ", sc.description, " ---")
		var ok: bool = await _run_scenario(sc)
		_total += 1
		if ok:
			_passed += 1
			print("[PASS] ", sc.id)
		else:
			_failed += 1
			print("[FAIL] ", sc.id)

	print("\n==================================================")
	print(" Results: ", _passed, "/", _total, " passed", " (", _skipped, " skipped)")
	if _failed > 0:
		print(" ", _failed, " FAILED")
	print("==================================================")

	if _failed > 0:
		quit(1)
	else:
		quit()

func _run_scenario(scenario) -> bool:
	# Boot scene if specified
	if scenario.scene_path != "":
		var s = load(scenario.scene_path)
		if not s:
			print("  ERROR: scene not found: ", scenario.scene_path)
			return false
		var instance = s.instantiate()
		if not instance:
			print("  ERROR: instantiate failed")
			return false
		root.add_child(instance)

	# Wait for rendering
	for _i in range(scenario.wait_frames):
		await process_frame

	# Init registry (lazy)
	if not _registry:
		var reg_script = load(REGISTRY_PATH)
		_registry = reg_script.new()

	# Run steps
	var all_ok: bool = true
	for i in range(scenario.steps.size()):
		var step: Dictionary = scenario.steps[i]
		var tool: String = step.tool
		var args: Dictionary = step.get("args", {})
		var result = _registry.dispatch(tool, args)

		var expect_key: String = step.get("expect_key", "")
		var expect_op: String = step.get("expect_op", "==")
		var expect_value = step.get("expect_value")

		var passed: bool = _validate(result, expect_key, expect_op, expect_value)
		var marker: String = "[OK]" if passed else "[FAIL]"

		if _verbose or not passed:
			print("  ", marker, " step ", i + 1, ": ", tool, "(", JSON.stringify(args), ")")
			if not passed:
				print("        expected ", expect_key, " ", expect_op, " ", expect_value)
				print("        got: ", _get_nested(result, expect_key))

		if not passed:
			all_ok = false

	return all_ok

## Validate a single result against expected
func _validate(result, expect_key: String, expect_op: String, expect_value) -> bool:
	var actual = _get_nested(result, expect_key)
	if actual == null and expect_value != null:
		return false

	match expect_op:
		"==": return actual == expect_value
		"!=": return actual != expect_value
		">=": return actual >= expect_value
		"<=": return actual <= expect_value
		">":  return actual > expect_value
		"<":  return actual < expect_value
		"contains":
			if actual is String and expect_value is String:
				return expect_value in actual
			if actual is Array and expect_value is String:
				return expect_value in actual
			return false
		"has_key":
			if actual is Dictionary:
				return expect_value in actual
			return false
		_:
			return actual == expect_value

## Navigate nested dicts via dot-separated keys
func _get_nested(dict, key_path: String):
	if dict == null or key_path == "":
		return dict
	if not dict is Dictionary:
		return null
	var parts: PackedStringArray = key_path.split(".")
	var current = dict
	for i in range(parts.size()):
		var key: String = parts[i]
		if current is Dictionary:
			if not key in current:
				return null
			current = current[key]
		elif current is Array:
			var idx: int = key.to_int()
			if idx < 0 or idx >= current.size():
				return null
			current = current[idx]
		else:
			return null
	return current

func _load_scenarios() -> void:
	var da = DirAccess.open(SCENARIO_DIR)
	if not da:
		print("WARNING: scenario dir not found: ", SCENARIO_DIR)
		return
	da.list_dir_begin()
	var entry: String = da.get_next()
	while entry != "":
		if entry.ends_with(".tres") and not entry.begins_with("."):
			var path: String = SCENARIO_DIR + entry
			var res = load(path)
			if res is Resource and res.get("script") != null:
				_scenarios.append(res)
		entry = da.get_next()
	da.list_dir_end()

func _filter_scenarios() -> void:
	if _filter == "":
		return
	var filtered: Array = []
	for sc in _scenarios:
		var s = sc
		var tokens: PackedStringArray = _filter.to_lower().split(",")
		for token in tokens:
			var t: String = token.strip_edges()
			if s.id.to_lower().contains(t) or s.description.to_lower().contains(t):
				filtered.append(s)
				break
	_scenarios = filtered

func _is_enabled(id: String) -> bool:
	var cfg = ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		return cfg.get_value("scenarios", id, true)
	return true

func _list_scenarios() -> void:
	_load_scenarios()
	print("Available MCP test scenarios:")
	for sc in _scenarios:
		var s = sc
		var renderer: String = " [renderer]" if s.requires_renderer else ""
		print("  ", s.id, renderer, ": ", s.description, " (", s.steps.size(), " steps)")

func _parse_args() -> void:
	var all_args: PackedStringArray = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())

	for arg in all_args:
		if arg == "--mcp-test-verbose":
			_verbose = true
		elif arg == "--mcp-test-list":
			_list_only = true
		elif arg == "--mcp-test-headless":
			push_error("--mcp-test-headless is forbidden for MCP live testing")
			_argument_error = true
		elif arg.begins_with("--mcp-test-filter="):
			_filter = arg.trim_prefix("--mcp-test-filter=")