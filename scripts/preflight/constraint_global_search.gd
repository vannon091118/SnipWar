class_name PreflightConstraintGlobalSearch
extends RefCounted

## Validates that Global Search tool works correctly (functional smoke test).

var _query: String
var _extensions: Array[String]
var _exclude_dirs: Array[String]
var _max_results: int
var _context_lines: int
var _regex_mode: bool = false
var _freq_mode: bool = false
var _defs_mode: bool = false
var _definition_sources: Array[Dictionary] = []

func constraint_name() -> String:
	return "global_search"

func run(ctx: PreflightContext) -> bool:
	# Test 1: Basic search returns results
	var results_basic = _run_search("fleet")
	if not ctx.check(results_basic.has("results"), "Global Search basic query returns results"):
		return false
	if not ctx.check(results_basic.results.size() > 0, "Global Search finds 'fleet' in codebase"):
		return false

	# Test 2: Type filter works
	var results_type = _run_search("fleet", ["gd"])
	if not ctx.check(results_type.has("by_type"), "Global Search type filter returns by_type"):
		return false
	if not ctx.check(results_type.by_type.has("gd"), "Global Search filters to .gd files"):
		return false

	# Test 3: JSON output is valid
	if not ctx.check(results_basic.has("query"), "Global Search JSON has query field"):
		return false
	if not ctx.check(results_basic.has("duration_ms"), "Global Search JSON has duration_ms"):
		return false

	# Test 4: Exclude dirs works
	var results_exclude = _run_search("fleet", [], ["addons"])
	if not ctx.check(results_exclude.has("total_files_scanned"), "Global Search exclude returns scanned count"):
		return false

	# Test 5: LOC counting is present
	if not ctx.check(results_basic.has("total_line_count"), "Global Search reports total_line_count"):
		return false
	if not ctx.check(results_basic.total_line_count > 0, "Global Search total_line_count > 0"):
		return false
	# Verify line_count per file
	if results_basic.results.size() > 0:
		var first_hit: Dictionary = results_basic.results[0]
		if not ctx.check(first_hit.has("line_count"), "Global Search hit has line_count per file"):
			return false

	# Test 6: Frequency aggregation (--freq)
	var results_freq = _run_search_freq("fleet")
	if not ctx.check(results_freq.has("frequency"), "Global Search --freq returns frequency array"):
		return false
	if not ctx.check(results_freq.frequency.size() > 0, "Global Search --freq has non-empty frequency"):
		return false
	var first_freq: Dictionary = results_freq.frequency[0]
	if not ctx.check(first_freq.has("count"), "Global Search frequency entries have count"):
		return false

	# Test 7: Definitions mode (--defs) scans all GDScript sources.
	var results_defs = _run_search_defs("assemble_ship")
	if not ctx.check(results_defs.has("definitions"), "Global Search --defs returns definitions data"):
		return false
	if not ctx.check(results_defs.definitions.has("total_definitions"), "Global Search --defs reports total definitions"):
		return false
	if not ctx.check(results_defs.has("definition_files_scanned") and results_defs.definition_files_scanned > 0, "Global Search --defs scans GDScript sources"):
		return false

	# Test 8: Regex mode (--regex)
	var results_regex = _run_search_regex("func")
	if not ctx.check(results_regex.has("results"), "Global Search --regex returns results"):
		return false
	if not ctx.check(results_regex.results.size() > 0, "Global Search --regex finds matches"):
		return false
	# Regex matches should have matched_text
	var first_regex_match: Dictionary = results_regex.results[0].matches[0]
	if not ctx.check(first_regex_match.has("matched_text"), "Global Search regex match has matched_text"):
		return false

	if ctx.verbose:
		print("Global Search: basic=%d hits, gd-only=%d hits, freq=%d unique, defs=%d, regex=%d hits, LOC=%d, duration=%dms" % [
			results_basic.total_hits, results_type.total_hits,
			results_freq.frequency.size(), results_defs.definitions.total_definitions,
			results_regex.total_hits, results_basic.total_line_count, results_basic.duration_ms
		])

	return true

