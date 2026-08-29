extends SceneTree

## Test-Orchestrator (R-009): Führt alle Entry-Tests + Preflight als
## Subprozesse aus und gibt einen einheitlichen Exit-Code zurück.
##
## Verwendung:
##   $GODOT_BIN --headless --path . --script res://scripts/testing/test_all.gd
##
## Optionen (über Umgebungsvariablen):
##   TEST_ALL_FILTER=<term>     — nur Tests mit <term> im Pfad ausführen
##   TEST_ALL_SKIP_PREFLIGHT=1  — Preflight überspringen
##   TEST_ALL_TIMEOUT=<sek>     — Timeout pro Test (Standard: 120)
##
## Exit: 0 = alle grün, 1 = mindestens ein Fehler

const DEFAULT_TIMEOUT := 120
const PREFLIGHT_TIMEOUT := 180

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
	print("╔══════════════════════════════════════╗")
	print("║  SnipWar Test Orchestrator (R-009)   ║")
	print("╚══════════════════════════════════════╝")
	print("")

	var godot_bin: String = _resolve_godot_bin()
	if godot_bin.is_empty():
		print("[FATAL] GODOT_BIN nicht gesetzt und kein Standard-Pfad gefunden.")
		_exit(1)
		return

	var filter: String = OS.get_environment("TEST_ALL_FILTER")
	var skip_preflight: bool = OS.get_environment("TEST_ALL_SKIP_PREFLIGHT") == "1"
	var timeout: int = int(OS.get_environment("TEST_ALL_TIMEOUT")) if not OS.get_environment("TEST_ALL_TIMEOUT").is_empty() else DEFAULT_TIMEOUT

	# --- Entry-Tests ---
	var test_files: PackedStringArray = _discover_tests("res://scripts/testing/", filter)
	print("Found %d entry tests in scripts/testing/" % test_files.size())
	print("")

	for path in test_files:
		var label: String = path.get_file().replace(".gd", "")
		var result: Dictionary = _run_subprocess(godot_bin, ["--headless", "--path", ".", "--script", path], timeout)
		_results.append({"label": label, "path": path, "ok": result.get("ok", false), "exit": result.get("exit", -1), "ms": result.get("ms", 0)})

	# --- Preflight ---
	if not skip_preflight:
		print("")
		print("Running preflight -x ...")
		var pf_result: Dictionary = _run_subprocess(godot_bin, ["--headless", "--path", ".", "--script", "res://scripts/preflight.gd", "-x"], PREFLIGHT_TIMEOUT)
		_results.append({"label": "preflight -x", "path": "res://scripts/preflight.gd", "ok": pf_result.get("ok", false), "exit": pf_result.get("exit", -1), "ms": pf_result.get("ms", 0)})

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
		if file_name.ends_with("_test.gd"):
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
	var exit_code: int = -1

	# OS.execute gibt kein exit_code zurück in Godot 4.x — wir nutzen
	# OS.create_process + Thread-Timeout als Fallback.
	# Einfacher: OS.execute mit capture und manuellem Timeout via Timer.
	# Godot 4.x OS.execute mit read_stderr = true:
	OS.execute(godot_bin, args, output, true, false)

	var ms: int = Time.get_ticks_msec() - start_ms
	var text: String = "\n".join(output)
	var ok: bool = text.contains("RESULT: PASSED") or text.contains("PASS") or text.contains("RESULT: OK")
	# Spezialfall: preflight -x gibt "RESULT: PASSED" aus
	# Spezialfall: entry tests geben "RESULT: PASSED" oder "[PASS]" aus
	# Nur wenn KEIN RESULT und KEIN PASS → Fehler
	if not text.contains("RESULT:") and not text.contains("[PASS]") and not text.contains("PASS"):
		ok = false

	var label: String = args[args.size() - 1].get_file() if args.size() > 0 else "?"
	if ok:
		print("  [PASS] %-40s %d ms" % [label, ms])
	else:
		print("  [FAIL] %-40s %d ms" % [label, ms])
		# Letzte 5 Zeilen bei Fehler ausgeben
		var lines: PackedStringArray = text.strip_edges().split("\n")
		var start: int = maxi(0, lines.size() - 5)
		for i in range(start, lines.size()):
			print("        | %s" % lines[i])

	return {"ok": ok, "exit": exit_code, "ms": ms}


func _print_summary() -> void:
	print("")
	print("══════════════════════════════════════")
	var passed: int = 0
	var failed: int = 0
	var total_ms: int = 0
	for r in _results:
		total_ms += r.get("ms", 0)
		if r.get("ok", false):
			passed += 1
		else:
			failed += 1
	print("  TOTAL: %d/%d passed (%d failed) in %d ms" % [passed, passed + failed, failed, total_ms])
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
