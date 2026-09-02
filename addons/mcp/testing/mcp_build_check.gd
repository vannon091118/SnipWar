extends SceneTree

## Build-time parse check for MCP modules (autonomy + dock + runtime client).
## Usage: godot --headless --path . --script res://addons/.../mcp_build_check.gd

const FILES := [
	"res://addons/mcp/runtime/autonomy/mcp_path_validator.gd",
	"res://addons/mcp/runtime/autonomy/mcp_workspace_journal.gd",
	"res://addons/mcp/runtime/autonomy/mcp_project_tools.gd",
	"res://addons/mcp/runtime/autonomy/mcp_contract_gate.gd",
	"res://addons/mcp/runtime/autonomy/mcp_autonomy_contracts.gd",
	"res://addons/mcp/runtime/autonomy/mcp_capability_planner.gd",
	"res://addons/mcp/runtime/autonomy/mcp_chain_controller.gd",
	"res://addons/mcp/runtime/core/mcp_tool_registry.gd",
	"res://addons/mcp/runtime/core/mcp_custom_tool_loader.gd",
	"res://addons/mcp/runtime/context/mcp_context_store.gd",
	"res://addons/mcp/runtime/host/mcp_server.gd",
	"res://addons/mcp/runtime/host/mcp_runtime.gd",
	"res://addons/mcp/runtime/lifecycle/mcp_lifecycle.gd",
	"res://addons/mcp/runtime/protocol/mcp_protocol.gd",
	"res://addons/mcp/runtime/tools/runtime/mcp_runtime_tools.gd",
	"res://addons/mcp/runtime/tools/runtime/mcp_input_scheduler.gd",
	"res://addons/mcp/runtime/tools/e2e/mcp_goal_player.gd",
	"res://addons/mcp/runtime/tools/e2e/mcp_e2e.gd",
	"res://addons/mcp/runtime/tools/gameplay/mcp_gameplay_tools.gd",
	"res://addons/mcp/runtime/tools/ux/mcp_ux_pipeline.gd",
	"res://addons/mcp/runtime/tools/vision/mcp_vision.gd",
	"res://addons/mcp/editor/gdscript_mcp_plugin.gd",
	"res://addons/mcp/editor/mcp_dock.gd",
	"res://addons/mcp/editor/mcp_runtime_client.gd",
	"res://addons/mcp/runtime/tools/agent/mcp_agent_activity.gd",
	"res://addons/mcp/testing/mcp_player_contract_test.gd",
]


func _init() -> void:
	var failed := false
	for path in FILES:
		var resource: Resource = load(path)
		if resource == null or not resource.can_instantiate():
			print("[FAIL] " + path)
			failed = true
		else:
			print("[OK]   " + path)
	quit(1 if failed else 0)
