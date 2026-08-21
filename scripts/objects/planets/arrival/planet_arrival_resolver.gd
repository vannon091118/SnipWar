class_name PlanetArrivalResolver

## Deterministic arrival/combat resolution for Planet nodes. Kept out of
## planet.gd so the Planet node owns state and lifecycle while this static
## helper owns the worker MVP rule, fleet-vs-fleet battles and fleet-vs-ground
## conquest. Planet keeps thin public wrappers, so all callers stay stable.

## Number of surviving attackers registered as workers on a captured planet when
## the result comes from a fleet-vs-fleet FleetBattleSimulator outcome. The
## simulator returns surviving ships (not workers); we convert ships to workers
## at this fixed rate so capture always produces a measurable garrison on the
## destination. ConquestSimulator already operates on workers directly.
const _CAPTURED_WORKER_PER_SHIP := 10

static func resolve_arrival(planet: Planet, source_faction: StringName, amount: int) -> StringName:
	var incoming: int = maxi(amount, 0)
	if incoming <= 0 or source_faction.is_empty() or source_faction == &"neutral":
		return Planet.ARRIVAL_REJECTED
	var destination_faction: StringName = planet.get_faction()
	if destination_faction == source_faction:
		planet.register_workers(incoming)
		return Planet.ARRIVAL_FRIENDLY
	var bonus_defense: int = PlanetTraitAggregator.aggregate_defense_rating(planet)
	var defenders: int = planet.worker_count + bonus_defense
	if incoming <= defenders:
		planet.unregister_workers(mini(incoming, planet.worker_count))
		return Planet.ARRIVAL_REPELLED
	planet.unregister_workers(planet.worker_count)
	planet.set_faction(source_faction)
	planet.register_workers(incoming - defenders)
	return Planet.ARRIVAL_CAPTURED

## Resolves an incoming FleetSnapshot (assembled ships) through the existing
## deterministic FleetBattleSimulator (fleet-vs-fleet) and ConquestSimulator
## (fleet-vs-ground) – the worker-count MVP rule in resolve_arrival() stays for
## pure-worker transit.
##
## defender_fleet: non-null with ships → FleetBattleSimulator; null/empty →
## ConquestSimulator using this planet's defenders.
##
## Returns a Dictionary with `result` (ARRIVAL_*), `surviving_attackers` (int)
## and `duration` (float). Side effects when captured: set_faction(
## attacking_faction) and register_workers(survivor_count).
static func simulate_ship_arrival(planet: Planet, arriving_fleet: FleetSnapshot, defender_fleet: FleetSnapshot = null, battle_seed: int = 1337, conquest_seed: int = 42, ship_role: StringName = &"") -> Dictionary:
	var out: Dictionary = {
		"result": Planet.ARRIVAL_REJECTED,
		"surviving_attackers": 0,
		"duration": 0.0,
		"replay": null,
		"defender_fleet": defender_fleet,
	}
	if planet == null or arriving_fleet == null or arriving_fleet.ships.is_empty():
		return out
	var attacking_faction: StringName = arriving_fleet.faction
	if String(attacking_faction).is_empty() or attacking_faction == GameState.FACTION_NEUTRAL:
		return out
	var resolved_role: StringName = ship_role if not String(ship_role).is_empty() else arriving_fleet.mission_role
	if resolved_role == &"colony":
		if planet.get_faction() == GameState.FACTION_NEUTRAL:
			var state: Node = GameStateAccess.autoload(planet)
			if state != null and state.has_scanned_planet(attacking_faction, planet.planet_id):
				out["result"] = Planet.ARRIVAL_SETTLED
				out["surviving_attackers"] = maxi(arriving_fleet.ships.size() * 10, 1)
			return out
		return out
	if planet.get_faction() == attacking_faction:
		out["result"] = Planet.ARRIVAL_FRIENDLY
		out["surviving_attackers"] = arriving_fleet.ships.size() * _CAPTURED_WORKER_PER_SHIP
		return out
	if defender_fleet != null and not defender_fleet.ships.is_empty():
		var battle: CombatReplay = FleetBattleSimulator.simulate_battle(arriving_fleet, defender_fleet, battle_seed)
		out["replay"] = battle.copy()
		out["duration"] = battle.duration
		out["surviving_attackers"] = battle.survivors_a.size() * _CAPTURED_WORKER_PER_SHIP
		out["result"] = Planet.ARRIVAL_CAPTURED if battle.winner == attacking_faction else Planet.ARRIVAL_REPELLED
		return out
	var conquest: CombatReplay = ConquestSimulator.simulate_conquest(
		arriving_fleet,
		0,
		planet.worker_count,
		PlanetTraitAggregator.aggregate_defense_rating(planet),
		planet.get_perimeter_slots(),
		planet.get_defense_range(),
		conquest_seed
	)
	out["replay"] = _conquest_replay_result(planet, conquest)
	out["duration"] = conquest.duration
	out["surviving_attackers"] = conquest.surviving_attackers
	out["result"] = Planet.ARRIVAL_CAPTURED if conquest.captured else Planet.ARRIVAL_REPELLED
	return out

