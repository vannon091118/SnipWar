class_name PreflightConstraintDeadCode
extends RefCounted

## Reports heuristic dead-code candidates without failing the suite. Godot
## lifecycle, signals, Callable and reflection can legitimately hide callers.

const EXCLUDE_DIRS: Array[String] = [".godot", ".git", ".import", "build", "dist", "node_modules"]
const KNOWN_RUNTIME_ENTRYPOINTS: Array[String] = [
	"_ready", "_process", "_input", "_unhandled_input", "_notification",
	"_enter_tree", "_exit_tree", "_draw", "_physics_process", "_init",
]
const KNOWN_PUBLIC_API_PREFIXES: Array[String] = ["assert_", "get_", "set_", "can_", "has_", "is_", "begin_", "advance_", "dispatch_"]

func constraint_name() -> String:
	return "dead_code"

func requires_scene() -> bool:
	return false

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

	var usage_text := ""
	for source in sources:
		usage_text += "\n" + _usage_text(source.lines)

	var candidates: Array[Dictionary] = []
	var usage_tokens: Dictionary = _build_usage_tokens(usage_text)
	for definition in definitions:
		var name: String = str(definition.name)
		var used: bool = usage_tokens.has(name)
		# Public methods are often intentional API entrypoints called by Godot,
		# resources, MCP registry routing, or external integrations. Keep them as
		# candidates only when they lack any evidence and do not inflate the
		# actionable list with standard assertion/accessor contracts.
		if not used and _is_known_entrypoint(name, str(definition.file)):
			used = true
		if not used:
			var candidate := definition.duplicate(true)
			candidate["reason"] = _candidate_reason(name, str(definition.file))
			candidates.append(candidate)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name) < String(b.name))
	print("[dead_code] %d public functions scanned, %d unresolved candidates" % [definitions.size(), candidates.size()])
	if not candidates.is_empty():
		print("[dead_code] Warning: unresolved means no static evidence; lifecycle, signals, Callable, reflection and external API calls may still be valid")
		for candidate in candidates.slice(0, 50):
			print("[dead_code]   %s (%s) -> %s:%d" % [candidate.name, candidate.reason, candidate.file, candidate.line])
		if candidates.size() > 50:
			print("[dead_code]   ... %d additional candidates omitted" % (candidates.size() - 50))
	return ctx.check(true, "Dead-code usage reconstruction completed (%d unresolved candidates; warnings are non-blocking)" % candidates.size())

func _build_usage_tokens(text: String) -> Dictionary:
	var tokens: Dictionary = {}
	var token_regex := RegEx.new()
	token_regex.compile("[A-Za-z_][A-Za-z0-9_]*")
	for match in token_regex.search_all(text):
		tokens[match.get_string()] = true
	return tokens

func _candidate_reason(name: String, file: String) -> String:
	if file.begins_with("res://addons/gdscript_mcp/"):
		return "MCP external/registry candidate"
	if file.begins_with("res://scripts/preflight/") or file.begins_with("res://scripts/doki/"):
		return "test/tooling entrypoint candidate"
	if name.begins_with("get_") or name.begins_with("can_") or name.begins_with("has_"):
		return "read/API candidate"
	return "review candidate"

func _is_known_entrypoint(name: String, file: String) -> bool:
	if name in KNOWN_RUNTIME_ENTRYPOINTS:
		return true
	for prefix in KNOWN_PUBLIC_API_PREFIXES:
		if name.begins_with(prefix):
			return true
	if file.begins_with("res://addons/gdscript_mcp/") and (name == "dispatch_tool" or name == "dispatch_async" or name == "get_tool_defs"):
		return true
	if file.begins_with("res://scripts/preflight/") or file.begins_with("res://scripts/doki/"):
		return true
	return false

func _usage_text(lines: Array[String]) -> String:
	var result := ""
	for line in lines:
		if line.strip_edges().begins_with("func ") or line.strip_edges().begins_with("static func "):
			# Keep function signatures in the text: a caller can be in another
			# declaration, but avoid counting the definition itself as a use.
			continue
		result += "\n" + line
	return result

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
