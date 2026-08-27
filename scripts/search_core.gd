class_name SearchCore
extends RefCounted

## SearchCore — die EINE Scan-Engine für SnipWar-Volltextsuche.
##
## Wird von BEIDEM genutzt:
##   - CLI-Tool  scripts/global_search.gd   (dünner Wrapper, LLM-JSON-Output)
##   - Preflight (constraint_global_search.gd)
##
## LLM-optimiert: Ergebnis enthält Treffer + Kontext UND einen kompakten
## dependency_graph (class_name-Verfügbarkeit, extends-Kette, preload/load-
## Abhängigkeiten) — ein einziger Tool-Call liefert alle Relationen.

const DEFAULT_EXTENSIONS: Array[String] = [
	"gd", "tres", "tscn", "gdshader", "import", "json", "csv", "md", "txt",
	"cs", "glsl", "shader", "cfg", "ini", "toml", "yaml", "yml", "xml"
]
const DEFAULT_EXCLUDE_DIRS: Array[String] = [".godot", ".git", ".import", "build", "dist", "node_modules"]

var query: String = ""
var alternatives: Array[String] = []
var extensions: Array[String] = []
var exclude_dirs: Array[String] = []
var max_results: int = 200
var context_lines: int = 2
var regex_mode: bool = false
## alle gd-Quellen des letzten Laufs (für den dependency graph)
var _gd_sources: Array[Dictionary] = []
## Wenn true, überspringt run() den _scan_dir-Durchlauf.
## Wird von PreflightCodeIndex.inject_into_search_core() gesetzt.
var _sources_injected: bool = false


## Befüllt _gd_sources von extern (PreflightCodeIndex-Sharing).
## Muss vor configure()+run() aufgerufen werden.
## Format: Array[{file:String, lines:Array[String]}]
func inject_sources(sources: Array[Dictionary]) -> void:
	_gd_sources.clear()
	_gd_sources.assign(sources)
	_sources_injected = true


func configure(q: String, types: Array = [], exclude: Array = [], p_max_results: int = 200, p_context_lines: int = 2, p_regex_mode: bool = false) -> void:
	query = q
	alternatives.clear()
	for part in q.to_lower().split("|"):
		var trimmed := part.strip_edges()
		if not trimmed.is_empty():
			alternatives.append(trimmed)
	if alternatives.is_empty():
		alternatives.append(q.to_lower())
	extensions = []
	extensions.assign(types) if not types.is_empty() else extensions.assign(DEFAULT_EXTENSIONS)
	exclude_dirs = []
	for e in exclude:
		if String(e).is_empty():
			continue
		exclude_dirs.append(String(e))
	if exclude_dirs.is_empty():
		exclude_dirs.assign(DEFAULT_EXCLUDE_DIRS)
	max_results = p_max_results
	context_lines = maxi(0, p_context_lines)
	regex_mode = p_regex_mode


func run() -> Dictionary:
	var hits: Array[Dictionary] = []
	var start_ms: int = Time.get_ticks_msec()
	var totals: Array

	if _sources_injected:
		# Fast path: index already in RAM, no disk scan needed.
		# Respects exclude_dirs by skipping files whose path contains an excluded segment.
		_sources_injected = false  # Reset so next standalone run() works correctly
		var total_lines := 0
		for source in _gd_sources:
			var file_path: String = String(source.file)
			var excluded := false
			for excl_dir in exclude_dirs:
				if file_path.contains("/" + excl_dir + "/") or file_path.contains("\\" + excl_dir + "\\"):
					excluded = true
					break
			if excluded:
				continue
			var lines: Array = source.get("lines", [])
			total_lines += lines.size()
			_search_lines_for_hits(file_path, "gd", lines, hits)
		totals = [_gd_sources.size(), total_lines]
	else:
		# Normal path: full disk scan (CLI tool, standalone usage).
		_gd_sources.clear()
		totals = _scan_dir("res://", hits, 0, 0)

	var duration_ms: int = Time.get_ticks_msec() - start_ms

	var by_type: Dictionary = {}
	for hit in hits:
		var ext := String(hit.get("type", ""))
		by_type[ext] = int(by_type.get(ext, 0)) + int(hit.get("matches", []).size())

	var result := {
		"query": query,
		"alternatives": alternatives if alternatives.size() > 1 else [],
		"total_hits": hits.size(),
		"total_files_scanned": int(totals[0]),
		"total_line_count": int(totals[1]),
		"duration_ms": duration_ms,
		"by_type": by_type,
		"results": hits.slice(0, max_results),
		"classes_available": _class_availability(),
		"dependency_graph": _dependency_graph(),
	}
	return result


## Liefert {ClassName: res://Pfad} aller gefundenen class_name-Deklarationen.
func _class_availability() -> Dictionary:
	var result: Dictionary = {}
	for source in _gd_sources:
		var path := String(source.file)
		for line in source.lines:
			var l := String(line).strip_edges()
			if l.begins_with("class_name "):
				result[l.substr("class_name ".length()).strip_edges()] = path
				break
	return result


