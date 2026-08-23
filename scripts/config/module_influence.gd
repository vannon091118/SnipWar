class_name ModuleInfluence
extends RefCounted

## Mathematical foundation of the module-based ship damage model.
##
## Every mounted module carries an "influence" on the ship's HP state. The
## influence of a module type scales sub-linearly with the number of mounted
## instances so redundancy has a price: one drive has 20 % influence, two
## drives share ~30 % total (≈15.2 % each), three share ~38 % (≈12.6 % each).
##
## Formula:  influence_total(weight, n) = weight * n^EXPONENT
## The exponent 0.6 reproduces the intended fair curve (1 → 20 %, 2 → ~15 %
## per instance) while keeping the total influence of a type growing with
## diminishing returns.

const INFLUENCE_EXPONENT := 0.6

const INFLUENCE_HULL := 0.30
const INFLUENCE_DRIVE := 0.20
const INFLUENCE_WEAPON := 0.20
const INFLUENCE_SHIELD := 0.15
const INFLUENCE_SCANNER := 0.10
const INFLUENCE_UTILITY := 0.05

const TRAIT_SPEED := &"speed"
const TRAIT_DPS := &"dps"
const TRAIT_RANGE := &"range"
const TRAIT_ARMOR := &"armor"
const TRAIT_INTEGRITY := &"integrity"
const TRAIT_REPAIR := &"repair"

## Repair drone tiers: module HP regenerates in tower defense but never past
## these caps (T1 = "functional only", T2 = 50 %, T3 = 60 %).
const REPAIR_CAP_T1 := 0.35
const REPAIR_CAP_T2 := 0.5
const REPAIR_CAP_T3 := 0.6
## Recharge pacing: T2 charges slowly (high charge time), T3 medium.
const REPAIR_RATE_T1 := 2.0
const REPAIR_RATE_T2 := 1.2
const REPAIR_RATE_T3 := 2.8

## Booster modules amplify every mounted drone module effect (2 levels).
const BOOSTER_BONUS_T1 := 0.25
const BOOSTER_BONUS_T2 := 0.5

const REPAIR_DRONE_T1: StringName = &"repair_drone_t1"
const REPAIR_DRONE_T2: StringName = &"repair_drone_t2"
const REPAIR_DRONE_T3: StringName = &"repair_drone_t3"
const BOOSTER_T1: StringName = &"drone_booster_t1"
const BOOSTER_T2: StringName = &"drone_booster_t2"


## Base influence weight of a slot type before count scaling.
static func base_weight(slot_type: StringName) -> float:
	match slot_type:
		ShipPartDefinition.SLOT_HULL:
			return INFLUENCE_HULL
		ShipPartDefinition.SLOT_DRIVE:
			return INFLUENCE_DRIVE
		ShipPartDefinition.SLOT_WEAPON:
			return INFLUENCE_WEAPON
		ShipPartDefinition.SLOT_SHIELD:
			return INFLUENCE_SHIELD
		ShipPartDefinition.SLOT_SCANNER:
			return INFLUENCE_SCANNER
	return INFLUENCE_UTILITY


## The primary ship stat a destroyed module of this slot type degrades.
static func influence_trait(slot_type: StringName) -> StringName:
	match slot_type:
		ShipPartDefinition.SLOT_HULL:
			return TRAIT_INTEGRITY
		ShipPartDefinition.SLOT_DRIVE:
			return TRAIT_SPEED
		ShipPartDefinition.SLOT_WEAPON:
			return TRAIT_DPS
		ShipPartDefinition.SLOT_SHIELD:
			return TRAIT_ARMOR
		ShipPartDefinition.SLOT_SCANNER:
			return TRAIT_RANGE
		_:
			return TRAIT_REPAIR if slot_type == REPAIR_DRONE_T1 or slot_type == REPAIR_DRONE_T2 or slot_type == REPAIR_DRONE_T3 else TRAIT_DPS


## Influence trait of a concrete mounted part (utility modules derive their
## trait from the stat their trait definition primarily boosts).
static func trait_for_part(part: ShipPartDefinition) -> StringName:
	if part == null:
		return TRAIT_ARMOR
	if not String(part.influence_trait).is_empty():
		return part.influence_trait
	if part.slot_type != ShipPartDefinition.SLOT_UTILITY:
		return influence_trait(part.slot_type)
	var part_trait: TraitDefinition = part.trait_definition
	if part_trait == null:
		return TRAIT_ARMOR
	if part_trait.dps_bonus > 0.0:
		return TRAIT_DPS
	if part_trait.range_bonus > 0.0 or part_trait.attack_range_bonus > 0.0:
		return TRAIT_RANGE
	if not is_equal_approx(part_trait.transfer_speed_multiplier, 1.0):
		return TRAIT_SPEED
	if part_trait.hull_hp_bonus > 0:
		return TRAIT_ARMOR
	return TRAIT_ARMOR


