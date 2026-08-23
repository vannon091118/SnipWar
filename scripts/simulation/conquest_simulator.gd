@tool
class_name ConquestSimulator
extends RefCounted

const DEFAULT_CONQUEST_CONFIG: ConquestConfig = preload("res://resources/config/conquest_config_default.tres")

static func simulate_conquest(attack_fleet: FleetSnapshot, attacker_workers: int, defending_workers: int, defense_rating: int, perimeter_slots: int, defense_range: float, conquest_seed: int = 42, config: ConquestConfig = null) -> CombatReplay:
	var cfg: ConquestConfig = config if config != null else DEFAULT_CONQUEST_CONFIG
	var rng := RandomNumberGenerator.new()
	rng.seed = conquest_seed

	# Minions aufbauen (Worker + Schiffe)
	var attacker_hp := float(attacker_workers * 10)
	var attacker_dps := float(attacker_workers * 2.0)

	if attack_fleet != null:
		attacker_hp += attack_fleet.total_hull_hp
		attacker_dps += attack_fleet.total_dps

	# Verteidigung aufbauen (Türme + Garnison)
	var tower_count := mini(perimeter_slots, maxi(1, defense_rating))
	var tower_dps := float(tower_count * 5.0 + defense_rating * 3.0)
	var defender_hp := float(defending_workers * 15 + defense_rating * 20)
	var defender_dps := float(defending_workers * 2.0) + tower_dps
	var attacker_initial_hp: float = attacker_hp
	var attacker_initial_dps: float = attacker_dps
	var defender_initial_hp: float = defender_hp
	var defender_initial_dps: float = defender_dps

	var time := 0.0
	var tick := cfg.tick
	var max_time := cfg.max_time

	while time < max_time and attacker_hp > 0.0 and defender_hp > 0.0:
		time += tick
		var dmg_to_def: float = attacker_dps * tick * rng.randf_range(cfg.damage_variance_min, cfg.damage_variance_max)
		var dmg_to_att: float = defender_dps * tick * rng.randf_range(cfg.damage_variance_min, cfg.damage_variance_max)

		defender_hp = maxf(0.0, defender_hp - dmg_to_def)
		attacker_hp = maxf(0.0, attacker_hp - dmg_to_att)

	var replay := CombatReplay.new_conquest(conquest_seed)
	replay.captured = defender_hp <= 0.0 and attacker_hp > 0.0
	replay.surviving_attackers = int(ceil(attacker_hp / 10.0)) if replay.captured else 0
	replay.surviving_garrison = int(ceil(defender_hp / 15.0)) if not replay.captured else 0
	replay.duration = time
	replay.attacker_initial_hp = attacker_initial_hp
	replay.attacker_initial_dps = attacker_initial_dps
	replay.defender_initial_hp = defender_initial_hp
	replay.defender_initial_dps = defender_initial_dps
	replay.attacker_workers = attacker_workers
	replay.defending_workers = defending_workers
	replay.defense_rating = defense_rating
	replay.perimeter_slots = perimeter_slots
	replay.tower_count = tower_count
	replay.defense_range = defense_range
	return replay

