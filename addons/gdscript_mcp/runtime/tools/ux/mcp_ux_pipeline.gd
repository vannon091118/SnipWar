extends RefCounted
class_name McpUxPipeline

## UX pipeline facade. Combines:
##  - FAST live scene-tree snapshot (McpUxLive) — authoritative labels + clicks
##  - VISUAL pixel analysis (McpVision) — evidence, images, regions
##  - event-driven watch clock: signature delta → analysis only on change
##  - debug log collection (EventLog + engine stdout) for E2E anomaly spotting
##
## Analysis stages (analyze):
##   Stage 0: live snapshot (scene tree controls)
##   Stage 1: visual capture (screenshot, context artifact, palette)
##   Stage 2: rects + text regions
##   Stage 3: classification (McpUxClassify)
##   Stage 4: grouping (McpUxGeometry)
##   Stage 5: scene hint merge (live authoritative)
##   Stage 6: interactables (live + pixel candidates)

const VISION_PATH := "res://addons/gdscript_mcp/runtime/tools/vision/mcp_vision.gd"
const RUNTIME_TOOLS_PATH := "res://addons/gdscript_mcp/runtime/tools/runtime/mcp_runtime_tools.gd"
const DEBUG_PATH := "res://addons/gdscript_mcp/runtime/tools/debug/mcp_debug.gd"

var _vision: RefCounted
var _debug: RefCounted
var _context_store: RefCounted
var _last_analysis: Dictionary = {}

## Response-size guard: full control dumps regularly exceed 100 KB (Anomalie M1).
## The agent needs visible, interactive controls first — everything beyond the
## cap is summarized as a count instead of dumped raw.
const MAX_CONTROLS_IN_RESPONSE: int = 60
var _latest_snapshot: Dictionary = {}
var _watch_enabled := false
var _watch_visual := false
var _watch_interval_seconds := 0.5
var _watch_accumulator := 0.0
var _watch_sequence := 0
var _last_signature := ""
var _last_visual_signature := ""
var _watch_visual_busy := false
var _lifecycle: RefCounted = null
var _log_cursor: int = 0
var _lifecycle_log_cursor: int = 0
var _log_stream_cursor: int = 0
var _log_seen: Dictionary = {}
var _log_seen_order: Array[String] = []
const MAX_LOG_SEEN := 512


func set_context_store(store: RefCounted) -> void:
	_context_store = store
	if _vision != null and _vision.has_method("set_context_store"):
		_vision.set_context_store(store)


func set_lifecycle(lifecycle: RefCounted) -> void:
	_lifecycle = lifecycle


func get_watch_status() -> Dictionary:
	return {
		"enabled": _watch_enabled,
		"include_visual": _watch_visual,
		"interval_ms": int(_watch_interval_seconds * 1000.0),
		"sequence": _watch_sequence,
		"last_signature": _last_signature,
		"snapshot": _latest_snapshot.duplicate(true) if not _latest_snapshot.is_empty() else {},
	}


func _ensure_vision() -> bool:
	if _vision != null:
		return true
	var vision_script: Resource = load(VISION_PATH)
	if vision_script == null:
		return false
	_vision = vision_script.new()
	if _context_store != null and _vision.has_method("set_context_store"):
		_vision.set_context_store(_context_store)
	return _vision != null


func _ensure_debug() -> bool:
	if _debug != null:
		return true
	var debug_script: Resource = load(DEBUG_PATH)
	if debug_script == null:
		return false
	_debug = debug_script.new()
	return _debug != null


## Called by the MCP host on every lifecycle tick. Event-driven watch:
##  - signature delta (scene/controls changed) → rebuild live snapshot
##  - visual watch additionally re-analyzes pixels when signature or
##    `_visual_change_required` tells us the frame actually changed
func tick(delta: float, visual_allowed: bool = true) -> void:
	if not _watch_enabled:
		return
	_watch_accumulator += delta
	if _watch_accumulator < _watch_interval_seconds:
		return
	_watch_accumulator = 0.0
	var live := McpUxLive.build_snapshot()
	var signature := McpUxLive.control_signature(live)
	var controls_changed := signature != _last_signature
	if not controls_changed and not _watch_visual:
		return
	if _watch_visual and not visual_allowed:
		return
	if controls_changed:
		_last_signature = signature
		_watch_sequence += 1
		_latest_snapshot = live.duplicate(true)
		_latest_snapshot["watch_sequence"] = _watch_sequence
	if _watch_visual and visual_allowed and not _watch_visual_busy:
		_watch_visual_busy = true
		call_deferred("_run_watch_visual")


