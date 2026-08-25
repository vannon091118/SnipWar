#!/usr/bin/env -S godot --headless --path . --script

## global_search.gd — LLM-optimierte Volltext-Suche über ALLE Projektdateien.
##
## Nutzung:
##   $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "suchbegriff"
##   $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "fleet" --type gd,tres
##   $GODOT_BIN --headless --path . --script res://scripts/global_search.gd --help
##
## Output: IMMER ein kompaktes JSON (ein einziger print):
##   - Treffer mit Zeile + Kontext
##   - classes_available   (ClassName -> res://-Pfad, wer verfügbar ist)
##   - dependency_graph    (je Datei: class_name, extends, preloads, loads)
## Kein Human-Format, keine Artefakt-Dateien — der Agent bekommt alle
## Relationen in einem Tool-Call.

extends SceneTree

const SEARCH_CORE := preload("res://scripts/search_core.gd")

var _args: Dictionary = {}

func _init() -> void:
	_parse_args()

	if _args.has("help") or _args.has("h"):
		print(_help_text())
		quit(0)
		return

	var q: String = _args.get("query", "")
	if q.is_empty():
		printerr("Fehler: Suchbegriff fehlt. Nutze --help für Hilfe.")
		quit(1)
		return

	var core: Object = SEARCH_CORE.new()
	core.configure(
		q,
		String(_args.get("type", "")).split(",") if _args.has("type") else [],
		String(_args.get("exclude", "")).split(",") if _args.has("exclude") else [],
		int(_args.get("max", 200)),
		int(_args.get("context", 2)),
		_args.has("regex")
	)
	var result: Dictionary = core.run()
	# Kompakteres Top-Level: die dependency-Daten sind die wertvollsten Teile.
	result["query"] = q
	print(JSON.stringify(result, "\t"))
	quit(0)


func _parse_args() -> void:
	var all_args: PackedStringArray = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	var i := 0
	while i < all_args.size():
		var arg := all_args[i]
		if arg.begins_with("--"):
			var key := arg.trim_prefix("--")
			if i + 1 < all_args.size() and not all_args[i + 1].begins_with("-"):
				_args[key] = all_args[i + 1]
				i += 2
			else:
				_args[key] = true
				i += 1
		elif arg.begins_with("-"):
			var key := arg.trim_prefix("-")
			if i + 1 < all_args.size() and not all_args[i + 1].begins_with("-"):
				_args[key] = all_args[i + 1]
				i += 2
			else:
				_args[key] = true
				i += 1
		else:
			_args["query"] = arg
			i += 1


func _help_text() -> String:
	return """Global Search — LLM-Volltextsuche (ein JSON-output)

  $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "begriff" [OPTIONEN]

OPTIONEN:
  --type, -t <exts>      Komma-getrennt (default: alle Code/Config/Doc)
  --exclude, -e <dirs>   Verzeichnisse ausschließen (default: .godot,.git,.import)
  --max, -m <n>          Max Dateien mit Treffern (default 200)
  --context, -c <n>      Kontext-Zeilen pro Treffer (default 2)
  --regex                RegEx-Suche mit Gruppen (matched_text/groups)
  --help, -h             Diese Hilfe

AUSGABE (immer JSON, ein Print):
  results[]             {file, type, line_count, matches[{line,text,context,groups?}]}
  classes_available     {ClassName: res://Pfad}  — wer ist verfügbar
  dependency_graph      {res://Pfad: {class_name, extends, preloads[], loads[]}}
  total_hits, total_files_scanned, total_line_count, duration_ms, by_type
"""