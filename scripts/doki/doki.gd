extends SceneTree
## DOKI CommitLayer CLI v2 — deterministischer Commit-Narrator.
## Aufruf:  $GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- <cmd> [args]
## Subcommands:
##   init                    Genesis: Chain am HEAD verankern (einmalig)
##   prepare "<impuls>"      idle → prepared (nach `git add`; schreibt .doki/prompt.txt)
##   finish                  prepared → verified (Body via --body, --body-file oder stdin)
##   verify-only <msgfile>   Checks 1-9 auf Message (commit-msg Hook)
##   finalize                verified → idle (post-commit Hook; idempotent)
##   repair                  Recovery: Crash / rebase / amend
##   status                  Zustand + Chain-Info
## Optionen: --repo <pfad>, --model <id>, --json

const ORCHESTRATOR_SCRIPT: String = "res://scripts/doki/orchestration/commit_orchestrator.gd"

var _json_output: bool = false


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var exit_code: int = _main(args)
	quit(exit_code)


func _main(args: PackedStringArray) -> int:
	if args.is_empty():
		_print_help()
		return 0

	var command: String = args[0]
	var rest: Array = []
	for i in range(1, args.size()):
		rest.append(args[i])

	var repo_root: String = _option(rest, "--repo", ".")
	_json_output = _has_flag(rest, "--json")
	repo_root = ProjectSettings.globalize_path(repo_root) if repo_root.begins_with("res://") else repo_root

	# Orchestrator-Skript erst einmal laden (Parser-Fehler früh melden)
	var orchestrator: DOKI_CommitOrchestrator = _build_orchestrator(repo_root)
	if orchestrator == null:
		push_error("DOKI: Orchestrator konnte nicht erstellt werden.")
		return 1

	match command:
		"init":
			var seed_last: int = int(_option(rest, "--seed-last", "0"))
			return _ok(orchestrator.init_flow(seed_last), "DOKI initialisiert:")
		"prepare":
			var impulse: String = _positional(rest, 0)
			var model_id: String = _option(rest, "--model", "claude-sonnet-4")
			if impulse.is_empty():
				return _fail("prepare: Impuls erforderlich.   doki prepare \"<impuls>\"")
			var result: Dictionary = orchestrator.prepare(impulse, model_id)
			if not result["ok"]:
				return _fail(str(result.get("error", "prepare fehlgeschlagen.")))
			if _json_output:
				_print_json({"ok": true, "narrator": result["session"].get("narrator", ""), "mood": result["session"].get("mood", ""), "composite": result["session"].get("composite", ""), "prompt_path": result.get("prompt_path", ""), "is_arc_climax": result["session"].get("is_arc_climax", false)})
				return 0
			print("✓ prepare: Narrator=%s Mood=%s Composite=%s" % [result["session"].get("narrator", ""), result["session"].get("mood", ""), result["session"].get("composite", "")])
			print("  Prompt: %s" % result.get("prompt_path", ""))
			if bool(result["session"].get("is_arc_climax", false)):
				print("  ⚠ ARC_CLIMAX — dieser Commit ist das Staffelfinale!")
			return 0
		"finish":
			var body: String = _body_input(rest)
			if body.is_empty():
				return _fail("finish: Body fehlt. Text via --body, --body-file oder stdin übergeben.")
			var result: Dictionary = orchestrator.finish(body)
			if not result["ok"]:
				if result.get("phase") == "verify":
					print("✗ HARTE BLOCKS (Checks 7-9):")
					for e in result.get("errors", []):
						print("  ✗ %s" % str(e))
					if not result.get("soft_errors", []).is_empty():
						print("Warnungen (1-6):")
						for e in result.get("soft_errors", []):
							print("  ⚠ %s" % str(e))
					return 1
				return _fail(str(result.get("error", "finish fehlgeschlagen.")))
			if _json_output:
				_print_json({"ok": true, "message": result["message"]})
				return 0
			print("✓ finish: 9 Checks — Message geschrieben nach .commit_msg.txt")
			for e in result.get("soft_errors", []):
				print("  ⚠ %s" % str(e))
			print("  → git commit -F .commit_msg.txt")
			return 0
		"gate":
			var gate_result: Dictionary = orchestrator.gate()
			if not gate_result["ok"]:
				return _fail(str(gate_result.get("error", "Gate blockiert den Commit.")))
			if _json_output:
				_print_json(gate_result)
				return 0
			return 0
		"verify-only":
			var msg_file: String = _positional(rest, 0)
			if msg_file.is_empty():
				return _fail("verify-only: Message-Datei erforderlich.")
			var full_path: String = msg_file if msg_file.is_absolute_path() else repo_root.path_join(msg_file)
			if not FileAccess.file_exists(full_path):
				return _fail("verify-only: Datei nicht gefunden: %s" % full_path)
			var message: String = FileAccess.get_file_as_string(full_path)
			var result: Dictionary = orchestrator.verify_only(message)
			if not result["ok"]:
				for e in result.get("errors", []):
					print("✗ %s" % str(e))
				if not result.get("soft_errors", []).is_empty():
					print("Warnungen (1-6):")
					for e in result.get("soft_errors", []):
						print("  ⚠ %s" % str(e))
				return 1
			print("✓ verify-only: Alle harten Checks (7-9) bestanden.")
			return 0
		"finalize":
			var result: Dictionary = orchestrator.finalize_flow_run()
			if not result["ok"]:
				return _fail(str(result.get("error", "finalize fehlgeschlagen.")))
			if bool(result.get("idempotent", false)):
				return 0
			if _json_output:
				_print_json({"ok": true, "entry": result.get("entry", {})})
				return 0
			var entry: Dictionary = result.get("entry", {})
			print("✓ finalize: Chain-Eintrag %d (c%d, p%d, %s, %s)" % [int(entry.get("seq", 0)), int(entry.get("c", 0)), int(entry.get("p_id", 0)), str(entry.get("narrator", "")), str(entry.get("composite", ""))])
			var arc_result: Dictionary = result.get("arc", {})
			if bool(arc_result.get("advanced", false)):
				print("  ✦ ARC abgeschlossen: '%s' → neuer Arc '%s'" % [str(arc_result.get("old_arc_name", "")), str(arc_result.get("new_arc_name", ""))])
			return 0
		"amend":
			var body: String = _body_input(rest)
			if body.is_empty():
				return _fail("amend: Body fehlt. Text via --body, --body-file oder stdin übergeben.")
			var result: Dictionary = orchestrator.amend(body)
			if not result["ok"]:
				if result.get("phase") == "verify":
					print("✗ HARTE BLOCKS (Checks 1-8):")
					for e in result.get("errors", []):
						print("  ✗ %s" % str(e))
					if not result.get("soft_errors", []).is_empty():
						print("Warnungen (1-6):")
						for e in result.get("soft_errors", []):
							print("  ⚠ %s" % str(e))
					return 1
				return _fail(str(result.get("error", "amend fehlgeschlagen.")))
			if _json_output:
				_print_json({"ok": true, "message": result["message"]})
				return 0
			print("✓ amend: Checks 1-8 bestanden — Message geschrieben nach .commit_msg.txt")
			print("  → git commit --amend -F .commit_msg.txt")
			return 0
		"repair":
			var result: Dictionary = orchestrator.repair()
			if not result["ok"]:
				return _fail(str(result.get("error", "repair fehlgeschlagen.")))
			for r in result.get("repaired", []):
				print("✓ repair: %s" % str(r))
			if result.get("repaired", []).is_empty():
				print("✓ repair: nichts zu tun.")
			return 0
		"status":
			var result: Dictionary = orchestrator.status()
			if result.get("initialized", false) == false:
				print("DOKI: nicht initialisiert — `doki init` läuft noch nicht.")
				return 0
			if _json_output:
				_print_json(result)
				return 0
			print("DOKI Status")
			print("  Zustand:   %s" % str(result.get("state", "?")))
			print("  Anker:     %s (%s)" % [str(result.get("anchor", {}).get("hash", "?")).substr(0, 7), str(result.get("anchor", {}).get("subject", ""))])
			print("  Chain:     %d Einträge, letzter c=%d" % [int(result.get("entries", 0)), int(result.get("latest_c", 0))])
			var last: Dictionary = result.get("last_entry", {})
			if not last.is_empty():
				print("  Letzter:   p%d %s (%s, %s)" % [int(last.get("p_id", 0)), str(last.get("composite", "")), str(last.get("narrator", "")), str(last.get("mood", ""))])
			var composite: String = str(result.get("composite", ""))
			if not composite.is_empty():
				print("  Session:   %s (%s, %s)" % [composite, str(result.get("narrator", "")), str(result.get("mood", ""))])
			return 0
		_:
			return _fail("Unbekanntes Kommando: %s" % command)