static func commit_ship_arrival(planet: Planet, arriving_fleet: FleetSnapshot, result: Dictionary, emit_replay: bool = true) -> Dictionary:
	if planet == null or arriving_fleet == null:
		return result
	var outcome: StringName = result.get("result", Planet.ARRIVAL_REJECTED) as StringName
	var replay: CombatReplay = result.get("replay") as CombatReplay
	if replay != null and emit_replay:
		planet.conflict_simulated.emit(replay.simulation_type, replay.copy())
	if outcome == Planet.ARRIVAL_FRIENDLY:
		planet.register_workers(int(result.get("surviving_attackers", 0)))
	elif outcome == Planet.ARRIVAL_SETTLED:
		planet.set_faction(arriving_fleet.faction)
		planet.register_workers(int(result.get("surviving_attackers", 0)))
	elif outcome == Planet.ARRIVAL_CAPTURED:
		planet.unregister_workers(planet.worker_count)
		planet.set_faction(arriving_fleet.faction)
		planet.register_workers(int(result.get("surviving_attackers", 0)))
	var defender_fleet: FleetSnapshot = result.get("defender_fleet") as FleetSnapshot
	if defender_fleet != null and replay != null and replay.is_battle():
		var state: Node = GameStateAccess.autoload(planet)
		if state != null:
			state.reconcile_defender_fleet(planet.planet_id, defender_fleet, replay.survivors_b)
	return result

static func resolve_ship_arrival(planet: Planet, arriving_fleet: FleetSnapshot, defender_fleet: FleetSnapshot = null, battle_seed: int = 1337, conquest_seed: int = 42, ship_role: StringName = &"") -> Dictionary:
	var result := simulate_ship_arrival(planet, arriving_fleet, defender_fleet, battle_seed, conquest_seed, ship_role)
	return commit_ship_arrival(planet, arriving_fleet, result)


static func _resolve_ship_vs_fleet(planet: Planet, arriving_fleet: FleetSnapshot, defender_fleet: FleetSnapshot, battle_seed: int, attacking_faction: StringName, out: Dictionary) -> Dictionary:
	var battle: CombatReplay = FleetBattleSimulator.simulate_battle(arriving_fleet, defender_fleet, battle_seed)
	planet.conflict_simulated.emit(&"battle", battle.copy())
	var winner: StringName = battle.winner
	var survivors: Array[ShipAssembly] = battle.survivors_a
	var defender_survivors: Array[ShipAssembly] = battle.survivors_b
	var state: Node = GameStateAccess.autoload(planet)
	var surviving_defenders: Array[ShipAssembly] = []
	if winner != attacking_faction:
		surviving_defenders = defender_survivors
	if state != null:
		state.reconcile_defender_fleet(planet.planet_id, defender_fleet, surviving_defenders)
	if winner == attacking_faction:
		planet.unregister_workers(planet.worker_count)
		planet.set_faction(attacking_faction)
		var gain: int = survivors.size() * _CAPTURED_WORKER_PER_SHIP
		if gain > 0:
			planet.register_workers(gain)
		out["result"] = Planet.ARRIVAL_CAPTURED
		out["surviving_attackers"] = gain
	else:
		out["result"] = Planet.ARRIVAL_REPELLED
	out["duration"] = battle.duration
	return out


