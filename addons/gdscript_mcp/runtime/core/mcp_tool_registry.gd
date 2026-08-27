extends RefCounted
class_name McpToolRegistry

## McpToolRegistry — Central tool collection and dispatch.
## Each module (Vision, Debug, RuntimeTools, UxPipeline, E2E) provides:
##   static get_tool_defs() → Array   (tool schemas)
##   dispatch_tool(name, args) → Variant  (instance method)
##   dispatch_async(name, args) → Variant (instance, for async tools)
##
## The registry lazily loads modules, collects all tool defs,
## and routes dispatch by tool-name prefix convention.

const RUNTIME_TOOLS_PATH := "res://addons/gdscript_mcp/runtime/tools/runtime/mcp_runtime_tools.gd"
const VISION_PATH := "res://addons/gdscript_mcp/runtime/tools/vision/mcp_vision.gd"
const DEBUG_PATH := "res://addons/gdscript_mcp/runtime/tools/debug/mcp_debug.gd"
const UX_PATH := "res://addons/gdscript_mcp/runtime/tools/ux/mcp_ux_pipeline.gd"
const E2E_PATH := "res://addons/gdscript_mcp/runtime/tools/e2e/mcp_e2e.gd"
const PLAYTHROUGH_PATH := "res://addons/gdscript_mcp/runtime/tools/e2e/mcp_playthrough_tools.gd"
const GAME_SYSTEMS_PATH := "res://addons/gdscript_mcp/runtime/tools/systems/mcp_audio_tools.gd"
const GAMEPLAY_TOOLS_PATH := "res://addons/gdscript_mcp/runtime/tools/gameplay/mcp_gameplay_tools.gd"
const CUSTOM_LOADER_PATH := "res://addons/gdscript_mcp/runtime/core/mcp_custom_tool_loader.gd"
const CODE_ANALYZER_PATH := "res://addons/gdscript_mcp/runtime/tools/e2e/mcp_code_analyzer.gd"
const GOAL_PLAYER_PATH := "res://addons/gdscript_mcp/runtime/tools/e2e/mcp_goal_player.gd"
const AUTONOMY_PLANNER_PATH := "res://addons/gdscript_mcp/runtime/autonomy/mcp_capability_planner.gd"
const AUTONOMY_CONTRACTS_PATH := "res://addons/gdscript_mcp/runtime/autonomy/mcp_autonomy_contracts.gd"
const CHAIN_CONTROLLER_PATH := "res://addons/gdscript_mcp/runtime/autonomy/mcp_chain_controller.gd"

var _role := "runtime"
var _worker: Node = null
var _runtime_tools: RefCounted = null
var _vision: RefCounted = null
var _debug: RefCounted = null
var _ux: RefCounted = null
var _e2e: RefCounted = null
var _playthrough: RefCounted = null
var _game_systems: RefCounted = null
var _gameplay: RefCounted = null
var _custom_loader: RefCounted = null
var _chain_host_dispatch: Callable = Callable()


## Der Server meldet sich als Host-Tool-Dispatcher für Chain-Steps
## (runtime_mcp_status, runtime_agent_activity, editor_logs_read & Co. leben
## nicht in der Registry). Wird an den Chain-Controller weitergereicht —
## auch nachträglich, falls der Controller lazy erst später entsteht.
func set_chain_host_dispatch(dispatch: Callable) -> void:
	_chain_host_dispatch = dispatch
	if _chain_controller != null and _chain_controller.has_method("set_host_dispatch"):
		_chain_controller.set_host_dispatch(dispatch)
var _code_analyzer: RefCounted = null
var _goal_player: RefCounted = null
var _autonomy_planner: RefCounted = null
var _autonomy_contracts: RefCounted = null
var _chain_controller: RefCounted = null
var _tools: Array = []
var _context_store: RefCounted = null
var _loaded := false
var _autonomy_writes := false
var _lifecycle: RefCounted = null


func set_role(role: String) -> void:
	_role = role if role != "" else "runtime"


func set_worker(worker: Node) -> void:
	_worker = worker
	if _vision != null and _vision.has_method("set_worker"):
		_vision.set_worker(worker)


func set_lifecycle(lifecycle: RefCounted) -> void:
	_lifecycle = lifecycle
	if _ux != null and _ux.has_method("set_lifecycle"):
		_ux.set_lifecycle(lifecycle)


