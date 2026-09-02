class_name PreflightConstraintNarrativeRuntime
extends RefCounted

## Narrative Runtime Gate als Preflight-Constraint (NARRATIVE_ENGINE_DESIGN G19:
## fail-closed, Bestandteil des Preflight). Ruft die Python-Runtime (stdlib-only)
## im Verify-Modus auf — read-only, temporäre Archive — und prüft Exit-Code +
## alle G-Checks auf PASS.
##
## Das ist der einzige Berührungspunkt zwischen Godot-Seite und Runtime
## (Narrative Adapter): Der Gameplay-Core hat keine direkte Abhängigkeit zur
## Runtime; die Schnittstelle ist datenorientiert (CLI → JSON).

func constraint_name() -> String:
	return "narrative_runtime"

func constraint_description() -> String:
	return "Narrative Runtime Gate: stdlib-only, Purity, Event-IDs, Chain-Gaps, Rebuild==Incremental, Relationship/Belief/Thread/Public-State/Spotlight contracts"

func requires_scene() -> bool:
	return false

const CACHE_PATH := "user://narrative_runtime_cache.json"
# DOKI-Migration: narrative Artefakte liegen seit der Pfad-Migration unter
# .doki/ (nicht mehr am Repo-Root). Fallback auf Root für ältere Stände.
const CHAIN_PATH := "res://.doki/narrative_chain.json"
const CHANGE_INDEX_PATH := "res://.doki/change_index.json"
const RUNTIME_DIR := "res://.doki/narrative_runtime"

func run(ctx: PreflightContext) -> bool:
	var root := ProjectSettings.globalize_path("res://")
	# --- R-012: File-based cache ---
	# Hash über Chain + ChangeIndex + Gate-CLI-Code. Bei Cache-Hit:
	# Python-Subprocess überspringen (~20s Ersparnis).
	var current_hash := _compute_hash()
	var cached := _read_cache()
	if cached.get("hash", "") == current_hash and cached.has("result"):
		var result: Dictionary = cached["result"]
		var all_pass: bool = result.get("all_pass", false)
		var checks: int = result.get("checks", 0)
		var msg: String = "Narrative Runtime Gate: %d checks — %s (cached)" % [checks, "all PASS" if all_pass else "FAIL"]
		return ctx.check(all_pass, msg, result)
	# --- Cache miss: Python-Subprocess ausführen ---
	var output: Array = []
	# Pfad-Migration: Runtime lebt unter .doki/narrative_runtime. Aufruf mit
	# explizitem sys.path (Package-Kontext für die relativen Imports), statt
	# PYTHONPATH im Hook-Kontext setzen zu müssen.
	var py_code := "import sys; sys.path.insert(0, r'%s'); from narrative_runtime.gate_cli import main; raise SystemExit(main())" % root.path_join(".doki")
	var py_bin := "python3"
	var exit_code: int = OS.execute(py_bin, ["-c", py_code, "--root", root], output, true)
	if exit_code != OK:
		output = []
		py_bin = "python"
		exit_code = OS.execute(py_bin, ["-c", py_code, "--root", root], output, true)
	var raw := ""
	if not output.is_empty():
		raw = String(output[0]).strip_edges()
	if exit_code != OK:
		return ctx.check(false,
			"Narrative Runtime Gate: %s exited %d — Runtime nicht konform oder Python fehlt (fail-closed)" % [py_bin, exit_code],
			{"output": raw.left(400)})
	var parsed := {}
	if raw.begins_with("{"):
		parsed = JSON.parse_string(raw) as Dictionary
	var all_pass := true
	var failed_gates: Array[String] = []
	if parsed.is_empty():
		all_pass = false
		failed_gates.append("no-json")
	else:
		for gate_name in parsed:
			if String(parsed[gate_name]) != "PASS":
				all_pass = false
				failed_gates.append(String(gate_name))
	var result: Dictionary = {"all_pass": all_pass, "checks": parsed.size(), "gates": parsed}
	_write_cache(current_hash, result)
	return ctx.check(all_pass,
		"Narrative Runtime Gate: %d checks — %s" % [parsed.size(), "all PASS" if all_pass else "FAIL: %s" % ", ".join(failed_gates)],
		{"gates": parsed})

func _compute_hash() -> String:
	# Hash over chain + change-index + ALL runtime sources (gate_cli and every
	# module it imports). Hashing only gate_cli.py let a nonconformance in
	# observe.py/store.py/etc. slip past the cache and keep a stale PASS alive
	# — fail-closed means the cache must invalidate on ANY runtime code change.
	var parts: PackedStringArray = []
	for path in [CHAIN_PATH, CHANGE_INDEX_PATH]:
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			parts.append(f.get_as_text())
			f.close()
	var dir := DirAccess.open(RUNTIME_DIR)
	if dir != null:
		var files: Array = []
		dir.list_dir_begin()
		while true:
			var entry: String = dir.get_next()
			if entry.is_empty():
				break
			if entry.ends_with(".py"):
				files.append(entry)
		dir.list_dir_end()
		files.sort()
		for fname in files:
			var f := FileAccess.open(RUNTIME_DIR.path_join(String(fname)), FileAccess.READ)
			if f != null:
				parts.append(f.get_as_text())
				f.close()
	return str("".join(parts).hash())

func _read_cache() -> Dictionary:
	var f := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var raw: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}

func _write_cache(hash_value: String, result: Dictionary) -> void:
	var data: Dictionary = {"hash": hash_value, "result": result}
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()