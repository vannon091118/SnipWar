extends SceneTree

## Unified Check — ein einziger Entry-Point für alle Verifikation.
##
## Läuft in Phasen, jede Phase prüft nur was der Check-Scope erfordert:
##   1. Scope auflösen (staged files → contracts → constraints)
##   2. Compile-Gate (nur .gd im Scope, oder alle wenn --full)
##   3. Preflight (nur Constraints die der Scope erfordert)
##   4. Tests (nur Tests die zum Scope-Modul gehören)
##
## Der Scope wird zu BEGINN festgelegt und ist danach unveränderlich.
## Jede Datei außerhalb des Scope muss begründet werden (--takeover).
##
## Usage:
##   $GODOT_BIN --headless --path . --script res://scripts/check.gd [options]
##
## Options:
##   --scope=<staged|full|manifest.json>   Scope-Quelle (default: staged)
##   --takeover=<path1,path2,...>          Fremde Dateien in den Scope aufnehmen
##   --full                                Voll-Lauf (ignoriert Scope, alles prüfen)
##   --cheap-path                          Nur pure Constraints (kein Scene-Boot)
##   --fail-fast / -x                      Nach erstem Fehler abbrechen
##   --verbose / -v                        Detail-Output
##   --skip-compile                        Compile-Gate überspringen
##   --skip-preflight                      Preflight überspringen
##   --skip-tests                          Tests überspringen
##   --scope-report                        Nur Scope-Analyse ausgeben, nichts prüfen
##
## Exit: 0 = alles grün, 1 = Fehler, 2 = Scope unauflösbar

const CHANGE_IMPACT_RESOLVER := preload("res://scripts/preflight_v2/change_impact_resolver.gd")
const CONSTRAINT_SCANNER := preload("res://scripts/preflight_v2/constraint_scanner.gd")
const PREFLIGHT_LOCK := preload("res://scripts/preflight_lock.gd")

var _failures: Array[String] = []
var _scope: Dictionary = {}
var _verbose: bool = false
var _fail_fast: bool = false
var _lock_token: String = ""

func _init() -> void:
	var args: Dictionary = _parse_args()

	if args.get("help", false):
		_print_help()
		quit(0)
		return

	_verbose = args.get("verbose", false)
	_fail_fast = args.get("fail_fast", false)

	# ─── Phase 1: Scope festlegen ──────────────────────────────────────
	# Der Scope wird ZU BEGINN festgelegt und ist danach unveränderlich.
	# Jede Änderung außerhalb muss über --takeover begründet werden.
	print("══════════════════════════════════════════════════")
	print(" SnipWar Unified Check")
	print("══════════════════════════════════════════════════")

	if args.get("full", false):
		print(" Mode: FULL (kein Scope-Filter)")
		_scope = {"ok": true, "full": true, "constraints": [], "paths": [], "contracts": []}
	else:
		var scope_source: String = args.get("scope", "staged")
		var takeover: String = args.get("takeover", "")
		_scope = _resolve_scope(scope_source, takeover)
		if not _scope.get("ok", false):
			printerr("[check] FATAL: Scope nicht auflösbar — %s" % str(_scope.get("error", "unknown")))
			quit(2)
			return

		# Scope-Report Mode: nur Analyse, kein Testen
		if args.get("scope_report", false):
			_print_scope_report()
			quit(0)
			return

		_print_scope_report()

	# ─── Preflight-Mutex (TASK-015): NUR EIN Verifikations-Lauf gleichzeitig ───
	# Ein zweiter Lauf blockt in einer Warteschlange, bis der laufende fertig ist.
	# Stale-Locks (Crash) werden nach STALE_SECONDS automatisch übernommen.
	var lock_res: Dictionary = PREFLIGHT_LOCK.acquire_blocking("check.gd")
	if not bool(lock_res.get("ok", false)):
		printerr("[check] FATAL: %s" % str(lock_res.get("error", "preflight-lock fehlgeschlagen")))
		quit(1)
		return
	_lock_token = str(lock_res.get("token", ""))

	# ─── Phase 2: Compile-Gate (scope-gefiltert) ──────────────────────
	if not args.get("skip_compile", false):
		print("\n── PHASE 1: Compile-Gate ──────────────────────")
		_run_compile_gate(args)
		if _fail_fast and not _failures.is_empty():
			_finish()
			return

	# ─── Phase 3: Preflight (scope-gefiltert) ─────────────────────────
	if not args.get("skip_preflight", false):
		print("\n── PHASE 2: Preflight ──────────────────────────")
		_run_preflight(args)
		if _fail_fast and not _failures.is_empty():
			_finish()
			return

	# ─── Phase 4: Tests (scope-gefiltert) ─────────────────────────────
	if not args.get("skip_tests", false):
		print("\n── PHASE 3: Entry-Tests ────────────────────────")
		_run_tests(args)
		if _fail_fast and not _failures.is_empty():
			_finish()
			return

	_finish()


