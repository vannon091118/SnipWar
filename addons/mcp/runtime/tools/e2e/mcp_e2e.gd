extends RefCounted
class_name McpE2E

## McpE2E — Playability test runner for the MCP server (remote testing scope).
##
## Runs named playthrough scenarios against the LIVE game, entirely visible:
## every step (click, key, screenshot, analysis, log read) happens in-engine and
## is printed to the console so a human watching the window sees exactly what
## an agent would do remotely. Results + anomalies (EventLog errors/warnings)
## are collected per scenario.

const ARCHIVE_PATH := "res://addons/mcp/runtime/context/mcp_playthrough_archive.gd"

var _registry: RefCounted
var _archive: RefCounted
var _results: Array[Dictionary] = []


func setup(registry: RefCounted) -> void:
	_registry = registry
	var archive_script: Resource = load(ARCHIVE_PATH)
	if archive_script:
		_archive = archive_script.new()


## List available E2E scenarios.
func list_scenarios() -> Array:
	return [
		{"id": "main_menu", "description": "MainMenu: buttons visible, NEUES SPIEL click", "steps": 3},
		{"id": "new_game_to_world", "description": "NEUES SPIEL -> World: PlanetField boots", "steps": 4},
		{"id": "pause_save_menu", "description": "World: ESC -> PauseMenu, SPEICHERN, HAUPTMENU", "steps": 8},
		{"id": "virtual_mouse_edges", "description": "MCP input isolation: virtual mouse activation, bounds and invalid input", "steps": 6},
		{"id": "freeze_step", "description": "Deterministic: freeze -> click -> step_frame -> verify paused again", "steps": 7},
		{"id": "analyze_and_goal", "description": "Code Analyzer scans project + Goal Player evaluates expressions", "steps": 6},
	]


## Run the named scenario. Every action is visible in-engine; steps await
## process frames/timers internally so the window shows the whole playthrough.
func run_scenario(scenario_id: String) -> Dictionary:
	_results.clear()
	var start_ms := Time.get_ticks_msec()
	_info("### E2E SCENARIO: " + scenario_id)

	var ok := true
	match scenario_id:
		"main_menu":
			ok = await _scenario_main_menu()
		"new_game_to_world":
			ok = await _scenario_new_game_to_world()
		"pause_save_menu":
			ok = await _scenario_pause_save_menu()
		"virtual_mouse_edges":
			ok = await _scenario_virtual_mouse_edges()
		"freeze_step":
			ok = await _scenario_freeze_step()
		"analyze_and_goal":
			ok = await _scenario_analyze_and_goal()
		_:
			ok = false
			_results.append({"status": "FAIL", "description": "unknown scenario", "detail": scenario_id})

	var elapsed := float(Time.get_ticks_msec() - start_ms) / 1000.0
	var failures := _results.filter(func(r): return r.get("status") == "FAIL")
	var succeeded := ok and failures.is_empty()
	var verdict := "PASS" if succeeded else "FAIL"
	var anomalies: Array = await _collect_anomalies()
	print("### E2E RESULT [" + scenario_id + "]: " + verdict + " | steps=" + str(_results.size()) +
		" | failures=" + str(failures.size()) + " | elapsed=" + str(elapsed).pad_decimals(1) + "s")
	for anomaly in anomalies:
		print("  [ANOMALY] " + str(anomaly.get("level", "?")) + ": " + str(anomaly.get("message", anomaly)))
	if succeeded:
		await _archive_success(scenario_id, elapsed, _results.size(), anomalies.size())
	return {
		"scenario": scenario_id,
		"ok": succeeded,
		"verdict": verdict,
		"steps": _results.duplicate(true),
		"failures": failures.size(),
		"anomalies": anomalies,
		"elapsed_seconds": elapsed,
	}


# ═══════════════════════════════════════════════════════════════════════════
# Scenarios
# ═══════════════════════════════════════════════════════════════════════════

func _scenario_main_menu() -> bool:
	var ok := true
	var analysis: Dictionary = await _collect_step(true)
	ok = _check("main_menu", "scene", analysis.get("scene", ""), "main_menu") and ok
	ok = _check("main_menu", "has >=2 interactables", (analysis.get("interactables", []) as Array).size() >= 2, true) and ok
	var find_btn: Variant = _call("runtime_ux_find", {"description": "Neues Spiel"})
	ok = _check("main_menu", "button 'Neues Spiel' findable", bool(find_btn.get("found", false)), true) and ok
	return ok


