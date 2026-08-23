#!/usr/bin/env -S godot --headless --path . --script

## global_search.gd \u2014 Godot-optimierter Volltext-Search \u00fcber ALLE Dateitypen im Repo
##
## Nutzung:
##   $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "suchbegriff"
##   $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "fleet" --type gd,tres,tscn
##   $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "resource" --exclude .godot,addons
##   $GODOT_BIN --headless --path . --script res://scripts/global_search.gd --help
##
## Unterschied zu concept_search.gd:
## - Sucht in ALLEN Dateitypen (.tres, .tscn, .gdshader, .json, .md, .import, .csv, ...)
## - Liefert zeilenweise Treffer mit Kontext (JSON-Output f\u00fcr LLM-Parsing)
## - Keine Semantik, keine Synonyme \u2014 reiner Text-Match

extends SceneTree

const DEFAULT_EXTENSIONS: Array[String] = [
	"gd", "tres", "tscn", "gdshader", "import", "json", "csv", "md", "txt",
	"cs", "glsl", "shader", "cfg", "ini", "toml", "yaml", "yml", "xml"
]
const DEFAULT_EXCLUDE_DIRS: Array[String] = [".godot", "addons", ".git", ".import", "build", "dist", "node_modules"]

var _args: Dictionary = {}
var _query: String = ""
var _extensions: Array[String] = []
var _exclude_dirs: Array[String] = []
var _max_results: int = 200
var _context_lines: int = 2
var _json_output: bool = true

func _init() -> void:
	_parse_args()

	if _args.has("help") or _args.has("h"):
		_print_help()
		quit(0)
		return

	if not _args.has("query") or _args["query"].is_empty():
		print("Fehler: Suchbegriff fehlt. Nutze --help f\u00fcr Hilfe.")
		quit(1)
		return

	_query = _args["query"].to_lower()
	var ext_str: String = _args.get("type", ",".join(DEFAULT_EXTENSIONS))
	var excl_str: String = _args.get("exclude", ",".join(DEFAULT_EXCLUDE_DIRS))
	_extensions = []
	for e in ext_str.split(","):
		_extensions.append(e.strip_edges())
	_exclude_dirs = []
	for e in excl_str.split(","):
		_exclude_dirs.append(e.strip_edges())
	_max_results = int(_args.get("max", _max_results))
	_context_lines = int(_args.get("context", _context_lines))
	_json_output = not _args.has("no-json")

	var results = _search_all()
	if _json_output:
		print(JSON.stringify(results, "\t"))
	else:
		_print_human(results)
	quit(0)

func _parse_args() -> void:
	var all_args: PackedStringArray = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())

	var i := 0
	while i < all_args.size():
		var arg: String = all_args[i]
		if arg.begins_with("--"):
			var key: String = arg.trim_prefix("--")
			if i + 1 < all_args.size() and not all_args[i + 1].begins_with("-"):
				_args[key] = all_args[i + 1]
				i += 2
			else:
				_args[key] = true
				i += 1
		elif arg.begins_with("-") and not arg.begins_with("--"):
			var key: String = arg.trim_prefix("-")
			if i + 1 < all_args.size() and not all_args[i + 1].begins_with("-"):
				_args[key] = all_args[i + 1]
				i += 2
			else:
				_args[key] = true
				i += 1
		else:
			_args["query"] = arg
			i += 1

func _search_all() -> Dictionary:
	var hits: Array[Dictionary] = []
	var total_files_scanned: int = 0
	var start_time: float = Time.get_ticks_msec() / 1000.0

	_scan_dir("res://", hits, total_files_scanned)

	var duration_ms: int = int((Time.get_ticks_msec() / 1000.0 - start_time) * 1000)

	var by_type: Dictionary = {}
	for hit in hits:
		var t: String = hit.type
		by_type[t] = by_type.get(t, 0) + hit.matches.size()

	return {
		"query": _args["query"],
		"total_hits": hits.size(),
		"total_files_scanned": total_files_scanned,
		"duration_ms": duration_ms,
		"by_type": by_type,
		"results": hits.slice(0, _max_results)
	}

func _scan_dir(path: String, hits: Array, total_files_scanned: int) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
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
			_scan_dir(child_path, hits, total_files_scanned)
		else:
			total_files_scanned += 1
			var ext: String = entry.get_extension().to_lower()
			if ext in _extensions:
				_scan_file(child_path, ext, hits)
	dir.list_dir_end()

func _scan_file(path: String, ext: String, hits: Array) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return

	var lines: Array[String] = []
	while not file.eof_reached():
		lines.append(file.get_line())
	file.close()

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
				"context": context
			})

	if not matches.is_empty():
		hits.append({
			"file": path,
			"type": ext,
			"matches": matches
		})

func _print_human(results: Dictionary) -> void:
	print("=== Global Search: '%s' (%d Treffer in %d Dateien, %dms) ===" % [results.query, results.total_hits, results.results.size(), results.duration_ms])
	print("")
	for hit in results.results:
		print("\uD83D\uDCC4 %s (%s)" % [hit.file, hit.type])
		for match in hit.matches:
			for ctx in match.context:
				var prefix: String = "  >" if ctx.is_match else "   "
				print("%s %d: %s" % [prefix, ctx.line, ctx.content])
		print("")

func _print_help() -> void:
	print("""
Global Search \u2014 Volltext-Suche \u00fcber ALLE Dateitypen im Godot-Projekt
=====================================================================

NUTZUNG:
  $GODOT_BIN --headless --path . --script res://scripts/global_search.gd [OPTIONEN] SUCHBEGRIFF

OPTIONEN:
  --type, -t <exts>     Komma-getrennte Liste von Extensions (Default: alle Code/Config/Doc)
                        Beispiel: --type gd,tres,tscn,json,md
  --exclude, -e <dirs>  Verzeichnisse ausschlie\u00dfen (Default: .godot,addons,.git,.import,build,dist)
                        Beispiel: --exclude .godot,addons
  --max, -m <n>         Max Ergebnisse (Default: 200)
  --context, -c <n>     Kontext-Zeilen vor/nach Treffer (Default: 2)
  --no-json             Menschlich lesbarer Output statt JSON
  --help, -h            Diese Hilfe

BEISPIELE:
  # Suche nach "fleet" in allen Dateien
  $GODOT_BIN --headless --path . --script res://scripts/global_search.gd fleet

  # Nur in GDScript, TRES, TSCN
  $GODOT_BIN --headless --path . --script res://scripts/global_search.gd fleet --type gd,tres,tscn

  # Exkludiere addons, nur JSON-Output
  $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "resource" --exclude addons

  # Menschlich lesbar
  $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "fleet_supply" --no-json

UNTERSCHIED ZU concept_search.gd:
  concept_search.gd  \u2192 Semantisch: Konzepte, Klassen, Dom\u00e4nen, Synonyme (DE/EN), freie Slots
  global_search.gd   \u2192 Volltext: Alle Dateitypen, Zeilen-Kontext, rohe Matches
""")