extends RefCounted
class_name McpVision

## Vision facade for the runtime session.
## Screenshots are written to McpContextStore and MCP returns only metadata.
## Pixel work is delegated to bounded helper modules or the optional local worker.

const WORKER_UNAVAILABLE := "vision worker is not enabled or connected"

var _last_screenshot_image: Image = null
var _previous_screenshot_image: Image = null
var _last_context_id := ""
var _context_store: RefCounted = null
var _worker: Node = null
var _capture: McpVisionCapture


func _init() -> void:
	_capture = McpVisionCapture.new()


func set_context_store(store: RefCounted) -> void:
	_context_store = store


func set_worker(worker: Node) -> void:
	_worker = worker


func get_last_context_id() -> String:
	return _last_context_id


func _mime_type(format_name: String) -> String:
	return "image/jpeg" if format_name == "jpg" or format_name == "jpeg" else "image/png"


func _commit_capture(capture: Dictionary, format_name: String, persist_context: bool, source: String = "godot_viewport") -> Dictionary:
	if capture.has("error"):
		return capture
	var image: Image = capture.get("image") as Image
	if image == null or image.is_empty():
		return {"error": "Captured image is empty"}
	_previous_screenshot_image = _last_screenshot_image
	_last_screenshot_image = image
	_last_context_id = ""
	var context: Dictionary = {}
	if persist_context and _context_store != null:
		context = _context_store.write_image(image, format_name, {
			"source": source,
			"pipeline": "vision",
		})
		if context.has("error"):
			return context
		_last_context_id = str(context.get("context_id", ""))
	var blank_check := _check_blank_screen(image)
	var result := {
		"format": str(capture.get("format", format_name)),
		"mime_type": _mime_type(format_name),
		"width": int(capture.get("width", image.get_width())),
		"height": int(capture.get("height", image.get_height())),
		"size_bytes": int(context.get("size_bytes", capture.get("size_bytes", 0))),
		"context": context,
		"context_id": _last_context_id,
		"image": image,
		"screen_quality": blank_check,
	}
	return result


func capture_screenshot_sync(format_name: String = "png", persist_context: bool = true) -> Dictionary:
	_hide_cursor_for_capture()
	var capture: Dictionary = _capture.capture_screenshot_sync(format_name)
	_show_cursor_after_capture()
	return _commit_capture(capture, format_name, persist_context)


func capture_screenshot(format_name: String = "png", persist_context: bool = true) -> Dictionary:
	_hide_cursor_for_capture()
	var capture: Dictionary = await _capture.capture_screenshot(format_name)
	_show_cursor_after_capture()
	return _commit_capture(capture, format_name, persist_context)


func get_viewport_for_capture() -> Viewport:
	return McpVisionCapture.get_viewport_for_capture()


## Detect blank / near-uniform-gray screens that indicate rendering failure.
## Returns a quality assessment so agents can skip or retry.
func _check_blank_screen(image: Image) -> Dictionary:
	if image == null or image.is_empty():
		return {"quality": "empty", "warning": "Image is empty — viewport may not be rendering"}
	var w := mini(image.get_width(), 320)
	var h := mini(image.get_height(), 240)
	var step: int = maxi(1, mini(w, h) / 40)
	var unique_colors: Dictionary = {}
	var total := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := image.get_pixel(x, y)
			# Quantize to 32 levels per channel for color counting.
			var key := "%d,%d,%d" % [int(c.r8 / 8), int(c.g8 / 8), int(c.b8 / 8)]
			unique_colors[key] = true
			total += 1
	var color_count := unique_colors.size()
	if color_count <= 1:
		return {"quality": "blank", "warning": "Screen appears blank/uniform — game may not be rendering", "unique_colors": color_count}
	if color_count <= 4:
		return {"quality": "near_blank", "warning": "Screen has very few colors (possible gray overlay or loading state)", "unique_colors": color_count}
	if color_count <= 12:
		return {"quality": "low_detail", "unique_colors": color_count}
	return {"quality": "normal", "unique_colors": color_count}


## Hide the virtual mouse cursor overlay before capturing a screenshot.
func _hide_cursor_for_capture() -> void:
	var scheduler := McpInputScheduler.get_or_create()
	if scheduler != null:
		scheduler.hide_cursor()


## Restore the virtual mouse cursor after screenshot capture.
func _show_cursor_after_capture() -> void:
	var scheduler := McpInputScheduler.get_or_create()
	if scheduler != null:
		scheduler.show_cursor()


func get_pixel(img: Image, x: int, y: int) -> Dictionary:
	return McpVisionCapture.get_pixel(img, x, y)


