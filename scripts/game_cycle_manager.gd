extends Node

signal battle_started(context: BattleContext)
signal battle_committed(context: BattleContext)
signal victory_detected(faction: StringName, reason: StringName)

var _pending_battle: BattleContext
var _committed_battles: Dictionary = {}
var _victory_locked: bool = false
var _return_to_world_after_battle: bool = false

func _ready() -> void:
	var state: Node = _game_state()
	if state != null and state.has_signal("faction_changed") and not state.faction_changed.is_connected(_on_faction_changed):
		state.faction_changed.connect(_on_faction_changed)
	if state != null and state.has_method("pending_battle_context"):
		_pending_battle = state.pending_battle_context()

func begin_battle(context: BattleContext, show_scene: bool = true) -> bool:
	if context == null or context.replay == null:
		return false
	_pending_battle = context.copy()
	_return_to_world_after_battle = show_scene
	var state: Node = _game_state()
	if state != null and state.has_method("set_pending_battle_context"):
		state.set_pending_battle_context(_pending_battle)
	battle_started.emit(_pending_battle)
	if show_scene:
		var director: Node = get_node_or_null("/root/SceneDirectorService")
		if director != null and director.has_method("transition_to_layer2"):
			director.call("transition_to_layer2", _pending_battle)
	return true

func pending_battle() -> BattleContext:
	return _pending_battle.copy() if _pending_battle != null else null

func apply_battle_result(context: BattleContext = null) -> bool:
	var resolved: BattleContext = context if context != null else _pending_battle
	if resolved == null or resolved.replay == null or resolved.committed:
		return false
	if _committed_battles.has(resolved.battle_id):
		return false
	var state: Node = _game_state()
	if state == null:
		return false
	var replay := resolved.replay
	if resolved.route_engagement:
		var route_fleets: Array[Array] = [replay.survivors_a, replay.survivors_b]
		for index in range(mini(resolved.transit_ids.size(), route_fleets.size())):
			var record: TransitRecord = state.get_transit(resolved.transit_ids[index])
			if record == null:
				continue
			var survivors: Array[ShipAssembly] = route_fleets[index]
			record.fleet.ships = []
			for survivor in survivors:
				if survivor != null:
					record.fleet.ships.append(survivor.copy())
			if record.fleet.ships.is_empty():
				state.remove_transit(record.transit_id)
			else:
				record.status = TransitRecord.STATUS_IN_FLIGHT
				record.elapsed = maxf(record.elapsed, resolved.engagement_time_a if index == 0 else resolved.engagement_time_b)
				state.update_transit(record)
		resolved.committed = true
		_committed_battles[resolved.battle_id] = true
		_pending_battle = null
		if state.has_method("clear_pending_battle_context"):
			state.clear_pending_battle_context(resolved.battle_id)
		battle_committed.emit(resolved)
		_return_to_world()
		return true
	if replay.is_battle():
		var attacker_won := replay.winner == resolved.fleet_a.faction
		var defender_survivors: Array[ShipAssembly] = replay.survivors_b
		if resolved.fleet_b != null and not String(resolved.fleet_b.source_planet_id).is_empty():
			state.reconcile_defender_fleet(resolved.fleet_b.source_planet_id, resolved.fleet_b, defender_survivors)
		if attacker_won and resolved.fleet_a != null:
			var destination_id: StringName = resolved.fleet_a.destination_planet_id
			var worker_gain := replay.survivors_a.size() * 10
			if state.faction_of(destination_id) != resolved.fleet_a.faction:
				state.set_faction(destination_id, resolved.fleet_a.faction)
			if worker_gain > 0:
				state.add_starting_workers(destination_id, worker_gain)
		for ship in resolved.fleet_a.ships:
			if ship == null:
				continue
			if not _assembly_survived(replay.survivors_a, ship.ship_id):
				state.ship_lost.emit(resolved.fleet_a.source_planet_id, ship.ship_id)
		for transit_id in resolved.transit_ids:
			state.remove_transit(transit_id)
		resolved.committed = true
		_committed_battles[resolved.battle_id] = true
		_pending_battle = null
		if state.has_method("clear_pending_battle_context"):
			state.clear_pending_battle_context(resolved.battle_id)
		battle_committed.emit(resolved)
		_return_to_world()
		return true
	return false

func _return_to_world() -> void:
	if not _return_to_world_after_battle:
		return
	_return_to_world_after_battle = false
	var director: Node = get_node_or_null("/root/SceneDirectorService")
	if director != null and director.has_method("transition_to_layer1"):
		director.call("transition_to_layer1")

func check_victory() -> bool:
	if _victory_locked:
		return true
	var state: Node = _game_state()
	if state == null:
		return false
	var player_home: StringName = state.homeworld_for(GameState.FACTION_PLAYER)
	var cpu_home: StringName = state.homeworld_for(GameState.FACTION_CPU)
	if not String(player_home).is_empty() and state.faction_of(player_home) == GameState.FACTION_CPU:
		_victory_locked = true
		victory_detected.emit(GameState.FACTION_CPU, &"homeworld_capture")
		return true
	if not String(cpu_home).is_empty() and state.faction_of(cpu_home) == GameState.FACTION_PLAYER:
		_victory_locked = true
		victory_detected.emit(GameState.FACTION_PLAYER, &"homeworld_capture")
		return true
	return false

func _on_faction_changed(_planet_id: StringName, _old_faction: StringName, _new_faction: StringName) -> void:
	check_victory()

func _assembly_survived(survivors: Array[ShipAssembly], ship_id: StringName) -> bool:
	for survivor in survivors:
		if survivor != null and survivor.ship_id == ship_id:
			return true
	return false

func _game_state() -> Node:
	return get_node_or_null("/root/GameState")