func _scenario_new_game_to_world() -> bool:
	var ok := true
	var find_btn := _find("Neues Spiel")
	if not bool(find_btn.get("found", false)):
		return _check("new_game", "button found before click", false, true) and false
	var clicked: Variant = await _call_async("runtime_ux_click", {"description": "Neues Spiel"})
	ok = _check("new_game", "NEUES SPIEL clicked", bool(clicked.get("clicked", false)), true) and ok
	await _wait_for("scene", "game_view", 20)
	var world: Dictionary = await _collect_step(true)
	ok = _check("new_game", "world scene loaded", str(world.get("scene", "")) == "game_view", true) and ok
	ok = _check("new_game", "PlanetField exists", _node_exists("PlanetField"), true) and ok
	return ok

func _scenario_pause_save_menu() -> bool:
	if not await _ensure_main_menu():
		return false
	var world_ok := await _scenario_new_game_to_world()
	if not world_ok:
		return false
	var ok := true
	var esc: Variant = _call("runtime_key", {"keycode": KEY_ESCAPE, "pressed": true})
	ok = _check("pause", "ESC sent", bool(esc.get("sent", false)), true) and ok
	_call("runtime_key", {"keycode": KEY_ESCAPE, "pressed": false})
	await _wait_ms(1500)
	var pause_content_visible := _node_visible("PauseMenu/Content")
	ok = _check("pause", "PauseMenu visible", pause_content_visible, true) and ok
	if not pause_content_visible:
		_info("  [DIAG] PauseMenu/Content not visible — checking PauseMenu node directly")
		var tree := Engine.get_main_loop()
		if tree is SceneTree:
			var root := (tree as SceneTree).root
			var pm := root.find_child("PauseMenu", true, false)
			_info("  [DIAG] PauseMenu node: " + str(pm) + " paused=" + str((tree as SceneTree).paused))
	var save := _find("SPEICHERN")
	if bool(save.get("found", false)):
		var saved: Variant = await _call_async("runtime_ux_click", {"description": "SPEICHERN"})
		ok = _check("pause", "SPEICHERN clicked", bool(saved.get("clicked", false)), true) and ok
	else:
		ok = _check("pause", "SPEICHERN button visible", false, true) and ok
	await _wait_ms(1000)
	var menu := _find("HAUPTMEN")
	if bool(menu.get("found", false)):
		var menu_click: Variant = await _call_async("runtime_ux_click", {"description": "HAUPTMEN"})
		ok = _check("pause", "HAUPTMENU clicked", bool(menu_click.get("clicked", false)), true) and ok
		# PauseMenu._on_menu_pressed() calls set_paused(false) then
		# SceneDirectorService.goto_scene("menu") with a 600 ms fade.
		# Guard: force-unpause in case the deferred switch inherits stale state.
		await _wait_ms(500)
		var tree := Engine.get_main_loop()
		if tree is SceneTree and (tree as SceneTree).paused:
			(tree as SceneTree).paused = false
		await _wait_ms(3500)
	else:
		ok = _check("pause", "HAUPTMENU button visible", false, true) and ok
	var scan: Variant = _call("runtime_ux_scan", {})
	var scene_name := str(scan.get("scene", "")) if scan is Dictionary else ""
	if scene_name != "main_menu":
		_info("  [DIAG] still at scene='" + scene_name + "' after menu click — tree paused=" + str(_is_tree_paused()))
	ok = _check("pause", "back at main menu", scene_name, "main_menu") and ok
	return ok


func _is_tree_paused() -> bool:
	var tree := Engine.get_main_loop()
	return (tree as SceneTree).paused if tree is SceneTree else false


