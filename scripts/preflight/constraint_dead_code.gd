class_name PreflightConstraintDeadCode
extends RefCounted

## Reports heuristic dead-code candidates without failing the suite. Godot
## lifecycle, signals, Callable and reflection can legitimately hide callers.

const EXCLUDE_DIRS: Array[String] = [".godot", ".git", ".import", "build", "dist", "node_modules"]

func constraint_name() -> String:
	return "dead_code"

func run(ctx: PreflightContext) -> bool:
	var definitions: Array[Dictionary] = []
	var sources: Array[Dictionary] = []
	_collect_sources("res://", sources)
	var definition_regex := RegEx.new()
	definition_regex.compile("^\\s*(?:static\\s+)?func\\s+([A-Za-z0-9_]+)")
	for source in sources:
		var lines: Array[String] = source.lines
		for index in range(lines.size()):
			var match := definition_regex.search(lines[index])
			if match == null:
				continue
			var name := match.get_string(1)
			if name.begins_with("_"):
				continue
			definitions.append({"name": name, "file": source.file, "line": index + 1})

	var wanted: Dictionary = {}
	for definition in definitions:
		wanted[definition.name] = 0
	var call_regex := RegEx.new()
	call_regex.compile("(^|[^A-Za-z0-9_])(_?[A-Za-z0-9_]+)\\s*\\(")
	for source in sources:
		for line in source.lines:
			if definition_regex.search(line) != null:
				continue
			for match in call_regex.search_all(line):
				var name := match.get_string(2)
				if wanted.has(name):
					wanted[name] = int(wanted[name]) + 1

	var candidates: Array[Dictionary] = []
	for definition in definitions:
		if int(wanted.get(definition.name, 0)) == 0:
			candidates.append(definition)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name) < String(b.name))
	print("[dead_code] %d public functions scanned, %d heuristic candidates" % [definitions.size(), candidates.size()])
	if not candidates.is_empty():
		print("[dead_code] Warning: static analysis cannot see lifecycle, signal, Callable or reflection calls")
		for candidate in candidates.slice(0, 50):
			print("[dead_code]   %s -> %s:%d" % [candidate.name, candidate.file, candidate.line])
		if candidates.size() > 50:
			print("[dead_code]   ... %d additional candidates omitted" % (candidates.size() - 50))
	return ctx.check(true, "Dead-code heuristic completed (%d candidates; warnings are non-blocking)" % candidates.size())

func _collect_sources(path: String, result: Array[Dictionary]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if entry.begins_with(".") or entry in EXCLUDE_DIRS:
			continue
		var child := path.path_join(entry)
		if directory.current_is_dir():
			_collect_sources(child, result)
		elif entry.ends_with(".gd"):
			var lines: Array[String] = []
			var file := FileAccess.open(child, FileAccess.READ)
			if file == null:
				continue
			while not file.eof_reached():
				lines.append(file.get_line())
			file.close()
			result.append({"file": child, "lines": lines})
	directory.list_dir_end()
