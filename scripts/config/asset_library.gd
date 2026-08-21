@tool
class_name AssetLibrary
extends RefCounted

## Runtime-discovered visual building blocks. The scan is deliberately explicit
## and one-shot: callers invoke scan_composition_assets() once for each fresh
## world startup, then pass the returned arrays into the runtime WorldConfig.

static func scan_composition_assets() -> Dictionary:
	return {
		"base_textures": _scan_textures("res://assets/objects/planets"),
		"decal_textures": _scan_textures("res://assets/objects/planets/decals"),
	}

static func _scan_textures(directory_path: String) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return result
	var files: PackedStringArray = directory.get_files()
	var sorted_files: Array[String] = []
	for file_name in files:
		var name := String(file_name)
		if name.ends_with(".svg"):
			sorted_files.append(name)
	sorted_files.sort()
	for file_name in sorted_files:
		var texture := load(directory_path.path_join(file_name)) as Texture2D
		if texture != null:
			result.append(texture)
	return result