static func _resolve_colony_ship_arrival(planet: Planet, arriving_fleet: FleetSnapshot, attacking_faction: StringName, out: Dictionary) -> Dictionary:
	var state: Node = GameStateAccess.autoload(planet)
	if planet.get_faction() != GameState.FACTION_NEUTRAL or state == null or not state.has_scanned_planet(attacking_faction, planet.planet_id):
		out["result"] = Planet.ARRIVAL_REJECTED
		return out
	var settlers: int = maxi(arriving_fleet.ships.size() * 10, 1)
	planet.set_faction(attacking_faction)
	planet.register_workers(settlers)
	out["result"] = Planet.ARRIVAL_SETTLED
	out["surviving_attackers"] = settlers
	return out


static func _resolve_ship_vs_planet(planet: Planet, arriving_fleet: FleetSnapshot, conquest_seed: int, attacking_faction: StringName, out: Dictionary) -> Dictionary:
	var defender_workers: int = planet.worker_count
	var defense_rating: int = PlanetTraitAggregator.aggregate_defense_rating(planet)
	var conquest: CombatReplay = ConquestSimulator.simulate_conquest(
		arriving_fleet, 0, defender_workers, defense_rating,
		planet.get_perimeter_slots(), planet.get_defense_range(), conquest_seed)
	planet.conflict_simulated.emit(&"conquest", _conquest_replay_result(planet, conquest))
	if conquest.captured:
		planet.unregister_workers(planet.worker_count)
		planet.set_faction(attacking_faction)
		var gain: int = conquest.surviving_attackers
		if gain > 0:
			planet.register_workers(gain)
		out["result"] = Planet.ARRIVAL_CAPTURED
		out["surviving_attackers"] = gain
	else:
		out["result"] = Planet.ARRIVAL_REPELLED
	out["duration"] = conquest.duration
	return out


static func _conquest_replay_result(planet: Planet, conquest: CombatReplay) -> CombatReplay:
	# The simulator owns combat numbers; Planet owns the attacked planet's
	# presentation identity. The replay stores the stable planet id so
	# ConquestScene can resolve the visual from the active catalog.
	var replay_result: CombatReplay = conquest.copy()
	replay_result.planet_id = planet.planet_id
	replay_result.planet_name = planet.display_name
	replay_result.planet_texture_path = planet.planet_texture.resource_path if planet.planet_texture != null else ""
	return replay_result


static func resolve_mission(planet: Planet, source_faction: StringName, amount: int, mission_type: StringName = &"military", source_planet_id: StringName = &"") -> StringName:
	if mission_type == GameState.MISSION_COLONY:
		return _resolve_colony(planet, source_faction, amount)
	if mission_type == GameState.MISSION_CARGO:
		return _resolve_cargo(planet, source_faction, amount)
	if mission_type == GameState.MISSION_COLLECT:
		return _resolve_collect(planet, source_faction, amount, source_planet_id)
	return resolve_military_arrival(planet, source_faction, amount, source_planet_id)

