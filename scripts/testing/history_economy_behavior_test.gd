extends SceneTree

func _initialize() -> void:
	var simulator := HistorySimulator.new()
	var result: Dictionary = simulator.simulate_with_snapshots(
		{&"a": {"territory": 1, "economy": 40, "military": 20, "science": 20, "alive": true}},
		{&"p_a": {"owner": &"a"}}, 777, 20, null, 5
	)
	_assert(not result.get("snapshots", []).is_empty(), "history emits snapshots")
	print("HISTORY_BEHAVIOR: PASS")
	quit()

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error("HISTORY_BEHAVIOR: FAIL — " + message)
		quit(1)