## Input-isolation check: the MCP virtual mouse stays within viewport bounds,
## rejects invalid keys/empty find-targets, and remains active afterwards.
func _scenario_virtual_mouse_edges() -> bool:
	var ok := true
	var initial: Variant = _call("runtime_virtual_mouse_status", {})
	ok = _check("virtual_mouse", "MCP virtual mouse active", bool(initial.get("active", false)), true) and ok
	ok = _check("virtual_mouse", "physical mouse blocked", bool(initial.get("physical_mouse_blocked", false)), true) and ok
	var moved: Variant = _call("runtime_mouse_move", {"x": -100, "y": 99999})
	ok = _check("virtual_mouse", "out-of-bounds move accepted and clamped", bool(moved.get("moved", false)), true) and ok
	var status: Variant = _call("runtime_virtual_mouse_status", {})
	var position: Dictionary = status.get("position", {})
	var bounds: Dictionary = status.get("bounds", {})
	var in_bounds := float(position.get("x", -1.0)) >= 0.0 and float(position.get("y", -1.0)) >= 0.0 and float(position.get("x", -1.0)) <= float(bounds.get("x", 0.0)) and float(position.get("y", -1.0)) <= float(bounds.get("y", 0.0))
	ok = _check("virtual_mouse", "position stays within viewport bounds", in_bounds, true) and ok
	var invalid_key: Variant = _call("runtime_key", {"keycode": 0, "pressed": true})
	ok = _check("virtual_mouse", "invalid key rejected", bool(invalid_key.get("sent", false)), false) and ok
	var empty_find: Variant = _call("runtime_ux_find", {"description": ""})
	ok = _check("virtual_mouse", "empty target rejected", bool(empty_find.get("found", false)), false) and ok
	var final_status: Variant = _call("runtime_virtual_mouse_status", {})
	ok = _check("virtual_mouse", "virtual cursor state remains active", bool(final_status.get("active", false)), true) and ok
	return ok


func _scenario_freeze_step() -> bool:
	if not await _ensure_main_menu():
		return false
	var ok := true
	var tree := Engine.get_main_loop()

	# 1. Freeze the game tree.
	var freeze: Variant = _call("runtime_freeze", {})
	ok = _check("freeze", "freeze activates", bool(freeze.get("ok", false)), true) and ok
	ok = _check("freeze", "tree paused after freeze", bool(freeze.get("tree_paused", false)), true) and ok

	# 2. Queue a direct click (no UX pipeline — just raw input dispatch).
	var node_btn := _find("Neues Spiel")
	if not bool(node_btn.get("found", false)):
		return _check("freeze", "NEUES SPIEL findable", false, true) and false
	var center: Dictionary = node_btn.get("center", {})
	var clicked: Variant = _call("runtime_click", {"x": int(center.get("x", 0)), "y": int(center.get("y", 0)), "hold_frames": 2})
	ok = _check("freeze", "click queued in freeze", bool(clicked.get("clicked", false)), true) and ok

	# 3. Verify tree is STILL paused (freeze held).
	var fs1: Variant = _call("runtime_freeze_status", {})
	ok = _check("freeze", "still paused after click (freeze held)", bool(fs1.get("tree_paused", false)), true) and ok
	ok = _check("freeze", "inputs pending in queue", int(fs1.get("pending_inputs", 0)) > 0, true) and ok

	# 4. Step 40 consecutive frames — the SceneDirector's create_tween()
	#    fade (0.6s ≈ 36 frames at 60 fps) needs consecutive unpaused frames
	#    to fire its _switch_scene callback. runtime_step_frames(count) keeps
	#    the tree unpaused for `count` frames, then re-freezes automatically.
	var sr: Variant = _call("runtime_step_frames", {"count": 40})
	var total_stepped := int(sr.get("stepping", 0))
	ok = _check("freeze", "step_frames accepted", bool(sr.get("ok", false)), true) and ok

	# 5. Poll until the engine has processed the 40 frames and re-froze.
	#    runtime_step_frames returns immediately; the frames tick down over time.
	var re_frozen := false
	for _poll in range(100):
		var fs2: Variant = _call("runtime_freeze_status", {})
		if bool(fs2.get("tree_paused", false)):
			re_frozen = true
			total_stepped = int(fs2.get("frames_stepped", total_stepped))
			break
		if tree is SceneTree:
			await (tree as SceneTree).process_frame
	ok = _check("freeze", "re-frozen after stepping " + str(total_stepped) + " frames", re_frozen, true) and ok
	ok = _check("freeze", "frames counted correctly", total_stepped > 1, true) and ok

	# 6. Unfreeze — game should resume and world loads.
	var unfreeze: Variant = _call("runtime_unfreeze", {})
	ok = _check("freeze", "unfreeze accepted", bool(unfreeze.get("ok", false)), true) and ok
	ok = _check("freeze", "tree no longer paused", bool(unfreeze.get("tree_paused", false)), false) and ok
	await _wait_ms(2000)

	# 7. Verify world loaded.
	var scan: Variant = _call("runtime_ux_scan", {})
	var scene_name := str(scan.get("scene", ""))
	ok = _check("freeze", "world loaded after freeze-step flow", scene_name == "game_view", true) and ok
	ok = _check("freeze", "PlanetField exists", _node_exists("PlanetField"), true) and ok

	_info("  [FREEZE DIAG] total frames stepped: " + str(total_stepped) + " | scene: " + scene_name)
	return ok


