extends SceneTree

## McpPlaythroughDriver — visible, in-engine E2E playthrough runner.
##
## Runs McpE2E scenarios against the LIVE game with the real renderer in a
## window (never headless). Because --script SceneTree scripts do NOT load the
## main scene automatically, the driver instantiates the main menu itself, then
## feeds the exact same tool calls an external MCP agent would issue.
##
## Usage (windowed, from project root):
##   $GODOT_BIN --path . --script res://addons/gdscript_mcp/testing/e2e/mcp_playthrough_driver.gd
##   $GODOT_BIN --path . --script ... --mcp-e2e=new_game_to_world
##   $GODOT_BIN --path . --script ... --mcp-e2e-list

const MAIN_MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"  # Default (SnipWar). Konfigurierbar über application/mcp/main_menu_scene.
const E2E_PATH := "res://addons/gdscript_mcp/runtime/tools/e2e/mcp_e2e.gd"
const REGISTRY_PATH := "res://addons/gdscript_mcp/runtime/core/mcp_tool_registry.gd"
const INPUT_SCHEDULER_PATH := "res://addons/gdscript_mcp/runtime/tools/runtime/mcp_input_scheduler.gd"

var _scenario := "main_menu"
var _list_only := false
var _virtual_mouse_scheduler: Node


func _initialize() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--mcp-e2e-list":
			_list_only = true
		elif arg.begins_with("--mcp-e2e="):
			_scenario = arg.trim_prefix("--mcp-e2e=")


func _init() -> void:
	# Deferred so the main loop is ready (autoloads are available; waiting for
	# the first frame guarantees the window exists).
	call_deferred("_run")


func _run() -> void:
	if OS.has_feature("headless") or "--headless" in OS.get_cmdline_args():
		push_error("MCP playthrough requires a visible renderer; headless mode is forbidden")
		quit(2)
		return
	await process_frame
	await process_frame
	_activate_virtual_mouse()

	var e2e_script: Resource = load(E2E_PATH)
	if e2e_script == null:
		push_error("E2E module not found: " + E2E_PATH)
		quit(1)
		return
	var registry_script: Resource = load(REGISTRY_PATH)
	if registry_script == null:
		push_error("Registry script not found")
		quit(1)
		return
	var registry: RefCounted = registry_script.new()
	var e2e: RefCounted = e2e_script.new()
	e2e.setup(registry)

	if _list_only:
		for scenario in e2e.list_scenarios():
			print("- " + str(scenario.get("id", "?")) + ": " + str(scenario.get("description", "")))
		quit(0)
		return

	var main_menu_scene := _resolve_main_menu_scene()
	var packed: PackedScene = load(main_menu_scene)
	if packed == null:
		push_error("Main menu scene not found: " + main_menu_scene)
		quit(1)
		return
	root.add_child(packed.instantiate())
	await process_frame
	await process_frame

	print("Starting E2E playthrough in windowed mode. Watch the game window!")
	var result: Dictionary = await e2e.run_scenario(_scenario)
	_deactivate_virtual_mouse()
	quit(0 if bool(result.get("ok", false)) else 1)


func _activate_virtual_mouse() -> void:
	var scheduler_script: Resource = load(INPUT_SCHEDULER_PATH)
	if scheduler_script == null:
		return
	_virtual_mouse_scheduler = scheduler_script.new() as Node
	if _virtual_mouse_scheduler == null:
		return
	_virtual_mouse_scheduler.name = "McpInputScheduler"
	root.add_child(_virtual_mouse_scheduler)
	_virtual_mouse_scheduler.call("activate_virtual_mouse", "visible_e2e", Vector2(-1.0, -1.0), true, true)


func _deactivate_virtual_mouse() -> void:
	if _virtual_mouse_scheduler != null and is_instance_valid(_virtual_mouse_scheduler):
		_virtual_mouse_scheduler.call("deactivate_virtual_mouse")
	_virtual_mouse_scheduler = null


## Löst den Hauptmenü-Szenen-Pfad projektagnostisch auf.
## Default: SnipWar (res://scenes/main_menu/main_menu.tscn). Andere Projekte
## setzen application/mcp/main_menu_scene in project.godot.
static func _resolve_main_menu_scene() -> String:
	var configured := str(ProjectSettings.get_setting("application/mcp/main_menu_scene", MAIN_MENU_SCENE))
	if configured.begins_with("res://"):
		return configured
	return MAIN_MENU_SCENE