func get_pixel_region(img: Image, x: int, y: int, w: int, h: int, step: int = 4) -> Dictionary:
	return McpVisionCapture.get_pixel_region(img, x, y, w, h, step)


func find_color(img: Image, target_hex: String, tolerance: float = 0.05, search_rect: Dictionary = {}) -> Dictionary:
	return McpVisionColor.find_color(img, target_hex, tolerance, search_rect)


func find_all_colors(img: Image, target_hex: String, tolerance: float = 0.05, min_size: int = 4) -> Dictionary:
	return McpVisionColor.find_all_colors(img, target_hex, tolerance, min_size)


func count_color_pixels(img: Image, target_hex: String, tolerance: float = 0.05, rect: Dictionary = {}) -> Dictionary:
	return McpVisionColor.count_color_pixels(img, target_hex, tolerance, rect)


func image_diff(previous_context_id: String = "", threshold: int = 10) -> Dictionary:
	var previous := _previous_screenshot_image
	if previous_context_id != "" and _context_store != null:
		var stored: Image = _context_store.read_image(previous_context_id)
		if stored != null:
			previous = stored
	return McpVisionCompare.image_diff(previous, threshold, _last_screenshot_image)


func frame_changed_since(previous_context_id: String = "", threshold: int = 20) -> Dictionary:
	var diff := image_diff(previous_context_id, threshold)
	if diff.has("error"):
		return diff
	return {
		"changed": not bool(diff.get("stable", false)),
		"changed_pixels": diff.get("changed_pixels", 0),
		"change_ratio": diff.get("change_ratio", 0.0),
	}


func find_template(template_b64: String, threshold: float = 0.85, search_rect: Dictionary = {}) -> Dictionary:
	return McpVisionCompare.find_template(template_b64, threshold, search_rect, _last_screenshot_image)


func find_template_all(template_b64: String, threshold: float = 0.75, search_rect: Dictionary = {}) -> Dictionary:
	return McpVisionCompare.find_template_all(template_b64, threshold, search_rect, _last_screenshot_image)


func detect_rects(img: Image, edge_sensitivity: float = 0.15, min_size: int = 8) -> Dictionary:
	return McpVisionDetect.detect_rects(img, edge_sensitivity, min_size)


func detect_text_regions(img: Image, dark_on_light: bool = true, min_chars: int = 3, min_size: int = 8) -> Dictionary:
	return McpVisionDetect.detect_text_regions(img, dark_on_light, min_chars, min_size)


func sample_grid(img: Image, rows: int, cols: int, rect: Dictionary = {}) -> Dictionary:
	return McpVisionDetect.sample_grid(img, rows, cols, rect)


func dominant_color(img: Image, rect: Dictionary = {}) -> Dictionary:
	return McpVisionDetect.dominant_color(img, rect)


func wait_for_stable(threshold: int = 50, max_frames: int = 60, timeout_ms: int = 5000) -> Dictionary:
	var safe_threshold := maxi(0, threshold)
	var safe_max_frames := clampi(max_frames, 1, 600)
	var safe_timeout_ms := clampi(timeout_ms, 1, 600000)
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"error": "No scene tree"}
	var previous: Image = null
	var current: Image = null
	var start_ms := Time.get_ticks_msec()
	var frames_checked := 0
	var stable_count := 0

	while frames_checked < safe_max_frames:
		if Time.get_ticks_msec() - start_ms > safe_timeout_ms:
			return {"stable": false, "elapsed_ms": Time.get_ticks_msec() - start_ms, "frames": frames_checked}
		var capture: Dictionary = await _capture.capture_screenshot("png")
		if capture.has("error"):
			return capture
		current = capture.get("image") as Image
		if current == null:
			return {"error": "Captured image is empty"}
		_previous_screenshot_image = previous
		_last_screenshot_image = current
		if previous != null:
			var diff := McpVisionCompare.image_diff(previous, safe_threshold, current)
			if diff.has("error"):
				return diff
			if bool(diff.get("stable", false)):
				stable_count += 1
				if stable_count >= 3:
					var result := _commit_capture(capture, "png", true, "stable_frame")
					result.erase("image")
					result["stable"] = true
					result["elapsed_ms"] = Time.get_ticks_msec() - start_ms
					result["frames"] = frames_checked
					return result
			else:
				stable_count = 0
		previous = current
		frames_checked += 1
		await (tree as SceneTree).process_frame

	var final_result := _commit_capture({"image": current, "format": "png", "width": current.get_width(), "height": current.get_height()}, "png", true, "stable_timeout")
	final_result.erase("image")
	final_result["stable"] = true
	final_result["elapsed_ms"] = Time.get_ticks_msec() - start_ms
	final_result["frames"] = frames_checked
	return final_result