## ─── Scope-Auflösung ────────────────────────────────────────────────

func _resolve_scope(source: String, takeover: String) -> Dictionary:
	var staged_paths: Array[String] = []

	if source == "staged" or source.is_empty():
		staged_paths = _get_staged_paths()
	elif source == "full":
		return {"ok": true, "full": true, "constraints": [], "paths": [], "contracts": []}
	elif FileAccess.file_exists(source):
		# Manifest-Datei (JSON mit "paths" oder "constraints")
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
		if parsed is Dictionary:
			var paths: Array = (parsed as Dictionary).get("paths", [])
			for p in paths:
				staged_paths.append(String(p))

	# Takeover: fremde Dateien in den Scope aufnehmen
	if not takeover.is_empty():
		for path in takeover.split(","):
			var t: String = path.strip_edges()
			if not t.is_empty() and not staged_paths.has(t):
				staged_paths.append(t)
				print(" [takeover] %s in Scope aufgenommen" % t)

	if staged_paths.is_empty():
		# Kein Scope = Voll-Lauf (aber warnen)
		print(" [scope] Keine staged files — Voll-Lauf")
		return {"ok": true, "full": true, "constraints": [], "paths": [], "contracts": []}

	# ChangeImpactResolver: paths → contracts → constraints
	var result: Dictionary = CHANGE_IMPACT_RESOLVER.resolve(staged_paths)
	if not result.get("ok", false):
		return result

	# Modulabhängige Scope-Lokalisierung: das System weiß, wo der Scope liegt.
	# Die Contracts definieren den Modul-Kontext (z.B. "ships", "economy", "doki").
	# "Das ist von mir" = die Dateien liegen in einem Contract den der Agent kennt.
	var contracts: Array = result.get("contracts", [])
	var constraints: Array = result.get("constraints", [])

	print(" [scope] %d Dateien → %d Contracts → %d Constraints" % [
		staged_paths.size(), contracts.size(), constraints.size()
	])

	return {
		"ok": true,
		"full": false,
		"paths": staged_paths,
		"contracts": contracts,
		"constraints": constraints,
		"warnings": result.get("warnings", []),
	}


func _get_staged_paths() -> Array[String]:
	var output: Array = []
	var exit_code := OS.execute("git", ["diff", "--cached", "--name-only", "--diff-filter=ACMR"], output, true)
	if exit_code != 0:
		return []
	var paths: Array[String] = []
	for line in "\n".join(output).strip_edges().split("\n"):
		if not line.is_empty():
			paths.append(line)
	return paths


func _print_scope_report() -> void:
	if _scope.get("full", false):
		print(" Scope: FULL (alle Constraints)")
		return
	print(" Scope: %d Dateien" % (_scope.get("paths", []) as Array).size())
	if _verbose:
		for p in _scope.get("paths", []):
			print("   %s" % str(p))
	var contracts: Array = _scope.get("contracts", [])
	if not contracts.is_empty():
		print(" Contracts: %s" % ", ".join(contracts))
	var constraints: Array = _scope.get("constraints", [])
	if not constraints.is_empty():
		print(" Constraints: %s" % ", ".join(constraints))
	var warnings: Array = _scope.get("warnings", [])
	if not warnings.is_empty():
		for w in warnings:
			print(" [warn] %s" % str(w))


## ─── Phase: Compile-Gate ────────────────────────────────────────────

func _run_compile_gate(args: Dictionary) -> void:
	# Im Scope-Modus: nur .gd im Scope kompilieren.
	# Im Full-Modus: compile_gate.gd als Subprozess.
	if _scope.get("full", false):
		var output: Array = []
		var exit_code := OS.execute(_godot_bin(), [
			"--headless", "--path", ".", "--script", "res://scripts/testing/compile_gate.gd"
		], output, true)
		var text: String = "\n".join(output)
		if exit_code == 0 and text.contains("COMPILE_GATE: PASS"):
			print(" [PASS] compile_gate (full)")
		else:
			_failures.append("compile_gate: FAIL")
			print(" [FAIL] compile_gate (full)")
			for line in text.split("\n"):
				if line.contains("ERROR") or line.contains("FAIL"):
					print("   %s" % line)
	else:
		# Scope-Modus: nur staged .gd Dateien kompilieren
		var gd_files: Array[String] = []
		for p in _scope.get("paths", []):
			if str(p).ends_with(".gd"):
				gd_files.append(str(p))
		if gd_files.is_empty():
			print(" [SKIP] keine .gd Dateien im Scope")
			return
		var passed: int = 0
		for path in gd_files:
			var script := load("res://" + path) as Script
			if script == null:
				# Versuch direkten Reload
				var gd := GDScript.new()
				gd.source_code = FileAccess.get_file_as_string("res://" + path)
				var result := gd.reload()
				if result == OK:
					passed += 1
				else:
					_failures.append("compile: %s (reload error)" % path)
					print(" [FAIL] %s" % path)
			else:
				passed += 1
		print(" [PASS] %d/%d .gd Dateien kompilieren" % [passed, gd_files.size()])


