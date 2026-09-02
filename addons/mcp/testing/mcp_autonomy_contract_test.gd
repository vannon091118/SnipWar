extends SceneTree

## Slice-A contract test. This is a contract/probe test only; it does not count
## as the required visible FULL_MCP_PASS until run through a live MCP session.

const CONTRACTS_PATH := "res://addons/gdscript_mcp/runtime/autonomy/mcp_autonomy_contracts.gd"
const PLANNER_PATH := "res://addons/gdscript_mcp/runtime/autonomy/mcp_capability_planner.gd"

var _failed := 0

class ContractRegistry extends RefCounted:
	var definitions: Array = [
		{
			"name": "runtime_mcp_status",
			"description": "status",
			"inputSchema": {"type": "object", "properties": {}},
		},
		{
			"name": "runtime_ux_scan",
			"description": "scan",
			"inputSchema": {"type": "object", "properties": {}},
		},
	]

	func get_all_tools() -> Array:
		return definitions.duplicate(true)


func _init() -> void:
	_run()


func _run() -> void:
	var contracts_script: Resource = load(CONTRACTS_PATH)
	var planner_script: Resource = load(PLANNER_PATH)
	_check(contracts_script != null, "contracts script loads")
	_check(planner_script != null, "planner script loads")
	if _failed > 0:
		_finish()
		return

	var contracts: RefCounted = contracts_script.new()
	var read_tool: Dictionary = contracts.normalize_tool({
		"name": "runtime_mcp_status",
		"description": "status",
		"inputSchema": {"type": "object", "properties": {}},
	})
	_check(bool(read_tool.get("metadata_valid", false)), "read tool metadata is valid")
	_check(str(read_tool.get("access", "")) == "read", "status is read-only")
	_check(not bool(read_tool.get("mutates", true)), "status cannot mutate")
	_check(contracts.validate_tool_metadata(read_tool).is_empty(), "valid metadata has no errors")

	var invalid: Dictionary = contracts.normalize_tool({
		"name": "broken_tool",
		"inputSchema": {"type": "object", "properties": {}},
		"mutates": true,
		"rollback": "none",
	})
	_check(not bool(invalid.get("metadata_valid", true)), "invalid mutation metadata is rejected")
	_check(not contracts.validate_tool_metadata(invalid).is_empty(), "invalid metadata reports errors")

	var registry: RefCounted = ContractRegistry.new()
	var planner: RefCounted = planner_script.new()
	planner.setup(registry, null, null)
	var blocked: Dictionary = planner.plan("nonexistent capability", ["never_produced"], "headless", false)
	_check(str(blocked.get("verdict", "")) == "BLOCKED", "unavailable capability is blocked")
	_check(not bool(blocked.get("rollback", {}).get("mutations", true)), "blocked receipt reports no mutation")
	var status_plan: Dictionary = planner.plan("lifecycle_observation", [], "headless", false)
	_check(str(status_plan.get("verdict", "")) == "PASS", "available output selects a tool")
	_check(not status_plan.get("steps", []).is_empty(), "selection contains a machine-readable step")
	_check(status_plan.get("steps", [])[0].has("postconditions"), "step contains postconditions")
	_check(status_plan.get("steps", [])[0].has("evidence"), "step contains evidence")

	print("Slice-A autonomy contract test: %d failure(s)" % _failed)
	_finish()


func _finish() -> void:
	quit(1 if _failed > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] " + description)
	else:
		print("[FAIL] " + description)
		_failed += 1