func _run_watch_visual() -> void:
	if not _ensure_vision():
		_watch_visual_busy = false
		return
	var live := McpUxLive.build_snapshot()
	var capture: Dictionary = await _vision.capture_screenshot("png", false)
	if capture.has("error"):
		_latest_snapshot["watch_error"] = capture
		_watch_visual_busy = false
		return
	var image: Image = capture.get("image") as Image
	if image == null or image.is_empty():
		_watch_visual_busy = false
		return
	var visual_signature := McpUxLive.visual_signature(image)
	var control_signature := McpUxLive.control_signature(live)
	var controls_changed := control_signature != _last_signature
	if not controls_changed and visual_signature == _last_visual_signature:
		_watch_visual_busy = false
		return
	_last_visual_signature = visual_signature
	# Watch analysis stays in memory. It must not create a persistent artifact
	# on every poll; explicit screenshot/worker tools own artifact retention.
	var context: Dictionary = {}
	var visual := _analyze_pixels(image)
	var changed := _build_analysis_result(live, visual, context, int(capture.get("width", 0)), int(capture.get("height", 0)), true, {"context": context, "context_id": "", "format": "png", "mime_type": "image/png", "size_bytes": 0})
	_latest_snapshot = changed.duplicate(true)
	_last_signature = control_signature
	_watch_visual_busy = false


func analyze(include_visual: bool = true) -> Dictionary:
	var live := McpUxLive.build_snapshot()
	if not include_visual:
		return _build_analysis_result(live, {}, {}, 0, 0, false)
	if not _ensure_vision():
		return {"error": "Vision module not loaded", "live": live}
	var capture: Dictionary = _vision.capture_screenshot_sync("png", true)
	if capture.has("error"):
		return {"error": "Capture failed: " + str(capture.get("error", "")), "live": live}
	var image: Image = capture.get("image") as Image
	var visual := _analyze_pixels(image) if image != null and not image.is_empty() else {}
	return _build_analysis_result(live, visual, capture.get("context", {}), int(capture.get("width", 0)), int(capture.get("height", 0)), true, capture)


func _build_analysis_result(live: Dictionary, visual: Dictionary, image_context: Dictionary, width: int, height: int, include_visual: bool, capture: Dictionary = {}) -> Dictionary:
	var elements: Array = visual.get("elements", [])
	var interactables: Array = McpUxLive.interactables(live.get("controls", []))
	var scene_hint := str(live.get("scene", "unknown"))
	if scene_hint == "unknown" and not visual.is_empty():
		scene_hint = str(visual.get("scene", "unknown"))
	if width <= 0 or height <= 0:
		var main_loop := Engine.get_main_loop()
		if main_loop is SceneTree:
			var viewport_size := (main_loop as SceneTree).root.get_visible_rect().size
			width = int(viewport_size.x)
			height = int(viewport_size.y)
	var all_controls: Array = live.get("controls", [])
	# Truncation info lives in a separate key (NOT as a fake entry inside the
	# controls array) so control_signature/interactables consumers never see a
	# synthetic control.
	var capped_controls: Array = all_controls.slice(0, MAX_CONTROLS_IN_RESPONSE)
	var result := {
		"width": width,
		"height": height,
		"scene": scene_hint,
		"scene_path": live.get("scene_path", ""),
		"perf": _compact_perf(),
		"agent_context": _build_agent_context(scene_hint, interactables, elements, width, height),
		"live": live,
		"controls": capped_controls,
		"controls_total": all_controls.size(),
		"elements": elements,
		"groups": visual.get("groups", []),
		"interactables": interactables,
		"text_regions": visual.get("text_regions", []),
		"palette": visual.get("palette", []),
		"layout_grid": visual.get("layout_grid", []),
		"context": image_context,
		"watch_sequence": _watch_sequence,
	}
	if include_visual and not image_context.is_empty() and not visual.is_empty():
		result["artifact"] = {
			"context_id": capture.get("context_id", ""),
			"format": capture.get("format", "png"),
			"mime_type": capture.get("mime_type", "image/png"),
			"width": width,
			"height": height,
			"size_bytes": capture.get("size_bytes", 0),
			"context": image_context,
		}
	_last_analysis = result
	_latest_snapshot = result.duplicate(true)
	_last_signature = McpUxLive.control_signature(result)
	return result