## ─── Helfer ─────────────────────────────────────────────────────────────
static func _build_orchestrator(repo_root: String) -> DOKI_CommitOrchestrator:
	var orchestrator := DOKI_CommitOrchestrator.new(repo_root)
	return orchestrator


static func _option(args: Array, name: String, default_value: String) -> String:
	for i in args.size():
		if str(args[i]) == name and i + 1 < args.size():
			return str(args[i + 1])
	return default_value


static func _has_flag(args: Array, flag: String) -> bool:
	return args.has(flag)


static func _positional(args: Array, index: int) -> String:
	var positionals: Array = []
	for a in args:
		if not str(a).begins_with("--"):
			positionals.append(str(a))
	return str(positionals[index]) if index < positionals.size() else ""


## Body-Eingabe: --body <text> | --body-file <pfad> | stdin (Pipe).
static func _body_input(args: Array) -> String:
	var inline: String = _option(args, "--body", "")
	if not inline.is_empty():
		return inline
	var file_body: String = _option(args, "--body-file", "")
	if not file_body.is_empty():
		var full_path: String = file_body if file_body.is_absolute_path() else _option(args, "--repo", ".").path_join(file_body)
		if not FileAccess.file_exists(full_path):
			return ""
		return FileAccess.get_file_as_string(full_path)
	# stdin lesen NUR mit explizitem --stdin Flag (Godot 4.7 hat kein
	# is_stdin_connected(); ohne Flag könnte ein geschlossenes stdin als
	# „wartet auf Eingabe“ hängen). Hooks nutzen --body bzw. --body-file.
	if _has_flag(args, "--stdin"):
		return OS.read_string_from_stdin()
	return ""


