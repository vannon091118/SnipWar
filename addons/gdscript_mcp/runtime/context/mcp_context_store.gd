extends RefCounted
class_name McpContextStore

## Local-only artifact store for runtime/editor vision.
## MCP returns metadata and local paths; workers read the files directly.

const DEFAULT_ROOT_PATH := "user://mcp_context"
const DEFAULT_TTL_SECONDS := 45.0
const MAX_RECORDS := 6
const MAX_TOTAL_BYTES := 32 * 1024 * 1024

var _root_path := DEFAULT_ROOT_PATH
var _records: Dictionary = {}
var _sequence := 0


func _init() -> void:
	_ensure_directory()
	_cleanup_disk(Time.get_unix_time_from_system())


func configure(root_path: String) -> void:
	var normalized := root_path.strip_edges()
	_root_path = normalized if normalized != "" else DEFAULT_ROOT_PATH
	_records.clear()
	_ensure_directory()
	_cleanup_disk(Time.get_unix_time_from_system())


func write_image(image: Image, format_name: String, metadata: Dictionary = {}, ttl_seconds: float = DEFAULT_TTL_SECONDS) -> Dictionary:
	if image == null or image.is_empty():
		return {"error": "Cannot store an empty image"}
	_ensure_directory()
	_sequence += 1
	var normalized_format := "jpg" if format_name == "jpg" or format_name == "jpeg" else "png"
	var extension := ".jpg" if normalized_format == "jpg" else ".png"
	var now := Time.get_unix_time_from_system()
	var context_id := "frame_%d_%d" % [Time.get_ticks_msec(), _sequence]
	var relative_image_path := _root_path.path_join(context_id + extension)
	var absolute_image_path := ProjectSettings.globalize_path(relative_image_path)
	var bytes: PackedByteArray
	var worker_relative_path := relative_image_path
	var worker_absolute_path := absolute_image_path
	var worker_bytes := PackedByteArray()
	if normalized_format == "jpg":
		bytes = image.save_jpg_to_buffer(88)
		# The optional local workers intentionally have no JPEG dependency. Keep
		# the requested JPEG artifact for callers and a PNG companion for worker
		# analysis in the same session-local directory.
		worker_relative_path = _root_path.path_join(context_id + ".png")
		worker_absolute_path = ProjectSettings.globalize_path(worker_relative_path)
		worker_bytes = image.save_png_to_buffer()
	else:
		bytes = image.save_png_to_buffer()
	var image_file := FileAccess.open(absolute_image_path, FileAccess.WRITE)
	if image_file == null:
		return {"error": "Could not open context image for writing"}
	image_file.store_buffer(bytes)
	image_file.close()
	if normalized_format == "jpg":
		var worker_file := FileAccess.open(worker_absolute_path, FileAccess.WRITE)
		if worker_file == null:
			DirAccess.remove_absolute(absolute_image_path)
			return {"error": "Could not open worker context image for writing"}
		worker_file.store_buffer(worker_bytes)
		worker_file.close()

	var record := {
		"context_id": context_id,
		"path": relative_image_path,
		"absolute_path": absolute_image_path,
		"format": normalized_format,
		"mime_type": "image/jpeg" if normalized_format == "jpg" else "image/png",
		"width": image.get_width(),
		"height": image.get_height(),
		"size_bytes": bytes.size(),
		"worker_path": worker_relative_path,
		"worker_absolute_path": worker_absolute_path,
		"worker_format": "png",
		"worker_size_bytes": worker_bytes.size() if normalized_format == "jpg" else 0,
		"created_at": now,
		"expires_at": now + maxf(1.0, ttl_seconds),
		"metadata": metadata.duplicate(true),
	}
	if not _write_metadata(record):
		_remove_record_files(record)
		return {"error": "Could not write context metadata"}
	_records[context_id] = record
	_enforce_limits()
	return record.duplicate(true)


func get_root_path() -> String:
	return ProjectSettings.globalize_path(_root_path)


func get_record(context_id: String) -> Dictionary:
	_cleanup_disk(Time.get_unix_time_from_system())
	if not _records.has(context_id):
		return {}
	return (_records[context_id] as Dictionary).duplicate(true)


func read_image(context_id: String) -> Image:
	var record := get_record(context_id)
	if record.is_empty():
		return null
	var path := str(record.get("absolute_path", ""))
	if path == "":
		path = ProjectSettings.globalize_path(str(record.get("path", "")))
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	var format_name := str(record.get("format", "png"))
	var load_error: int = OK
	if format_name == "jpg":
		load_error = image.load_jpg(path)
	else:
		load_error = image.load_png(path)
	return image if load_error == OK and not image.is_empty() else null