func analyze_async(include_visual: bool = true) -> Dictionary:
	var live := McpUxLive.build_snapshot()
	if not include_visual:
		return _build_analysis_result(live, {}, {}, 0, 0, false)
	if not _ensure_vision():
		return {"error": "Vision module not loaded", "live": live}
	var capture: Dictionary = await _vision.capture_screenshot("png", true)
	if capture.has("error"):
		return {"error": "Capture failed: " + str(capture.get("error", "")), "live": live}
	var image: Image = capture.get("image") as Image
	var visual := _analyze_pixels(image) if image != null and not image.is_empty() else {}
	return _build_analysis_result(live, visual, capture.get("context", {}), int(capture.get("width", 0)), int(capture.get("height", 0)), true, capture)


## Compact responsiveness metrics for the agent (reuses McpDebugPerf).
func _compact_perf() -> Dictionary:
	var metrics: Dictionary = {}
	if _ensure_debug():
		metrics = _debug.get_perf_metrics()
	return {
		"fps": metrics.get("fps", 0),
		"draw_calls": metrics.get("draw_calls", 0),
		"objects": metrics.get("objects", 0),
		"nodes": metrics.get("nodes", 0),
		"process_ms": metrics.get("process_ms", 0),
	}


## Image→Context translation: a compact textual transcript of the UI so that
## models WITHOUT vision capabilities still get a precise, lossless description
## (exact labels from the scene tree, clickable targets with screen coords).
func _build_agent_context(scene_hint: String, interactables: Array, elements: Array, width: int, height: int) -> String:
	var lines: Array[String] = []
	lines.append("scene=" + scene_hint + " size=" + str(width) + "x" + str(height))
	if not interactables.is_empty():
		lines.append("interactables:")
		for raw in interactables:
			var c: Dictionary = raw as Dictionary
			var rect: Dictionary = c.get("rect", {})
			var hint := String(c.get("text", ""))
			if hint == "":
				hint = String(c.get("name", ""))
			lines.append("  - " + hint + " @(" + str(int(rect.get("x", 0))) + "," + str(int(rect.get("y", 0))) + "," + str(int(rect.get("w", 0))) + "x" + str(int(rect.get("h", 0))) + ")")
	else:
		lines.append("interactables: none")
	return "\n".join(lines)


func scan_interactables(root_path: String = "/root", max_controls: int = 300, max_depth: int = 32) -> Dictionary:
	var live := McpUxLive.build_snapshot(root_path, max_controls, max_depth)
	return {
		"scene": live.get("scene", "unknown"),
		"scene_path": live.get("scene_path", ""),
		"interactables": McpUxLive.interactables(live.get("controls", [])),
		"controls": live.get("controls", []),
		"scroll_containers": live.get("scroll_containers", []),
		"count": McpUxLive.interactables(live.get("controls", [])).size(),
		"watch_sequence": _watch_sequence,
	}


## Check whether a control's rect is within the visible viewport.
## Filters out nodes scrolled far outside view (ScrollContainer children).
func _in_viewport(candidate_rect: Dictionary) -> bool:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return true  # cannot determine, allow
	var vs := (ml as SceneTree).root.get_visible_rect().size
	var y := float(candidate_rect.get("y", 0.0))
	var h := float(candidate_rect.get("h", 0.0))
	return y + h > 0.0 and y < float(vs.y) + 200.0  # 200px overscan tolerance


