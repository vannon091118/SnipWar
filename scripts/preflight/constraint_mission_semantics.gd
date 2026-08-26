class_name PreflightConstraintMissionSemantics
extends RefCounted

## Mission type constants, faction indicator colors and colony/cargo/military
## arrival semantics on owned and neutral planets.

func constraint_name() -> String:
	return "mission_semantics"

func requires_scene() -> bool:
	return true


func run(ctx: PreflightContext) -> bool:
	var field: Node = ctx.field
	var game_state: Node = ctx.game_state

	# Test mission type constants
	if not ctx.check(GameState.MISSION_MILITARY == &"military" and GameState.MISSION_CARGO == &"cargo" and GameState.MISSION_COLONY == &"colony" and GameState.MISSION_COLLECT == &"collect", "mission type constants defined"):
		return false

	# Faction indicators must be visually distinct per faction.
	var faction_transformer_config: TransformerConfig = preload("res://resources/config/transformer_default.tres")
	if not ctx.check(faction_transformer_config.faction_player_tint != faction_transformer_config.faction_cpu_tint and faction_transformer_config.faction_player_tint != faction_transformer_config.faction_neutral_tint and faction_transformer_config.faction_cpu_tint != faction_transformer_config.faction_neutral_tint, "faction indicator colors are not distinguishable"):
		return false

	var player_homeworld: StringName = game_state.homeworld_for(GameState.FACTION_PLAYER)
	var cpu_homeworld_id: StringName = game_state.homeworld_for(GameState.FACTION_CPU)
	var mission_source: Planet = ctx.find_planet_by_id(field, player_homeworld)
	var mission_cpu: Planet = ctx.find_planet_by_id(field, cpu_homeworld_id)
	var mission_neutral: Planet = null
	for planet_child in field.get_children():
		if planet_child is Planet and mission_neutral == null and (planet_child as Planet).get_faction() == GameState.FACTION_NEUTRAL:
			mission_neutral = planet_child as Planet
	if not ctx.check(mission_source != null and mission_cpu != null and mission_neutral != null, "mission test planets missing"):
		return false

	# Colony settles a neutral planet peacefully
	game_state.set_faction(mission_neutral.planet_id, GameState.FACTION_NEUTRAL)
	mission_neutral.unregister_workers(mission_neutral.worker_count)
	var colony_result: StringName = mission_neutral.resolve_mission(GameState.FACTION_PLAYER, 2, GameState.MISSION_COLONY)
	if not ctx.check(colony_result == Planet.ARRIVAL_SETTLED and mission_neutral.get_faction() == GameState.FACTION_PLAYER and mission_neutral.worker_count == 2, "colony mission did not settle a neutral planet"):
		return false

	# Colony on an already owned planet is rejected
	var colony_owned_result: StringName = mission_neutral.resolve_mission(GameState.FACTION_CPU, 1, GameState.MISSION_COLONY)
	if not ctx.check(colony_owned_result == Planet.ARRIVAL_REJECTED and mission_neutral.get_faction() == GameState.FACTION_PLAYER, "colony mission must be rejected on an owned planet"):
		return false

	# Cargo reinforces an own planet (resource transfer)
	game_state.set_faction(mission_source.planet_id, GameState.FACTION_PLAYER)
	var cargo_before: int = mission_source.worker_count
	var cargo_result: StringName = mission_source.resolve_mission(GameState.FACTION_PLAYER, 3, GameState.MISSION_CARGO)
	if not ctx.check(cargo_result == Planet.ARRIVAL_FRIENDLY and mission_source.worker_count == cargo_before + 3, "cargo mission did not reinforce an own planet"):
		return false

	# Cargo against an enemy planet is rejected
	var cargo_enemy_result: StringName = mission_cpu.resolve_mission(GameState.FACTION_PLAYER, 3, GameState.MISSION_CARGO)
	if not ctx.check(cargo_enemy_result == Planet.ARRIVAL_REJECTED and mission_cpu.get_faction() == GameState.FACTION_CPU, "cargo mission must be rejected against an enemy planet"):
		return false

	# Military missions keep attack semantics via resolve_arrival
	var military_result: StringName = mission_neutral.resolve_mission(GameState.FACTION_CPU, 4, GameState.MISSION_MILITARY)
	if not ctx.check(military_result == Planet.ARRIVAL_CAPTURED and mission_neutral.get_faction() == GameState.FACTION_CPU, "military mission should capture an undefended planet"):
		return false

	# Transport state is data-first: the visible cluster may be rebuilt, but the
	# phase/cargo contract must remain available from GameState.
	var transport_path: Array[Vector2] = [mission_source.global_position, mission_cpu.global_position]
	var transport_id: StringName = game_state.begin_worker_transport(GameState.FACTION_PLAYER, mission_source.planet_id, mission_cpu.planet_id, 2, 1.0, transport_path)
	if not ctx.check(not String(transport_id).is_empty(), "worker transport record should be created"):
		return false
	if not ctx.check(game_state.get_worker_transport_records(GameState.FACTION_PLAYER).size() == 1 and game_state.get_worker_transport_records(GameState.FACTION_PLAYER)[0].get("phase") == &"outbound", "worker transport should start outbound"):
		return false
	game_state.update_worker_transport(transport_id, &"returning", GameState.RES_MATERIAL, 4)
	var transport_record: Dictionary = game_state.get_worker_transport_records(GameState.FACTION_PLAYER)[0]
	if not ctx.check(transport_record.get("phase") == &"returning" and transport_record.get("cargo_amount", 0) == 4, "worker transport should persist returning cargo"):
		return false
	if not ctx.check(game_state.complete_worker_transport(transport_id) and game_state.get_worker_transport_records(GameState.FACTION_PLAYER).is_empty(), "delivered worker transport should be removed from active records"):
		return false

	return true