## Pro-Datei: class_name, extends-Kette, preload/load-Abhängigkeiten.
func _dependency_graph() -> Dictionary:
	var regex_class := RegEx.new()
	regex_class.compile("class_name ([A-Za-z0-9_]+)")
	var regex_extends := RegEx.new()
	regex_extends.compile("\\bextends\\s+([A-Za-z0-9_.\\:]+)")
	var regex_preload := RegEx.new()
	regex_preload.compile("preload\\(\"(res://[^\"]+)\"")
	var regex_load := RegEx.new()
	regex_load.compile("(?:pre)?load\\(\"([^\"]+\\.(?:gd|tres|tscn))\"")
	var graph: Dictionary = {}
	for source in _gd_sources:
		var path: String = String(source.file)
		var entry := {
			"class_name": "",
			"extends": "",
			"preloads": [],
			"loads": [],
		}
		for line in source.lines:
			var l := String(line)
			if entry.class_name == "" and "class_name " in l:
				var m := regex_class.search(l)
				if m != null:
					entry.class_name = m.get_string(1)
			if entry.extends == "" and "extends" in l:
				var ex := regex_extends.search(l)
				if ex != null:
					entry.extends = ex.get_string(1)
			if "preload(" in l:
				var pr := regex_preload.search(l)
				if pr != null:
					entry.preloads.append(pr.get_string(1))
			if "load(" in l:
				var ld := regex_load.search(l)
				if ld != null:
					entry.loads.append(ld.get_string(1))
		graph[path] = entry
	return graph


func _scan_dir(path: String, hits: Array, running_files: int, running_lines: int) -> Array:
	var totals: Array = [running_files, running_lines]
	var directory := DirAccess.open(path)
	if directory == null:
		return totals
	directory.list_dir_begin()
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if entry.begins_with(".") or entry in exclude_dirs:
			continue
		var child: String = path.path_join(entry)
		if directory.current_is_dir():
			var sub := _scan_dir(child, hits, totals[0], totals[1])
			totals = [sub[0], sub[1]]
		else:
			totals = [totals[0] + 1, totals[1]]
			var ext: String = entry.get_extension().to_lower()
			if ext in extensions and not _is_binary(child, ext):
				totals[1] = totals[1] + _process_file(child, ext, hits)
	directory.list_dir_end()
	return totals


func _process_file(path: String, ext: String, hits: Array) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var lines: Array[String] = []
	while not file.eof_reached():
		lines.append(file.get_line())
	file.close()
	if ext == "gd":
		_gd_sources.append({"file": path, "lines": lines})
	_search_lines_for_hits(path, ext, lines, hits)
	return lines.size()


## Sucht in bereits gelesenen Zeilen nach Treffern und fügt sie zu `hits` hinzu.
## Kein Disk-I/O — wird sowohl vom normalen _process_file als auch vom
## inject_sources-Schnellpfad in run() genutzt.
func _search_lines_for_hits(path: String, ext: String, lines: Array, hits: Array) -> void:
	var matches: Array[Dictionary] = []
	if regex_mode:
		var regex := RegEx.new()
		var regex_ok := regex.compile(query) == OK
		for i in lines.size():
			var m: RegExMatch = regex.search(lines[i]) if regex_ok else null
			if not regex_ok and not _line_matches(lines[i]):
				continue
			var groups: Array[String] = []
			if m != null:
				for gi in range(1, m.get_group_count() + 1):
					groups.append(m.get_string(gi))
			matches.append({
				"line": i + 1,
				"text": lines[i].strip_edges(),
				"groups": groups,
				"context": _context(lines, i),
			})
	else:
		for i in lines.size():
			if not _line_matches(lines[i]):
				continue
			matches.append({
				"line": i + 1,
				"text": lines[i].strip_edges(),
				"context": _context(lines, i),
			})

	if not matches.is_empty():
		hits.append({
			"file": path,
			"type": ext,
			"line_count": lines.size(),
			"matches": matches,
		})


func _line_matches(line: String) -> bool:
	for alt in alternatives:
		if line.findn(alt) != -1:
			return true
	return false


func _context(lines: Array[String], idx: int) -> Array[Dictionary]:
	var start := maxi(0, idx - context_lines)
	var end := mini(lines.size() - 1, idx + context_lines)
	var result: Array[Dictionary] = []
	for j in range(start, end + 1):
		result.append({
			"line": j + 1,
			"text": lines[j].strip_edges(),
			"is_match": j == idx,
		})
	return result


func _is_binary(path: String, ext: String) -> bool:
	if ext in ["png", "jpg", "jpeg", "webp", "gif", "bmp", "ico", "ogg", "wav", "mp3", "mp4", "ttf", "otf", "woff", "woff2", "pck", "zip", "gz", "rar", "7z"]:
		return true
	return false