#!/usr/bin/env -S godot --headless --path . --script

## global_search.gd \u2014 Godot-optimierter Volltext-Search \u00fcber ALLE Dateitypen im Repo
##
## Nutzung:
##   $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "suchbegriff"
##   $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "fleet" --type gd,tres,tscn
##   $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "resource" --exclude .godot,addons
##   $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "audio|animation"  # OR-Suche
##   $GODOT_BIN --headless --path . --script res://scripts/global_search.gd --help
##
## Unterschied zu concept_search.gd:
## - Sucht in ALLEN Dateitypen (.tres, .tscn, .gdshader, .json, .md, .import, .csv, ...)
## - Liefert zeilenweise Treffer mit Kontext (JSON-Output f\u00fcr LLM-Parsing)
## - Pipe-Alternation: "a|b" sucht nach "a" ODER "b" (OR-Suche)
## - Keine Semantik, keine Synonyme \u2014 reiner Text-Match

extends SceneTree

const DEFAULT_EXTENSIONS: Array[String] = [
	"gd", "tres", "tscn", "gdshader", "import", "json", "csv", "md", "txt",
	"cs", "glsl", "shader", "cfg", "ini", "toml", "yaml", "yml", "xml"
]
const DEFAULT_EXCLUDE_DIRS: Array[String] = [".godot", ".git", ".import", "build", "dist", "node_modules"]

var _args: Dictionary = {}
var _query: String = ""
var _query_alternatives: Array[String] = []
var _extensions: Array[String] = []
var _exclude_dirs: Array[String] = []
var _max_results: int = 200
var _max_files: int = 0  ## 0 = unlimited
var _context_lines: int = 2
var _json_output: bool = true
var _freq_mode: bool = false  ## --freq: frequency aggregation
var _defs_mode: bool = false  ## --defs: function definition vs. call-site analysis
var _regex_mode: bool = false  ## --regex: regex matching with capture groups

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

	_query = _args["query"]
	# Pipe-alternation: "a|b" → match any of ["a", "b"]
	var raw: String = _query.to_lower()
	for part in raw.split("|"):
		var trimmed: String = part.strip_edges()
		if not trimmed.is_empty():
			_query_alternatives.append(trimmed)
	# Fallback: if no alternatives parsed (e.g. empty pipe), use whole string
	if _query_alternatives.is_empty():
		_query_alternatives.append(raw)
	var ext_str: String = _args.get("type", ",".join(DEFAULT_EXTENSIONS))
	var excl_str: String = _args.get("exclude", ",".join(DEFAULT_EXCLUDE_DIRS))
	_extensions = []
	for e in ext_str.split(","):
		_extensions.append(e.strip_edges())
	_exclude_dirs = []
	for e in excl_str.split(","):
		_exclude_dirs.append(e.strip_edges())
	_max_results = int(_args.get("max", _max_results))
	_max_files = int(_args.get("max-files", _max_files))
	_context_lines = int(_args.get("context", _context_lines))
	_json_output = not _args.has("no-json")
	_freq_mode = _args.has("freq")
	_defs_mode = _args.has("defs")
	_regex_mode = _args.has("regex")

	var results = _search_all()
	if _json_output:
		print(JSON.stringify(results, "\t"))
	else:
		if _freq_mode:
			_print_freq(results)
		elif _defs_mode:
			_print_defs(results)
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
		"query": _args["query"],
		"alternatives": _query_alternatives if _query_alternatives.size() > 1 else [],
		"total_hits": hits.size(),
		"total_files_scanned": total_files_scanned,
		"total_line_count": total_line_count,
		"duration_ms": duration_ms,
		"by_type": by_type,
		"results": hits.slice(0, _max_results)
	}

	# Frequency aggregation (--freq)
	if _freq_mode:
		result_dict["frequency"] = _aggregate_frequency(hits)

	# Definitions analysis (--defs)
	if _defs_mode:
		result_dict["definitions"] = _analyze_definitions(hits)

	return result_dict