## Wave-based tower-defense simulation against a planet's buildable grid.
## `defender_grid` is a Planet.get_defense_snapshot() payload. Deterministic:
## the same conquest_seed always produces the same replay.
##
## Minions derived from ships carry their module state: towers destroy modules
## individually (drive destroyed → minion stops advancing), repair drones
## regenerate module HP up to their tier cap, and the base only takes damage
## from minions that actually reached it.
static func simulate_grid_conquest(
	attacker_fleet: FleetSnapshot,
	attacker_workers: int,
	defender_grid: Dictionary,
	config: ConquestConfig = null,
	conquest_seed: int = 42
) -> CombatReplay:
	var cfg: ConquestConfig = config if config != null else DEFAULT_CONQUEST_CONFIG
	var rng := RandomNumberGenerator.new()
	rng.seed = conquest_seed

	var minions: Array[AssaultMinionDefinition] = []
	var minion_ships: Array[ShipAssembly] = []
	var spread_index := 0
	for _i in range(maxi(attacker_workers, 0)):
		var worker_minion := AssaultMinionDefinition.new()
		worker_minion.hp = cfg.minion_hp
		worker_minion.max_hp = cfg.minion_hp
		worker_minion.dps = cfg.minion_dps
		worker_minion.speed = cfg.minion_speed
		worker_minion.pos = _spawn_pos(spread_index)
		worker_minion.id = StringName("m_%d" % minions.size())
		spread_index += 1
		minions.append(worker_minion)
	if attacker_fleet != null:
		for ship in attacker_fleet.ships:
			var ship_minion := AssaultMinionDefinition.from_ship(ship, null, cfg.minion_hp, cfg.minion_dps, cfg.minion_speed, cfg)
			ship_minion.id = StringName("m_%d" % minions.size())
			ship_minion.pos = _spawn_pos(spread_index)
			spread_index += 1
			minions.append(ship_minion)
			minion_ships.append(ship.copy())

	var attacker_hp := 0.0
	var attacker_dps := 0.0
	for minion in minions:
		attacker_hp += minion.current_hp()
		attacker_dps += minion.dps
	var attacker_initial_hp: float = attacker_hp
	var attacker_initial_dps: float = attacker_dps

	var base_hp := maxf(1.0, cfg.base_total_hp)
	var tower_count := 0
	if defender_grid != null and not defender_grid.is_empty():
		base_hp = maxf(1.0, float(defender_grid.get("base_hp", cfg.base_total_hp)))
		for building in defender_grid.get("buildings", []):
			if building is Dictionary and building.get("building_id", &"") != &"":
				tower_count += 1
	var tower_dps := float(tower_count) * cfg.tower_dps
	var base_initial_hp: float = base_hp

	var time := 0.0
	var tick := cfg.tick
	var max_time := cfg.max_time * float(cfg.max_waves)
	var base_hp_history: Array[float] = [base_hp]
	var wave_events: Array[BattleEvent] = []
	var grid_snapshots: Array[Dictionary] = []
	var wave_index := 0
	var base_x := 0.0

	while wave_index < cfg.max_waves and time < max_time and base_hp > 0.0 and _alive_minions(minions).size() > 0:
		wave_events.append(BattleEvent.create(time, BattleEvent.TYPE_WAVE_START, &"wave", &"", float(wave_index)))
		var wave_elapsed := 0.0
		var wave_dmg_to_base := 0.0
		while wave_elapsed < cfg.wave_interval and base_hp > 0.0 and _alive_minions(minions).size() > 0:
			time += tick
			wave_elapsed += tick
			# Minions march toward the base; destroyed drives immobilize them.
			for minion in minions:
				if not minion.is_alive() or minion.speed <= 0.0:
					continue
				minion.pos.x = minf(minion.pos.x + minion.speed * tick, base_x)
				if minion.pos.x >= base_x - 1.0:
					wave_dmg_to_base += minion.dps * tick
			base_hp = maxf(0.0, base_hp - wave_dmg_to_base * rng.randf_range(cfg.damage_variance_min, cfg.damage_variance_max))
			# Towers engage random minions and destroy individual modules.
			for _tower_index in tower_count:
				var targets := _alive_minions(minions)
				if targets.is_empty():
					break
				var target: AssaultMinionDefinition = targets[rng.randi_range(0, targets.size() - 1)]
				var dmg: float = cfg.tower_dps * tick * rng.randf_range(cfg.damage_variance_min, cfg.damage_variance_max)
				wave_events.append(BattleEvent.create(time, BattleEvent.TYPE_TOWER_FIRE, &"tower", &"", dmg, Vector2(base_x - 20.0, 0.0), target.pos))
				var applied := target.take_damage(dmg, rng)
				if applied > 0.0:
					# L2/L3 convention: TYPE_MODULE_HIT carries the hit unit in target_id.
					wave_events.append(BattleEvent.create(time + 0.05, BattleEvent.TYPE_MODULE_HIT, &"tower", target.id, applied, target.pos, target.pos))
					for destroyed_mod in target.consume_destroyed_modules():
						wave_events.append(BattleEvent.create_module(
							time + 0.05,
							BattleEvent.TYPE_MODULE_DESTROYED,
							target.id,
							&"",
							0.0,
							destroyed_mod.get("part_id", &"") as StringName,
							destroyed_mod.get("slot_type", &"") as StringName,
							destroyed_mod.get("trait", &"") as StringName,
							target.pos,
							target.pos
						))
			# Repair drones regenerate module HP (capped, never full).
			for minion in minions:
				if not minion.is_alive():
					continue
				var healed: float = minion.repair(tick, rng)
				if healed > 0.0:
					wave_events.append(BattleEvent.create(time + 0.1, BattleEvent.TYPE_REPAIR, &"", minion.id, healed, minion.pos, minion.pos))
			base_hp_history.append(base_hp)
		wave_events.append(BattleEvent.create(time, BattleEvent.TYPE_BASE_DAMAGE, &"wave", &"base", wave_dmg_to_base))
		wave_events.append(BattleEvent.create(time, BattleEvent.TYPE_WAVE_CLEARED, &"wave", &"", float(wave_index)))
		grid_snapshots.append({"wave": wave_index, "base_hp": base_hp, "attacker_hp": _total_minion_hp(minions)})
		wave_index += 1

	var replay := CombatReplay.new_conquest(conquest_seed)
	var survivors := _alive_minions(minions)
	replay.captured = base_hp <= 0.0 and survivors.size() > 0
	replay.surviving_attackers = survivors.size() if replay.captured else 0
	replay.surviving_minion_ids = []
	for survivor in survivors:
		replay.surviving_minion_ids.append(survivor.id)
	replay.surviving_garrison = tower_count
	replay.duration = time
	replay.attacker_initial_hp = attacker_initial_hp
	replay.attacker_initial_dps = attacker_initial_dps
	replay.defender_initial_hp = base_initial_hp
	replay.defender_initial_dps = tower_dps
	replay.tower_count = tower_count
	replay.perimeter_slots = tower_count
	replay.base_hp_history = base_hp_history
	replay.wave_events = wave_events
	replay.grid_snapshots = grid_snapshots
	replay.minion_ships = minion_ships
	return replay


static func _spawn_pos(spread_index: int) -> Vector2:
	return Vector2(-220.0, float(spread_index % 7 - 3) * 30.0)


static func _alive_minions(minions: Array[AssaultMinionDefinition]) -> Array[AssaultMinionDefinition]:
	var result: Array[AssaultMinionDefinition] = []
	for minion in minions:
		if minion != null and minion.is_alive():
			result.append(minion)
	return result


static func _total_minion_hp(minions: Array[AssaultMinionDefinition]) -> float:
	var total := 0.0
	for minion in minions:
		if minion != null and minion.is_alive():
			total += minion.current_hp()
	return total