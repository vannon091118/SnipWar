extends RefCounted
class_name McpPathValidator

## Slice B/C - zentrale res://- und user://- Pfadvalidierung.
## Fail-closed: erlaubtes Praefix, kein Traversal, kein absoluter OS-Pfad,
## kein Root-/Nebenpfad, keine Kontrollzeichen.


static func normalize(path: String) -> String:
	return String(path).replace("\\", "/").strip_edges()


static func is_allowed_path(path: String, allowed_prefixes: Array = []) -> Dictionary:
	var normalized := normalize(path)
	if normalized == "":
		return {"ok": false, "reason": "empty path"}
	if not (normalized.begins_with("res://") or normalized.begins_with("user://")):
		return {"ok": false, "reason": "only res:// and user:// paths are supported"}
	if normalized.contains(".."):
		return {"ok": false, "reason": "path traversal (..) is not allowed"}
	for part in normalized.split("/"):
		if part.contains(char(0)) or part.contains("\n") or part.contains("\r"):
			return {"ok": false, "reason": "control characters in path"}
	if allowed_prefixes.size() > 0:
		var allowed := false
		for prefix in allowed_prefixes:
			var normalized_prefix := normalize(str(prefix))
			if normalized == normalized_prefix or normalized.begins_with(normalized_prefix + "/"):
				allowed = true
				break
		if not allowed:
			return {"ok": false, "reason": "path outside allowed prefixes: " + str(allowed_prefixes)}
	return {"ok": true, "path": normalized}


static func is_within_root(path: String, root: String) -> Dictionary:
	var normalized := normalize(path)
	var normalized_root := normalize(root)
	if normalized_root == "":
		return {"ok": false, "reason": "missing root"}
	if normalized == normalized_root or normalized.begins_with(normalized_root + "/"):
		return {"ok": true, "path": normalized}
	return {"ok": false, "reason": "path outside of workspace root"}


static func sha256_of_text(text: String) -> String:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(text.to_utf8_buffer())
	return hasher.finish().hex_encode()


static func sha256_of_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	return hasher.finish().hex_encode()


static func file_exists(path: String) -> bool:
	return FileAccess.file_exists(path)


static func secure_read(path: String, allowed_prefixes: Array = []) -> Dictionary:
	var valid := is_allowed_path(path, allowed_prefixes)
	if not bool(valid.get("ok", false)):
		return {"ok": false, "error": str(valid.get("reason", "invalid path"))}
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "file not found: " + path}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "cannot open file: " + path}
	var text := f.get_as_text()
	f.close()
	return {"ok": true, "text": text, "sha256": sha256_of_file(path), "bytes": text.to_utf8_buffer().size()}