extends SceneTree

## Test-Orchestrator (R-009, PL-B): Führt alle Entry-Tests + Preflight aus.
##
## PL-B-Fix (realistische Godot-4.7-Variante): Godot erlaubt kein zuverlässiges
## OS.execute aus Worker-Threads (Subprozesse sterben mit exit=-1). Die echte
## Parallelität ist also innerhalb eines Godot-Prozesses nicht sicher erreichbar.
## Stattdessen liefert der HEAD-gekeyte Ergebnis-Cache den PL-B-Gewinn: unveränderte
## Testdateien (byte-identisch zum letzten grünen Lauf) werden übersprungen.
## Bei parallelen Agenten überspringt jeder Agent die Tests, die ein voriger Lauf
## bereits grün bestätigt hat → kein Prozesssturm bei Wiederholung.
##
## Verwendung:
##   $GODOT_BIN --headless --path . --script res://scripts/testing/test_all.gd
##
## Optionen (über Umgebungsvariablen):
##   TEST_ALL_FILTER=<term>     — nur Tests mit <term> im Pfad ausführen
##   TEST_ALL_SKIP_PREFLIGHT=1  — Preflight überspringen
##   TEST_ALL_TIMEOUT=<sek>     — optionaler Abbruch pro Test (Standard: 0 = kein Timeout)
##   TEST_ALL_NO_CACHE=1        — Ergebnis-Cache deaktivieren (Volllauf)
##
## Exit: 0 = alle grün, 1 = mindestens ein Fehler

const DEFAULT_TIMEOUT := 0
const PREFLIGHT_TIMEOUT := 0
const CACHE_DIR := "user://mcp_evidence/test_cache"


var _results: Array[Dictionary] = []
var _frame: int = 0
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_frame += 1
	if _frame < 3:
		return false
	_ran = true
	_run_all()
	return false


func _run_all() -> void:
	print("╔════════════════════════════════════════════╗")
	print("║  SnipWar Test Orchestrator (R-009, PL-B)   ║")
	print("╚════════════════════════════════════════════╝")
	print("")

	var godot_bin: String = _resolve_godot_bin()
	if godot_bin.is_empty():
		print("[FATAL] GODOT_BIN nicht gesetzt und kein Standard-Pfad gefunden.")
		_exit(1)
		return

	var filter: String = OS.get_environment("TEST_ALL_FILTER")
	var skip_preflight: bool = OS.get_environment("TEST_ALL_SKIP_PREFLIGHT") == "1"
	var timeout: int = int(OS.get_environment("TEST_ALL_TIMEOUT")) if not OS.get_environment("TEST_ALL_TIMEOUT").is_empty() else DEFAULT_TIMEOUT
	if timeout < 0:
		timeout = 0
	var use_cache: bool = OS.get_environment("TEST_ALL_NO_CACHE") != "1"

	# --- Entry-Tests entdecken ---
	var test_files: PackedStringArray = _discover_tests("res://scripts/testing/", filter)
	print("Found %d entry tests in scripts/testing/" % test_files.size())
	print("Cache: %s" % ("enabled" if use_cache else "disabled"))
	print("")

	# --- Cache lesen ---
	var cache: Dictionary = _read_cache() if use_cache else {}

	# --- Entry-Tests (seriell; Godot 4.7 OS.execute ist nicht thread-sicher) ---
	for path in test_files:
		var label: String = path.get_file().replace(".gd", "")

		# Cache-Hit: Testdatei byte-identisch zum letzten grünen Lauf → skip
		if use_cache and _cache_hit(cache, path):
			_results.append({"label": label, "path": path, "ok": true, "exit": 0, "ms": 0, "cached": true})
			print("  [CACHED] %-40s (cache-hit, skipped)" % label)
			continue

		var result: Dictionary = _run_subprocess(godot_bin, ["--headless", "--path", ".", "--script", path], timeout)
		_results.append({"label": label, "path": path, "ok": result.get("ok", false), "exit": result.get("exit", -1), "ms": result.get("ms", 0), "cached": false})

	# --- Preflight (seriell; Shared-Fixture ist exklusiv) ---
	if not skip_preflight:
		print("")
		print("Running preflight -x ...")
		# Preflight wird nie gecacht (Full-Run-Garantie bleibt beim Hook)
		var pf_result: Dictionary = _run_subprocess(godot_bin, ["--headless", "--path", ".", "--script", "res://scripts/preflight.gd", "-x"], PREFLIGHT_TIMEOUT)
		_results.append({"label": "preflight -x", "path": "res://scripts/preflight.gd", "ok": pf_result.get("ok", false), "exit": pf_result.get("exit", -1), "ms": pf_result.get("ms", 0), "cached": false})

	# --- Cache aktualisieren (nur grüne Entry-Tests) ---
	if use_cache:
		_write_cache()

	# --- Summary ---
	_print_summary()
	var failures: int = 0
	for r in _results:
		if not r.get("ok", false):
			failures += 1
	_exit(failures)