func find_element(description: String, search_rect: Dictionary = {}, root_path: String = "/root", max_controls: int = 300, max_depth: int = 32) -> Dictionary:
	var normalized_description := description.strip_edges()
	if normalized_description.is_empty():
		return {"found": false, "description": description, "error": "description must not be empty"}
	var live := McpUxLive.build_snapshot(root_path, max_controls, max_depth)
	var width := int(_latest_analysis_value("width", 0))
	var height := int(_latest_analysis_value("height", 0))
	var normalized := normalized_description.to_lower()
	var best: Dictionary = {}
	var best_score := 0.0
	for control in live.get("controls", []):
		var candidate: Dictionary = control as Dictionary
		# `find` is the click-target resolver. Labels remain in snapshots for
		# context, but must never win over the actual interactive control.
		if not bool(candidate.get("interactable", false)) or bool(candidate.get("disabled", false)):
			continue
		var score := _description_score(normalized, candidate)
		# Penalize elements scrolled far outside the visible viewport
		if not _in_viewport(candidate.get("rect", {})):
			score -= 0.5
		if not search_rect.is_empty() and not _inside_rect(candidate.get("rect", {}), search_rect, width, height):
			score -= 0.8
		if score > best_score:
			best_score = score
			best = candidate.duplicate(true)
	if best_score >= 0.25:
		best["found"] = true
		best["match_score"] = best_score
		return best

	if _last_analysis.is_empty() or _last_analysis.get("elements", []).is_empty():
		var refreshed := analyze(true)
		if refreshed.has("error"):
			return refreshed
		for element in refreshed.get("elements", []):
			var visual_candidate: Dictionary = element as Dictionary
			if not bool(visual_candidate.get("interactable", false)):
				continue
			var visual_score := _description_score(normalized, visual_candidate)
			if visual_score > best_score:
				best_score = visual_score
				best = visual_candidate.duplicate(true)
	if best_score >= 0.25:
		best["found"] = true
		best["match_score"] = best_score
		return best
	return {"found": false, "description": description, "best_score": best_score}


func read_region(rect: Dictionary = {}) -> Dictionary:
	if not _ensure_vision():
		return {"error": "Vision module not loaded"}
	var capture: Dictionary = _vision.capture_screenshot_sync("png", true)
	if capture.has("error"):
		return capture
	var image: Image = capture.get("image") as Image
	if image == null:
		return {"error": "Captured image empty"}
	return {
		"hint": McpUxText.read_text_hint(image, rect),
		"rect": rect,
		"context_id": capture.get("context_id", ""),
		"context": capture.get("context", {}),
	}


func start_watch(interval_ms: int = 500, include_visual: bool = false) -> Dictionary:
	_watch_enabled = true
	_watch_visual = include_visual
	_watch_interval_seconds = clampf(float(interval_ms) / 1000.0, 0.05, 10.0)
	_watch_accumulator = 0.0
	_latest_snapshot = McpUxLive.build_snapshot()
	_last_signature = McpUxLive.control_signature(_latest_snapshot)
	_watch_sequence += 1
	_latest_snapshot["watch_sequence"] = _watch_sequence
	return get_watch_status()


func stop_watch() -> Dictionary:
	_watch_enabled = false
	_watch_accumulator = 0.0
	return get_watch_status()


func latest_snapshot() -> Dictionary:
	if _watch_enabled and not _latest_snapshot.is_empty():
		return _latest_snapshot.duplicate(true)
	return McpUxLive.build_snapshot()


## Log cursor: position in the merged log stream (index of last entry seen).
## Resets to 0 when the adapter or log source changes.


