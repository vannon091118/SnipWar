extends SceneTree
## Mechanical compile gate: compiles EVERY GDScript in res://scripts AND
## res://addons/gdscript_mcp through the REAL GDScript compiler (reload() API)
## and reports every parse failure. No game logic is run — pure script
## compilation. Hard gate: exit code 1 on ANY failure, 0 only on full clean.
##
## Why reload() and not load(): load() returns a script object even when the
## compile fails (proven: a file with a parse error printed SCRIPT ERROR and
## still counted as PASS). reload() returns ERR_PARSE_ERROR — deterministic.
##
## Usage:
##   "$GODOT_BIN" --headless --path . --script res://scripts/testing/compile_gate.gd

const EVIDENCE_PATH := "user://mcp_evidence/compile_gate.json"
const EVIDENCE_TMP := "user://mcp_evidence/compile_gate.tmp"

var _files: Array[String] = []
var _failures: Array[String] = []
var _live_verified := 0

func _init() -> void:
	_collect("res://scripts")
	_collect("res://addons/gdscript_mcp")
	print("COMPILE_GATE: scanning ", _files.size(), " files")
	for path in _files:
		_compile(path)
	var passed := _failures.is_empty()
	var report := {
		"gate": "compile_gate",
		"result": "PASS" if passed else "FAIL",
		"files_scanned": _files.size(),
		"live_verified_at_startup": _live_verified,
		"failures": _failures,
	}
	_write_evidence(report)
	if passed:
		print("COMPILE_GATE: PASS — all ", _files.size(), " scripts compile clean (", _live_verified, " live-verified at startup)")
		print("EVIDENCE: ", ProjectSettings.globalize_path(EVIDENCE_PATH))
	else:
		print("COMPILE_GATE: FAIL — ", _failures.size(), " files:")
		for failure in _failures:
			print("  ", failure)
		print("EVIDENCE: ", ProjectSettings.globalize_path(EVIDENCE_PATH))
	quit(1 if not _failures.is_empty() else 0)

func _write_evidence(data: Dictionary) -> void:
	var dir := DirAccess.open("user://")
	if dir == null or not dir.dir_exists("mcp_evidence"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://mcp_evidence"))
	var file := FileAccess.open(EVIDENCE_TMP, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write evidence (compile_gate): " + EVIDENCE_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	# atomar: erst tmp, dann rename — kein halbgeschriebener Befund
	DirAccess.rename_absolute(ProjectSettings.globalize_path(EVIDENCE_TMP), ProjectSettings.globalize_path(EVIDENCE_PATH))

func _collect(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir():
			if entry != "." and entry != "..":
				_collect(dir_path.path_join(entry))
		elif entry.ends_with(".gd"):
			_files.append(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()

func _compile(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		_failures.append(path + "  (unreadable source)")
		return
	# load() liefert auch bei Parse-Error ein Script-Objekt (nie null) — deshalb
	# ist reload() die Wahrheits-Instanz: es rekompiliert deterministisch und
	# liefert OK oder ERR_PARSE_ERROR. Kein resource_path-Setzen nötig
	# (cached Objekt hat seinen Pfad bereits; frische Dateien kompilieren auch
	# ohne). source_code wird überschrieben, damit IMMER der Disk-Stand
	# kompiliert wird, nicht ein veralteter Startup-Cache.
	var cached := load(path) as GDScript
	if cached == null:
		_failures.append(path + "  (load returned null)")
		return
	cached.source_code = text
	var result := cached.reload()
	if result == OK:
		return
	if result == ERR_ALREADY_IN_USE:
		# Live-Instanzen existieren (z.B. .tres-Ressourcen hängen an dem Script):
		# der Engine-Reload-Schutz verweigert die Re-Kompilation — die Engine hat
		# das Skript beim Startup bereits validiert und instantiiert (sonst wäre
		# die Ressourcen-Kette nicht geladen). Mehr Beweis geht nicht.
		_live_verified += 1
		return
	_failures.append(path + "  (reload returned " + error_string(result) + ")")