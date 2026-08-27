class_name PreflightCodeIndex
extends RefCounted

## Shared In-Memory Codebase Index für die Preflight Suite.
##
## Liest alle relevanten Quelltexte beim Start EINMAL sequenziell von Disk
## und hält sie als RAM-Tabellen vor. Alle Pure-Constraints greifen
## ausschließlich auf diesen Index zu — kein eigenes FileAccess mehr.
##
## API:
##   build()                        → Einmaliger Disk-Scan (call once before Phase 1)
##   gd_sources                     → Array[{file, content, lines[]}] aller .gd-Dateien
##   sources_under(root)            → gefilterte Sicht (Prefix-Match auf file)
##   get_file_content(path)         → gecachter Inhalt einer beliebigen Datei
##   inject_into_search_core(core)  → befüllt SearchCore._gd_sources ohne zweiten Scan
##   stats()                        → {files_gd, files_cached, total_loc, build_ms}

const SCAN_ROOT    := "res://"
const EXCLUDE_DIRS: Array[String] = [
	".godot", ".git", ".import", "build", "dist", "node_modules",
]

## Pfade, die unabhängig von der .gd-Filterung immer gecacht werden.
const ALWAYS_CACHE: Array[String] = [
	"res://docs/FINDINGS.md",
	"res://CHANGELOG.md",
]

## Array[Dictionary{file:String, content:String, lines:Array[String]}]
## Enthält alle .gd-Quelltexte, die beim Scan gefunden wurden.
var gd_sources: Array[Dictionary] = []

## Vollständiger Inhalt ausgewählter Nicht-.gd-Dateien (path → content).
var _file_cache: Dictionary = {}

var _build_ms: float = 0.0
var _total_loc: int = 0
var _built: bool = false


## Sequenzieller Einmal-Scan. Muss vor Phase 1 aufgerufen werden.
func build() -> void:
	if _built:
		push_warning("[PreflightCodeIndex] build() called more than once — ignoring")
		return
	gd_sources.clear()
	_file_cache.clear()
	_total_loc = 0
	var t0 := Time.get_ticks_usec()

	_scan_dir(SCAN_ROOT)

	# Statische Docs immer cachen (falls nicht bereits als .gd erfasst)
	for path in ALWAYS_CACHE:
		if not _file_cache.has(path) and FileAccess.file_exists(path):
			_file_cache[path] = FileAccess.get_file_as_string(path)

	_build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_built = true


## Gibt alle gd_sources zurück, deren Pfad mit `root` beginnt.
## Nützlich für Constraints, die nur eine Sub-Tree brauchen (z.B. addons/).
func sources_under(root: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source in gd_sources:
		if String(source.file).begins_with(root):
			result.append(source)
	return result


## Gibt den gecachten Inhalt einer Datei zurück.
## Liest einmalig nach (lazy) falls der Pfad nicht im ALWAYS_CACHE war.
## Gibt "" zurück wenn die Datei nicht existiert.
func get_file_content(path: String) -> String:
	if _file_cache.has(path):
		return String(_file_cache[path])
	if FileAccess.file_exists(path):
		var content: String = FileAccess.get_file_as_string(path)
		_file_cache[path] = content
		return content
	return ""


## Befüllt SearchCore._gd_sources mit den bereits gelesenen Daten.
## Danach startet SearchCore.run() keinen eigenen _scan_dir-Durchlauf mehr.
## SearchCore muss inject_sources() unterstützen (seit diesem Commit).
func inject_into_search_core(core: SearchCore) -> void:
	# Konvertiere in das Format, das SearchCore._gd_sources erwartet:
	# {file: String, lines: Array[String]}
	# (content wird von SearchCore nicht gebraucht, nur lines)
	var converted: Array[Dictionary] = []
	for source in gd_sources:
		converted.append({
			"file": String(source.file),
			"lines": source.lines,
		})
	core.inject_sources(converted)


## Laufzeit-Metriken des letzten build()-Aufrufs.
func stats() -> Dictionary:
	return {
		"files_gd":     gd_sources.size(),
		"files_cached": _file_cache.size(),
		"total_loc":    _total_loc,
		"build_ms":     _build_ms,
	}


# --- Interner Scan ---

func _scan_dir(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if entry.begins_with(".") or entry in EXCLUDE_DIRS:
			continue
		var child: String = path.path_join(entry)
		if directory.current_is_dir():
			_scan_dir(child)
		elif entry.ends_with(".gd"):
			_load_gd_file(child)
	directory.list_dir_end()


func _load_gd_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var lines: Array[String] = []
	while not file.eof_reached():
		lines.append(file.get_line())
	file.close()
	_total_loc += lines.size()
	var content: String = "\n".join(lines)
	gd_sources.append({
		"file":    path,
		"content": content,
		"lines":   lines,
	})