func _run_search(query: String, types: Array[String] = [], exclude: Array[String] = []) -> Dictionary:
	_query = query.to_lower()
	if types.size() > 0:
		_extensions = types
	else:
		_extensions = ["gd", "tres", "tscn", "json", "md"]

	if exclude.size() > 0:
		_exclude_dirs = exclude
	else:
		_exclude_dirs = [".godot", ".git", ".import", "build", "dist", "node_modules"]

	_max_results = 50
	_context_lines = 2
	_regex_mode = false
	_freq_mode = false
	_defs_mode = false

	return _search_all()

func _run_search_freq(query: String) -> Dictionary:
	_query = query.to_lower()
	_extensions = ["gd", "tres", "tscn", "json", "md"]
	_exclude_dirs = [".godot", ".git", ".import", "build", "dist", "node_modules"]
	_max_results = 50
	_context_lines = 2
	_regex_mode = false
	_freq_mode = true

	return _search_all()

func _run_search_defs(query: String) -> Dictionary:
	_query = query.to_lower()
	_extensions = ["gd"]
	_exclude_dirs = [".godot", ".git", ".import", "build", "dist", "node_modules"]
	_max_results = 50
	_context_lines = 0
	_regex_mode = false
	_freq_mode = false
	_defs_mode = true

	return _search_all()

func _run_search_regex(query: String) -> Dictionary:
	_query = query  # Keep original case for regex
	_extensions = ["gd", "tres", "tscn", "json", "md"]
	_exclude_dirs = [".godot", ".git", ".import", "build", "dist", "node_modules"]
	_max_results = 50
	_context_lines = 2
	_regex_mode = true
	_freq_mode = false
	_defs_mode = false

	return _search_all()

func _search_all() -> Dictionary:
	var hits: Array[Dictionary] = []
	_definition_sources.clear()
	var total_files_scanned: int = 0
	var total_line_count: int = 0
	var start_time: float = Time.get_ticks_msec() / 1000.0

	var scan_totals: Array = _scan_dir("res://", hits, 0, 0)
	total_files_scanned = int(scan_totals[0])
	total_line_count = int(scan_totals[1])

	var duration_ms: int = int((Time.get_ticks_msec() / 1000.0 - start_time) * 1000)

	var by_type: Dictionary = {}
	for hit in hits:
		var t: String = hit.type
		by_type[t] = by_type.get(t, 0) + hit.matches.size()

	var result_dict: Dictionary = {
		"query": _query,
		"total_hits": hits.size(),
		"total_files_scanned": total_files_scanned,
		"total_line_count": total_line_count,
		"duration_ms": duration_ms,
		"by_type": by_type,
		"results": hits.slice(0, _max_results)
	}

	if _freq_mode:
		result_dict["frequency"] = _aggregate_frequency(hits)
	if _defs_mode:
		result_dict["definitions"] = _analyze_definitions()
		result_dict["definition_files_scanned"] = _definition_sources.size()

	return result_dict

## Returns [files_scanned, line_count]; GDScript ints are value types, so
## totals accumulate via return values (same contract as global_search.gd).
func _scan_dir(path: String, hits: Array, running_files: int, running_lines: int) -> Array:
	var totals: Array = [int(running_files), int(running_lines)]
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return totals
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue
		if entry in _exclude_dirs:
			continue
		var child_path: String = path.path_join(entry)
		if dir.current_is_dir():
			totals = _scan_dir(child_path, hits, int(totals[0]), int(totals[1]))
		else:
			totals[0] = int(totals[0]) + 1
			var ext: String = entry.get_extension().to_lower()
			if ext in _extensions:
				totals[1] = int(totals[1]) + _scan_file(child_path, ext, hits)
	dir.list_dir_end()
	return totals

