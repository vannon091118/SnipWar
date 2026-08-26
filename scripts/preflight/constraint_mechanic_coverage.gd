class_name PreflightConstraintMechanicCoverage
extends RefCounted

## Discovers all game mechanics by reflecting on GameState signals,
## verifies that each has a test model, and reports unregistered
## mechanics. This constraint is READ-ONLY — it never mutates state.

func constraint_name() -> String:
	return "mechanic_coverage"

func requires_scene() -> bool:
	return false

func run(ctx: PreflightContext) -> bool:
	var registry := MechanicRegistry.new()
	var total := registry.count()
	if not ctx.check(total > 0, "MechanicRegistry discovered zero mechanics — reflection may be broken"):
		return false

	# --- Verify all mechanics have descriptions ---
	var all_mechanics := registry.get_all()
	var economy_mechanics := registry.get_by_domain(&"economy")
	if not ctx.check(not economy_mechanics.is_empty(), "MechanicRegistry domain lookup returned no economy mechanics"):
		return false
	for mechanic in all_mechanics:
		if not ctx.check(
			not mechanic.description.is_empty() and not mechanic.description.begins_with("Unknown"),
			"Mechanic '%s' has no description — add it to _describe_signal()" % String(mechanic.id)
		):
			return false

	# --- Verify domain assignment ---
	for mechanic in all_mechanics:
		if not ctx.check(
			mechanic.domain != &"unknown",
			"Mechanic '%s' has no domain assignment — add it to _populate_domain_hints()" % String(mechanic.id)
		):
			return false

	# --- Check for broken test models ---
	var broken := registry.discover_broken_models()
	for mechanic in broken:
		if not ctx.check(
			false,
			"Mechanic '%s' test model not found: %s" % [String(mechanic.id), mechanic.test_model_path]
		):
			return false

	# --- Report unregistered mechanics (soft warning, not failure) ---
	var unregistered := registry.discover_unregistered()
	if not unregistered.is_empty():
		var names: PackedStringArray = []
		for mechanic in unregistered:
			names.append(String(mechanic.id))
		# This is informational — new mechanics are expected during development.
		# The check passes but logs the gap.
		push_warning("MechanicCoverage: %d mechanics without test models: %s" % [unregistered.size(), ", ".join(names)])

	# --- Verify ScenarioSnapshot files exist ---
	var available := ScenarioLoader.list_available()
	if not ctx.check(
		available.size() > 0,
		"No scenario files found in res://resources/scenarios/ — create at least one ScenarioSnapshot"
	):
		return false

	# --- Verify each scenario has valid metadata ---
	# Note: save_data may be null for starter/template scenarios.
	# The ScenarioLoader handles this gracefully (applies seed only).
	for path in available:
		var snapshot: ScenarioSnapshot = load(path) as ScenarioSnapshot
		if not ctx.check(
			snapshot != null,
			"Cannot load scenario: " + path
		):
			return false
		if not ctx.check(
			not String(snapshot.scenario_id).is_empty(),
			"Scenario '%s' has empty scenario_id" % path
		):
			return false
		if not ctx.check(
			not snapshot.display_name.is_empty(),
			"Scenario '%s' has empty display_name" % path
		):
			return false
		if not ctx.check(
			not snapshot.phase.is_empty(),
			"Scenario '%s' has empty phase" % path
		):
			return false

	# --- Summary ---
	var registered := registry.count_registered()
	if ctx.verbose:
		print("MechanicCoverage: %s" % registry.summary())
		print("MechanicCoverage: %d scenario files available" % available.size())
		for path in available:
			var snap: ScenarioSnapshot = load(path) as ScenarioSnapshot
			if snap != null:
				print("  → %s" % snap.summary())

	return true
