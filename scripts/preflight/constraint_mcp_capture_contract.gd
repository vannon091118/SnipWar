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
	# Use pre-loaded sources filtered to the MCP addon subtree.
	var mcp_sources: Array[Dictionary] = ctx.code_index.sources_under(SCAN_ROOT)
	var capture_sites := _check_capture_sites(mcp_sources, failures)
	for tool_name: String in ASYNC_TOOLS:
		var tool_path: String = SCAN_ROOT.path_join(str(ASYNC_TOOLS[tool_name]))
		_check_async_marker(tool_path, tool_name, ctx.code_index, failures)
	if not failures.is_empty():
		for failure in failures:
			print("[mcp_capture_contract] VIOLATION: " + failure)
	var summary := "get_image() nur nach frame_post_draw (%d Sites), keine Sync-Umgehung, Screenshot-Tools _async" % capture_sites
	return ctx.check(failures.is_empty() and capture_sites > 0, summary, {"violations": "\n".join(failures)})


## Iteriert über bereits geladene MCP-Quellen statt Disk-Scan.
func _check_capture_sites(sources: Array[Dictionary], failures: PackedStringArray) -> int:
	var capture_sites := 0
	var func_header := RegEx.new()
	func_header.compile("^\\s*(?:static\\s+)?func\\s+")
	for source in sources:
		var gd_path: String = String(source.file)
		var lines: Array = source.get("lines", [])
		var func_start := 0
		var sync_bypass := false
		for i in lines.size():
			var line := String(lines[i])
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
				var probe := String(lines[j]).strip_edges()
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


## Liest Tool-Defs via CodeIndex statt eigenem FileAccess.
func _check_async_marker(path: String, tool: String, code_index: PreflightCodeIndex, failures: PackedStringArray) -> void:
	var content: String = code_index.get_file_content(path)
	if content.is_empty():
		failures.append("C| %s: nicht lesbar (Tool %s)" % [path, tool])
		return
	var def_regex := RegEx.new()
	def_regex.compile("^\\s*_make(?:_tool)?\\(\\s*\"%s\"" % tool)
	var tail_regex := RegEx.new()
	tail_regex.compile(",\\s*true\\s*\\)\\s*,?\\s*$")
	for line in content.split("\n"):
		if def_regex.search(line) == null:
			continue
		if tail_regex.search(line) == null:
			failures.append("C| %s Tool '%s' ist nicht async deklariert (Def endet nicht mit ', true')" % [path, tool])
		return
	failures.append("C| %s: Tool '%s' fehlt im Tool-Katalog" % [path, tool])
