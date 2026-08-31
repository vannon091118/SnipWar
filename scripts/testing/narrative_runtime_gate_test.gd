extends SceneTree

## Narrative Runtime Gate Entry Test: Validates Python narrative_runtime
## G1-G24 gates pass (fail-closed, read-only verification).

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Check if narrative_chain.json and change_index.json exist
	var chain_path: String = "res://narrative_chain.json"
	var index_path: String = "res://change_index.json"
	
	if not FileAccess.file_exists(chain_path):
		_failures.append("narrative_chain.json not found at %s" % chain_path)
		_quit()
		return
	
	if not FileAccess.file_exists(index_path):
		_failures.append("change_index.json not found at %s" % index_path)
		_quit()
		return
	
	# Try to run Python gate_cli
	var py_bin: String = "python3"
	var output: Array = []
	var exit_code: int = OS.execute(py_bin, ["-m", "narrative_runtime.gate_cli", "--root", ProjectSettings.globalize_path("res://")], output, true)
	
	if exit_code != 0:
		# Try python instead of python3
		output = []
		py_bin = "python"
		exit_code = OS.execute(py_bin, ["-m", "narrative_runtime.gate_cli", "--root", ProjectSettings.globalize_path("res://")], output, true)
	
	if exit_code != 0:
		var error_msg: String = "Narrative Runtime Gate: %s exited %d" % [py_bin, exit_code]
		if not output.is_empty():
			error_msg += " — Output: " + String(output[0]).strip_edges().left(200)
		_failures.append(error_msg)
		_quit()
		return
	
	# Parse JSON output
	var raw: String = ""
	if not output.is_empty():
		raw = String(output[0]).strip_edges()
	
	if not raw.begins_with("{"):
		_failures.append("Narrative Runtime Gate output not JSON: %s" % raw.left(200))
		_quit()
		return
	
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		_failures.append("Narrative Runtime Gate JSON parse failed")
		_quit()
		return
	
	# Verify all gates PASS
	var all_pass: bool = true
	var failed_gates: Array[String] = []
	var gate_count: int = 0
	
	for gate_name in parsed:
		gate_count += 1
		if String(parsed[gate_name]) != "PASS":
			all_pass = false
			failed_gates.append("%s=%s" % [gate_name, String(parsed[gate_name])])
	
	if gate_count == 0:
		_failures.append("Narrative Runtime Gate returned no gates")
	elif not all_pass:
		_failures.append("Narrative Runtime Gate FAILED gates: %s" % ", ".join(failed_gates))
	
	# Verify expected gates (G1-G24)
	var expected_gates: Array = ["G1", "G2", "G3", "G4", "G5", "G6/G7", "G8/G9", "G10/G14", "G11", "G12", "G13", "G14", "G15", "G16", "G17", "G18", "G19", "G20", "G21", "G22", "G23", "G24"]
	for expected in expected_gates:
		if not parsed.has(expected):
			_failures.append("Missing expected gate: %s" % expected)
	
	# Verify cache invalidation works (R-012)
	var runtime_dir: String = "res://narrative_runtime"
	var cache_path: String = "user://narrative_runtime_cache.json"
	
	if FileAccess.file_exists(cache_path):
		var cache_file: FileAccess = FileAccess.open(cache_path, FileAccess.READ)
		if cache_file != null:
			var cache_raw: String = cache_file.get_as_text()
			cache_file.close()
			var cache_parsed: Variant = JSON.parse_string(cache_raw)
			if cache_parsed is Dictionary and cache_parsed.has("hash"):
				# Hash should include all runtime .py files
				var cached_hash: String = str(cache_parsed["hash"])
				var current_hash: String = _compute_runtime_hash()
				if cached_hash != current_hash:
					_failures.append("Runtime cache hash mismatch (cache invalidation working)")
	
	_quit()

func _compute_runtime_hash() -> String:
	var parts: PackedStringArray = []
	var chain_path: String = "res://narrative_chain.json"
	var index_path: String = "res://change_index.json"
	
	for path in [chain_path, index_path]:
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			parts.append(f.get_as_text())
			f.close()
	
	var runtime_dir: String = "res://narrative_runtime"
	var dir := DirAccess.open(runtime_dir)
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
			var f := FileAccess.open(runtime_dir.path_join(String(fname)), FileAccess.READ)
			if f != null:
				parts.append(f.get_as_text())
				f.close()
	
	return str("".join(parts).hash())

func _quit() -> void:
	if not _failures.is_empty():
		for failure in _failures:
			printerr("[NARRATIVE-GATE-FAIL] " + failure)
		print("NARRATIVE RUNTIME GATE ENTRY TEST: FAIL (%d failures)" % _failures.size())
		quit(1)
	else:
		print("NARRATIVE RUNTIME GATE ENTRY TEST: PASS (all G1-G24 gates verified)")
		quit(0)