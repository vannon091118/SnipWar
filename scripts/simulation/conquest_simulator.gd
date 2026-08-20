@tool
class_name ConquestSimulator
extends RefCounted

static func simulate_conquest(attack_fleet: FleetSnapshot, attacker_workers: int, defending_workers: int, defense_rating: int, perimeter_slots: int, defense_range: float, conquest_seed: int = 42) -> Dictionary:
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

	var time := 0.0
	var tick := 0.5
	var max_time := 20.0

	while time < max_time and attacker_hp > 0.0 and defender_hp > 0.0:
		time += tick
		var dmg_to_def: float = attacker_dps * tick * rng.randf_range(0.9, 1.1)
		var dmg_to_att: float = defender_dps * tick * rng.randf_range(0.9, 1.1)

		defender_hp = maxf(0.0, defender_hp - dmg_to_def)
		attacker_hp = maxf(0.0, attacker_hp - dmg_to_att)

	var captured: bool = defender_hp <= 0.0 and attacker_hp > 0.0
	var surviving_attackers := int(ceil(attacker_hp / 10.0))
	var surviving_garrison := int(ceil(defender_hp / 15.0))

	return {
		"captured": captured,
		"surviving_attackers": surviving_attackers if captured else 0,
		"surviving_garrison": surviving_garrison if not captured else 0,
		"duration": time,
		"attacker_workers": attacker_workers,
		"defending_workers": defending_workers,
		"defense_rating": defense_rating,
		"perimeter_slots": perimeter_slots,
		"tower_count": tower_count,
		"defense_range": defense_range,
		"conquest_seed": conquest_seed,
	}
