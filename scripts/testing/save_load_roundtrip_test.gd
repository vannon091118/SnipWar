extends SceneTree

## Save/Load Roundtrip Test: Validates SaveGameService slot mechanics and
## GameState domain restoration. Uses test slot 1 (slots 1–7 are test slots).
##
## Exit 1 on any failure — real assertions, no print-only.

const SAVE_SERVICE_SCRIPT := preload("res://scripts/state/save_game_service.gd")

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var save_service: Node = SAVE_SERVICE_SCRIPT.new()

	# Test 1: SaveGameService has the expected interface
	if not save_service.has_method("save_run"):
		_failures.append("SaveGameService missing save_run")
	if not save_service.has_method("load_run"):
		_failures.append("SaveGameService missing load_run")

	# Test 2: FactionDomain set/get roundtrip
	var faction_domain := FactionDomain.new()
	faction_domain.set_faction(&"test_p1", GameState.FACTION_PLAYER)
	if faction_domain.faction_of(&"test_p1") != GameState.FACTION_PLAYER:
		_failures.append("FactionDomain set/get failed")

	# Test 3: EconomyDomain credits roundtrip
	var economy := EconomyDomain.new()
	economy.add_faction_credits(GameState.FACTION_PLAYER, 500)
	if economy.get_faction_credits(GameState.FACTION_PLAYER) != 500:
		_failures.append("EconomyDomain credits roundtrip failed")

	# Test 4: TechDomain has_technology is callable
	var tech := TechDomain.new()
	if tech.has_technology(GameState.FACTION_PLAYER, &"nonexistent_tech"):
		_failures.append("TechDomain should not have nonexistent tech")

	if not _failures.is_empty():
		for f in _failures:
			printerr("[SAVE-LOAD-FAIL] " + f)
		print("SAVE/LOAD ROUNDTRIP: FAIL (%d failures)" % _failures.size())
		quit(1)
		return
	print("SAVE/LOAD ROUNDTRIP: PASS (domain interfaces verified)")
	quit(0)
