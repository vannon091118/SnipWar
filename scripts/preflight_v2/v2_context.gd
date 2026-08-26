class_name PreflightV2Context
extends PreflightContext

## Extends PreflightContext with state-checkpointing, phase tracking,
## and enhanced diagnostics.  Drop-in replacement: existing constraints
## see the full PreflightContext API unchanged.

var phase_name: String = ""
var phase_index: int = 0

## Set by check() when --fail-fast triggers. The runner checks this
## instead of relying on tree.quit(1) which kills the process.
var early_exit_requested: bool = false


## Override _init to skip parent PreflightContext._init() which creates
## an unused PreflightFixture (V2Fixture replaces it in Phase 2).
func _init(p_tree: SceneTree) -> void:
	tree = p_tree
	start_timestamp_msec = Time.get_ticks_msec()

# --- Checkpoint snapshot ---
var _snapshot_ownership: Dictionary = {}  # faction -> count
var _snapshot_resources: Dictionary = {}  # faction -> {resource_id: amount}
var _snapshot_techs: Dictionary = {}      # faction -> Array
var _snapshot_upgrades: Dictionary = {}   # planet_id -> Array
var _snapshot_node_count: int = 0         # field child count (scene-level drift)
var _snapshot_transit_count: int = 0      # active transit count
var _snapshot_worker_counts: Dictionary = {}  # planet_id -> int

var checkpoint_count: int = 0
var isolation_warnings: Array[Dictionary] = []


# --- Override check() to fix fail-fast (no tree.quit) ---
# MUST stay in sync with PreflightContext.check(). The only difference
# is the fail-fast tail: parent calls tree.quit(1), we set a flag.
# We cannot call super.check() here because tree.quit(1) is not interceptable.

func check(condition: bool, message: String, details: Dictionary = {}) -> bool:
	checks_run += 1
	if condition:
		checks_passed += 1
		if verbose:
			print("    [PASS] " + message)
		return true

	failure_count += 1
	var failure_entry: Dictionary = {
		"constraint": active_constraint,
		"message": message,
		"details": details,
		"time_msec": Time.get_ticks_msec() - start_timestamp_msec,
	}
	failures.append(failure_entry)

	var prefix := ""
	if not active_constraint.is_empty():
		prefix = "[" + active_constraint + "] "
	push_error("FAIL " + prefix + message)
	print("    [FAIL] " + prefix + message)

	if not details.is_empty():
		for key in details:
			print("           * %s: %s" % [key, str(details[key])])

	if fail_fast:
		print("\n[preflight-v2] Early exit requested (--fail-fast). Summary will follow.")
		early_exit_requested = true

	return false


# --- Phase tracking ---

func begin_phase(p_name: String) -> void:
	phase_name = p_name
	phase_index += 1
	if verbose:
		print("\n  ═══ PHASE %d: %s ═══" % [phase_index, p_name])


# --- State Checkpointing ---

func take_checkpoint() -> void:
	if game_state == null:
		return
	var state: Node = game_state

	_snapshot_ownership = {}
	for faction in [GameState.FACTION_PLAYER, GameState.FACTION_CPU, GameState.FACTION_NEUTRAL]:
		_snapshot_ownership[faction] = state.get_ownership_count(faction)

	_snapshot_resources = {}
	for faction in [GameState.FACTION_PLAYER, GameState.FACTION_CPU]:
		var res_snap: Dictionary = {}
		for res_id in GameState.ALL_RESOURCES:
			res_snap[res_id] = state.get_faction_resource(faction, res_id)
		_snapshot_resources[faction] = res_snap

	_snapshot_techs = {}
	for faction in [GameState.FACTION_PLAYER, GameState.FACTION_CPU]:
		_snapshot_techs[faction] = state.get_researched_technologies(faction).duplicate()

	_snapshot_upgrades = {}
	_snapshot_worker_counts = {}
	if field != null:
		for child in field.get_children():
			var planet: Planet = child as Planet
			if planet != null:
				_snapshot_upgrades[planet.planet_id] = state.get_planet_upgrades(planet.planet_id).duplicate()
				_snapshot_worker_counts[planet.planet_id] = planet.worker_count
		_snapshot_node_count = field.get_child_count()

	_snapshot_transit_count = state.get_transit_records().size() if state.has_method("get_transit_records") else 0

	checkpoint_count += 1


func verify_checkpoint() -> bool:
	if game_state == null or _snapshot_ownership.is_empty():
		return true

	var state: Node = game_state
	var ok := true

	for faction in _snapshot_ownership:
		var current: int = state.get_ownership_count(faction)
		var expected: int = int(_snapshot_ownership[faction])
		if current != expected:
			ok = false
			isolation_warnings.append({
				"constraint": active_constraint,
				"type": "ownership_drift",
				"faction": String(faction),
				"expected": expected,
				"actual": current,
			})

	for faction in _snapshot_resources:
		var res_snap: Dictionary = _snapshot_resources[faction]
		for res_id in res_snap:
			var current: int = state.get_faction_resource(faction, res_id)
			var expected: int = int(res_snap[res_id])
			if current != expected:
				ok = false
				isolation_warnings.append({
					"constraint": active_constraint,
					"type": "resource_drift",
					"faction": String(faction),
					"resource": String(res_id),
					"expected": expected,
					"actual": current,
				})

	for faction in _snapshot_techs:
		var current: Array = state.get_researched_technologies(faction)
		var expected: Array = _snapshot_techs[faction]
		if current.size() != expected.size():
			ok = false
			isolation_warnings.append({
				"constraint": active_constraint,
				"type": "tech_drift",
				"faction": String(faction),
				"expected_count": expected.size(),
				"actual_count": current.size(),
			})

	# Scene-level drift: field child count
	if field != null:
		var current_count: int = field.get_child_count()
		if current_count != _snapshot_node_count:
			ok = false
			isolation_warnings.append({
				"constraint": active_constraint,
				"type": "node_count_drift",
				"expected": _snapshot_node_count,
				"actual": current_count,
			})

	# Scene-level drift: active transit count
	var current_transits: int = state.get_transit_records().size() if state.has_method("get_transit_records") else 0
	if current_transits != _snapshot_transit_count:
		ok = false
		isolation_warnings.append({
			"constraint": active_constraint,
			"type": "transit_count_drift",
			"expected": _snapshot_transit_count,
			"actual": current_transits,
		})

	# Worker count drift
	if field != null:
		for pid in _snapshot_worker_counts:
			var planet: Planet = find_planet_by_id(field, pid)
			if planet == null:
				continue
			var current_workers: int = planet.worker_count
			var expected_workers: int = _snapshot_worker_counts[pid]
			if current_workers != expected_workers:
				ok = false
				isolation_warnings.append({
					"constraint": active_constraint,
					"type": "worker_count_drift",
					"planet": String(pid),
					"expected": expected_workers,
					"actual": current_workers,
				})

	return ok


func print_isolation_report() -> void:
	if isolation_warnings.is_empty():
		return
	print("\n--- Isolation Warnings (%d mutations detected) ---" % isolation_warnings.size())
	for w in isolation_warnings:
		print("  [%s] %s: %s" % [w["constraint"], w["type"], str(w)])
	print("---")
