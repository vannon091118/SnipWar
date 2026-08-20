class_name PreflightConstraintIngamePlayerAndTransitions
extends RefCounted

## FloatingText, IngamePlayerControls, SceneDirector and battle/conquest scene playback.

func constraint_name() -> String:
	return "ingame_player_and_transitions"


func run(ctx: PreflightContext) -> bool:
	# 1. FloatingText
	var dummy_parent := Node2D.new()
	ctx.root().add_child(dummy_parent)
	var ft: FloatingText = FloatingText.spawn(dummy_parent, "-25", Vector2(100, 100), Color.YELLOW, 0.5)
	if not ctx.check(ft != null, "FloatingText spawn failed"):
		return false
	dummy_parent.queue_free()

	# 2. IngamePlayerControls
	var controls := IngamePlayerControls.new()
	ctx.root().add_child(controls)
	controls.setup(20.0)
	if not ctx.check(controls.total_duration == 20.0, "IngamePlayerControls total_duration mismatch"):
		return false
	if not ctx.check(controls.is_playing == true, "IngamePlayerControls should start playing"):
		return false
	controls._on_play_pressed()
	if not ctx.check(controls.is_playing == false, "IngamePlayerControls play toggle failed"):
		return false
	controls._on_speed_pressed() # changes from 1.0x to 2.0x
	if not ctx.check(controls.playback_speed == 2.0, "IngamePlayerControls speed toggle failed"):
		return false
	controls.set_progress(5.0)
	if not ctx.check(controls.current_time == 5.0, "IngamePlayerControls progress set failed"):
		return false
	controls.queue_free()

	# 3. SceneDirector
	var director := SceneDirector.new()
	ctx.root().add_child(director)
	var midpoint_called := [false]
	director.transition(0.1, func(): midpoint_called[0] = true)
	if not ctx.check(director.is_transitioning() == true, "SceneDirector should be transitioning"):
		return false
	await director.transition_completed
	if not ctx.check(midpoint_called[0] == true, "SceneDirector midpoint callback not executed"):
		return false
	if not ctx.check(director.is_transitioning() == false, "SceneDirector should finish transition"):
		return false
	director.queue_free()

	# 4. BattleScene with Ingame Controls and data-driven ship visuals.
	var visual_fleet := FleetSnapshot.new()
	visual_fleet.fleet_id = &"fleet_visual_readback"
	visual_fleet.faction = GameState.FACTION_PLAYER
	visual_fleet.ships = [{
		"hull": &"hull_t2",
		"drive": &"drive_t1",
		"weapon": &"weapon_t1",
		"shield": &"shield_t1",
		"scanner": &"scanner_t2",
		"modules": [&"module_reactor"]
	}]
	visual_fleet.calculate_stats()
	var visual_defender := FleetSnapshot.new()
	visual_defender.fleet_id = &"fleet_visual_defender"
	visual_defender.faction = GameState.FACTION_CPU
	visual_defender.ships = [{
		"hull": &"hull_t1",
		"drive": &"drive_t1",
		"weapon": &"weapon_t1",
		"shield": &"shield_t1",
		"scanner": &"scanner_t1",
		"modules": []
	}]
	visual_defender.calculate_stats()
	var visual_result: Dictionary = FleetBattleSimulator.simulate_battle(visual_fleet, visual_defender, 4242)
	var visual_spawn: BattleEvent = null
	for event_value in visual_result.get("events", []):
		var candidate: BattleEvent = event_value as BattleEvent
		if candidate != null and candidate.event_type == BattleEvent.TYPE_SPAWN and candidate.source_id == &"a_0":
			visual_spawn = candidate
			break
	var visual_ship_data: Dictionary = {}
	if visual_spawn != null:
		var raw_ship_data: Variant = visual_spawn.get("ship_data")
		if raw_ship_data is Dictionary:
			visual_ship_data = raw_ship_data as Dictionary
	if not ctx.check(visual_ship_data.get("hull", &"") == &"hull_t2", "battle spawn event must preserve its FleetSnapshot ship data"):
		return false

	var battle := BattleScene.new()
	ctx.root().add_child(battle)
	battle.play_battle(visual_result)
	if not ctx.check(battle.visible == true, "BattleScene should be visible during playback"):
		return false
	battle._process(0.0)
	var rendered_ship: Node = battle._ships.get(&"a_0") as Node
	if not ctx.check(rendered_ship is CompositeShipView, "BattleScene must render spawn events with CompositeShipView"):
		return false
	var rendered_hull: Sprite2D = rendered_ship.get_node_or_null("HullSprite") as Sprite2D
	if not ctx.check(rendered_hull != null and rendered_hull.texture == preload("res://assets/objects/workers/cluster_m.svg"), "BattleScene must render the event's T2 hull asset"):
		return false
	battle._finish_battle()
	if not ctx.check(battle.visible == false, "BattleScene should hide on finish"):
		return false
	battle.queue_free()

	# 5. ConquestScene with Ingame Controls and the attacked planet visual.
	var conquest_target: PlanetDefinition = ctx.planet_catalog.definition_for(&"ocean")
	if not ctx.check(conquest_target != null, "ocean planet definition missing for conquest visual test"):
		return false
	var conquest := ConquestScene.new()
	ctx.root().add_child(conquest)
	var conquest_payload: Dictionary = {
		"captured": true,
		"duration": 1.5,
		"planet_id": conquest_target.planet_id,
		"planet_name": conquest_target.display_name,
		"planet_texture": conquest_target.planet_texture,
		"perimeter_slots": 4,
		"tower_count": 4,
		"surviving_attackers": 3,
		"surviving_garrison": 2,
		"defense_range": 180.0,
		"conquest_seed": 2025,
	}
	conquest.play_conquest(conquest_payload)
	if not ctx.check(conquest.visible == true, "ConquestScene should be visible during playback"):
		return false
	if not ctx.check(conquest._planet_sprite.texture == conquest_target.planet_texture, "ConquestScene must render the attacked planet visual"):
		return false
	if not ctx.check(conquest._towers.size() == 4, "ConquestScene must render the result tower count"):
		return false
	if not ctx.check(conquest._attackers.size() == 3, "ConquestScene must render the surviving attacker count"):
		return false
	if not ctx.check(is_equal_approx(conquest._garrison_bar.max_value, 2.0) and is_equal_approx(conquest._garrison_bar.value, 2.0), "ConquestScene must initialize the surviving garrison"):
		return false
	var first_visual_pick: int = conquest._visual_rng.randi()
	var repeat_conquest := ConquestScene.new()
	ctx.root().add_child(repeat_conquest)
	repeat_conquest.play_conquest(conquest_payload)
	var repeat_visual_pick: int = repeat_conquest._visual_rng.randi()
	if not ctx.check(first_visual_pick == repeat_visual_pick, "ConquestScene cosmetic choices must be seed-deterministic"):
		return false
	repeat_conquest._finish_conquest()
	repeat_conquest.queue_free()
	conquest._finish_conquest()
	if not ctx.check(conquest.visible == false, "ConquestScene should hide on finish"):
		return false
	conquest.queue_free()

	return true