## Collect recent debug logs via the project adapter (or engine-only if no
## adapter is registered). Supports cursor-based delta reads and anomaly
## classification per entry.
func collect_logs(limit: int = 100, filter_str: String = "", cursor: int = -1) -> Dictionary:
	var safe_limit := clampi(limit, 1, 256)
	var effective_cursor := _log_cursor if cursor < 0 else maxi(0, cursor)
	var adapter = _get_project_adapter()
	var all_raw: Array = []
	var source_counts := {"mcp": 0, "engine": 0, "project": 0}

	# Collect MCP lifecycle events first so queue drops and worker failures are
	# visible alongside project EventLog entries.
	if _lifecycle != null:
		var lifecycle_payload: Dictionary = _lifecycle.events_since(_lifecycle_log_cursor, 64)
		for raw_event in lifecycle_payload.get("entries", []):
			if raw_event is Dictionary:
				var lifecycle_entry: Dictionary = (raw_event as Dictionary).duplicate(true)
				lifecycle_entry["source"] = "mcp"
				lifecycle_entry["text"] = str(lifecycle_entry.get("text", ""))
				lifecycle_entry["_index"] = all_raw.size()
				all_raw.append(lifecycle_entry)
				source_counts["mcp"] = source_counts.get("mcp", 0) + 1
		_lifecycle_log_cursor = int(lifecycle_payload.get("next_cursor", _lifecycle_log_cursor))

	# Collect from adapter sources
	if adapter != null and adapter.has_method("log_sources"):
		var sources: Array = adapter.log_sources()
		for source in sources:
			var source_name := str(source)
			# Project event log via adapter
			if source_name == "event_log" and adapter.has_method("log_normalize_entry"):
				var raw_entries := _read_project_event_log(adapter)
				for raw in raw_entries:
					var normalized: Dictionary = adapter.log_normalize_entry("event_log", raw)
					if not normalized.is_empty():
						normalized["_index"] = all_raw.size()
						all_raw.append(normalized)
						source_counts["project"] = source_counts.get("project", 0) + 1

	# Assign a stable cursor to each merged entry. Rebuilding the merged list
	# every poll changes array indexes, so an index-based cursor would skip new
	# lifecycle entries and duplicate older project entries.
	var occurrences: Dictionary = {}
	for raw_entry in all_raw:
		var entry: Dictionary = raw_entry
		var source := str(entry.get("source", ""))
		var base_key := source + ":" + str(entry.get("cursor", "")) + ":" + str(entry.get("stamp", "")) + ":" + str(entry.get("category", "")) + ":" + str(entry.get("text", ""))
		var occurrence := int(occurrences.get(base_key, 0))
		occurrences[base_key] = occurrence + 1
		var stable_key := base_key + ":" + str(occurrence)
		if not _log_seen.has(stable_key):
			_log_stream_cursor += 1
			_log_seen[stable_key] = _log_stream_cursor
			_log_seen_order.append(stable_key)
		entry["_stream_cursor"] = int(_log_seen[stable_key])
	while _log_seen_order.size() > MAX_LOG_SEEN:
		var old_key := _log_seen_order.pop_front()
		_log_seen.erase(old_key)

	var delta: Array = []
	var anomalies: Array = []
	var searched := str(filter_str).to_lower().strip_edges()
	for i in range(all_raw.size() - 1, -1, -1):
		if delta.size() >= safe_limit:
			break
		var entry: Dictionary = all_raw[i]
		if int(entry.get("_stream_cursor", 0)) <= effective_cursor:
			continue
		var text := str(entry.get("text", ""))
		if searched != "" and not text.to_lower().contains(searched):
			continue
		var public_entry := entry.duplicate(true)
		public_entry.erase("_index")
		public_entry.erase("_stream_cursor")
		delta.append(public_entry)
		if _is_anomaly(public_entry):
			anomalies.append(public_entry)
	delta.reverse()
	_log_cursor = _log_stream_cursor

	return {
		"entries": delta,
		"count": delta.size(),
		"anomalies": anomalies,
		"anomaly_count": anomalies.size(),
		"next_cursor": str(_log_cursor),
		"source_counts": source_counts,
		"cursor_reset": effective_cursor > _log_stream_cursor,
	}


## Anomaly: error/fatal always; warnings from MCP; project warnings unless silent.
func _is_anomaly(entry: Dictionary) -> bool:
	var level := str(entry.get("level", "")).to_lower()
	var source := str(entry.get("source", ""))
	var visible: bool = entry.get("visible", true)
	if level == "error" or level == "fatal":
		return true
	if level == "warning":
		return source == "mcp" or visible
	return false


## Read raw entries from the project's EventLog via the adapter.
func _read_project_event_log(adapter) -> Array:
	var main_loop := Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return []
	var root := (main_loop as SceneTree).root
	if root == null:
		return []
	var event_log: Node = root.get_node_or_null("/root/EventLog")
	if event_log == null:
		return []
	if event_log.has_method("get_entries"):
		var raw: Variant = event_log.get_entries()
		return raw if raw is Array else []
	return []