func set_autonomy_writes(enabled: bool) -> void:
	_autonomy_writes = enabled
	if _autonomy_planner != null and _autonomy_planner.has_method("set_mutations_allowed"):
		_autonomy_planner.set_mutations_allowed(enabled)


func get_autonomy_writes() -> bool:
	return _autonomy_writes


func get_runtime_status() -> Dictionary:
	var result: Dictionary = {"role": _role}
	if _runtime_tools != null and _runtime_tools.has_method("get_input_status"):
		result["input"] = _runtime_tools.get_input_status()
	if _vision != null and _vision.has_method("worker_status"):
		result["vision_worker"] = _vision.worker_status()
	return result


func set_context_store(store: RefCounted) -> void:
	_context_store = store
	if _vision != null and _vision.has_method("set_context_store"):
		_vision.set_context_store(store)
	if _ux != null and _ux.has_method("set_context_store"):
		_ux.set_context_store(store)


func get_autonomy_planner() -> RefCounted:
	if not _loaded:
		_load_all()
	return _autonomy_planner


func get_watch_status() -> Dictionary:
	if _ux != null and _ux.has_method("get_watch_status"):
		return _ux.get_watch_status()
	return {}


func tick(delta: float, visual_allowed: bool = true) -> void:
	if _ux != null and _ux.has_method("tick"):
		_ux.tick(delta, visual_allowed)


## Collect all tool definitions from all modules.
func get_all_tools() -> Array:
	if not _loaded:
		_load_all()
	return _tools


## Dispatch a tool call to the correct module.
## Returns the result Variant (Dictionary or error).
func dispatch(tool_name: String, args: Dictionary) -> Variant:
	if not _loaded:
		_load_all()

	var name: String = tool_name

	# Runtime tools (scene tree, input, eval, inspector)
	if _is_runtime_tool(name) and _runtime_tools:
		return _runtime_tools.dispatch_tool(name, args)

	# Vision tools (screenshot, pixel, color, template, detect, grid)
	if _is_vision_tool(name) and _vision:
		return _vision.dispatch_tool(name, args)

	# Debug tools (perf, engine info, project, files, memory, profile)
	if _is_debug_tool(name) and _debug:
		return _debug.dispatch_tool(name, args)

	# UX pipeline tools (analyze, scan, find, read, click)
	if _is_ux_tool(name) and _ux:
		return _ux.dispatch_tool(name, args)

	# E2E playability scenarios (list/run)
	if _is_e2e_tool(name) and _e2e:
		return _e2e.dispatch_tool(name, args)

	# Playthrough archive/API (success store, presets, frames)
	if _is_playthrough_tool(name) and _playthrough:
		return _playthrough.dispatch_tool(name, args)

	# Game systems (audio, animation, network, gamepad, shader, particles)
	if _is_game_system_tool(name) and _game_systems:
		return _game_systems.dispatch_tool(name, args)

	# Gameplay domain bridge (GameState query/steer: game_*)
	if _is_gameplay_tool(name) and _gameplay:
		return _gameplay.dispatch_tool(name, args)

	# Custom tools (hot-reload from res://mcp_tools/)
	if name.begins_with("custom_") and _custom_loader:
		return McpCustomToolLoader.dispatch(name, args)

	# Code Analyzer (static project analysis)
	if _is_code_analyzer_tool(name) and _code_analyzer:
		return _code_analyzer.dispatch_tool(name, args)

	# Goal Player (autonomous playtesting)
	if _is_goal_player_tool(name) and _goal_player:
		return _goal_player.dispatch_tool(name, args)

	# Chain Controller (declarative test and feature chains)
	if _is_chain_controller_tool(name) and _chain_controller:
		return _chain_controller.dispatch_tool(name, args)

	# Autonomy planner (Slice A, read-only capability contracts)
	if _is_autonomy_tool(name) and _autonomy_planner:
		return _autonomy_planner.dispatch_tool(name, args)

	return {"error": "Unknown tool: " + tool_name}