## Total influence of `count` identical modules of one type.
static func type_influence(weight: float, count: int) -> float:
	if count <= 0:
		return 0.0
	return weight * pow(float(count), INFLUENCE_EXPONENT)


## Per-instance influence when `count` identical modules share one type.
static func instance_influence(weight: float, count: int) -> float:
	if count <= 0:
		return 0.0
	return type_influence(weight, count) / float(count)


## Groups mounted modules into influence types: core combat slots (drive,
## weapon, shield) scale together across copies, utility modules scale per
## identical part id. Returns a Dictionary keyed by type key -> count.
static func aggregate_type_counts(module_entries: Array) -> Dictionary:
	var counts: Dictionary = {}
	for entry in module_entries:
		var slot_type: StringName = entry.get("slot_type", &"") as StringName
		var part_id: StringName = entry.get("part_id", &"") as StringName
		var key: StringName = slot_type
		if slot_type == ShipPartDefinition.SLOT_UTILITY or ShipPartDefinition.is_utility_slot(slot_type):
			key = part_id
		counts[key] = int(counts.get(key, 0)) + 1
	return counts


## Distributes `total_hp` across the given module entries (each entry must
## carry part_id + slot_type) according to their normalized influences. Each
## entry receives "weight" (per-instance influence) and "hp"/"max_hp".
static func distribute_hp(module_entries: Array, total_hp: float) -> void:
	if module_entries.is_empty():
		return
	var counts := aggregate_type_counts(module_entries)
	var type_influences: Dictionary = {}
	var total_influence := 0.0
	for key in counts:
		var entry: Dictionary = _first_entry_of_type(module_entries, key as StringName)
		var weight: float = base_weight(entry.get("slot_type", &"") as StringName)
		var type_inf: float = type_influence(weight, int(counts[key]))
		type_influences[key] = type_inf
		total_influence += type_inf
	if total_influence <= 0.0:
		return
	for entry in module_entries:
		var slot_type: StringName = entry.get("slot_type", &"") as StringName
		var part_id: StringName = entry.get("part_id", &"") as StringName
		var key: StringName = slot_type
		if ShipPartDefinition.is_utility_slot(slot_type):
			key = part_id
		var per_instance: float = float(type_influences.get(key, 0.0)) / float(counts.get(key, 1))
		var module_hp: float = total_hp * per_instance / total_influence
		entry["weight"] = per_instance
		entry["hp"] = module_hp
		entry["max_hp"] = module_hp


static func _first_entry_of_type(module_entries: Array, type_key: StringName) -> Dictionary:
	for entry in module_entries:
		var slot_type: StringName = entry.get("slot_type", &"") as StringName
		var part_id: StringName = entry.get("part_id", &"") as StringName
		var key: StringName = slot_type
		if ShipPartDefinition.is_utility_slot(slot_type):
			key = part_id
		if key == type_key:
			return entry
	return {}


## True for parts that belong to the drone module family (amplified by boosters).
static func is_drone_part(part: ShipPartDefinition) -> bool:
	if part == null:
		return false
	return part.module_role == "drone"


## Booster multiplier applied to all mounted drone module effects. Sums the
## tier bonuses of every mounted booster module (T1 +25 %, T2 +50 % each).
static func booster_multiplier(parts: Array) -> float:
	var multiplier := 1.0
	for part in parts:
		if part == null or part.module_role != "booster":
			continue
		if part.id == BOOSTER_T1:
			multiplier += BOOSTER_BONUS_T1
		elif part.id == BOOSTER_T2:
			multiplier += BOOSTER_BONUS_T2
	return multiplier


## Resolves the tower-defense repair profile of a ship: cap from the highest
## mounted repair drone tier, rate from the sum of all mounted repair drones
## (amplified by boosters). Returns {cap: float, rate: float}.
static func repair_profile(parts: Array, cfg: ConquestConfig = null) -> Dictionary:
	var cap := 0.0
	var rate := 0.0
	for part in parts:
		if part == null:
			continue
		match part.id:
			REPAIR_DRONE_T1:
				cap = maxf(cap, REPAIR_CAP_T1 if cfg == null else cfg.repair_cap_t1)
				rate += REPAIR_RATE_T1 if cfg == null else cfg.repair_rate_t1
			REPAIR_DRONE_T2:
				cap = maxf(cap, REPAIR_CAP_T2 if cfg == null else cfg.repair_cap_t2)
				rate += REPAIR_RATE_T2 if cfg == null else cfg.repair_rate_t2
			REPAIR_DRONE_T3:
				cap = maxf(cap, REPAIR_CAP_T3 if cfg == null else cfg.repair_cap_t3)
				rate += REPAIR_RATE_T3 if cfg == null else cfg.repair_rate_t3
	if cap <= 0.0 or rate <= 0.0:
		return {"cap": 0.0, "rate": 0.0}
	rate *= booster_multiplier(parts)
	return {"cap": cap, "rate": rate}


## Human-readable influence readback for tooltips, e.g. "20 %".
static func percent(weight: float) -> String:
	return "%d %%" % int(round(weight * 100.0))