## ─── Phase: Preflight ───────────────────────────────────────────────

func _run_preflight(args: Dictionary) -> void:
	var pf_args: Array = ["--headless", "--path", ".", "--script", "res://scripts/preflight.gd"]
	if _fail_fast:
		pf_args.append("-x")
	if args.get("cheap_path", false):
		pf_args.append("--cheap-path")

	if not _scope.get("full", false) and not (_scope.get("constraints", []) as Array).is_empty():
		# Scope-Modus: nur die Constraints laufen die der Scope erfordert
		var constraint_filter: String = ",".join(_scope.get("constraints", []))
		pf_args.append("--filter=" + constraint_filter)
		print(" Läuft %d Constraints (scope-gefiltert)" % (_scope.get("constraints", []) as Array).size())
	else:
		print(" Läuft alle Constraints (full)")

	var output: Array = []
	# Subprozess erbt das Lock-Flag: der Child-Preflight acquiriert NICHT erneut
	# (Parent hält das Lock — sonst Deadlock Parent↔Child).
	OS.set_environment("PREFLIGHT_LOCK_HELD", "1")
	var exit_code := OS.execute(_godot_bin(), pf_args, output, true)
	OS.set_environment("PREFLIGHT_LOCK_HELD", "")
	# Exit-Code ist die einzige Wahrheit (M2 Fix): ein Test der nach PASS crasht
	# hinterlässt „RESULT: PASSED“ im Output aber exit!=0 → False-Green vermieden.
	if exit_code == 0:
		print(" [PASS] preflight")
	else:
		var text: String = "\n".join(output)
		_failures.append("preflight: FAIL (exit=%d)" % exit_code)
		print(" [FAIL] preflight (exit=%d)" % exit_code)
		# Letzte 8 Zeilen bei Fehler
		var lines: PackedStringArray = text.strip_edges().split("\n")
		var start: int = maxi(0, lines.size() - 8)
		for i in range(start, lines.size()):
			if not lines[i].is_empty():
				print("   %s" % lines[i])


## ─── Phase: Entry-Tests ────────────────────────────────────────────

func _run_tests(args: Dictionary) -> void:
	# Im Scope-Modus: nur Tests die zum Scope-Modul gehören.
	# Nutzt Contract → Test-Substring-Matching (wie test_all.gd), keine
	# hartcodierte Präfix-Map (S4 Fix).
	var contract_to_substring: Dictionary = {
		"ships": "ship",
		"economy": "economy",
		"save": "save",
		"combat": "combat",
		"navigation": "navigation",
		"fleet": "navigation",
		"world": "world",
		"sectors": "sector",
		"doki": "chain",
		"preflight": "constraint",
		"mcp": "mcp",
		"docs": "docs",
		"history": "historical",
		"game_state": "save",
		"ui_flow": "r008",
	}

	var test_filter: String = ""
	if not _scope.get("full", false):
		var contracts: Array = _scope.get("contracts", [])
		var substrings: Array[String] = []
		for c in contracts:
			var s: String = str(contract_to_substring.get(c, ""))
			if not s.is_empty() and not substrings.has(s):
				substrings.append(s)
		# Auch Tests die zum doki-Contract gehören: narrative_runtime, chain
		if contracts.has("doki"):
			for extra in ["narrative_runtime", "chain"]:
				if not substrings.has(extra):
					substrings.append(extra)
		if not substrings.is_empty():
			test_filter = ",".join(substrings)

	if test_filter.is_empty() and not _scope.get("full", false):
		print(" [SKIP] keine Tests für Scope-Contracts")
		return

	# Tests entdecken (Substring-Matching wie test_all.gd)
	var test_dir := DirAccess.open("res://scripts/testing/")
	if test_dir == null:
		print(" [SKIP] testing/ nicht gefunden")
		return
	test_dir.list_dir_begin()
	var test_files: Array[String] = []
	var fname: String = test_dir.get_next()
	while not fname.is_empty():
		if fname.ends_with("_test.gd"):
			if test_filter.is_empty():
				test_files.append(fname)
			else:
				# Substring-Matching (wie test_all.gd), nicht nur Präfix
				for s in test_filter.split(","):
					var sub: String = s.strip_edges()
					if not sub.is_empty() and fname.contains(sub):
						test_files.append(fname)
						break
		fname = test_dir.get_next()
	test_dir.list_dir_end()
	test_files.sort()

	if test_files.is_empty():
		print(" [SKIP] keine Tests gefunden")
		return

	var passed: int = 0
	var failed: int = 0
	for tf in test_files:
		var output: Array = []
		var exit_code := OS.execute(_godot_bin(), [
			"--headless", "--path", ".", "--script", "res://scripts/testing/" + tf
		], output, true)
		if exit_code == 0:
			passed += 1
			print(" [PASS] %s" % tf)
		else:
			failed += 1
			_failures.append("test: %s (exit=%d)" % [tf, exit_code])
			print(" [FAIL] %s (exit=%d)" % [tf, exit_code])
			if _fail_fast:
				break
	print(" Tests: %d/%d passed" % [passed, passed + failed])