func worker_status() -> Dictionary:
	if _worker == null or not is_instance_valid(_worker) or not _worker.has_method("get_status"):
		return {"enabled": false, "connected": false, "reason": WORKER_UNAVAILABLE}
	return _worker.get_status()


func worker_request(operation: String, args: Dictionary) -> Dictionary:
	if _worker == null or not is_instance_valid(_worker) or not _worker.has_method("request"):
		return {"error": WORKER_UNAVAILABLE}
	return await _worker.request(operation, args)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_last_screenshot_image = null
		_previous_screenshot_image = null
		_context_store = null
		_worker = null


static func get_tool_defs() -> Array:
	return [
		_make_tool("runtime_screenshot", "Capture the visible viewport as a local context artifact; returns path, id, dimensions and expiry metadata", {"format": {"type": "string", "enum": ["png", "jpg"], "default": "png"}, "persist_context": {"type": "boolean", "default": true}}, [], true),
		_make_tool("runtime_get_pixel", "Get the color of a pixel from the last screenshot", {"x": {"type": "integer"}, "y": {"type": "integer"}}, ["x", "y"]),
		_make_tool("runtime_get_pixel_region", "Sample a screenshot region as a color grid", {"x": {"type": "integer"}, "y": {"type": "integer"}, "w": {"type": "integer"}, "h": {"type": "integer"}, "step": {"type": "integer", "default": 4}}, ["x", "y", "w", "h"]),
		_make_tool("runtime_find_color", "Find the first pixel matching a target hex color", {"target_hex": {"type": "string"}, "tolerance": {"type": "number", "default": 0.05}, "search_rect": {"type": "object"}}, ["target_hex"]),
		_make_tool("runtime_find_all_colors", "Find all regions matching a target hex color", {"target_hex": {"type": "string"}, "tolerance": {"type": "number", "default": 0.05}, "min_size": {"type": "integer", "default": 4}}, ["target_hex"]),
		_make_tool("runtime_count_color_pixels", "Count pixels matching a target color", {"target_hex": {"type": "string"}, "tolerance": {"type": "number", "default": 0.05}, "rect": {"type": "object"}}, ["target_hex"]),
		_make_tool("runtime_image_diff", "Compare the last screenshot with a prior local context artifact", {"previous_context_id": {"type": "string", "default": ""}, "threshold": {"type": "integer", "default": 10}}),
		_make_tool("runtime_wait_for_stable", "Wait until the visible screen stops changing and keep only the final local artifact", {"threshold": {"type": "integer", "default": 50}, "max_frames": {"type": "integer", "default": 60}, "timeout_ms": {"type": "integer", "default": 5000}}, [], true),
		_make_tool("runtime_frame_changed", "Check whether the current frame changed since a local context artifact", {"previous_context_id": {"type": "string", "default": ""}, "threshold": {"type": "integer", "default": 20}}),
		_make_tool("runtime_find_template", "Find a template image in the current screenshot", {"template_b64": {"type": "string"}, "threshold": {"type": "number", "default": 0.85}, "search_rect": {"type": "object"}}, ["template_b64"]),
		_make_tool("runtime_find_template_all", "Find all matches of a template image", {"template_b64": {"type": "string"}, "threshold": {"type": "number", "default": 0.75}, "search_rect": {"type": "object"}}, ["template_b64"]),
		_make_tool("runtime_detect_rects", "Detect rectangular UI elements in the last screenshot", {"edge_sensitivity": {"type": "number", "default": 0.15}, "min_size": {"type": "integer", "default": 8}}),
		_make_tool("runtime_detect_text_regions", "Find likely text regions in the last screenshot", {"dark_on_light": {"type": "boolean", "default": true}, "min_size": {"type": "integer", "default": 8}}),
		_make_tool("runtime_sample_grid", "Sample the last screenshot on a regular grid", {"rows": {"type": "integer"}, "cols": {"type": "integer"}, "rect": {"type": "object"}}, ["rows", "cols"]),
		_make_tool("runtime_dominant_color", "Find the dominant color in a screenshot rectangle", {"rect": {"type": "object"}}),
		_make_tool("runtime_context_list", "List recent local vision artifacts", {"limit": {"type": "integer", "default": 4}}),
		_make_tool("runtime_context_release", "Delete one local vision artifact immediately", {"context_id": {"type": "string"}}, ["context_id"]),
		_make_tool("runtime_context_cleanup", "Delete expired local vision artifacts"),
		_make_tool("runtime_vision_worker_status", "Read the optional local vision/OCR worker status"),
		_make_tool("runtime_vision_worker_analyze", "Analyze one local context artifact in the external worker", {"context_id": {"type": "string"}, "ocr": {"type": "boolean", "default": false}}, ["context_id"], true),
		_make_tool("runtime_vision_worker_ocr", "Run optional local OCR on one context artifact", {"context_id": {"type": "string"}}, ["context_id"], true),
		_make_tool("runtime_vision_worker_compare", "Compare two local context artifacts in the external worker", {"context_a": {"type": "string"}, "context_b": {"type": "string"}}, ["context_a", "context_b"], true),
	]


