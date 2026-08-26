extends Node
## Optional project bridge. It auto-detects common Godot autoload contracts but
## keeps every project-specific capability optional.

@export var project_id: String = ""
@export var capabilities: Array[String] = []


func _ready() -> void:
	if project_id == "":
		project_id = str(ProjectSettings.get_setting("application/config/name", "godot_project")).to_lower().replace(" ", "_")
	_refresh_capabilities()


func current_scene() -> String:
	var root := _get_root()
	if root == null or root.get_tree().current_scene == null:
		return "unknown"
	return String(root.get_tree().current_scene.name)


func state_fingerprint() -> String:
	var state := _get_game_state()
	if state == null:
		return ""
	if state.has_method("snapshot_run"):
		var snapshot: Variant = state.call("snapshot_run")
		var canonical := JSON.stringify(_canonical(snapshot))
		return "%d:%d" % [canonical.hash(), canonical.length()]
	return ""


func snapshot_capture() -> Variant:
	var state := _get_game_state()
	if state != null and state.has_method("snapshot_run"):
		return state.call("snapshot_run")
	return null


func snapshot_restore(data: Variant) -> bool:
	var state := _get_game_state()
	if state == null or not state.has_method("restore_run") or data == null:
		return false
	var restored: Variant = state.call("restore_run", data)
	return bool(restored)


func log_sources() -> Array[String]:
	var result: Array[String] = ["engine"]
	if _get_event_log() != null:
		result.push_front("event_log")
	return result


func log_normalize_entry(source: String, raw: Variant) -> Dictionary:
	if source == "event_log" and raw is Dictionary:
		var entry: Dictionary = raw
		return {
			"source": "project",
			"level": str(entry.get("level", "info")),
			"category": str(entry.get("category", "project")),
			"text": str(entry.get("text", entry.get("message", ""))),
			"stamp": str(entry.get("stamp", Time.get_datetime_string_from_system())),
			"visible": bool(entry.get("visible", true)),
		}
	if source == "engine" and raw is String:
		return {
			"source": "engine",
			"level": "info",
			"category": "engine",
			"text": str(raw),
			"stamp": Time.get_datetime_string_from_system(),
			"visible": true,
		}
	return {}


## Postcondition hints are intentionally NOT hardcoded for UI flows anymore:
## MCP agents discover the current UI from scratch via runtime_ux_* and persist
## what they learn into the playthrough archive. Removing the old
## "IN FORSCHUNG" hint, which referenced the deleted TechnologyMenu.
func postcondition_hints(_mechanic: String) -> Dictionary:
	return {}


func _refresh_capabilities() -> void:
	capabilities.clear()
	if _get_event_log() != null:
		capabilities.append("event_log")
	if _get_game_state() != null:
		capabilities.append("state_snapshot")
	capabilities.append("scene_detection")


func _get_root() -> Window:
	var main_loop: Object = Engine.get_main_loop()
	if main_loop is SceneTree:
		return (main_loop as SceneTree).root
	return null


func _get_game_state() -> Node:
	return _find_autoload_or_named_node("GameState")


func _get_event_log() -> Node:
	return _find_autoload_or_named_node("EventLog")


func _find_autoload_or_named_node(node_name: String) -> Node:
	var root := _get_root()
	if root == null:
		return null
	var direct := root.get_node_or_null("/root/" + node_name)
	if direct != null:
		return direct
	return root.find_child(node_name, true, false)


func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var dictionary: Dictionary = {}
		for key in value:
			dictionary[String(key)] = _canonical(value[key])
		return dictionary
	if value is Array:
		var array: Array = []
		for item in value:
			array.append(_canonical(item))
		return array
	if value is StringName:
		return String(value)
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Vector3:
		return {"x": value.x, "y": value.y, "z": value.z}
	if value is Color:
		return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
	if value is Resource:
		var resource_data: Dictionary = {}
		for raw_property in value.get_property_list():
			var property: Dictionary = raw_property
			var property_name := str(property.get("name", ""))
			if property_name == "script" or not (int(property.get("usage", 0)) & PROPERTY_USAGE_STORAGE):
				continue
			resource_data[property_name] = _canonical(value.get(property_name))
		return resource_data
	if value is int or value is float or value is bool or value is String or value == null:
		return value
	return {"_class": value.get_class()}
