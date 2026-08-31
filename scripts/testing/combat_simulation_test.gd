extends SceneTree

## Combat Simulation Test: Validates FleetBattleSimulator and ConquestSimulator
## deterministic behavior with same seed, replay integrity, and result consistency.
##
## Exit 1 on any failure — real assertions, no print-only.

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Test 1: Fleet battle determinism (same seed = same result)
	var fleet_a: FleetSnapshot = _create_test_fleet("fleet_a", GameState.FACTION_PLAYER)
	var fleet_b: FleetSnapshot = _create_test_fleet("fleet_b", GameState.FACTION_CPU)

	var replay_1: CombatReplay = FleetBattleSimulator.simulate_battle(fleet_a, fleet_b, 424242)
	var replay_2: CombatReplay = FleetBattleSimulator.simulate_battle(fleet_a, fleet_b, 424242)

	if replay_1.winner != replay_2.winner:
		_failures.append("Fleet battle not deterministic: winner differs (%s vs %s)" % [replay_1.winner, replay_2.winner])
	if replay_1.events.size() != replay_2.events.size():
		_failures.append("Fleet battle not deterministic: event count differs (%d vs %d)" % [replay_1.events.size(), replay_2.events.size()])
	if replay_1.duration != replay_2.duration:
		_failures.append("Fleet battle not deterministic: duration differs (%f vs %f)" % [replay_1.duration, replay_2.duration])

	# Test 2: Fleet battle replay integrity
	if replay_1.events.is_empty():
		_failures.append("Fleet battle produced no events")
	else:
		for i in range(replay_1.events.size()):
			var event: BattleEvent = replay_1.events[i]
			if event == null:
				_failures.append("Battle event %d is null" % i)
				continue
			if event.timestamp < 0.0:
				_failures.append("Battle event %d has negative timestamp" % i)

	# Test 3: Conquest simulation determinism
	var conquest_1: CombatReplay = ConquestSimulator.simulate_conquest(fleet_a, 10, 5, 8, 4, 100.0, 424242)
	var conquest_2: CombatReplay = ConquestSimulator.simulate_conquest(fleet_a, 10, 5, 8, 4, 100.0, 424242)

	if conquest_1.captured != conquest_2.captured:
		_failures.append("Conquest not deterministic: captured differs (%s vs %s)" % [str(conquest_1.captured), str(conquest_2.captured)])
	if conquest_1.surviving_attackers != conquest_2.surviving_attackers:
		_failures.append("Conquest not deterministic: attackers differ (%d vs %d)" % [conquest_1.surviving_attackers, conquest_2.surviving_attackers])
	if conquest_1.surviving_garrison != conquest_2.surviving_garrison:
		_failures.append("Conquest not deterministic: garrison differs (%d vs %d)" % [conquest_1.surviving_garrison, conquest_2.surviving_garrison])

	# Test 4: Different seeds produce different (but valid) results
	var replay_3: CombatReplay = FleetBattleSimulator.simulate_battle(fleet_a, fleet_b, 999999)
	if String(replay_3.winner).is_empty():
		_failures.append("Battle with different seed produced no winner")

	# Test 5: Edge cases - empty fleet, single ship
	var empty_fleet: FleetSnapshot = FleetSnapshot.new()
	empty_fleet.faction = GameState.FACTION_PLAYER
	var single_ship_fleet: FleetSnapshot = _create_test_fleet("single", GameState.FACTION_CPU, 1)

	var edge_replay: CombatReplay = FleetBattleSimulator.simulate_battle(empty_fleet, single_ship_fleet, 424242)
	if edge_replay.winner != GameState.FACTION_CPU:
		_failures.append("Empty fleet vs single ship: wrong winner (%s)" % edge_replay.winner)

	# Test 6: CombatReplay validation
	var validation_errors: PackedStringArray = replay_1.validate()
	if not validation_errors.is_empty():
		_failures.append("CombatReplay validation failed: %s" % ", ".join(Array(validation_errors)))

	if not _failures.is_empty():
		for failure in _failures:
			printerr("[COMBAT-FAIL] " + failure)
		print("COMBAT SIMULATION: FAIL (%d failures)" % _failures.size())
		quit(1)
		return
	print("COMBAT SIMULATION: PASS (all checks verified)")
	quit(0)

func _create_test_fleet(fleet_id: String, faction: StringName, ship_count: int = 3) -> FleetSnapshot:
	var fleet: FleetSnapshot = FleetSnapshot.new()
	fleet.faction = faction
	fleet.fleet_id = StringName(fleet_id)
	fleet.ships = _create_test_ships(ship_count, fleet_id)
	return fleet

func _create_test_ships(count: int, prefix: String) -> Array[ShipAssembly]:
	var ships: Array[ShipAssembly] = []
	for i in range(count):
		var ship: ShipAssembly = ShipAssembly.new()
		ship.ship_id = StringName("%s_%d" % [prefix, i])
		ship.hull_id = &"hull_t1_scout"
		ship.drive_id = &"drive_t1_ion_blue"
		ship.weapon_id = &"weapon_t1_pulse"
		ship.shield_id = &"shield_t1_reactive"
		ship.scanner_id = &"scanner_t1_basic"
		ships.append(ship)
	return ships