## Returns [files_scanned, line_count]. GDScript ints are value types, so
## totals cannot be mutated in place by callees — accumulate via return values.
func _scan_dir(path: String, hits: Array, running_files: int, running_lines: int) -> Array:
	var totals: Array = [int(running_files), int(running_lines)]
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return totals
	if _max_files > 0 and int(totals[0]) >= _max_files:
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
			if _max_files > 0 and int(totals[0]) >= _max_files:
				break
			totals[0] = int(totals[0]) + 1
			var ext: String = entry.get_extension().to_lower()
			if ext in _extensions:
				if _regex_mode:
					totals[1] = int(totals[1]) + _scan_file_regex(child_path, ext, hits)
				else:
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


	var matches: Array[Dictionary] = []
	for i in range(lines.size()):
		var line: String = lines[i]
		if _line_matches(line):
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
			"line_count": lines.size(),
			"matches": matches
		})
	return lines.size()

func _print_human(results: Dictionary) -> void:
	var label: String = results.query
	if results.has("alternatives") and not results.alternatives.is_empty():
		label += " (OR: %s)" % ", ".join(results.alternatives)
	var line_info: String = ""
	if results.has("total_line_count") and results.total_line_count > 0:
		line_info = ", %d LOC gesamt" % results.total_line_count
	print("=== Global Search: '%s' (%d Treffer in %d Dateien%s, %dms) ===" % [
		label, results.total_hits, results.results.size(), line_info, results.duration_ms
	])
	print("")
	for hit in results.results:
		var lc: String = "" if not hit.has("line_count") else " [%d LOC]" % hit.line_count
		print("📄 %s (%s%s)" % [hit.file, hit.type, lc])
		for match in hit.matches:
			for ctx in match.context:
				var prefix: String = "  >" if ctx.is_match else "   "
				print("%s %d: %s" % [prefix, ctx.line, ctx.content])
		print("")

func _print_help() -> void:
	print("""
Global Search — Volltext-Suche über ALLE Dateitypen im Godot-Projekt
=====================================================================

NUTZUNG:
  $GODOT_BIN --headless --path . --script res://scripts/global_search.gd [OPTIONEN] SUCHBEGRIFF

OPTIONEN:
  --type, -t <exts>     Komma-getrennte Liste von Extensions (Default: alle Code/Config/Doc)
                        Beispiel: --type gd,tres,tscn,json,md
  --exclude, -e <dirs>  Verzeichnisse ausschließen (Default: .godot,.git,.import,build,dist)
                        Beispiel: --exclude .godot,.git
  --max, -m <n>         Max Dateien mit Treffern (Default: 200)
  --max-files <n>       Max Dateien zum Scannen (Default: 0=unlimited, Schutz vor Timeouts)
  --context, -c <n>     Kontext-Zeilen vor/nach Treffer (Default: 2)
  --no-json             Menschlich lesbarer Output statt JSON
  --freq                Häufigkeits-Aggregation: unique count pro Treffer-Zeile
  --defs                Funktions-Definitionen vs. Aufrufe (nur .gd Dateien)
  --regex               RegEx-Modus mit Capture-Group-Extraktion
  --help, -h            Diese Hilfe

BEISPIELE:
  # Suche nach "fleet" in allen Dateien (mit LOC-Angabe pro Datei)
  $GODOT_BIN --headless --path . --script res://scripts/global_search.gd fleet --no-json

  # OR-Suche mit Pipe: findet "runtime_audio" ODER "runtime_animation"
  $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "runtime_audio|runtime_animation"

  # Frequenz-Aggregation: welche Zeilen kommen wie oft vor?
  $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "emit_signal" --freq --no-json

  # Dead-Code-Analyse: func definiert vs. aufgerufen
  $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "assemble_ship" --defs --no-json

  # Regex mit Capture-Groups: extrahiere Funktionsnamen
  $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "func (_?[a-z_]+)" --regex --no-json

  # Schutz vor Timeouts: max. 500 Dateien scannen
  $GODOT_BIN --headless --path . --script res://scripts/global_search.gd "func" --max-files 500 --no-json

  # Nur in GDScript, TRES, TSCN
  $GODOT_BIN --headless --path . --script res://scripts/global_search.gd fleet --type gd,tres,tscn

PIPE-ALTERNATION:
  Verwende "|" als Trenner fuer OR-Suchen:
    "audio|animation"  findet Dateien mit "audio" ODER "animation"
    "a|b|c"            findet Dateien mit "a" ODER "b" ODER "c"
  Funktioniert auch im ConceptIndex (concept_search.gd).

REGEX-MODUS (--regex):
  Nutzt Godot RegEx fuer fortgeschrittene Suche mit Capture-Groups:
    "func (_?[a-z_]+)"     extrahiert Funktionsnamen
    "class_name (\\w+)"     extrahiert Klassennamen
    "\\[resource\\]"          findet TRES-Header

FREQUENZ (--freq):
  Aggregiert Treffer-Zeilen nach Häufigkeit (absteigend).
  Ideal für: Dead-Code-Kandidaten, Why-Scanning, unique-count-Pipelines.

DEFINITIONS-MODUS (--defs):
  Zählt func-Definitionen und Aufrufstellen für .gd Dateien.
  Zeigt "Dead-Code-Kandidaten" (definiert aber 0 Aufrufe).

UNTERSCHIED ZU concept_search.gd:
  concept_search.gd  → Semantisch: Konzepte, Klassen, Domänen, Synonyme (DE/EN), freie Slots
  global_search.gd   → Volltext: Alle Dateitypen, Zeilen-Kontext, rohe Matches, Regex, Aggregation
""")

