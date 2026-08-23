extends RefCounted
class_name McpUxLive

## McpUxLive — Live scene-tree snapshot for the UX pipeline.
## Extracted so the pipeline can answer "what changed?" cheaply:
##   build_snapshot() → full control listing
##   control_signature() → compact string for delta detection (watch clock)
## The pipeline polls this instead of re-running pixel analysis, and only does
## expensive visual analysis when the signature actually changed.

const MAX_DEPTH := 48
const MAX_CONTROLS := 1200

## Frame-cache: reuse the last snapshot within the same frame.
static var _cached_snapshot: Dictionary = {}
static var _cached_frame: int = -1


static func build_snapshot() -> Dictionary:
	# Always build a fresh snapshot — correctness over cache.
	var main_loop := Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return {"scene": "unknown", "scene_name": "", "scene_path": "", "controls": [], "control_count": 0}
	var tree := main_loop as SceneTree
	var root := tree.root
	var current := tree.current_scene
	var controls: Array = []
	if root != null:
		collect_controls(root, controls, 0)
	var scene_name := String(current.name) if current != null else "unknown"
	var snapshot := {
		"scene": scene_name_hint(scene_name, controls),
		"scene_name": scene_name,
		"scene_path": String(current.get_path()) if current != null else "",
		"controls": controls,
		"control_count": controls.size(),
		"timestamp_ms": Time.get_ticks_msec(),
	}
	_cached_frame = Engine.get_process_frames()
	_cached_snapshot = snapshot.duplicate(true)
	return snapshot


static func collect_controls(node: Node, controls: Array, depth: int) -> void:
	if depth > MAX_DEPTH or controls.size() >= MAX_CONTROLS:
		return
	# CanvasLayer nodes hold their children on a separate visual layer, but
	# get_children() still returns them — explicit visibility guard ensures
	# we only collect them when the layer itself is visible.
	var canvas_layer_visible := true
	if node is CanvasLayer:
		canvas_layer_visible = (node as CanvasLayer).visible
	if node is Control and (node as Control).is_visible_in_tree() and canvas_layer_visible:
		var control: Control = node as Control
		var is_button := node is BaseButton
		var is_input := node is LineEdit or node is TextEdit
		var is_label := node is Label
		if is_button or is_input or is_label:
			var rect := control.get_global_rect()
			var entry := {
				"source": "scene_tree",
				"path": String(node.get_path()),
				"name": String(node.name),
				"type": node.get_class(),
				"kind": "button" if is_button else ("input" if is_input else "label"),
				"rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
				"center": {"x": rect.position.x + rect.size.x * 0.5, "y": rect.position.y + rect.size.y * 0.5},
				"visible": true,
				"interactable": is_button or is_input,
				"has_focus": control.has_focus(),
				"mouse_filter": control.mouse_filter,
			}
			if node is BaseButton:
				var button: BaseButton = node as BaseButton
				entry["disabled"] = button.disabled
				entry["pressed"] = button.button_pressed
			if node is Button:
				entry["text"] = String((node as Button).text)
			elif node is Label:
				entry["text"] = String((node as Label).text)
			elif node is LineEdit:
				entry["text"] = String((node as LineEdit).text)
				entry["placeholder"] = String((node as LineEdit).placeholder_text)
			controls.append(entry)
	# Always recurse into children — CanvasLayer children are regular Node
	# children and must be traversed regardless of the parent type.
	for child in node.get_children():
		collect_controls(child, controls, depth + 1)


## Compact, order-independent fingerprint of the visible control set.
## Used by the watch clock to detect UI changes between polls.
static func control_signature(snapshot: Dictionary) -> String:
	var parts: Array[String] = []
	var controls: Array = snapshot.get("controls", [])
	for raw in controls:
		var c: Dictionary = raw as Dictionary
		var kind := String(c.get("kind", "?"))
		var text := String(c.get("text", "")).to_lower()
		var p := str(c.get("path", ""))
		var rect: Dictionary = c.get("rect", {})
		var geometry := "%d,%d,%d,%d" % [int(rect.get("x", 0)), int(rect.get("y", 0)), int(rect.get("w", 0)), int(rect.get("h", 0))]
		var disabled := 1 if bool(c.get("disabled", false)) else 0
		var pressed := 1 if bool(c.get("pressed", false)) else 0
		var focused := 1 if bool(c.get("has_focus", false)) else 0
		parts.append(kind + ":" + p + ":" + text + ":" + geometry + ":" + str(disabled) + ":" + str(pressed) + ":" + str(focused))
	parts.sort()
	return String(snapshot.get("scene", "?")) + "#" + "|".join(parts)


static func visual_signature(image: Image, sample_step: int = 12) -> String:
	if image == null or image.is_empty():
		return "empty"
	var step := maxi(1, sample_step)
	var hash_value: int = 17
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			var c := image.get_pixel(x, y)
			hash_value = int((hash_value * 31 + int(c.r * 255.0) * 3 + int(c.g * 255.0) * 5 + int(c.b * 255.0) * 7) & 0x7fffffff)
	return str(image.get_width()) + "x" + str(image.get_height()) + ":" + str(hash_value)


static func interactables(controls: Array) -> Array:
	var result: Array = []
	for raw in controls:
		var control: Dictionary = raw as Dictionary
		if bool(control.get("interactable", false)) and not bool(control.get("disabled", false)):
			result.append(control.duplicate(true))
	return result


static func scene_name_hint(scene_name: String, controls: Array) -> String:
	var lower := scene_name.to_lower()
	if "menu" in lower:
		return "main_menu"
	if "battle" in lower:
		return "battle"
	if "conquest" in lower:
		return "conquest"
	if "world" in lower or "background" in lower:
		return "game_view"
	for raw in controls:
		var control: Dictionary = raw as Dictionary
		if String(control.get("text", "")).to_upper() == "NEUES SPIEL":
			return "main_menu"
	return "unknown"