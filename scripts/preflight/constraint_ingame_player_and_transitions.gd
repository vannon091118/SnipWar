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

	# 4. BattleScene with Ingame Controls
	var battle := BattleScene.new()
	ctx.root().add_child(battle)
	var mock_res := {
		"winner": GameState.FACTION_PLAYER,
		"survivors_a": [],
		"survivors_b": [],
		"duration": 2.0,
		"events": Array([
			BattleEvent.create(0.0, BattleEvent.TYPE_SPAWN, &"a_0", &"", 100.0, Vector2(-100, 0)),
			BattleEvent.create(0.0, BattleEvent.TYPE_SPAWN, &"b_0", &"", 100.0, Vector2(100, 0)),
			BattleEvent.create(0.5, BattleEvent.TYPE_FIRE, &"a_0", &"b_0", 20.0, Vector2(-100, 0), Vector2(100, 0)),
			BattleEvent.create(0.6, BattleEvent.TYPE_HIT, &"a_0", &"b_0", 20.0, Vector2(-100, 0), Vector2(100, 0)),
			BattleEvent.create(1.0, BattleEvent.TYPE_DESTROYED, &"b_0", &"", 0.0, Vector2(100, 0))
		], TYPE_OBJECT, "RefCounted", BattleEvent) as Array[BattleEvent]
	}
	battle.play_battle(mock_res)
	if not ctx.check(battle.visible == true, "BattleScene should be visible during playback"):
		return false
	battle._finish_battle()
	if not ctx.check(battle.visible == false, "BattleScene should hide on finish"):
		return false
	battle.queue_free()

	# 5. ConquestScene with Ingame Controls
	var conquest := ConquestScene.new()
	ctx.root().add_child(conquest)
	conquest.play_conquest({"captured": true, "duration": 1.5})
	if not ctx.check(conquest.visible == true, "ConquestScene should be visible during playback"):
		return false
	conquest._finish_conquest()
	if not ctx.check(conquest.visible == false, "ConquestScene should hide on finish"):
		return false
	conquest.queue_free()

	return true