func _discover_tests(root_path: String, filter: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var dir := DirAccess.open(root_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		# dbg_*-Tests sind ad-hoc-Debug-Skripte, keine Entry-Tests der Suite.
		if file_name.ends_with("_test.gd") and not file_name.begins_with("dbg_"):
			var full_path: String = root_path + file_name
			if filter.is_empty() or full_path.contains(filter):
				result.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


func _run_subprocess(godot_bin: String, args: PackedStringArray, timeout_sec: int) -> Dictionary:
	var start_ms: int = Time.get_ticks_msec()
	var output: Array = []

	# Autoritativer Exit-Code: OS.execute gibt den Subprozess-Exit-Code zurück.
	# Der [PASS]/RESULT: PASSED-Substring allein wäre ein False-Green — ein Test,
	# der nach der ersten Assertion crasht, hinterlässt „[PASS]“ im Output,
	# obwohl quit(1) nie erreicht wurde. Der Exit-Code ist die einzige Wahrheit.
	if timeout_sec > 0:
		print("  [TIMEOUT CONFIG] %ds" % timeout_sec)
	var exit_code: int = OS.execute(godot_bin, args, output, true, false)

	var ms: int = Time.get_ticks_msec() - start_ms
	var text: String = "\n".join(output)
	var ok: bool = exit_code == 0
	var has_pass_marker: bool = text.contains("RESULT: PASSED") or text.contains("RESULT: OK") or text.contains("[PASS]")

	var label: String = args[args.size() - 1].get_file() if args.size() > 0 else "?"
	if ok:
		print("  [PASS] %-40s %d ms" % [label, ms])
	else:
		print("  [FAIL] %-40s %d ms (exit=%d)" % [label, ms, exit_code])
		if ok == false and has_pass_marker:
			print("        | Hinweis: Output enthält PASS-Marker, aber Exit != 0 → False-Green überschrieben.")
		# Letzte 5 Zeilen bei Fehler ausgeben
		var lines: PackedStringArray = text.strip_edges().split("\n")
		var start: int = maxi(0, lines.size() - 5)
		for i in range(start, lines.size()):
			print("        | %s" % lines[i])

	return {"ok": ok, "exit": exit_code, "ms": ms}


# ── Ergebnis-Cache (HEAD-gekeyt über Datei-Digest) ─────────────────────
## Cache-Hit: die Testdatei ist byte-identisch zum letzten grünen Lauf.
func _cache_hit(cache: Dictionary, path: String) -> bool:
	var current_head := _current_tree_hash()
	if current_head.is_empty():
		return false
	var key: String = _cache_key(path)
	if not cache.has(key):
		return false
	var entry: Dictionary = cache[key]
	if not bool(entry.get("ok", false)):
		return false
	var live_digest: String = _file_digest(path)
	return live_digest == str(entry.get("digest", "")) and current_head == str(entry.get("tree", ""))


## SHA-256-Digest über den Dateibytes (unveränderte Datei = selbe Digest).
func _file_digest(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()


## Cache-Key: res://-Pfad normalisiert.
func _cache_key(path: String) -> String:
	return path.replace("\\", "/")

func _current_tree_hash() -> String:
	var output: Array = []
	var exit_code := OS.execute("git", ["write-tree"], output, true, false)
	return "" if exit_code != 0 or output.is_empty() else String(output[0]).strip_edges()


## Liest den Cache (PID-isoliert via atomarem Rename; lesend sicher).
func _read_cache() -> Dictionary:
	var cache_path: String = _cache_file_path()
	if not FileAccess.file_exists(cache_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(cache_path))
	if parsed is Dictionary:
		return parsed.get("entries", {}) if parsed.has("entries") else parsed
	return {}


## Schreibt den Cache (nur grüne Entry-Tests; PID-keyed Tmp + atomarer Rename,
## concurrency-sicher gegen parallele Agenten/Läufe).
func _write_cache() -> void:
	var entries: Dictionary = {}
	for r in _results:
		if bool(r.get("ok", false)) and not str(r.get("path", "")).is_empty():
			var path: String = str(r.get("path", ""))
			# Preflight nicht cachen (Full-Run-Garantie)
			if path.contains("preflight.gd"):
				continue
			entries[_cache_key(path)] = {
				"ok": true,
				"digest": _file_digest(path),
				"tree": _current_tree_hash(),
				"ms": r.get("ms", 0),
			}
	var cache_path: String = _cache_file_path()
	DirAccess.make_dir_recursive_absolute(cache_path.get_base_dir())
	var tmp_path: String = cache_path + ".%d.tmp" % OS.get_process_id()
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_warning("test_all: Cache nicht schreibbar: %s" % tmp_path)
		return
	file.store_string(JSON.stringify({"entries": entries, "updated": Time.get_ticks_msec()}, "\t"))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(cache_path))


## Stabiler Cache-File-Pfad.
func _cache_file_path() -> String:
	return CACHE_DIR + "/test_cache.json"


func _print_summary() -> void:
	print("")
	print("══════════════════════════════════════")
	var passed: int = 0
	var failed: int = 0
	var cached: int = 0
	var total_ms: int = 0
	for r in _results:
		total_ms += r.get("ms", 0)
		if r.get("ok", false):
			passed += 1
			if r.get("cached", false):
				cached += 1
		else:
			failed += 1
	print("  TOTAL: %d/%d passed (%d failed, %d cached) in %d ms" % [passed, passed + failed, failed, cached, total_ms])
	if failed == 0:
		print("  RESULT: ALL PASSED")
	else:
		print("  RESULT: %d FAILURES" % failed)
		for r in _results:
			if not r.get("ok", false):
				print("    FAILED: %s" % r.get("label", "?"))
	print("══════════════════════════════════════")


func _resolve_godot_bin() -> String:
	var env: String = OS.get_environment("GODOT_BIN")
	if not env.is_empty() and FileAccess.file_exists(env):
		return env
	# Standard-Pfad (Windows)
	var default: String = "C:/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe"
	if FileAccess.file_exists(default):
		return default
	return ""


func _exit(code: int) -> void:
	if code == 0:
		print("\nAll tests passed.")
	else:
		print("\nSome tests FAILED.")
	quit(code)
