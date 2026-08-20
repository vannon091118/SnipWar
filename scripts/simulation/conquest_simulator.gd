@tool
class_name ConquestSimulator
extends RefCounted

static func simulate_conquest(attack_fleet: FleetSnapshot, attacker_workers: int, defending_workers: int, defense_rating: int, perimeter_slots: int, defense_range: float, conquest_seed: int = 42) -> CombatReplay:
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
	var tick := 0.5
	var max_time := 20.0

	while time < max_time and attacker_hp > 0.0 and defender_hp > 0.0:
		time += tick
		var dmg_to_def: float = attacker_dps * tick * rng.randf_range(0.9, 1.1)
		var dmg_to_att: float = defender_dps * tick * rng.randf_range(0.9, 1.1)

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
