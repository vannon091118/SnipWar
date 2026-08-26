extends Node

## Game-flow orchestrator: scene transitions, battle commits and victory checks.
##
## GameCycleManager is the single authority for game-flow decisions.
## BattleScene and ConquestScene are NEVER accessed directly — they are
## created and managed through typed interfaces (play_battle/play_conquest)
## and communicate back via signals.
##
## Inline replay orchestration: when a BattleScene or ConquestScene is
## created as an inline child (e.g. inside ConflictManager's parent node),
## the scene's completion signal is wired to apply_battle_result here.

signal battle_started(context: BattleContext)
signal battle_committed(context: BattleContext)
signal replay_completed(type: StringName, replay: CombatReplay)
signal victory_detected(faction: StringName, reason: StringName)

var _pending_battle: BattleContext
var _committed_battles: Dictionary = {}
var _victory_locked: bool = false
var _return_to_world_after_battle: bool = false
## Track inline replay nodes so we can clean them up on completion.
var _inline_battle: BattleScene = null
var _inline_conquest: ConquestScene = null

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
		_return_to_world(resolved.return_scene_id)
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
		_return_to_world(resolved.return_scene_id)
		return true
	return false

# --- Inline Replay Orchestration ---
# When a BattleScene or ConquestScene is created inside the Layer-1 tree
# (e.g. as a child of ConflictManager's parent), the scene's completion
# signal is wired here. GameCycleManager decides whether to commit the
# result and clean up.

## Creates a BattleScene as an inline child of `parent` and wires its
## completion signal to `apply_battle_result`. Used for AI-only or
## in-world replay without a full scene switch.
func begin_inline_battle(context: BattleContext, parent: Node) -> void:
	if context == null or context.replay == null or parent == null:
		return
	_free_inline_battle()
	var scene: BattleScene = BattleScene.new()
	scene.name = "BattleReplay"
	parent.add_child(scene)
	scene.battle_completed.connect(Callable(self, "_on_inline_battle_completed").bind(context))
	scene.play_battle(context.replay)
	_inline_battle = scene

## Creates a ConquestScene as an inline child of `parent` and wires its
## completion signal to `apply_battle_result`. Used for in-world replay
## without a full scene switch.
func begin_inline_conquest(context: BattleContext, parent: Node) -> void:
	if context == null or context.replay == null or parent == null:
		return
	_free_inline_conquest()
	var scene: ConquestScene = ConquestScene.new()
	scene.name = "ConquestReplay"
	parent.add_child(scene)
	scene.conquest_completed.connect(Callable(self, "_on_inline_conquest_completed").bind(context))
	scene.play_conquest(context.replay)
	_inline_conquest = scene

func _on_inline_battle_completed(_replay: CombatReplay, context: BattleContext) -> void:
	_free_inline_battle()
	apply_battle_result(context)
	replay_completed.emit(&"battle", _replay)

func _on_inline_conquest_completed(_replay: CombatReplay, context: BattleContext) -> void:
	_free_inline_conquest()
	apply_battle_result(context)
	replay_completed.emit(&"conquest", _replay)

func _free_inline_battle() -> void:
	if _inline_battle != null and is_instance_valid(_inline_battle):
		_inline_battle.queue_free()
	_inline_battle = null

func _free_inline_conquest() -> void:
	if _inline_conquest != null and is_instance_valid(_inline_conquest):
		_inline_conquest.queue_free()
	_inline_conquest = null

## Signal handler: ConflictManager emits replay_requested when a combat
## replay needs visual playback. GameCycleManager creates the appropriate
## inline scene and wires its completion to apply_battle_result.
func _on_replay_requested(simulation_type: StringName, replay: CombatReplay) -> void:
	if replay == null:
		return
	# Only player-initiated replays need visual playback.
	var state: Node = _game_state()
	var is_player := false
	if replay.is_battle():
		is_player = replay.winner == GameState.FACTION_PLAYER
	elif replay.is_conquest():
		is_player = replay.captured
	if not is_player:
		return
	# Build a minimal BattleContext for the inline replay. The ConflictManager
	## already stores any full context in _pending_overlay_context for the
	## route-engagement path; here we create a lightweight context for
	## planet-arrival replays that don't need full transit bookkeeping.
	var context := BattleContext.new()
	context.battle_id = &"inline_%s" % simulation_type
	context.replay = replay
	if replay.is_battle():
		context.fleet_a = FleetSnapshot.new()
		context.fleet_a.faction = GameState.FACTION_PLAYER
		context.fleet_b = FleetSnapshot.new()
		context.fleet_b.faction = GameState.FACTION_CPU
	else:
		context.fleet_a = FleetSnapshot.new()
		context.fleet_a.faction = GameState.FACTION_PLAYER
		context.fleet_b = FleetSnapshot.new()
		context.fleet_b.faction = GameState.FACTION_CPU
	# Find the appropriate parent for the inline scene.
	var parent: Node = _find_replay_parent()
	if parent == null:
		return
	if simulation_type == &"battle":
		begin_inline_battle(context, parent)
	elif simulation_type == &"conquest":
		begin_inline_conquest(context, parent)

## Finds the best parent node for an inline replay scene.
## Prefers the ConflictManager's parent (PlanetField) since that's
## where the Layer-1 world scene lives.
func _find_replay_parent() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var world: Node = tree.current_scene
	if world == null:
		return null
	var field: Node = world.get_node_or_null("PlanetField")
	return field if field != null else world

## Returns to the scene named by the battle context (`return_scene_id`, a
## SceneDirector registry id; defaults to "world"). The tree is not paused at
## this point — the battle scene never pauses it — so the director switch is
## safe without an explicit unpause.
func _return_to_world(return_scene_id: StringName = &"world") -> void:
	if not _return_to_world_after_battle:
		return
	_return_to_world_after_battle = false
	var director: Node = get_node_or_null("/root/SceneDirectorService")
	if director == null:
		return
	if director.has_method("goto_scene") and bool(director.call("goto_scene", return_scene_id)):
		return
	# Fallback keeps the historical guarantee: an unregistered or empty
	# return_scene_id still lands back on the strategy overworld.
	if director.has_method("transition_to_layer1"):
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