func _scenario_analyze_and_goal() -> bool:
	if not await _ensure_main_menu():
		return false
	var ok := true

	# 1. Code Analyzer: input detection
	var input_analysis: Variant = _call("runtime_analyze_input", {})
	var input_methods: Array = input_analysis.get("_input", []) if input_analysis is Dictionary else []
	ok = _check("analyze", "_input handlers found in project", not input_methods.is_empty(), true) and ok
	var unhandled: Array = input_analysis.get("_unhandled_input", []) if input_analysis is Dictionary else []
	ok = _check("analyze", "_unhandled_input handlers found", not unhandled.is_empty(), true) and ok

	# 2. Code Analyzer: GameState API
	var gs_api: Variant = _call("runtime_analyze_game_state", {})
	var method_count := int(gs_api.get("method_count", 0)) if gs_api is Dictionary else 0
	ok = _check("analyze", "GameState public methods > 0", method_count > 0, true) and ok

	# 3. Code Analyzer: project overview
	var project: Variant = _call("runtime_analyze_project", {})
	var scenes: Array = project.get("scenes", []) if project is Dictionary else []
	ok = _check("analyze", "scenes found in project", not scenes.is_empty(), true) and ok

	# 4. Goal Player: check trivial goal
	# 4. Goal Player: check trivial goal
	var goal_check: Variant = _call("runtime_goal_check", {"goal": "1 + 1 == 2"})
	var reached := bool(goal_check.get("reached", false)) if goal_check is Dictionary else false
	ok = _check("goal", "goal_check 1+1==2 reached", reached, true) and ok

	# 5. Goal Player: goal_history responds
	var history: Variant = _call("runtime_goal_history", {"limit": 3})
	var hist_count := int(history.get("count", -1)) if history is Dictionary else -1
	ok = _check("goal", "goal_history responds", hist_count >= 0, true) and ok

	_info("  [ANALYZE DIAG] input methods: " + str(input_methods.size()) + " _input, " + str(unhandled.size()) + " _unhandled_input")
	_info("  [ANALYZE DIAG] GameState public methods: " + str(method_count) + ", scenes: " + str(scenes.size()))
	return ok

# ═══════════════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════════════

## Persist successful scenarios into the playthrough archive (action + frame +
## GameState preset) so the agent can resume a full run across sessions.
func _archive_success(scenario_id: String, elapsed: float, steps: int, anomalies: int) -> void:
	if _archive == null:
		return
	var archived: Variant = await _archive.log_success("e2e_scenario:" + scenario_id,
		{"verdict": "SOLVED", "solved_count": steps, "fail_count": 0, "steps": steps, "elapsed_s": elapsed, "anomalies": anomalies}, null)
	if archived is Dictionary and archived.get("frame", "") != "":
		_info("  [ARCHIVE] " + scenario_id + " -> " + str(archived.get("frame", "")) +
			" + preset " + str(archived.get("preset", "")))

func _call(tool: String, args: Dictionary = {}) -> Variant:
	if not _registry:
		return {"error": "no registry"}
	return _registry.dispatch(tool, args)


func _find(description: String) -> Dictionary:
	var result: Variant = _call("runtime_ux_find", {"description": description})
	return result if result is Dictionary else {}


func _collect_step(include_visual: bool) -> Dictionary:
	var r: Variant = await _call_async("runtime_ux_analyze", {"include_visual": include_visual})
	if r is Dictionary:
		return r
	return {}


func _check(group: String, desc: String, actual: Variant, expected: Variant) -> bool:
	var ok: bool = actual == expected
	_results.append({"status": "PASS" if ok else "FAIL", "description": group + ": " + desc, "detail": str(actual)})
	_info(("[OK] " if ok else "[FAIL] ") + desc + " -> " + str(actual))
	return ok