## Resolves a worker military arrival through the deterministic conquest
## adapter. Assemblies are not inferred from a worker transit: an assembled
## ship enters the simulator only through ConflictManager/ShipBase, where its
## FleetSnapshot was explicitly reserved at launch.
static func resolve_military_arrival(planet: Planet, source_faction: StringName, amount: int, _source_planet_id: StringName = &"", conquest_seed: int = 42) -> StringName:
	var incoming: int = maxi(amount, 0)
	if incoming <= 0 or source_faction.is_empty() or source_faction == GameState.FACTION_NEUTRAL:
		return Planet.ARRIVAL_REJECTED
	if planet.get_faction() == source_faction:
		return resolve_arrival(planet, source_faction, incoming)

	var conquest: CombatReplay = ConquestSimulator.simulate_conquest(
		null,
		incoming,
		planet.worker_count,
		PlanetTraitAggregator.aggregate_defense_rating(planet),
		planet.get_perimeter_slots(),
		planet.get_defense_range(),
		conquest_seed
	)
	planet.conflict_simulated.emit(&"conquest", _conquest_replay_result(planet, conquest))
	if conquest.captured:
		planet.unregister_workers(planet.worker_count)
		planet.set_faction(source_faction)
		var survivors: int = conquest.surviving_attackers
		if survivors > 0:
			planet.register_workers(survivors)
		return Planet.ARRIVAL_CAPTURED

	# The simulator decides the outcome; preserve the existing worker-loss
	# contract for a repelled worker wave rather than turning tower HP into
	# persistent worker counts.
	planet.unregister_workers(mini(incoming, planet.worker_count))
	return Planet.ARRIVAL_REPELLED

static func _resolve_colony(planet: Planet, source_faction: StringName, amount: int) -> StringName:
	var incoming: int = maxi(amount, 0)
	if incoming <= 0 or source_faction.is_empty() or source_faction == GameState.FACTION_NEUTRAL:
		return Planet.ARRIVAL_REJECTED
	if planet.get_faction() != GameState.FACTION_NEUTRAL:
		return Planet.ARRIVAL_REJECTED
	planet.set_faction(source_faction)
	planet.register_workers(incoming)
	return Planet.ARRIVAL_SETTLED

static func _resolve_cargo(planet: Planet, source_faction: StringName, amount: int) -> StringName:
	var incoming: int = maxi(amount, 0)
	if incoming <= 0 or source_faction.is_empty() or source_faction == GameState.FACTION_NEUTRAL:
		return Planet.ARRIVAL_REJECTED
	if planet.get_faction() != source_faction:
		return Planet.ARRIVAL_REJECTED
	planet.register_workers(incoming)
	return Planet.ARRIVAL_FRIENDLY

static func _resolve_collect(planet: Planet, source_faction: StringName, amount: int, source_planet_id: StringName = &"") -> StringName:
	var incoming: int = maxi(amount, 0)
	if incoming <= 0 or source_faction.is_empty() or source_faction == GameState.FACTION_NEUTRAL:
		return Planet.ARRIVAL_REJECTED
	if planet.get_faction() != GameState.FACTION_NEUTRAL:
		return Planet.ARRIVAL_REJECTED
	var state: Node = GameStateAccess.autoload(planet)
	if state == null:
		return Planet.ARRIVAL_REJECTED
	var registered: int = state.register_gathering_workers(source_faction, planet.planet_id, incoming, source_planet_id)
	if registered <= 0:
		return Planet.ARRIVAL_REJECTED
	return Planet.ARRIVAL_COLLECTED

static func recall_gathering_workers(planet: Planet, target_faction: StringName, amount: int) -> int:
	var state: Node = GameStateAccess.autoload(planet)
	if state == null:
		return 0
	var source_id: StringName = state.get_gathering_source(target_faction, planet.planet_id) as StringName
	var withdrawn: int = state.withdraw_gathering_workers(target_faction, planet.planet_id, amount)
	if withdrawn <= 0:
		return 0
	if String(source_id).is_empty():
		return withdrawn
	var field: Node = planet.get_parent()
	if field == null:
		return withdrawn
	for child in field.get_children():
		var candidate := child as Planet
		if candidate != null and candidate.planet_id == source_id:
			candidate.register_workers(withdrawn)
			break
	return withdrawn