func _ok(result: Dictionary, label: String) -> int:
	if not result["ok"]:
		return _fail(str(result.get("error", "Fehler.")))
	if _json_output:
		_print_json(result)
		return 0
	print("✓ %s" % label)
	for key in result.keys():
		if key == "ok" or key == "error":
			continue
		var value: Variant = result[key]
		if value is Dictionary or value is Array:
			print("  %s: %s" % [key, JSON.stringify(value)])
		else:
			print("  %s: %s" % [key, str(value)])
	return 0


func _fail(message: String) -> int:
	if _json_output:
		_print_json({"ok": false, "error": message})
	else:
		print("✗ %s" % message)
	return 1


func _print_json(data: Variant) -> void:
	print(JSON.stringify(data))


func _print_help() -> void:
	print("DOKI CommitLayer CLI v2")
	print("  init [--seed-last N]    Genesis am HEAD verankern; letzte N Commits als Chain-Vorgeschichte")
	print("  prepare \"<impuls>\"      Nach `git add` — schreibt .doki/prompt.txt (Narrator+Mood deterministisch)")
	print("  finish                  Body via --body \"<text>\" / --body-file <pfad> / --stdin (explizit)")
	print("  amend                   DOKI-Message des letzten Commits nachbearbeiten (Body ersetzen)")
	print("  verify-only <msgfile>   Checks 1-9 (commit-msg Hook)")
	print("  gate                    pre-commit Gate (Session + Snapshot + .commit_msg.txt)")
	print("  finalize                Chain-Append nach Commit (post-commit Hook)")
	print("  repair                  Recovery nach Crash / rebase / amend")
	print("  status                  Zustand + Chain")
	print("Optionen: --repo <pfad>  --model <id>  --json")