func _scan_file(path: String, ext: String, hits: Array) -> int:
	if _is_binary_file(path, ext):
		return 0

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0

	var lines: Array[String] = []
	while not file.eof_reached():
		lines.append(file.get_line())
	file.close()
	if _defs_mode and ext == "gd":
		_definition_sources.append({"file": path, "lines": lines})

	var matches: Array[Dictionary] = []
	for i in range(lines.size()):
		var line: String = lines[i]
		if _query in line.to_lower():
			var start: int = max(0, i - _context_lines)
			var end: int = min(lines.size() - 1, i + _context_lines)
			var context: Array[Dictionary] = []
			for j in range(start, end + 1):
				context.append({
					"line": j + 1,
					"content": lines[j].strip_edges(),
					"is_match": j == i
				})
			matches.append({
				"match_line": i + 1,
				"matched_text": lines[i].strip_edges(),
				"groups": [],
				"context": context
			})

	if not matches.is_empty():
		hits.append({
			"file": path,
			"type": ext,
			"line_count": lines.size(),
			"matches": matches
		})
	return lines.size()

func _is_binary_file(path: String, ext: String) -> bool:
	var binary_extensions: Array[String] = ["png", "jpg", "jpeg", "webp", "gif", "bmp", "ico", "ogg", "wav", "mp3", "mp4", "avi", "mov", "ttf", "otf", "woff", "woff2", "eot", "pck", "zip", "gz", "tar", "rar", "7z"]
	if ext in binary_extensions:
		return true

	if ext == "tres" or ext == "import":
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			return false
		var header: PackedByteArray = file.get_buffer(4)
		file.close()
		if header.size() >= 1 and header[0] != 91:
			return true

	return false

func _analyze_definitions() -> Dictionary:
	var definitions: Array[Dictionary] = []
	var definition_regex := RegEx.new()
	definition_regex.compile("^\\s*(?:static\\s+)?func\\s+(_?[a-zA-Z0-9_]+)")
	for source in _definition_sources:
		var lines: Array[String] = source.lines
		for line_index in range(lines.size()):
			var match: RegExMatch = definition_regex.search(lines[line_index])
			if match == null:
				continue
			var name: String = match.get_string(1)
			if _query == "func" or _query in name.to_lower() or _query in lines[line_index].to_lower():
				definitions.append({"name": name, "file": source.file, "line": line_index + 1})

	var call_counts: Dictionary = {}
	var call_names: Dictionary = {}
	for definition in definitions:
		call_names[definition.name] = true
	var call_regex := RegEx.new()
	call_regex.compile("(^|[^A-Za-z0-9_])(_?[a-zA-Z0-9_]+)\\s*\\(")
	for source in _definition_sources:
		var lines: Array[String] = source.lines
		for line in lines:
			if definition_regex.search(line) != null:
				continue
			for call_match in call_regex.search_all(line):
				var called_name: String = call_match.get_string(2)
				if call_names.has(called_name):
					call_counts[called_name] = call_counts.get(called_name, 0) + 1

	var dead: Array[Dictionary] = []
	var live: Array[Dictionary] = []
	for definition in definitions:
		var entry := {
			"name": definition.name,
			"file": definition.file,
			"line": definition.line,
			"call_sites": call_counts.get(definition.name, 0)
		}
		if entry.call_sites == 0:
			dead.append(entry)
		else:
			live.append(entry)
	return {
		"total_definitions": definitions.size(),
		"dead_code_candidates": dead,
		"live_functions": live
	}

func _aggregate_frequency(hits: Array) -> Array[Dictionary]:
	var freq: Dictionary = {}
	for hit in hits:
		for match_obj in hit.matches:
			var text: String = ""
			if match_obj.has("matched_text"):
				text = match_obj.matched_text
			elif match_obj.has("context"):
				for ctx in match_obj.context:
					if ctx.is_match:
						text = ctx.content
						break
			if text.is_empty():
				continue
			freq[text] = freq.get(text, 0) + 1

	var sorted_keys: Array = freq.keys()
	sorted_keys.sort_custom(func(a, b): return freq[a] > freq[b])

	var result: Array[Dictionary] = []
	for key in sorted_keys:
		result.append({"line": key, "count": freq[key]})
	return result