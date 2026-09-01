@tool
class_name AssetLibrary
extends RefCounted

## Runtime-discovered visual building blocks. The scan is deliberately explicit
## and one-shot: callers invoke scan_composition_assets() once for each fresh
## world startup, then pass the returned assets to WorldConfig for installation.

static func _scan_textures(path: String) -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	var dir = DirAccess.open(path)
	if dir == null:
		push_warning("AssetLibrary: Cannot open directory %s" % path)
		return textures
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.begins_with("."):
			# Skip hidden files
			file_name = dir.get_next()
			continue
		if file_name.ends_with(".import") or file_name.ends_with(".uid"):
			# Skip Godot import-metadata sidecars (.svg.import, .uid) —
			# they are not resources and produce "No loader found" errors.
			file_name = dir.get_next()
			continue
		var full_path = path.path_join(file_name)
		if dir.current_is_dir():
			textures.append_array(_scan_textures(full_path))
		else:
			# Importable raster/vector formats (incl. SVG with a sidecar) load
			# through the import pipeline so they keep a real resource_path.
			# Unimported files (e.g. brand-new SVGs missing a .import sidecar)
			# fall back to a magenta stand-in so the world never boot-loops.
			var tex = load(full_path) as Texture2D
			if tex != null:
				textures.append(tex)
			else:
				var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
				img.fill(Color.MAGENTA)
				var fallback_tex = ImageTexture.create_from_image(img)
				if fallback_tex != null:
					textures.append(fallback_tex)
				else:
					push_warning("AssetLibrary: Failed to create fallback texture for %s" % full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
	return textures

static func scan_star_assets() -> Array[Texture2D]:
	return _scan_textures("res://assets/objects/stars")

static func scan_composition_assets() -> Dictionary:
	return {
		"base_textures": _scan_textures("res://assets/objects/planets"),
		"decal_textures": _scan_textures("res://assets/objects/planets/decals"),
		"star_textures": _scan_textures("res://assets/objects/stars"),
	}