## ─── Helpers ────────────────────────────────────────────────────────

func _godot_bin() -> String:
	var env: String = OS.get_environment("GODOT_BIN")
	if not env.is_empty() and FileAccess.file_exists(env):
		return env
	return "C:/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe"


func _finish() -> void:
	print("\n══════════════════════════════════════════════════")
	if _failures.is_empty():
		print(" RESULT: ALL PASSED")
	else:
		print(" RESULT: %d FAILURES" % _failures.size())
		for f in _failures:
			print("   FAILED: %s" % f)
	print("══════════════════════════════════════════════════")
	_exit(0 if _failures.is_empty() else 1)


## Central exit: gibt das Preflight-Lock frei (no-op ohne Token) und beendet.
func _exit(code: int) -> void:
	PREFLIGHT_LOCK.release(_lock_token)
	_lock_token = ""
	quit(code)
	return


func _parse_args() -> Dictionary:
	var parsed: Dictionary = {
		"verbose": false,
		"fail_fast": false,
		"full": false,
		"scope": "staged",
		"takeover": "",
		"skip_compile": false,
		"skip_preflight": false,
		"skip_tests": false,
		"scope_report": false,
		"help": false,
		"cheap_path": false,
	}
	var all_args: PackedStringArray = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	for arg in all_args:
		if arg == "--verbose" or arg == "-v":
			parsed["verbose"] = true
		elif arg == "--fail-fast" or arg == "-x":
			parsed["fail_fast"] = true
		elif arg == "--full":
			parsed["full"] = true
		elif arg == "--cheap-path":
			parsed["cheap_path"] = true
		elif arg == "--skip-compile":
			parsed["skip_compile"] = true
		elif arg == "--skip-preflight":
			parsed["skip_preflight"] = true
		elif arg == "--skip-tests":
			parsed["skip_tests"] = true
		elif arg == "--scope-report":
			parsed["scope_report"] = true
		elif arg == "--help" or arg == "-h":
			parsed["help"] = true
		elif arg.begins_with("--scope="):
			parsed["scope"] = arg.trim_prefix("--scope=")
		elif arg.begins_with("--takeover="):
			parsed["takeover"] = arg.trim_prefix("--takeover=")
	return parsed


func _print_help() -> void:
	print("""
SnipWar Unified Check
======================
Usage: godot --headless --path . --script res://scripts/check.gd [options]

Der Scope wird zu BEGINN festgelegt und ist danach unveränderlich.
Jede Datei außerhalb des Scope muss über --takeover begründet werden.

Options:
  --scope=<staged|full|manifest.json>   Scope-Quelle (default: staged)
  --takeover=<path1,path2,...>          Fremde Dateien in den Scope aufnehmen
  --full                                Voll-Lauf (ignoriert Scope, alles prüfen)
  --cheap-path                          Nur pure Constraints (kein Scene-Boot)
  --fail-fast / -x                      Nach erstem Fehler abbrechen
  --verbose / -v                        Detail-Output
  --skip-compile                        Compile-Gate überspringen
  --skip-preflight                      Preflight überspringen
  --skip-tests                          Tests überspringen
  --scope-report                        Nur Scope-Analyse ausgeben, nichts prüfen
  --help / -h                           Diese Hilfe

Phasen:
  1. Scope auflösen (staged files → contracts → constraints)
  2. Compile-Gate (scope-gefiltert oder full)
  3. Preflight (nur Constraints die der Scope erfordert)
  4. Tests (nur Tests die zum Scope-Modul gehören)

Modulabhängige Scope-Lokalisierung:
  Das System kennt den Modul-Kontext über Contracts.
  "Das ist von mir" = Dateien liegen in einem Contract den der Agent kennt.
  --takeover nimmt fremde Anpassungen explizit in den Scope auf.
""")