## Dispatch async tool.
func dispatch_async(tool_name: String, args: Dictionary) -> Variant:
	if not _loaded:
		_load_all()

	var name: String = tool_name

	if _is_runtime_tool(name) and _runtime_tools:
		return await _runtime_tools.dispatch_async(name, args)

	if _is_vision_tool(name) and _vision:
		return await _vision.dispatch_async(name, args)

	if _is_ux_tool(name) and _ux:
		return await _ux.dispatch_async(name, args)

	if _is_e2e_tool(name) and _e2e:
		return await _e2e.dispatch_async(name, args)

	if _is_playthrough_tool(name) and _playthrough:
		return await _playthrough.dispatch_async(name, args)

	# Custom tools async dispatch
	if name.begins_with("custom_") and _custom_loader:
		# Custom loader dispatch is sync, but we support await for forward-compat
		return McpCustomToolLoader.dispatch(name, args)

	# Goal Player async (runtime_goal_play)
	if _is_goal_player_tool(name) and _goal_player:
		return await _goal_player.dispatch_async(name, args)

	# Chain Controller async (runtime_chain_run)
	if _is_chain_controller_tool(name) and _chain_controller:
		return await _chain_controller.dispatch_async(name, args)

	# Autonomy planner async probe
	if _is_autonomy_tool(name) and _autonomy_planner:
		return await _autonomy_planner.dispatch_async(name, args)

	# Gameplay tools are synchronous; serve them on the async path too so
	# clients that always await never see "Unknown async tool".
	if _is_gameplay_tool(name) and _gameplay:
		return _gameplay.dispatch_tool(name, args)

	return {"error": "Unknown async tool: " + tool_name}


# ═══════════════════════════════════════════════════════════════
# Prefix-based routing
# ═══════════════════════════════════════════════════════════════

static func _is_runtime_tool(name: String) -> bool:
	return name in [
		"runtime_get_scene_tree", "runtime_find_node", "runtime_click",
		"runtime_drag", "runtime_key", "runtime_key_gesture", "runtime_mouse_move", "runtime_scroll", "runtime_virtual_mouse_status",
		"runtime_get_ui_state", "runtime_wait_frames", "runtime_wait_ms",
		"runtime_eval", "runtime_inspect_node", "runtime_find_nodes_by_type",
		"runtime_node_ancestry",
		"runtime_freeze", "runtime_unfreeze", "runtime_step_frame", "runtime_step_frames", "runtime_freeze_status",
		"runtime_camera_move_to",
	]


static func _is_vision_tool(name: String) -> bool:
	return name in [
		"runtime_screenshot", "runtime_get_pixel", "runtime_get_pixel_region",
		"runtime_find_color", "runtime_find_all_colors", "runtime_count_color_pixels",
		"runtime_image_diff", "runtime_wait_for_stable", "runtime_frame_changed",
		"runtime_find_template", "runtime_find_template_all", "runtime_detect_rects",
		"runtime_detect_text_regions", "runtime_sample_grid", "runtime_dominant_color",
		"runtime_context_list", "runtime_context_release", "runtime_context_cleanup",
		"runtime_vision_worker_status", "runtime_vision_worker_analyze",
		"runtime_vision_worker_ocr", "runtime_vision_worker_compare",
	]


static func _is_debug_tool(name: String) -> bool:
	return name in [
		"runtime_perf_metrics", "runtime_rendering_stats", "runtime_engine_info",
		"runtime_frame_timing", "runtime_project_config", "runtime_list_files",
		"runtime_class_info", "runtime_resource_uid", "runtime_event_log",
		"runtime_object_counts", "runtime_memory_info", "runtime_profile",
	]


static func _is_ux_tool(name: String) -> bool:
	return name in [
		"runtime_ux_analyze", "runtime_ux_scan", "runtime_ux_find",
		"runtime_ux_read", "runtime_ux_click", "runtime_ux_watch_start",
		"runtime_ux_watch_stop", "runtime_ux_watch_state", "runtime_ux_snapshot",
		"runtime_ux_logs",
	]


static func _is_e2e_tool(name: String) -> bool:
	return name in ["runtime_e2e_list", "runtime_e2e_run"]


static func _is_playthrough_tool(name: String) -> bool:
	return name.begins_with("runtime_playthrough_")


static func _is_gameplay_tool(name: String) -> bool:
	return name.begins_with("game_")


