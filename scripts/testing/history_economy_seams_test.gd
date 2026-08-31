extends SceneTree

func _initialize() -> void:
	var simulator := HistorySimulator.new()
	var factions := {
		&"a": {"territory": 1, "economy": 40, "military": 20, "science": 20, "alive": true},
		&"b": {"territory": 1, "economy": 35, "military": 20, "science": 20, "alive": true},
	}
	var planets := {
		&"p_a": {"owner": &"a"},
		&"p_b": {"owner": &"b"},
	}
	var result: Dictionary = simulator.simulate_with_snapshots(factions, planets, 777, 20, null, 5)
	var snapshots: Array = result.get("snapshots", [])
	_assert(not snapshots.is_empty(), "history emits snapshots")
	var first: HistoricalSnapshot = snapshots[0]
	var last: HistoricalSnapshot = snapshots[snapshots.size() - 1]
	# seam 1: economy state present per faction, evolving over years
	_assert(first.economy_state.has(&"a"), "snapshot contains faction economy")
	_assert(first.economy_state[&"a"].has("stock"), "snapshot contains stock")
	_assert(first.economy_state[&"a"].has("net"), "snapshot contains net balance")
	_assert(float(last.economy_state[&"a"].get("stock", 0.0)) != float(first.economy_state[&"a"].get("stock", 0.0)), "economy evolves across history")
	# seam 2: serialization round-trip
	var round_trip := HistoricalSnapshot.from_dict(first.to_dict())
	_assert(round_trip.economy_state == first.economy_state, "economy state survives snapshot serialization")
	# seam 2b: old snapshot dict without economy field loads with empty dict
	var legacy := HistoricalSnapshot.from_dict({"year": 0, "ownership": {}, "visual_state": {}, "wars": [], "truces": {}})
	_assert(legacy.economy_state.is_empty(), "legacy dict loads with empty economy")
	print("HISTORY_ECONOMY_SEAMS: PASS")
	quit()

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error("HISTORY_ECONOMY_SEAMS: FAIL — " + message)
		quit(1)
