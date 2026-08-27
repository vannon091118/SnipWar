class_name PreflightConstraintMcpCaptureContract
extends RefCounted

## HARTES mechanisches Gate für den MCP-Capture-Vertrag (kein Spielraum):
##   A. Jede `get_image()`-Site im MCP-Addon wartet in derselben Funktion auf
##      `frame_post_draw` — sonst ist der Frame-Inhalt undefiniert.
##   B. Die Sync-Umgehung `capture_screenshot_sync` darf nie wieder existieren
##      (Antwort vor dem Release-Frame).
##   C. Screenshot-touchende Tools tragen `_async=true`, damit Clients den
##      Vertrag Input → frame_post_draw → IST-Screenshot → Prüfung erzwingen.

const SCAN_ROOT: String = "res://addons/gdscript_mcp"

# Screenshot-touchende Tools → Datei, deren get_tool_defs() die Def baut.
const ASYNC_TOOLS: Dictionary = {
	"runtime_screenshot": "runtime/tools/vision/mcp_vision.gd",
	"runtime_ux_analyze": "runtime/tools/ux/mcp_ux_pipeline.gd",
	"runtime_ux_find": "runtime/tools/ux/mcp_ux_pipeline.gd",
	"runtime_ux_read": "runtime/tools/ux/mcp_ux_pipeline.gd",
	"runtime_ux_click": "runtime/tools/ux/mcp_ux_pipeline.gd",
}


func constraint_name() -> String:
	return "mcp_capture_contract"


func requires_scene() -> bool:
	return false


func run(ctx: PreflightContext) -> bool:
	var failures: PackedStringArray = []
	var capture_sites := _check_capture_sites(failures)
	for tool_name: String in ASYNC_TOOLS:
		_check_async_marker(SCAN_ROOT.path_join(str(ASYNC_TOOLS[tool_name])), tool_name, failures)
	if not failures.is_empty():
		for failure in failures:
			print("[mcp_capture_contract] VIOLATION: " + failure)
	var summary := "get_image() nur nach frame_post_draw (%d Sites), keine Sync-Umgehung, Screenshot-Tools _async" % capture_sites
	return ctx.check(failures.is_empty() and capture_sites > 0, summary, {"violations": "\n".join(failures)})


func _check_capture_sites(failures: PackedStringArray) -> int:
	var capture_sites := 0
	var func_header := RegEx.new()
	func_header.compile("^\\s*(?:static\\s+)?func\\s+")
	var gd_files: Array[String] = []
	_collect_gd_files(SCAN_ROOT, gd_files)
	gd_files.sort()
	for gd_path in gd_files:
		var file := FileAccess.open(gd_path, FileAccess.READ)
		if file == null:
			failures.append("%s: nicht lesbar" % gd_path)
			continue
		var lines: PackedStringArray = file.get_as_text().split("\n")
		file.close()
		var func_start := 0
		var sync_bypass := false
		for i in lines.size():
			var line := lines[i]
			# Kommentare sind kein Code: weder Capture-Site noch frame-Wait-Nachweis.
			if line.strip_edges().begins_with("#"):
				continue
			if line.contains("func capture_screenshot_sync"):
				sync_bypass = true
			if func_header.search(line) != null:
				func_start = i
			if not line.contains(".get_image("):
				continue
			capture_sites += 1
			var waited := false
			for j in range(func_start, i):
				var probe := lines[j].strip_edges()
				if probe.begins_with("#"):
					continue
				if probe.contains("frame_post_draw"):
					waited = true
					break
			if not waited:
				failures.append("A| %s:%d get_image() ohne frame_post_draw in derselben Funktion" % [gd_path, i + 1])
		if sync_bypass:
			failures.append("B| %s definiert die verbotene Sync-Umgehung capture_screenshot_sync" % gd_path)
	return capture_sites


## Tool-Defs sind einzeilige _make/_make_tool-Calls; der Def endet bei
## Async-Markierung mit `, true)`.
func _check_async_marker(path: String, tool: String, failures: PackedStringArray) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		failures.append("C| %s: nicht lesbar (Tool %s)" % [path, tool])
		return
	var def_regex := RegEx.new()
	def_regex.compile("^\\s*_make(?:_tool)?\\(\\s*\"%s\"" % tool)
	var tail_regex := RegEx.new()
	tail_regex.compile(",\\s*true\\s*\\)\\s*,?\\s*$")
	for line in file.get_as_text().split("\n"):
		if def_regex.search(line) == null:
			continue
		if tail_regex.search(line) == null:
			failures.append("C| %s Tool '%s' ist nicht async deklariert (Def endet nicht mit ', true')" % [path, tool])
		return
	failures.append("C| %s: Tool '%s' fehlt im Tool-Katalog" % [path, tool])


func _collect_gd_files(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect_gd_files(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
