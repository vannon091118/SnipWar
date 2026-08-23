class_name PreflightConstraintConceptIndex
extends RefCounted

## Validates the conceptual code index. Filesystem discovery is performed with
## Godot APIs so the audit does not depend on shell grep/ripgrep output.

func constraint_name() -> String:
	return "concept_index"

func run(ctx: PreflightContext) -> bool:
	var index: ConceptIndex = ConceptIndex.new()
	var discovered: Dictionary = {}
	_collect_class_names("res://scripts", discovered)

	var missing: PackedStringArray = []
	for class_name_value in discovered:
		if index.class_concept(String(class_name_value)) == null:
			missing.append(String(class_name_value))
	if not missing.is_empty():
		push_warning("ConceptIndex: %d classes not mapped: %s" % [missing.size(), ", ".join(missing)])

	var stale: PackedStringArray = index.stale_class_references()
	if not ctx.check(stale.is_empty(), "ConceptIndex contains stale class references", {"stale": stale} if not stale.is_empty() else {}):
		return false

	for term in ["ship", "fleet", "economy", "resource", "planet", "battle", "tech", "save", "worker", "navigation"]:
		if not ctx.check(not index.search(term).is_empty(), "ConceptIndex.search('%s') returned no results" % term):
			return false
	for term in ["ship", "economy", "planet"]:
		if not ctx.check(not index.expand(term).is_empty(), "ConceptIndex.expand('%s') returned no results" % term):
			return false

	if ctx.verbose:
		print("ConceptIndex: %s" % index.summary())
		print("ConceptIndex: %d classes discovered, %d unmapped, %d stale" % [discovered.size(), missing.size(), stale.size()])
	return true

func _collect_class_names(path: String, result: Dictionary) -> void:
	var directory: DirAccess = DirAccess.open(path)
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

func _scan_class_name(path: String, result: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.begins_with("class_name "):
			var class_name_value: String = line.substr("class_name ".length()).strip_edges()
			if not class_name_value.is_empty():
				result[class_name_value] = path
			break
	file.close()
