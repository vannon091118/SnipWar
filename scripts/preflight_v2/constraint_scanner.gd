extends RefCounted

## Scans the preflight/ directory for constraint scripts and builds a
## registry dynamically.  No manual CONSTRAINT_REGISTRY array needed.

const CONSTRAINT_DIR := "res://scripts/preflight"


## Returns Array[Dictionary] — each entry has keys:
##   id, script, desc, requires_scene
func scan() -> Array[Dictionary]:
	var registry: Array[Dictionary] = []
	var dir := DirAccess.open(CONSTRAINT_DIR)
	if dir == null:
		push_error("[constraint_scanner] Cannot open directory: %s" % CONSTRAINT_DIR)
		return registry

	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue
		if not entry.begins_with("constraint_"):
			continue
		if not entry.ends_with(".gd"):
			continue

		var file_path: String = CONSTRAINT_DIR.path_join(entry)
		var script: Script = load(file_path) as Script
		if script == null:
			push_warning("[constraint_scanner] Failed to load: %s" % file_path)
			continue

		var instance: RefCounted = script.new() as RefCounted
		if instance == null:
			push_warning("[constraint_scanner] Failed to instantiate: %s" % file_path)
			continue

		# Check for required interface
		if not _has_interface(instance):
			push_warning("[constraint_scanner] No constraint_name/run interface: %s" % file_path)
			continue

		var c_id: String = String(instance.constraint_name())
		var c_desc: String = ""
		if instance.has_method("constraint_description"):
			c_desc = String(instance.constraint_description())
		# Safe default: scene required. Constraints must opt-in to pure
		# by explicitly returning false from requires_scene().
		var c_requires_scene: bool = true
		if instance.has_method("requires_scene"):
			c_requires_scene = bool(instance.requires_scene())

		registry.append({
			"id": c_id,
			"script": script,
			"desc": c_desc,
			"requires_scene": c_requires_scene,
		})

	dir.list_dir_end()
	return registry


func _has_interface(instance: RefCounted) -> bool:
	return instance.has_method("constraint_name") and instance.has_method("run")
