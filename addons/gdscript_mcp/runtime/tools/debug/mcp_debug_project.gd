extends RefCounted
class_name McpDebugProject

## McpDebugProject — Project-level inspection (extracted from McpDebug).
## Static helpers for project config, file listing, class reflection.


static func get_project_config() -> Dictionary:
	var result: Dictionary = {}
	var property_list: Array = ProjectSettings.get_property_list()
	for prop in property_list:
		var pd: Dictionary = prop
		var pname: String = pd.name
		if pname.begins_with("_"):
			continue
		result[pname] = McpDebugHelpers.to_serializable(ProjectSettings.get_setting(pname))
	return result


static func list_project_files(filter_str: String = "", max_depth: int = 5) -> Dictionary:
	var files: Array = []
	var dirs: Array = []
	_collect_files_recursive("res://", filter_str, files, dirs, 0, max_depth)
	var sorted_files := files.duplicate()
	var sorted_dirs := dirs.duplicate()
	sorted_files.sort()
	sorted_dirs.sort()
	return {"files": sorted_files, "directories": sorted_dirs, "file_count": sorted_files.size(), "dir_count": sorted_dirs.size()}


static func _collect_files_recursive(base: String, filter_str: String, files: Array, dirs: Array, depth: int, max_depth: int) -> void:
	if depth > max_depth:
		return
	var da: DirAccess = DirAccess.open(base)
	if not da:
		return
	dirs.append(base)
	da.list_dir_begin()
	var entry: String = da.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = da.get_next()
			continue
		var full: String = base.path_join(entry)
		if da.current_is_dir():
			_collect_files_recursive(full, filter_str, files, dirs, depth + 1, max_depth)
		else:
			if filter_str == "" or filter_str in entry:
				files.append(full)
		entry = da.get_next()
	da.list_dir_end()


static func get_class_info(cls_name: String) -> Dictionary:
	if not ClassDB.class_exists(cls_name):
		return {"error": "Class not found: " + cls_name}

	var properties: Array = []
	for p in ClassDB.class_get_property_list(cls_name):
		var pd: Dictionary = p
		properties.append({"name": pd.name, "type": pd.type})

	var methods: Array = []
	for m in ClassDB.class_get_method_list(cls_name):
		var md: Dictionary = m
		var args: Array = []
		for a in md.args:
			var ad: Dictionary = a
			args.append({"name": ad.name, "type": ad.type})
		methods.append({"name": md.name, "args": args})

	var signals_list: Array = []
	for s in ClassDB.class_get_signal_list(cls_name):
		var sd: Dictionary = s
		signals_list.append({"name": sd.name, "arg_count": sd.args.size()})

	return {"name": cls_name, "base_class": ClassDB.get_parent_class(cls_name), "properties": properties, "methods": methods, "signals": signals_list}


static func get_resource_uid(path: String) -> Dictionary:
	var uid := ResourceLoader.get_resource_uid(path)
	return {"path": path, "exists": ResourceLoader.exists(path), "uid": uid}