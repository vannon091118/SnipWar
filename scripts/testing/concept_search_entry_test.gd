extends SceneTree

## ConceptIndex Search Entry Test: Validates ConceptIndex builds concepts
## and supports search/expand/class_concept/by_domain queries.
##
## Exit 1 on any failure — real assertions, no print-only.

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var concept_index: ConceptIndex = ConceptIndex.new()
	concept_index._build_concepts()

	# Test 1: Search by "ship" returns results
	var ship_results: Array = concept_index.search("ship")
	if ship_results.is_empty():
		_failures.append("ConceptIndex search 'ship' returned empty")

	# Test 2: Expand concept
	var expanded: Array = concept_index.expand("ship")
	if expanded.is_empty():
		_failures.append("ConceptIndex expand 'ship' returned empty")

	# Test 3: Class concept lookup for a known class
	var ship_concept = concept_index.class_concept("ShipManager")
	if ship_concept == null:
		_failures.append("ConceptIndex class_concept('ShipManager') returned null")

	# Test 4: By domain
	var economy_classes: Array = concept_index.by_domain("economy")
	if economy_classes.is_empty():
		_failures.append("ConceptIndex by_domain('economy') returned empty")

	# Test 5: Unmapped classes should be tracked
	var unmapped: Array[String] = concept_index.get_unmapped_classes()
	# Having some unmapped is acceptable; just verify the call works
	# and the list is a valid Array[String]

	# Test 6: Free slots query
	var free_slots: Array[Dictionary] = concept_index.get_concepts_with_free_slots()
	# May be empty or not — just verify it returns without crash

	if not _failures.is_empty():
		for f in _failures:
			printerr("[CONCEPT-SEARCH-FAIL] " + f)
		print("CONCEPT SEARCH ENTRY TEST: FAIL (%d failures)" % _failures.size())
		quit(1)
		return
	print("CONCEPT SEARCH ENTRY TEST: PASS (concept index verified)")
	quit(0)
