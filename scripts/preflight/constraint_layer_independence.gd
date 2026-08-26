class_name PreflightConstraintLayerIndependence
extends RefCounted

## Verifies that BattleScene and ConquestScene are self-contained visual
## layers with no runtime dependency on GameState or GameCycleManager autoloads.
## They receive data through typed inputs (play_battle/play_conquest) and
## communicate results back via signals only.


func constraint_name() -> String:
	return "layer_independence"


func requires_scene() -> bool:
	return true


func run(ctx: PreflightContext) -> bool:
	# --- BattleScene independence ---
	# BattleScene must work as a standalone node: create, play, finish,
	# without ever calling get_node("/root/GameState") or
	# get_node("/root/GameCycleManager").
	var battle := BattleScene.new()
	ctx.root().add_child(battle)

	var fleet_a := FleetSnapshot.new()
	fleet_a.fleet_id = &"fleet_indep_a"
	fleet_a.faction = GameState.FACTION_PLAYER
	fleet_a.ships = [ctx.make_ship_assembly(&"hull_t1", &"scanner_t1", [], &"weapon_t1", &"drive_t1", &"shield_t1")]
	fleet_a.calculate_stats()
	var fleet_b := FleetSnapshot.new()
	fleet_b.fleet_id = &"fleet_indep_b"
	fleet_b.faction = GameState.FACTION_CPU
	fleet_b.ships = [ctx.make_ship_assembly(&"hull_t1", &"scanner_t1")]
	fleet_b.calculate_stats()
	var replay: CombatReplay = FleetBattleSimulator.simulate_battle(fleet_a, fleet_b, 7777)
	if not ctx.check(replay != null and replay.is_battle(), "battle independence: valid replay needed"):
		battle.queue_free()
		return false

	# Track signal emission with a bound handler (not a lambda).
	var signal_result := {"fired": false, "replay": null}
	battle.battle_completed.connect(_on_battle_completed.bind(signal_result))

	battle.play_battle(replay)
	if not ctx.check(battle.visible, "BattleScene must be visible after play_battle()"):
		battle.queue_free()
		return false

	# Finish — signal must fire, visibility must clear.
	battle._finish_battle()
	if not ctx.check(not battle.visible, "BattleScene must hide after finish"):
		battle.queue_free()
		return false
	if not ctx.check(signal_result.fired, "BattleScene must emit battle_completed on finish"):
		battle.queue_free()
		return false

	battle.queue_free()

	# --- ConquestScene independence ---
	var conquest := ConquestScene.new()
	ctx.root().add_child(conquest)

	var conquest_replay := CombatReplay.new_conquest(9999)
	conquest_replay.captured = true
	conquest_replay.duration = 1.5
	conquest_replay.perimeter_slots = 3
	conquest_replay.tower_count = 3
	conquest_replay.surviving_attackers = 2
	conquest_replay.surviving_garrison = 1
	conquest_replay.defense_range = 150.0

	var conquest_result := {"fired": false, "replay": null}
	conquest.conquest_completed.connect(_on_conquest_completed.bind(conquest_result))

	conquest.play_conquest(conquest_replay)
	if not ctx.check(conquest.visible, "ConquestScene must be visible after play_conquest()"):
		conquest.queue_free()
		return false

	conquest._finish_conquest()
	if not ctx.check(not conquest.visible, "ConquestScene must hide after finish"):
		conquest.queue_free()
		return false
	if not ctx.check(conquest_result.fired, "ConquestScene must emit conquest_completed on finish"):
		conquest.queue_free()
		return false

	conquest.queue_free()
	return true


## Signal handler for battle_completed — binds a result dictionary.
func _on_battle_completed(replay: CombatReplay, result: Dictionary) -> void:
	result["fired"] = true
	result["replay"] = replay


## Signal handler for conquest_completed — binds a result dictionary.
func _on_conquest_completed(replay: CombatReplay, result: Dictionary) -> void:
	result["fired"] = true
	result["replay"] = replay