static func _is_game_system_tool(name: String) -> bool:
	return name in [
		"runtime_audio_play", "runtime_audio_stop", "runtime_audio_bus_info",
		"runtime_audio_set_volume", "runtime_audio_list_streams", "runtime_audio_set_stream",
		"runtime_audio_analyze", "runtime_audio_slice_auto",
		"runtime_audio_render_evidence", "runtime_audio_compare", "runtime_audio_review",
		"runtime_animation_list", "runtime_animation_play", "runtime_animation_stop",
		"runtime_animation_seek", "runtime_animation_get_info",
		"runtime_animation_tree_travel", "runtime_animation_tree_set_param",
		"runtime_gamepad_button", "runtime_gamepad_axis",
		"runtime_touch_event", "runtime_touch_drag",
		"runtime_shader_set_param", "runtime_particles_config",
		"runtime_network_create_server", "runtime_network_create_client",
		"runtime_network_disconnect", "runtime_network_get_peers",
		"runtime_network_send_rpc",
	]


static func _is_code_analyzer_tool(name: String) -> bool:
	return name in [
		"runtime_analyze_project", "runtime_analyze_input",
		"runtime_analyze_signals", "runtime_analyze_game_state",
	]


static func _is_autonomy_tool(name: String) -> bool:
	return name.begins_with("runtime_autonomy_")


static func _is_chain_controller_tool(name: String) -> bool:
	return name in ["runtime_chain_run", "runtime_chain_trace", "runtime_chain_validate"]


static func _is_goal_player_tool(name: String) -> bool:
	return name in [
		"runtime_goal_play", "runtime_goal_sequence", "runtime_goal_check", "runtime_goal_history",
	]


# ═══════════════════════════════════════════════════════════════
# Lazy loading
# ═══════════════════════════════════════════════════════════════

func _load_all() -> void:
	_tools = []
	# _loaded MUSS vor setup() gesetzt sein: setup() → _refresh_catalog() →
	# get_all_tools() würde sonst _load_all() erneut aufrufen (Endlosrekursion).
	_loaded = true
	if _role == "editor":
		_load_editor_autonomy_tools()
	else:
		_load_runtime_modules()
	_finalize_registry()


func _load_editor_autonomy_tools() -> void:
	if ResourceLoader.exists(AUTONOMY_PLANNER_PATH):
		var editor_planner_script = load(AUTONOMY_PLANNER_PATH)
		if editor_planner_script != null:
			_autonomy_planner = editor_planner_script.new()
			var editor_autonomy_defs = _autonomy_planner.get_tool_defs() if _autonomy_planner != null else []
			if editor_autonomy_defs is Array:
				_tools.append_array(editor_autonomy_defs)