## Resolve the optional McpProjectAdapter from autoloads.
func _get_project_adapter():
	var main_loop := Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return null
	var root := (main_loop as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null("/root/McpProjectAdapter")


func _analyze_pixels(image: Image) -> Dictionary:
	if image == null or image.is_empty():
		return {}
	var source_width := image.get_width()
	var source_height := image.get_height()
	var work_image := image
	if source_width > 480:
		var target_height: int = maxi(1, int(round(float(source_height) * 480.0 / float(source_width))))
		work_image = image.duplicate()
		work_image.resize(480, target_height, Image.INTERPOLATE_NEAREST)
	var width := work_image.get_width()
	var height := work_image.get_height()
	var grid := McpUxDetect.layout_grid(_vision, work_image, 8, 12)
	var palette := McpUxDetect.color_palette(work_image)
	var rects: Dictionary = _vision.detect_rects(work_image, 0.12, 10)
	var text: Dictionary = _vision.detect_text_regions(work_image, true, 3, 6)
	var elements: Array = []
	for raw_rect in rects.get("rects", []):
		var rect: Dictionary = raw_rect as Dictionary
		var classified: Dictionary = McpUxClassify.classify(work_image, rect, text.get("regions", []))
		if int(classified.get("type", 0)) != 0:
			elements.append(classified)
	var result := {
		"elements": elements,
		"groups": McpUxGeometry.group_elements(elements, width, height),
		"scene": McpUxDetect.detect_scene(work_image, elements, width, height),
		"text_regions": text.get("regions", []),
		"palette": palette,
		"layout_grid": grid.get("grid", []),
	}
	if width != source_width or height != source_height:
		_scale_visual_coordinates(result, float(source_width) / float(width), float(source_height) / float(height))
	return result


func _scale_visual_coordinates(value: Variant, scale_x: float, scale_y: float) -> void:
	if value is Array:
		for item in value:
			_scale_visual_coordinates(item, scale_x, scale_y)
		return
	if not value is Dictionary:
		return
	var dictionary: Dictionary = value
	for key in dictionary.keys():
		var key_text := str(key)
		if key_text in ["x", "center_x"]:
			dictionary[key] = float(dictionary[key]) * scale_x
		elif key_text in ["y", "center_y"]:
			dictionary[key] = float(dictionary[key]) * scale_y
		elif key_text in ["w", "width"]:
			dictionary[key] = float(dictionary[key]) * scale_x
		elif key_text in ["h", "height"]:
			dictionary[key] = float(dictionary[key]) * scale_y
		else:
			_scale_visual_coordinates(dictionary[key], scale_x, scale_y)


# ── Description scoring ────────────────────────────────────────────────────

func _description_score(description: String, candidate: Dictionary) -> float:
	var score := 0.0
	var text := String(candidate.get("text", "")).to_lower()
	var name := String(candidate.get("name", "")).to_lower()
	var kind := String(candidate.get("kind", candidate.get("type", ""))).to_lower()
	if text != "" and text == description:
		score += 1.0
	elif text != "" and (description in text or text in description):
		score += 0.75
	if name != "" and (description in name or name in description):
		score += 0.5
	if kind != "" and (description in kind or kind in description):
		score += 0.25
	if ("top" in description or "oben" in description) and float(candidate.get("rect", {}).get("y", 0.0)) < 200.0:
		score += 0.1
	# Disabled controls are visible but not actionable — an agent asked to click
	# a control wants the enabled instance (e.g. the first researchable FORSCHEN
	# row, not the disabled button of an already-researched tech).
	if bool(candidate.get("disabled", false)):
		score -= 0.6
	return score


func _inside_rect(candidate_rect: Dictionary, search_rect: Dictionary, width: int, height: int) -> bool:
	var rect := McpUxGeometry.resolve_rect(search_rect, maxi(width, 1), maxi(height, 1))
	var source: Dictionary = candidate_rect
	return float(source.get("x", 0.0)) >= float(rect.get("x", 0.0)) and float(source.get("y", 0.0)) >= float(rect.get("y", 0.0)) and float(source.get("x", 0.0)) + float(source.get("w", 0.0)) <= float(rect.get("x", 0.0)) + float(rect.get("w", 0.0)) and float(source.get("y", 0.0)) + float(source.get("h", 0.0)) <= float(rect.get("y", 0.0)) + float(rect.get("h", 0.0))


func _latest_analysis_value(key: String, default_value: Variant) -> Variant:
	return _last_analysis.get(key, default_value) if not _last_analysis.is_empty() else default_value


func dispatch_tool(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_ux_scan":
			return scan_interactables(str(args.get("root_path", "/root")), int(args.get("max_controls", 300)), int(args.get("max_depth", 32)))
		"runtime_ux_find":
			return find_element(str(args.get("description", "")), args.get("rect", {}), str(args.get("root_path", "/root")), int(args.get("max_controls", 300)), int(args.get("max_depth", 32)))
		"runtime_ux_watch_start":
			return start_watch(int(args.get("interval_ms", 500)), bool(args.get("include_visual", false)))
		"runtime_ux_watch_stop":
			return stop_watch()
		"runtime_ux_watch_state":
			return get_watch_status()
		"runtime_ux_snapshot":
			return latest_snapshot()
		"runtime_ux_logs":
			return collect_logs(int(args.get("limit", 100)), str(args.get("filter", "")), int(str(args.get("cursor", "-1"))))
		_:
			return {"error": "Unknown UX tool: " + tool_name}


func dispatch_async(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_ux_analyze":
			return await analyze_async(bool(args.get("include_visual", true)))
		"runtime_ux_read":
			return await read_region_async(args.get("rect", {}))
		"runtime_ux_click":
			return await _click_and_observe(str(args.get("description", "")), args.get("rect", {}), bool(args.get("retain_artifact", false)))
		_:
			return {"error": "Unknown async UX tool: " + tool_name}


static func get_tool_defs() -> Array:
	return [
		_make("runtime_ux_analyze", "Run the complete live-control plus visual UX pipeline", {"include_visual": {"type": "boolean", "default": true}}, [], true),
		_make("runtime_ux_scan", "Fast bounded live scan of clickable controls and exact labels", {"root_path": {"type": "string", "default": "/root"}, "max_controls": {"type": "integer", "default": 300}, "max_depth": {"type": "integer", "default": 32}}),
		_make("runtime_ux_find", "Find an interactable in a bounded visible scope by exact text, node name, type, or position", {"description": {"type": "string"}, "rect": {"type": "object"}, "root_path": {"type": "string", "default": "/root"}, "max_controls": {"type": "integer", "default": 300}, "max_depth": {"type": "integer", "default": 32}}, ["description"]),
		_make("runtime_ux_read", "Read a visual region and return local context metadata", {"rect": {"type": "object"}}, ["rect"], true),
		_make("runtime_ux_click", "Click an element and observe with a compact receipt; the screenshot artifact is released unless retained", {"description": {"type": "string"}, "rect": {"type": "object"}, "retain_artifact": {"type": "boolean", "default": false}}, ["description"], true),
		_make("runtime_ux_watch_start", "Start periodic, event-driven UX snapshots (signature-delta gated)", {"interval_ms": {"type": "integer", "default": 500}, "include_visual": {"type": "boolean", "default": false}}),
		_make("runtime_ux_watch_stop", "Stop periodic UX snapshots", {}),
		_make("runtime_ux_watch_state", "Read periodic UX watch state and latest snapshot", {}),
		_make("runtime_ux_snapshot", "Read the latest periodic UX snapshot without re-running detection", {}),
		_make("runtime_ux_logs", "Read recent log entries with cursor-based delta and anomaly detection", {"limit": {"type": "integer", "default": 100}, "filter": {"type": "string", "default": ""}, "cursor": {"type": "string", "description": "Opaque cursor from previous response for delta reads"}}),
	]


static func _make(tool_name: String, description: String, properties: Dictionary = {}, required: Array = [], async_tool: bool = false) -> Dictionary:
	var schema := {"type": "object", "properties": properties}
	if not required.is_empty():
		schema["required"] = required
	var tool := {"name": tool_name, "description": description, "inputSchema": schema}
	if async_tool:
		tool["_async"] = true
	return tool


# ═══════════════════════════════════════════════════════════════
# Async dispatch implementations
# ═══════════════════════════════════════════════════════════════

func read_region_async(rect: Dictionary = {}) -> Dictionary:
	return await read_region(rect)


## Atomarer Action-Receipt: finden, klicken, auf Release warten,
## nach dem Render Screenshot aufnehmen, Live-Zustand und Frame-Hash liefern.
## Klassifiziert MCP_ISSUE vs GAME_ISSUE anhand des Live-Deltas.
func _click_and_observe(description: String, search_rect: Dictionary = {}, retain_artifact: bool = false) -> Dictionary:
	# Phase 0: Snapshot BEFORE the click for delta comparison
	var before_live := McpUxLive.build_snapshot()

	var element := find_element(description, search_rect)
	if not bool(element.get("found", false)):
		return {"found": false, "clicked": false, "description": description, "verdict": "MCP_ISSUE", "verdict_reason": "Element not found in scene tree"}

	# Phase 1: Schedule the input
	var runtime_script: Resource = load(RUNTIME_TOOLS_PATH)
	if runtime_script == null:
		return {"error": "Runtime input module not available", "found": true, "verdict": "MCP_ISSUE", "verdict_reason": "Runtime module missing"}
	var runtime_tools: RefCounted = runtime_script.new()
	var click_args := {"path": element.get("path", ""), "x": -1, "y": -1}
	if String(click_args.path) == "":
		click_args["x"] = int(element.get("center", {}).get("x", 0))
		click_args["y"] = int(element.get("center", {}).get("y", 0))
	var click_result: Dictionary = runtime_tools.dispatch_tool("runtime_click", click_args) as Dictionary
	if not bool(click_result.get("clicked", false)):
		return {"found": true, "clicked": false, "result": click_result, "verdict": "MCP_ISSUE", "verdict_reason": "Click dispatch returned clicked=false"}

	# Phase 2: Wait for release + 1 extra frame for rendering
	var hold_frames: int = click_result.get("hold_frames", 1)
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"found": true, "clicked": true, "error": "No scene tree for observation", "verdict": "MCP_ISSUE", "verdict_reason": "No SceneTree"}
	for _i in range(hold_frames + 2):
		await (tree as SceneTree).process_frame

	# Phase 3: Capture post-click screenshot (with frame_post_draw)
	if not _ensure_vision():
		click_result["found"] = true
		click_result["receipt"] = {"after_live": McpUxLive.build_snapshot()}
		click_result["verdict"] = "INCONCLUSIVE"
		click_result["verdict_reason"] = "Vision module unavailable — cannot capture screenshot evidence"
		return click_result
	var capture: Dictionary = await _vision.capture_screenshot("png", true)
	var captured_image: Image = capture.get("image") as Image
	var frame_hash := McpUxLive.visual_signature(captured_image) if captured_image != null and not captured_image.is_empty() else ""

	# Phase 4: Live snapshot after the click + verdict classification
	var after_live := McpUxLive.build_snapshot()
	var before_sig := McpUxLive.control_signature(before_live)
	var after_sig := McpUxLive.control_signature(after_live)
	var live_changed := before_sig != after_sig

	# Phase 5: Verdict — MCP_ISSUE vs GAME_ISSUE vs SOLVED
	var verdict := "INCONCLUSIVE"
	var verdict_reason := ""
	if not live_changed:
		verdict = "MCP_ISSUE"
		verdict_reason = "Click was dispatched but scene-tree signature unchanged — input may not have landed"
	elif capture.has("error"):
		verdict = "INCONCLUSIVE"
		verdict_reason = "Live state changed but screenshot capture failed: " + str(capture.get("error", ""))
	else:
		# Both live and visual evidence agree: state changed.
		# Persist screenshot to context store only for non-trivial outcomes
		# (so the agent can fetch it manually if needed).
		verdict = "TO_CHECK"
		verdict_reason = "Live state changed, screenshot captured. Awaiting agent confirmation."

	click_result["found"] = true
	click_result["verdict"] = verdict
	click_result["verdict_reason"] = verdict_reason
	var context_id := str(capture.get("context_id", ""))
	var receipt := {
		"frame_id": Time.get_ticks_msec(),
		"frame_hash": frame_hash,
		"context_id": context_id,
		"width": int(capture.get("width", 0)),
		"height": int(capture.get("height", 0)),
		"before_live_signature": before_sig,
		"after_live_signature": after_sig,
		"live_changed": live_changed,
		"after_live": after_live,
		"artifact_retained": retain_artifact,
	}
	if retain_artifact:
		receipt["artifact"] = capture.get("context", {})
	elif context_id != "" and _context_store != null:
		var release_result: Dictionary = _context_store.release(context_id)
		receipt["artifact_released"] = bool(release_result.get("released", false))
	click_result["receipt"] = receipt
	return click_result