func _scan_file_regex(path: String, ext: String, hits: Array) -> int:
	if _is_binary_file(path, ext):
		return 0

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0

	var lines: Array[String] = []
	while not file.eof_reached():
		lines.append(file.get_line())
	file.close()

	# Compile regex from query
	var regex: RegEx = RegEx.new()
	var err: Error = regex.compile(_query)
	if err != OK:
		# Fallback: treat as literal substring
		var matches_literal: Array[Dictionary] = []
		for i in range(lines.size()):
			if _query.to_lower() in lines[i].to_lower():
				matches_literal.append({
					"match_line": i + 1,
					"matched_text": lines[i].strip_edges(),
					"groups": [],
					"context": _build_context(lines, i)
				})
		if not matches_literal.is_empty():
			hits.append({
				"file": path,
				"type": ext,
				"line_count": lines.size(),
				"matches": matches_literal
			})
		return lines.size()

	var matches: Array[Dictionary] = []
	for i in range(lines.size()):
		var line: String = lines[i]
		var result: RegExMatch = regex.search(line)
		if result != null:
			var groups: Array[String] = []
			for gi in range(1, result.get_group_count() + 1):
				groups.append(result.get_string(gi))
			matches.append({
				"match_line": i + 1,
				"matched_text": result.get_string(),
				"groups": groups,
				"context": _build_context(lines, i)
			})

	if not matches.is_empty():
		hits.append({
			"file": path,
			"type": ext,
			"line_count": lines.size(),
			"matches": matches
		})
	return lines.size()

func _build_context(lines: Array[String], match_idx: int) -> Array[Dictionary]:
	var start: int = max(0, match_idx - _context_lines)
	var end_idx: int = min(lines.size() - 1, match_idx + _context_lines)
	var context: Array[Dictionary] = []
	for j in range(start, end_idx + 1):
		context.append({
			"line": j + 1,
			"content": lines[j].strip_edges(),
			"is_match": j == match_idx
		})
	return context

func _line_matches(line: String) -> bool:
	var lower: String = line.to_lower()
	for alt in _query_alternatives:
		if alt in lower:
			return true
	return false

## Frequency aggregation: count unique match lines across all results.
func _aggregate_frequency(hits: Array) -> Array[Dictionary]:
	var freq: Dictionary = {}  ## line_text -> count
	for hit in hits:
		for match in hit.matches:
			var text: String = ""
			if match.has("matched_text"):
				text = match.matched_text
			elif match.has("context"):
				for ctx in match.context:
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

