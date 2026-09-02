extends SceneTree

const RESOLVER: Script = preload("res://scripts/preflight_v2/change_impact_resolver.gd")
const SCANNER: Script = preload("res://scripts/preflight_v2/constraint_scanner.gd")

var checks := 0
var failures := 0


func _init() -> void:
	# Valid known path → deterministic, non-empty required scope.
	var valid: Dictionary = RESOLVER.resolve(["scripts/state/game_state.gd"])
	_check(valid.ok, "known path resolves")
	_check(valid.constraints.has("game_state_compatibility"), "game_state_compatibility in required scope")
	_check(valid.constraints.has("save_game_roundtrip"), "transitive save contract in required scope")
	_check(not valid.constraints.is_empty(), "scope never empty on known path")

	# Deterministic: same input, same scope.
	var reordered: Dictionary = RESOLVER.resolve(["scripts/state/game_state.gd"])
	_check(valid.constraints == reordered.constraints, "resolution is deterministic")

	# Empty scope → fail closed.
	var empty: Dictionary = RESOLVER.resolve([])
	_check(not empty.ok and empty.error == "empty_staged_scope", "empty staged scope rejects")

	# Unknown path → fail closed (never guessed green).
	var unknown: Dictionary = RESOLVER.resolve(["some/unknown/thing.gd"])
	_check(not unknown.ok and String(unknown.error).begins_with("unknown_impact"), "unknown path rejects")

	# Unmapped status (rename/copy) → fail closed.
	var rename: Dictionary = RESOLVER.resolve_status(["R100\told.gd\tnew.gd"])
	_check(not rename.ok, "rename status rejects")

	# V3-005: Deletion status resolves (the deleted path must produce a
	# contract scope — deletions reach the resolver, never dropped early).
	var deletion: Dictionary = RESOLVER.resolve_status(["D\tscripts/state/chunk_save_data.gd"])
	_check(deletion.ok and deletion.contracts.has("save"), "deletion status resolves to contract scope")

	# V3-005: Deletion of an UNKNOWN path still fails closed.
	var deletion_unknown: Dictionary = RESOLVER.resolve_status(["D\tsome/unknown/thing.gd"])
	_check(not deletion_unknown.ok and String(deletion_unknown.error).begins_with("unknown_impact"),
		"deletion of unknown path rejects")

	# Managed narrative artifacts resolve (doki contract), never unknown.
	var auto: Dictionary = RESOLVER.resolve(["narrative_chain.json"])
	_check(auto.ok and auto.contracts.has("doki"), "auto-managed artifacts map to doki contract")

	# Scanner coverage: every constraint belongs to at least one contract.
	var scanner = SCANNER.new()
	var registry: Array = scanner.scan()
	_check(registry.size() >= 40, "registry discovered (%d)" % registry.size())
	var orphaned: Array[String] = []
	for entry in registry:
		# contracts_for is the canonical closure lookup
		if scanner.contracts_for(String(entry["id"])).is_empty():
			orphaned.append(String(entry["id"]))
	_check(orphaned.is_empty(), "no orphaned constraints" + ((": " + str(orphaned)) if not orphaned.is_empty() else ""))

	print("Checks: %d, Failures: %d" % [checks, failures])
	print("RESULT: %s" % ("PASSED" if failures == 0 else "FAILED"))
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("[PASS] %s" % label)
	else:
		failures += 1
		print("[FAIL] %s" % label)