## Polls until the given predicate returns true (or scene/text/FIND matcher).
## Deterministic instead of fixed sleeps. Returns true on success within timeout.
func _wait_for(mode: String, needle: String, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var scan: Variant = _call("runtime_ux_scan", {})
		if scan is Dictionary:
			match mode:
				"text":
					for ctrl in scan.get("controls", []):
						if ctrl is Dictionary and needle in String(ctrl.get("text", "")):
							return true
				"scene":
					if str(scan.get("scene", "")) == needle:
						return true
		if mode == "control":
			var found := _find(needle)
			if bool(found.get("found", false)):
				return true
		await _wait_ms(300)
	return false


## Szenarien laufen im frischen MainMenu; falls ein vorheriger Lauf in der
## World stecken blieb, zurück über ESC → Pause → HAUPTMENÜ navigieren.
func _ensure_main_menu() -> bool:
	var scan: Variant = _call("runtime_ux_scan", {})
	if str(scan.get("scene", "")) == "main_menu":
		return true
	# Force-unpause before navigation — a paused tree freezes scene transitions.
	var tree := Engine.get_main_loop()
	if tree is SceneTree and (tree as SceneTree).paused:
		(tree as SceneTree).paused = false
	_call("runtime_key", {"keycode": KEY_ESCAPE, "pressed": true})
	_call("runtime_key", {"keycode": KEY_ESCAPE, "pressed": false})
	await _wait_ms(800)
	var menu: Variant = _call("runtime_ux_find", {"description": "HAUPTMEN"})
	if bool(menu.get("found", false)):
		await _call_async("runtime_ux_click", {"description": "HAUPTMEN"})
		await _wait_ms(500)
		if tree is SceneTree and (tree as SceneTree).paused:
			(tree as SceneTree).paused = false
		await _wait_ms(2500)
		scan = _call("runtime_ux_scan", {})
		return str(scan.get("scene", "")) == "main_menu"
	return false


## Failure diagnostics: click coordinates + all visible texts (first 30).
func _dir_texts(label: String, click_result: Variant) -> void:
	if click_result is Dictionary:
		_info("  [" + label + "] click x=" + str(click_result.get("x", "?")) + " y=" + str(click_result.get("y", "?")) +
			" mode=" + str(click_result.get("mode", "?")))
	var scan: Variant = _call("runtime_ux_scan", {})
	var texts: Array = []
	for ctrl in (scan.get("controls", []) if scan is Dictionary else []):
		if ctrl is Dictionary and String(ctrl.get("text", "")) != "":
			texts.append(String(ctrl.get("text", "")))
	_info("  [SCAN] texts (" + str(texts.size()) + "): " + str(texts.slice(0, 30)))


func _node_exists(name: String) -> bool:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return false
	var root := (tree as SceneTree).root
	return root.find_child(name, true, false) != null


func _node_visible(path: String) -> bool:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return false
	var root := (tree as SceneTree).root
	var node := root.find_child(path.get_file(), true, false)
	return node != null and node is CanvasItem and (node as CanvasItem).is_visible_in_tree()


func _wait_ms(ms: int) -> void:
	await _call_async("runtime_wait_ms", {"ms": ms})


func _call_async(tool: String, args: Dictionary) -> Variant:
	if not _registry:
		return {"error": "no registry"}
	if _registry.has_method("dispatch_async"):
		return await _registry.dispatch_async(tool, args)
	return {"error": "no async dispatch"}


func _collect_anomalies() -> Array:
	var logs: Variant = _call("runtime_ux_logs", {})
	if logs is Dictionary:
		return logs.get("anomalies", [])
	return []


func _info(msg: String) -> void:
	print(msg)


# ═══════════════════════════════════════════════════════════════════════════
# MCP Module Interface: get_tool_defs() + dispatch_tool() + dispatch_async()
# ═══════════════════════════════════════════════════════════════════════════

func dispatch_tool(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_e2e_list":
			return {"scenarios": list_scenarios(), "count": list_scenarios().size()}
		"runtime_e2e_run":
			return {"error": "runtime_e2e_run is async; use the async dispatch path"}
		_:
			return {"error": "Unknown e2e tool: " + tool_name}


func dispatch_async(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_e2e_run":
			return await run_scenario(str(args.get("scenario_id", "")))
		_:
			return {"error": "Unknown async e2e tool: " + tool_name}


static func get_tool_defs() -> Array:
	return [
		_make("runtime_e2e_list", "List available E2E playability scenarios", {}),
		_make("runtime_e2e_run", "Run an E2E playability scenario visible in the window (reports anomalies)", {"scenario_id": {"type": "string"}}, ["scenario_id"], true),
	]


static func _make(tool_name: String, description: String, properties: Dictionary = {}, required: Array = [], async_tool: bool = false) -> Dictionary:
	var schema := {"type": "object", "properties": properties}
	if not required.is_empty():
		schema["required"] = required
	var tool := {"name": tool_name, "description": description, "inputSchema": schema}
	if async_tool:
		tool["_async"] = true
	return tool