## Function definition analysis: find func definitions and count call sites.
func _analyze_definitions(hits: Array) -> Dictionary:
	var func_defs: Array[Dictionary] = []  ## [{name, file, line}]

	# Step 1: Extract func definitions from .gd hits
	var regex_def: RegEx = RegEx.new()
	regex_def.compile("^\\s*(?:static\\s+)?func\\s+(_?[a-zA-Z0-9_]+)")
	for hit in hits:
		if hit.type != "gd":
			continue
		for match in hit.matches:
			var text: String = ""
			if match.has("matched_text"):
				text = match.matched_text
			elif match.has("context"):
				for ctx in match.context:
					if ctx.is_match:
						text = ctx.content
						break
			var def_result: RegExMatch = regex_def.search(text)
			if def_result != null:
				func_defs.append({
					"name": def_result.get_string(1),
					"file": hit.file,
					"line": match.match_line
				})

	# Step 2: Count call sites per function name across ALL hits
	var call_counts: Dictionary = {}  ## func_name -> count of non-definition lines
	for hit in hits:
		if hit.type != "gd":
			continue
		for match in hit.matches:
			var text: String = ""
			if match.has("matched_text"):
				text = match.matched_text
			elif match.has("context"):
				for ctx in match.context:
					if ctx.is_match:
						text = ctx.content
						break
			# Skip definition lines themselves
			var def_check: RegExMatch = regex_def.search(text)
			if def_check != null:
				continue
			# Count each func name that appears as a call
			for fd in func_defs:
				var fname: String = fd.name
				if fname in text:
					call_counts[fname] = call_counts.get(fname, 0) + 1

	var dead_candidates: Array[Dictionary] = []
	var live_funcs: Array[Dictionary] = []
	for fd in func_defs:
		var calls: int = call_counts.get(fd.name, 0)
		var entry: Dictionary = {
			"name": fd.name,
			"file": fd.file,
			"line": fd.line,
			"call_sites": calls
		}
		if calls == 0:
			dead_candidates.append(entry)
		else:
			live_funcs.append(entry)

	return {
		"total_definitions": func_defs.size(),
		"dead_code_candidates": dead_candidates,
		"live_functions": live_funcs
	}

func _print_freq(results: Dictionary) -> void:
	var label: String = results.query
	if results.has("alternatives") and not results.alternatives.is_empty():
		label += " (OR: %s)" % ", ".join(results.alternatives)
	var freq: Array = results.get("frequency", [])
	print("=== Frequency: '%s' (%d unique lines, %d Treffer) ===" % [
		label, freq.size(), results.total_hits
	])
	print("")
	for entry in freq:
		print("%4d×  %s" % [entry.count, entry.line])
	print("")

func _print_defs(results: Dictionary) -> void:
	var defs: Dictionary = results.get("definitions", {})
	var dead: Array = defs.get("dead_code_candidates", [])
	var live: Array = defs.get("live_functions", [])
	print("=== Definitions: '%s' (%d def, %d live, %d dead-code candidates) ===" % [
		results.query, defs.get("total_definitions", 0), live.size(), dead.size()
	])
	print("")
	if dead.size() > 0:
		print("⚠ Dead-Code-Kandidaten (definiert, 0 Aufrufe in Treffern):")
		for entry in dead:
			print("  %s → %s:%d" % [entry.name, entry.file, entry.line])
		print("")
	if live.size() > 0:
		print("✓ Genutzte Funktionen:")
		for entry in live:
			print("  %s (%d Aufrufe) → %s:%d" % [entry.name, entry.call_sites, entry.file, entry.line])
		print("")

func _is_binary_file(path: String, ext: String) -> bool:
	# Known binary extensions that should never be scanned as text
	var binary_extensions: Array[String] = ["png", "jpg", "jpeg", "webp", "gif", "bmp", "ico", "ogg", "wav", "mp3", "mp4", "avi", "mov", "ttf", "otf", "woff", "woff2", "eot", "pck", "zip", "gz", "tar", "rar", "7z"]
	if ext in binary_extensions:
		return true

	# For .tres and .import, check magic bytes (can be binary or text)
	if ext == "tres" or ext == "import":
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			return false
		var header: PackedByteArray = file.get_buffer(4)
		file.close()
		# .tres text format starts with '[', binary starts with different bytes
		# .import text format starts with '['
		if header.size() >= 1 and header[0] != 91:  # 91 = '['
			return true

	return false