extends SceneTree
## Entry-point falsification for the async capture contract:
## drives the REAL McpToolRegistry → McpUxPipeline on both dispatch surfaces.
## Headless, so every visual branch ends in the deterministic capture error —
## the assertions prove the RESULT CONTRACT (real Dictionary, no
## GDScriptFunctionState leak, no "unknown tool"), not pixels.
## exit 0 only when every case matches; exit 1 on deviation; exit 3 on hang.

const EVIDENCE_PATH := "user://mcp_evidence/mcp_capture_entry.json"
const ASYNC_UX_TOOLS := ["runtime_ux_analyze", "runtime_ux_find", "runtime_ux_read", "runtime_ux_click"]
const SYNC_ONLY_UX_TOOLS := ["runtime_ux_scan", "runtime_ux_watch_start", "runtime_ux_watch_stop", "runtime_ux_watch_state", "runtime_ux_snapshot", "runtime_ux_logs"]

var _checks: int = 0
var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  [PASS] " + label)
	else:
		_failures += 1
		print("  [FAIL] " + label)


func _init() -> void:
	# Watchdog: awaits that never resolve (e.g. frame_post_draw in a broken
	# headless path) must fail loudly instead of hanging CI.
	create_timer(20.0).timeout.connect(func() -> void:
		print("[t] WATCHDOG TIMEOUT — an await never resolved")
		quit(3)
	)
	var registry: RefCounted = load("res://addons/mcp/runtime/core/mcp_tool_registry.gd").new()
	var evidence: Array = []

	# T1 — sync surface must refuse runtime_ux_find explicitly (its screenshot
	# fallback waits for frame_post_draw; a sync call would leak a coroutine
	# state object instead of a Dictionary).
	var t1: Dictionary = registry.dispatch("runtime_ux_find", {"description": "NO_SUCH_ELEMENT_XYZ"})
	evidence.append({"id": "t1_sync_find_refused", "result": t1})
	_check(t1 is Dictionary and str(t1.get("error", "")).contains("async-only"), "T1 sync runtime_ux_find refused with async-only error")

	# T2 — async surface, empty description: early return without screenshot.
	var t2: Dictionary = await registry.dispatch_async("runtime_ux_find", {"description": "   "})
	evidence.append({"id": "t2_async_find_empty", "result": t2})
	_check(t2 is Dictionary and t2.get("found", true) == false and t2.has("error"), "T2 empty description → found=false + error, no capture")

	# T3 — async surface, unknown element: the visual fallback runs. Before the
	# await fix this path aborted on a GDScriptFunctionState and returned null.
	var t3: Dictionary = await registry.dispatch_async("runtime_ux_find", {"description": "NO_SUCH_ELEMENT_XYZ"})
	evidence.append({"id": "t3_async_find_fallback", "result": t3})
	_check(t3 != null and t3 is Dictionary and t3.has("error"), "T3 find fallback returns real Dictionary with capture error (headless)")

	# T4 — click not-found path: await find_element must yield a verdict dict.
	var t4: Dictionary = await registry.dispatch_async("runtime_ux_click", {"description": "NO_SUCH_ELEMENT_XYZ"})
	evidence.append({"id": "t4_async_click_notfound", "result": t4})
	_check(t4 is Dictionary and t4.get("found") == false and t4.get("clicked") == false and t4.get("verdict") == "MCP_ISSUE", "T4 click not-found → found=false, clicked=false, verdict=MCP_ISSUE")

	# T5 — analyze delegation (analyze → analyze_async), live-only branch.
	var t5: Dictionary = await registry.dispatch_async("runtime_ux_analyze", {"include_visual": false})
	evidence.append({"id": "t5_async_analyze_live", "result": {"width": t5.get("width"), "scene": t5.get("scene"), "error": t5.get("error", "")}})
	_check(t5 is Dictionary and not t5.has("error") and t5.has("agent_context") and t5.has("controls"), "T5 analyze include_visual=false → real analysis dict via delegation (headless: no window geometry)")

	# T6 — read_region on the async chain: headless capture error, real dict.
	var t6: Dictionary = await registry.dispatch_async("runtime_ux_read", {"rect": {"x": 0, "y": 0, "w": 10, "h": 10}})
	evidence.append({"id": "t6_async_read_capture_error", "result": t6})
	_check(t6 is Dictionary and t6.has("error"), "T6 read via async chain → capture error dictionary (headless), no crash")

	# T7 — runtime_ux_logs cursor/delta contract boundaries.
	var t7a: Dictionary = registry.dispatch("runtime_ux_logs", {"cursor": "999"})
	var t7b: Dictionary = registry.dispatch("runtime_ux_logs", {"limit": 0})
	evidence.append({"id": "t7_logs_cursor", "reset": t7a.get("cursor_reset"), "next": t7b.get("next_cursor"), "cursor_type": t7b.get("cursor_type")})
	_check(t7a is Dictionary and t7a.get("cursor_reset") == true, "T7a stale cursor 999 → cursor_reset=true")
	_check(t7b is Dictionary and t7b.get("count") == 0 and str(t7b.get("next_cursor", "")) != "" and t7b.get("cursor_type") == "monotonic_stream_id", "T7b limit clamps, next_cursor present, cursor_type documented")

	# T8 — tool-def async markers: exactly the screenshot-touching tools are async.
	var async_state := {}
	for def in registry.get_all_tools():
		var tool_name := str(def.get("name", ""))
		if tool_name.begins_with("runtime_ux_"):
			async_state[tool_name] = bool(def.get("_async", false))
	var t8_ok := true
	for tool_name in ASYNC_UX_TOOLS:
		t8_ok = t8_ok and async_state.get(tool_name, null) == true
	for tool_name in SYNC_ONLY_UX_TOOLS:
		t8_ok = t8_ok and async_state.get(tool_name, null) == false
	evidence.append({"id": "t8_async_markers", "state": async_state})
	_check(t8_ok, "T8 exactly {analyze, find, read, click} carry _async=true among UX tools")

	# T9 — OFFEN-3/4 contracts: fire-and-forget routing decision + evidence
	# freshness (pure statics on the real server script) + the pipeline's
	# non-coroutine live-only path used by the decoupled analyze.
	var server_script: GDScript = load("res://addons/mcp/runtime/host/mcp_server.gd")
	var decoupled_hit: bool = server_script.is_ux_analyze_decoupled("runtime_ux_analyze", {"include_visual": true})
	var decoupled_miss_a: bool = server_script.is_ux_analyze_decoupled("runtime_ux_analyze", {"include_visual": false})
	var decoupled_miss_b: bool = server_script.is_ux_analyze_decoupled("runtime_click", {"include_visual": true})
	evidence.append({"id": "t9_decoupled_routing", "hit": decoupled_hit, "miss_a": decoupled_miss_a, "miss_b": decoupled_miss_b})
	_check(decoupled_hit and not decoupled_miss_a and not decoupled_miss_b, "T9a is_ux_analyze_decoupled: only (runtime_ux_analyze, include_visual=true) routes to fire-and-forget")

	var fresh_disabled: Dictionary = server_script.evidence_freshness({"captured_at_ms": 1000}, 5000, 0)
	var fresh_old: Dictionary = server_script.evidence_freshness({"captured_at_ms": 1000}, 5000, 200)
	var fresh_current: Dictionary = server_script.evidence_freshness({"captured_at_ms": 4800}, 5000, 200)
	var fresh_unknown: Dictionary = server_script.evidence_freshness({"legacy": true}, 5000, 200)
	evidence.append({"id": "t9_freshness", "disabled": fresh_disabled, "old": fresh_old, "current": fresh_current, "unknown": fresh_unknown})
	_check(not bool(fresh_disabled.get("stale", true)) and bool(fresh_old.get("stale", false)) and not bool(fresh_current.get("stale", true)) and bool(fresh_unknown.get("stale", false)),
		"T9b evidence_freshness: max_age_ms=0 disabled, stale by age, fresh within budget, unknown stamp → stale")

	var ux: RefCounted = registry.get_ux_pipeline()
	_check(ux != null and ux.has_method("analyze_live_only"), "T9c registry.get_ux_pipeline exposes analyze_live_only (OFFEN-4 live path)")
	var live_only: Dictionary = ux.analyze_live_only("/root", 50, 8)
	evidence.append({"id": "t9_live_only", "scene": live_only.get("scene", ""), "has_error": live_only.has("error"), "has_artifact": live_only.has("artifact")})
	_check(live_only is Dictionary and not live_only.has("error") and live_only.has("agent_context") and not live_only.has("artifact"),
		"T9d analyze_live_only → live analysis dict without artifact, no coroutine suspension")

	DirAccess.make_dir_recursive_absolute("user://mcp_evidence")
	var evidence_file := FileAccess.open(EVIDENCE_PATH, FileAccess.WRITE)
	if evidence_file != null:
		evidence_file.store_string(JSON.stringify({"checks": _checks, "failures": _failures, "cases": evidence, "date": Time.get_datetime_string_from_system()}))
		evidence_file.close()
	print("[t] %d checks, %d failures — evidence: %s" % [_checks, _failures, EVIDENCE_PATH])
	quit(1 if _failures > 0 else 0)