func get_stats() -> Dictionary:
	var total_bytes := 0
	for value in _records.values():
		var record: Dictionary = value as Dictionary
		total_bytes += int(record.get("size_bytes", 0)) + int(record.get("worker_size_bytes", 0))
	return {
		"root": get_root_path(),
		"records": _records.size(),
		"total_bytes": total_bytes,
		"max_records": MAX_RECORDS,
		"max_total_bytes": MAX_TOTAL_BYTES,
		"ttl_seconds": DEFAULT_TTL_SECONDS,
	}


func latest(limit: int = 4) -> Dictionary:
	var safe_limit := maxi(0, limit)
	_cleanup_disk(Time.get_unix_time_from_system())
	var values: Array = []
	for value in _records.values():
		values.append((value as Dictionary).duplicate(true))
	values.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("created_at", 0.0)) > float(b.get("created_at", 0.0))
	)
	if values.size() > safe_limit:
		values = values.slice(0, safe_limit)
	return {"contexts": values, "count": values.size()}


func release(context_id: String) -> Dictionary:
	if not _records.has(context_id):
		return {"released": false, "context_id": context_id, "reason": "unknown_context"}
	var record: Dictionary = _records[context_id]
	_remove_record_files(record)
	_records.erase(context_id)
	return {"released": true, "context_id": context_id}


func cleanup() -> Dictionary:
	var removed := _cleanup_disk(Time.get_unix_time_from_system())
	_enforce_limits()
	return {"removed": removed, "remaining": _records.size(), "stats": get_stats()}


func clear() -> void:
	for value in _records.values():
		_remove_record_files(value as Dictionary)
	_records.clear()


func _ensure_directory() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_root_path))


func _write_metadata(record: Dictionary) -> bool:
	var metadata_path := ProjectSettings.globalize_path(_root_path.path_join(str(record.get("context_id", "")) + ".json"))
	var file := FileAccess.open(metadata_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(record))
	file.close()
	return true


func _cleanup_disk(now: float) -> int:
	_ensure_directory()
	var removed := 0
	var dir := DirAccess.open(_root_path)
	if dir == null:
		return removed
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".json"):
			var metadata_path := _root_path.path_join(entry)
			var absolute_metadata := ProjectSettings.globalize_path(metadata_path)
			var file := FileAccess.open(absolute_metadata, FileAccess.READ)
			var record: Dictionary = {}
			if file != null:
				var parsed: Variant = JSON.parse_string(file.get_as_text())
				file.close()
				if parsed is Dictionary:
					record = parsed
			var context_id := str(record.get("context_id", entry.trim_suffix(".json")))
			if record.is_empty() or float(record.get("expires_at", 0.0)) <= now:
				if not record.is_empty():
					_remove_record_files(record)
				else:
					DirAccess.remove_absolute(absolute_metadata)
				_records.erase(context_id)
				removed += 1
			else:
				_records[context_id] = record
		entry = dir.get_next()
	dir.list_dir_end()
	return removed


func _enforce_limits() -> void:
	var values: Array = []
	var total_bytes := 0
	for value in _records.values():
		var record: Dictionary = value as Dictionary
		values.append(record)
		total_bytes += int(record.get("size_bytes", 0)) + int(record.get("worker_size_bytes", 0))
	values.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("created_at", 0.0)) < float(b.get("created_at", 0.0))
	)
	while values.size() > MAX_RECORDS or total_bytes > MAX_TOTAL_BYTES:
		if values.is_empty():
			break
		var oldest: Dictionary = values.pop_front()
		total_bytes -= int(oldest.get("size_bytes", 0)) + int(oldest.get("worker_size_bytes", 0))
		release(str(oldest.get("context_id", "")))


func _remove_record_files(record: Dictionary) -> void:
	var image_path := str(record.get("absolute_path", ""))
	if image_path == "":
		image_path = ProjectSettings.globalize_path(str(record.get("path", "")))
	if image_path != "":
		DirAccess.remove_absolute(image_path)
	var worker_image_path := str(record.get("worker_absolute_path", ""))
	if worker_image_path != "" and worker_image_path != image_path:
		DirAccess.remove_absolute(worker_image_path)
	var context_id := str(record.get("context_id", ""))
	if context_id != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_root_path.path_join(context_id + ".json")))