func _load_runtime_modules() -> void:
	if ResourceLoader.exists(VISION_PATH):
		var vs = load(VISION_PATH)
		if vs:
			_vision = vs.new()
			var td = vs.get_tool_defs()
			if td is Array: _tools.append_array(td)

	if ResourceLoader.exists(DEBUG_PATH):
		var ds = load(DEBUG_PATH)
		if ds:
			_debug = ds.new()
			var td = ds.get_tool_defs()
			if td is Array: _tools.append_array(td)

	if ResourceLoader.exists(RUNTIME_TOOLS_PATH):
		var rs = load(RUNTIME_TOOLS_PATH)
		# can_instantiate() is false for scripts with parse errors — calling
		# new() on those raises and ABORTS _load_all, silently unregistering
		# every module loaded after the broken one.
		if rs != null and rs.can_instantiate():
			_runtime_tools = rs.new()
			var td = rs.get_tool_defs()
			if td is Array: _tools.append_array(td)
		else:
			# Editor-Start-Race: load() liefert das Skript ggf. vor Abschluss des
			# asynchronen Skriptserver-Compiles (Cache-Eintrag vergeben, aber noch
			# nicht kompilierbar). CACHE_MODE_IGNORE lädt frisch aus dem Quelltext —
			# deterministisch und ohne die "Another resource is loaded"-Kollision,
			# die GDScript.new() + manuelles resource_path erzeugt (das Skript ist
			# über class_name McpRuntimeTools bereits im ResourceCache registriert).
			var fresh: Resource = ResourceLoader.load(RUNTIME_TOOLS_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
			if fresh != null and fresh.can_instantiate():
				_runtime_tools = fresh.new()
				var fresh_defs = fresh.get_tool_defs()
				if fresh_defs is Array:
					_tools.append_array(fresh_defs)
			else:
				push_warning("McpToolRegistry: %s cannot be instantiated — runtime tools unavailable" % RUNTIME_TOOLS_PATH)

	if ResourceLoader.exists(UX_PATH):
		var us = load(UX_PATH)
		if us:
			_ux = us.new()
			var td = us.get_tool_defs()
			if td is Array:
				_tools.append_array(td)

	if ResourceLoader.exists(E2E_PATH):
		var es = load(E2E_PATH)
		if es:
			_e2e = es.new()
			if _e2e.has_method("setup"):
				_e2e.setup(self)
			var td = es.get_tool_defs()
			if td is Array:
				_tools.append_array(td)

	if ResourceLoader.exists(PLAYTHROUGH_PATH):
		var ps = load(PLAYTHROUGH_PATH)
		if ps:
			_playthrough = ps.new()
			if _playthrough.has_method("set_registry"):
				_playthrough.set_registry(self)
			var td = ps.get_tool_defs()
			if td is Array:
				_tools.append_array(td)

	if ResourceLoader.exists(GAME_SYSTEMS_PATH):
		var gs = load(GAME_SYSTEMS_PATH)
		if gs:
			var instance = gs.new()
			if instance != null:
				_game_systems = instance
				var td = gs.get_tool_defs()
				if td is Array:
					_tools.append_array(td)

	if ResourceLoader.exists(GAMEPLAY_TOOLS_PATH):
		var gp_tools = load(GAMEPLAY_TOOLS_PATH)
		if gp_tools:
			_gameplay = gp_tools.new()
			var td = gp_tools.get_tool_defs()
			if td is Array:
				_tools.append_array(td)

	if ResourceLoader.exists(CUSTOM_LOADER_PATH):
		var cs = load(CUSTOM_LOADER_PATH)
		if cs:
			var instance = cs.new()
			if instance != null:
				_custom_loader = instance
				var td := McpCustomToolLoader.discover_tools()
				if not td.is_empty():
					_tools.append_array(td)

	if ResourceLoader.exists(CODE_ANALYZER_PATH):
		var ca = load(CODE_ANALYZER_PATH)
		if ca:
			_code_analyzer = ca.new()
			var td = ca.get_tool_defs()
			if td is Array:
				_tools.append_array(td)

	if ResourceLoader.exists(AUTONOMY_PLANNER_PATH):
		var ap = load(AUTONOMY_PLANNER_PATH)
		if ap:
			_autonomy_planner = ap.new()
			var autonomy_defs = _autonomy_planner.get_tool_defs() if _autonomy_planner != null else []
			if autonomy_defs is Array:
				_tools.append_array(autonomy_defs)

	if ResourceLoader.exists(GOAL_PLAYER_PATH):
		var gp = load(GOAL_PLAYER_PATH)
		if gp:
			var instance = gp.new()
			if instance != null:
				_goal_player = instance
				if _goal_player.has_method("setup"):
					_goal_player.setup(self, _lifecycle)
			var td = gp.get_tool_defs()
			if td is Array:
				_tools.append_array(td)

	if ResourceLoader.exists(CHAIN_CONTROLLER_PATH):
		var cc = load(CHAIN_CONTROLLER_PATH)
		if cc:
			var instance = cc.new()
			if instance != null:
				_chain_controller = instance
				if _chain_controller.has_method("setup"):
					_chain_controller.setup(self, _lifecycle)
				if _chain_controller.has_method("set_host_dispatch") and _chain_host_dispatch.is_valid():
					_chain_controller.set_host_dispatch(_chain_host_dispatch)
			var td = cc.get_tool_defs()
			if td is Array:
				_tools.append_array(td)


func _finalize_registry() -> void:
	if _vision != null and _vision.has_method("set_context_store"):
		_vision.set_context_store(_context_store)
	if _vision != null and _vision.has_method("set_worker"):
		_vision.set_worker(_worker)
	if _ux != null and _ux.has_method("set_context_store"):
		_ux.set_context_store(_context_store)
	var contracts_script: Resource = load(AUTONOMY_CONTRACTS_PATH)
	if contracts_script != null:
		_autonomy_contracts = contracts_script.new()
		for index in range(_tools.size()):
			if _tools[index] is Dictionary:
				_tools[index] = McpAutonomyContracts.normalize_tool(_tools[index], "registry")
	if _autonomy_planner != null and _autonomy_planner.has_method("setup"):
		_autonomy_planner.setup(self, _lifecycle, _context_store)
	if _autonomy_planner != null and _autonomy_planner.has_method("set_mutations_allowed"):
		_autonomy_planner.set_mutations_allowed(_autonomy_writes)
	if _ux != null and _ux.has_method("set_lifecycle"):
		_ux.set_lifecycle(_lifecycle)
