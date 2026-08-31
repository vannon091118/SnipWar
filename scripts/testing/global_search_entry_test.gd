extends SceneTree

## Global Search Entry Test: Validates search_core.gd index and query
## functionality across project files.
##
## Exit 1 on any failure — real assertions, no print-only.

const SEARCH_CORE := preload("res://scripts/search_core.gd")

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var core: Object = SEARCH_CORE.new()

	# Test 1: Configure and run a search for a known term
	core.configure("GameState", [], [], 50, 2, false)
	var result: Dictionary = core.run()
	if result.is_empty():
		_failures.append("SearchCore run() returned empty result for 'GameState'")

	# Test 2: Results contain matches
	var matches: Array = result.get("matches", [])
	if matches.is_empty():
		_failures.append("SearchCore returned no matches for 'GameState'")
	else:
		# Verify at least one .gd file matched
		var found_gd: bool = false
		for m in matches:
			var path: String = str(m.get("file", m.get("path", "")))
			if path.ends_with(".gd"):
				found_gd = true
				break
		if not found_gd:
			_failures.append("SearchCore matches missing .gd files for 'GameState'")

	# Test 3: classes_available present
	var classes: Dictionary = result.get("classes_available", {})
	if classes.is_empty():
		_failures.append("SearchCore classes_available is empty")
	elif not classes.has("GameState"):
		_failures.append("SearchCore classes_available missing GameState")

	# Test 4: Regex search
	core.configure("func\\s+_ready", [], [], 20, 1, true)
	var regex_result: Dictionary = core.run()
	if regex_result.is_empty():
		_failures.append("SearchCore regex search returned empty")

	# Test 5: Type filter (gd only)
	core.configure("class_name", ["gd"], [], 50, 0, false)
	var gd_result: Dictionary = core.run()
	var gd_matches: Array = gd_result.get("matches", [])
	for m in gd_matches:
		var path: String = str(m.get("file", m.get("path", "")))
		if not path.ends_with(".gd"):
			_failures.append("GD filter returned non-.gd file: %s" % path)
			break

	# Test 6: Dependency graph present
	var dep_graph: Dictionary = result.get("dependency_graph", {})
	if dep_graph.is_empty():
		_failures.append("SearchCore dependency_graph is empty")

	if not _failures.is_empty():
		for f in _failures:
			printerr("[GLOBAL-SEARCH-FAIL] " + f)
		print("GLOBAL SEARCH ENTRY TEST: FAIL (%d failures)" % _failures.size())
		quit(1)
		return
	print("GLOBAL SEARCH ENTRY TEST: PASS (search index verified)")
	quit(0)
