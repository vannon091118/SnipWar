class_name PreflightConstraintGlobalSearch
extends RefCounted

## Validates the real global-search engine (SearchCore). Uses the SAME code
## the CLI tool runs — one scan instead of five duplicated scans.

const SEARCH_CORE := preload("res://scripts/search_core.gd")

func constraint_name() -> String:
	return "global_search"

func run(ctx: PreflightContext) -> bool:
	var core: Object = SEARCH_CORE.new()

	# Test 1: basic search returns hits + scan metrics
	core.configure("fleet", ["gd"])
	var basic: Dictionary = core.run()
	if not ctx.check(int(basic.get("total_hits", 0)) > 0, "SearchCore finds 'fleet' in .gd files"):
		return false
	if not ctx.check(basic.has("total_files_scanned") and int(basic.get("total_files_scanned", 0)) > 0, "SearchCore reports scanned file count"):
		return false
	if not ctx.check(basic.has("duration_ms"), "SearchCore reports duration_ms"):
		return false
	if not ctx.check(basic.has("total_line_count") and int(basic.get("total_line_count", 0)) > 0, "SearchCore reports total_line_count"):
		return false

	# Test 2: type filter — .gd-only must not contain other types
	var by_type: Dictionary = basic.get("by_type", {})
	var has_other_type: bool = false
	for ext_key in by_type:
		if String(ext_key) != "gd":
			has_other_type = true
	if not ctx.check(not has_other_type, "SearchCore type filter keeps only .gd files"):
		return false

	# Test 3: classes_available — the engine must see class_name declarations
	var classes: Dictionary = basic.get("classes_available", {})
	if not ctx.check(classes.size() > 10, "SearchCore discovers class_name availability (>10 classes): %d" % classes.size()):
		return false

	# Test 4: dependency_graph — preloads/extends per file must be present
	var graph: Dictionary = basic.get("dependency_graph", {})
	if not ctx.check(graph.size() > 10, "SearchCore builds dependency_graph for scanned .gd files (%d)" % graph.size()):
		return false
	var first_gd: Dictionary = {}
	for path_key in graph:
		first_gd = graph[path_key] as Dictionary
		break
	if not ctx.check(first_gd.has("extends") and first_gd.has("preloads") and first_gd.has("loads") and first_gd.has("class_name"), "SearchCore dependency entry shape is complete"):
		return false

	# Test 5: exclude dirs work
	core.configure("fleet", [], ["addons"])
	var excl: Dictionary = core.run()
	if not ctx.check(excl.has("total_files_scanned") and int(excl.get("total_files_scanned", 0)) > 0, "SearchCore exclude returns scanned count"):
		return false

	if ctx.verbose:
		print("SearchCore: hits=%d files=%d classes=%d graph=%d LOC=%d duration=%dms" % [
			int(basic.get("total_hits", 0)), int(basic.get("total_files_scanned", 0)),
			classes.size(), graph.size(), int(basic.get("total_line_count", 0)), int(basic.get("duration_ms", 0))
		])

	return true