func dispatch_tool(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_get_pixel": return get_pixel(_last_screenshot_image, int(args.get("x", 0)), int(args.get("y", 0)))
		"runtime_get_pixel_region": return get_pixel_region(_last_screenshot_image, int(args.get("x", 0)), int(args.get("y", 0)), int(args.get("w", 100)), int(args.get("h", 100)), int(args.get("step", 4)))
		"runtime_find_color": return find_color(_last_screenshot_image, str(args.get("target_hex", "#FFFFFF")), float(args.get("tolerance", 0.05)), args.get("search_rect", {}))
		"runtime_find_all_colors": return find_all_colors(_last_screenshot_image, str(args.get("target_hex", "#FFFFFF")), float(args.get("tolerance", 0.05)), int(args.get("min_size", 4)))
		"runtime_count_color_pixels": return count_color_pixels(_last_screenshot_image, str(args.get("target_hex", "#FFFFFF")), float(args.get("tolerance", 0.05)), args.get("rect", {}))
		"runtime_image_diff": return image_diff(str(args.get("previous_context_id", "")), int(args.get("threshold", 10)))
		"runtime_frame_changed": return frame_changed_since(str(args.get("previous_context_id", "")), int(args.get("threshold", 20)))
		"runtime_find_template": return find_template(str(args.get("template_b64", "")), float(args.get("threshold", 0.85)), args.get("search_rect", {}))
		"runtime_find_template_all": return find_template_all(str(args.get("template_b64", "")), float(args.get("threshold", 0.75)), args.get("search_rect", {}))
		"runtime_detect_rects": return detect_rects(_last_screenshot_image, float(args.get("edge_sensitivity", 0.15)), int(args.get("min_size", 8)))
		"runtime_detect_text_regions": return detect_text_regions(_last_screenshot_image, bool(args.get("dark_on_light", true)), 3, int(args.get("min_size", 8)))
		"runtime_sample_grid": return sample_grid(_last_screenshot_image, int(args.get("rows", 10)), int(args.get("cols", 10)), args.get("rect", {}))
		"runtime_dominant_color": return dominant_color(_last_screenshot_image, args.get("rect", {}))
		"runtime_context_list": return _context_store.latest(int(args.get("limit", 4))) if _context_store != null else {"contexts": [], "count": 0}
		"runtime_context_release": return _context_store.release(str(args.get("context_id", ""))) if _context_store != null else {"released": false, "reason": "context_store_unavailable"}
		"runtime_context_cleanup": return _context_store.cleanup() if _context_store != null else {"removed": 0, "remaining": 0}
		"runtime_vision_worker_status": return worker_status()
		_: return {"error": "Unknown vision tool: " + tool_name}


func dispatch_async(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_screenshot":
			var screenshot: Dictionary = await capture_screenshot(str(args.get("format", "png")), bool(args.get("persist_context", true)))
			screenshot.erase("image")
			return screenshot
		"runtime_wait_for_stable": return await wait_for_stable(int(args.get("threshold", 50)), int(args.get("max_frames", 60)), int(args.get("timeout_ms", 5000)))
		"runtime_vision_worker_analyze":
			return await worker_request("analyze", {"context_id": str(args.get("context_id", "")), "ocr": bool(args.get("ocr", false))})
		"runtime_vision_worker_ocr":
			return await worker_request("ocr", {"context_id": str(args.get("context_id", ""))})
		"runtime_vision_worker_compare":
			return await worker_request("compare", {"context_a": str(args.get("context_a", "")), "context_b": str(args.get("context_b", ""))})
		_: return {"error": "Unknown async vision tool: " + tool_name}


static func _make_tool(name: String, description: String, properties: Dictionary = {}, required: Array = [], async_tool: bool = false) -> Dictionary:
	var schema := {"type": "object", "properties": properties}
	if not required.is_empty(): schema["required"] = required
	var tool := {"name": name, "description": description, "inputSchema": schema}
	if async_tool: tool["_async"] = true
	return tool