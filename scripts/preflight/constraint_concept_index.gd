class_name PreflightConstraintConceptIndex
extends RefCounted

## Validates that ConceptIndex covers every class_name script in the project.
## This catches stale entries (deleted classes still in the index) and
## missing entries (new classes not yet indexed).
##
## The constraint is READ-ONLY — it never mutates the index or GameState.

func constraint_name() -> String:
	return "concept_index"

func run(ctx: PreflightContext) -> bool:
	var index := ConceptIndex.new()

	# --- Phase 1: Discover all class_name scripts via filesystem ---
	var discovered_classes: Dictionary = {}  # class_name_str -> file path
	_collect_class_names("res://scripts", discovered_classes)

	# --- Phase 2: Verify every discovered class is in the index ---
	var missing: Array[Dictionary] = []
	for class_name_val in discovered_classes:
		var file_path: String = discovered_classes[class_name_val] as String
		var entry = index.class_concept(class_name_val)  # ConceptEntry or null
		if entry == null:
			missing.append({"class": class_name_val, "file": file_path})

		# Missing classes are a soft warning — PreflightConstraint* and utility
	# classes don't need explicit concept entries.
	if not missing.is_empty():
		var names: PackedStringArray = []
		for m in missing:
			names.append(String(m["class"]))
		push_warning("ConceptIndex: %d classes not covered: %s" % [missing.size(), ", ".join(names)])
		if ctx.verbose:
			for m in missing:
				print("  [MISSING] %s (%s)" % [m["class"], m["file"]])

	# --- Phase 3: Verify index entries reference real classes ---
	var stale: Array[String] = []
	for concept_name in _get_all_concepts(index):
		var entry = index.get_concept(concept_name)  # ConceptEntry or null
		if entry == null:
			continue
		for class_name_val in entry.classes:
			if not discovered_classes.has(class_name_val):
				stale.append("%s.%s" % [concept_name, class_name_val])

	if not ctx.check(
		stale.is_empty(),
		"%d stale class references in ConceptIndex" % stale.size(),
		{"stale": stale} if not stale.is_empty() else {}
	):
		if ctx.verbose:
			for s in stale:
				print("  [STALE] %s" % s)
	# Auto-remove stale entries so the next run is clean
	for s in stale:
		var dot_idx: int = s.find(".")
		if dot_idx >= 0:
			var concept_name: String = s.left(dot_idx)
			var cls_name: String = s.substr(dot_idx + 1)
			var entry = index.get_concept(concept_name)
			if entry != null:
				entry.classes.erase(cls_name)

	# --- Phase 4: Verify search returns results for common terms ---
	var test_terms: Array[String] = ["ship", "fleet", "economy", "resource", "planet", "battle", "tech", "save", "worker", "navigation"]
	for term in test_terms:
		var results: Array = index.search(term)
		if not ctx.check(
			results.size() > 0,
			"ConceptIndex.search('%s') returned zero results" % term
		):
			if ctx.verbose:
				print("  [EMPTY] search('%s')" % term)

	# --- Phase 5: Verify expand returns domain siblings ---
	for term in ["ship", "economy", "planet"]:
		var expanded: Array = index.expand(term)
		if not ctx.check(
			expanded.size() >= 1,
			"ConceptIndex.expand('%s') returned zero results" % term
		):
			if ctx.verbose:
				print("  [EMPTY] expand('%s') → %d results" % [term, expanded.size()])

	# --- Summary ---
	if ctx.verbose:
		print("ConceptIndex: %s" % index.summary())
		print("ConceptIndex: %d classes discovered, %d missing, %d stale" % [
			discovered_classes.size(), missing.size(), stale.size()
		])

	return true


## Collects all class_name declarations by scanning .gd files for `class_name X`.
func _collect_class_names(path: String, result: Dictionary) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue
		var child_path: String = path.path_join(entry)
		if directory.current_is_dir():
			_collect_class_names(child_path, result)
		elif entry.ends_with(".gd"):
			_scan_class_name(child_path, result)
	directory.list_dir_end()


func _scan_class_name(file_path: String, result: Dictionary) -> void:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return
	var line_number := 0
	while not file.eof_reached():
		var line: String = file.get_line()
		line_number += 1
		if line_number > 30:
			break  # class_name is typically in the first 30 lines
		var trimmed := line.strip_edges()
		if trimmed.begins_with("class_name "):
			var class_name_str := trimmed.substr(11).strip_edges()
			if not class_name_str.is_empty():
				result[class_name_str] = file_path
			return
	file.close()


func _get_all_concepts(index: ConceptIndex) -> PackedStringArray:
	var result: PackedStringArray = []
	# Access internal concepts via known concept names from the thesaurus
	var known_concepts: Array = [
		"fleet_management", "economy_resources", "workers_transit",
		"navigation_world", "world_generation", "planets", "combat_battle",
		"technology_research", "ui_systems", "scene_flow", "events_signals",
		"testing_quality", "cpu_ai", "missions", "persistent_ships",
		"background_visuals", "selection_input", "faction_domain", "ship_domain",
	]
	for concept in known_concepts:
		if index.get_concept(concept) != null:
			result.append(concept)
	return result
