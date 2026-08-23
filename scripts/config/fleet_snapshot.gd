@tool
class_name FleetSnapshot
extends Resource

const DEFAULT_SHIP_PART_CATALOG: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")

## Base combat constants shared by stat calculation and the module-damage
## battle simulator so both sides of the model stay in lockstep.
const BASE_HULL_HP := 50.0
const BASE_DPS := 10.0
const BASE_RANGE := 100.0
const BASE_SPEED := 80.0

@export var fleet_id: StringName = &""
@export var faction: StringName = &"a"
@export var source_planet_id: StringName = &""
@export var destination_planet_id: StringName = &""
@export var mission_role: StringName = &""
@export var ships: Array[ShipAssembly] = []

@export_group("Aggregated Stats")
@export var total_hull_hp: float = 0.0
@export var total_dps: float = 0.0
@export var effective_range: float = 150.0
@export var speed: float = 80.0

func calculate_stats(catalog: ShipPartCatalog = null) -> void:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	total_hull_hp = 0.0
	total_dps = 0.0
	var min_speed: float = 120.0
	var max_range: float = 100.0

	for ship in ships:
		var ship_stats: Dictionary = calculate_ship_stats(ship, cat)
		total_hull_hp += float(ship_stats.get("hp", 50.0))
		total_dps += float(ship_stats.get("dps", 10.0))
		var ship_range: float = float(ship_stats.get("range", 100.0))
		var ship_speed: float = float(ship_stats.get("speed", 80.0))
		if ship_range > max_range:
			max_range = ship_range
		if ship_speed < min_speed:
			min_speed = ship_speed

	effective_range = max_range
	speed = min_speed if ships.size() > 0 else 80.0

## Resolves one assembled ship's complete stat profile. Battle and conquest
## simulators consume this same result instead of indexing loadout dictionaries.
##
## Returns hp/dps/range/speed (aggregates) plus "modules": an Array of per-module
## Dictionaries used by the module-based damage model:
## {part_id, slot_type, trait, weight, hp, max_hp, stat: {dps, range, speed_mult,
## armor, integrity}} and "booster_multiplier" for drone module amplification.
static func calculate_ship_stats(ship: ShipAssembly, catalog: ShipPartCatalog = null) -> Dictionary:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	var ship_hp: float = BASE_HULL_HP
	var ship_dps: float = BASE_DPS
	var ship_range: float = BASE_RANGE
	var ship_speed_mult := 1.0
	if ship == null or cat == null:
		var fallback: Array[Dictionary] = [{
			"part_id": &"hull",
			"slot_type": ShipPartDefinition.SLOT_HULL,
			"trait": ModuleInfluence.TRAIT_INTEGRITY,
			"weight": 1.0,
			"hp": ship_hp,
			"max_hp": ship_hp,
			"stat": {"dps": 0.0, "range": 0.0, "speed_mult": 1.0, "armor": 0.0, "integrity": ship_hp},
		}]
		return {"hp": ship_hp, "dps": ship_dps, "range": ship_range, "speed": BASE_SPEED, "modules": fallback, "booster_multiplier": 1.0}

	# --- Per-module stat payloads -------------------------------------------
	# Each payload lists the exact stat a module contributes while alive. The
	# battle simulator recomputes aggregates from alive modules only, so a
	# destroyed module immediately degrades its governed stat.
	var module_entries: Array[Dictionary] = []

	var hull_part: ShipPartDefinition = cat.resolve(ship.hull_id)
	var hull_variant: ShipComponentVariant = cat.resolve_variant(hull_part, ship.hull_variant_id)
	var hull_trait: TraitDefinition = cat.combined_trait(hull_part, hull_variant)
	var hull_integrity := 0.0
	if hull_part != null:
		hull_integrity += float(hull_part.tier * 30)
		if hull_trait != null:
			hull_integrity += float(hull_trait.hull_hp_bonus)
			ship_dps += hull_trait.dps_bonus
			ship_speed_mult *= hull_trait.transfer_speed_multiplier
	ship_hp += hull_integrity
	if hull_part != null:
		module_entries.append(_module_entry(hull_part, ShipPartDefinition.SLOT_HULL, {"dps": 0.0, "range": 0.0, "speed_mult": 1.0, "armor": 0.0, "integrity": hull_integrity}))

	var drive_part: ShipPartDefinition = cat.resolve(ship.drive_id)
	var drive_variant: ShipComponentVariant = cat.resolve_variant(drive_part, ship.drive_variant_id)
	var drive_trait: TraitDefinition = cat.combined_trait(drive_part, drive_variant)
	var drive_mult := 1.0
	if drive_part != null:
		if drive_trait != null:
			drive_mult = drive_trait.transfer_speed_multiplier
		ship_speed_mult *= drive_mult
		module_entries.append(_module_entry(drive_part, ShipPartDefinition.SLOT_DRIVE, {"dps": 0.0, "range": 0.0, "speed_mult": drive_mult, "armor": 0.0, "integrity": 0.0}))

	var weapon_part: ShipPartDefinition = cat.resolve(ship.weapon_id)
	var weapon_variant: ShipComponentVariant = cat.resolve_variant(weapon_part, ship.weapon_variant_id)
	var weapon_trait: TraitDefinition = cat.combined_trait(weapon_part, weapon_variant)
	var weapon_dps := 0.0
	var weapon_range := 0.0
	if weapon_part != null:
		weapon_dps += float(weapon_part.tier * 5)
		if weapon_trait != null:
			weapon_dps += weapon_trait.dps_bonus
			weapon_range += weapon_trait.attack_range_bonus
	ship_dps += weapon_dps
	ship_range += weapon_range
	if weapon_part != null:
		module_entries.append(_module_entry(weapon_part, ShipPartDefinition.SLOT_WEAPON, {"dps": weapon_dps, "range": weapon_range, "speed_mult": 1.0, "armor": 0.0, "integrity": 0.0}))

	var shield_part: ShipPartDefinition = cat.resolve(ship.shield_id)
	var shield_variant: ShipComponentVariant = cat.resolve_variant(shield_part, ship.shield_variant_id)
	var shield_trait: TraitDefinition = cat.combined_trait(shield_part, shield_variant)
	var shield_armor := 0.0
	if shield_part != null:
		shield_armor += float(shield_part.tier * 20)
		if shield_trait != null:
			shield_armor += float(shield_trait.hull_hp_bonus)
		ship_hp += shield_armor
		module_entries.append(_module_entry(shield_part, ShipPartDefinition.SLOT_SHIELD, {"dps": 0.0, "range": 0.0, "speed_mult": 1.0, "armor": shield_armor, "integrity": 0.0}))

	var scanner_part: ShipPartDefinition = cat.resolve(ship.scanner_id)
	var scanner_variant: ShipComponentVariant = cat.resolve_variant(scanner_part, ship.scanner_variant_id)
	var scanner_trait: TraitDefinition = cat.combined_trait(scanner_part, scanner_variant)
	var scanner_range := 0.0
	if scanner_part != null:
		scanner_range += float(scanner_part.tier * 40)
		if scanner_trait != null:
			scanner_range += scanner_trait.range_bonus
		ship_range += scanner_range
		module_entries.append(_module_entry(scanner_part, ShipPartDefinition.SLOT_SCANNER, {"dps": 0.0, "range": scanner_range, "speed_mult": 1.0, "armor": 0.0, "integrity": 0.0}))

	# Utility modules (legacy module_ids + dynamically mounted extra core parts)
	var all_module_ids: Array[StringName] = []
	all_module_ids.append_array(ship.module_ids)
	for mod_index in range(all_module_ids.size()):
		var mod_part: ShipPartDefinition = cat.resolve(all_module_ids[mod_index])
		var mod_variant: ShipComponentVariant = cat.resolve_variant(mod_part, ship.variant_id_for(ShipPartDefinition.SLOT_UTILITY, mod_index))
		var mod_trait: TraitDefinition = cat.combined_trait(mod_part, mod_variant)
		var mod_dps := 0.0
		var mod_range := 0.0
		var mod_armor := 0.0
		var mod_speed_mult := 1.0
		if mod_part != null:
			mod_dps += float(mod_part.tier * 5)
			if mod_trait != null:
				mod_dps += mod_trait.dps_bonus
				mod_range += mod_trait.range_bonus
				mod_armor += float(mod_trait.hull_hp_bonus)
				mod_speed_mult *= mod_trait.transfer_speed_multiplier
		ship_dps += mod_dps
		ship_range += mod_range
		ship_hp += mod_armor
		ship_speed_mult *= mod_speed_mult
		var slot_type: StringName = mod_part.slot_type if mod_part != null else ShipPartDefinition.SLOT_UTILITY
		module_entries.append(_module_entry(mod_part, slot_type, {"dps": mod_dps, "range": mod_range, "speed_mult": mod_speed_mult, "armor": mod_armor, "integrity": 0.0}))

	# --- Drone booster amplification ----------------------------------------
	# Boosters strengthen every mounted drone module; the multiplier is applied
	# to the stat payloads and returned for repair-rate amplification.
	var booster_multiplier := ModuleInfluence.booster_multiplier(_parts_of(module_entries, cat))
	if not is_equal_approx(booster_multiplier, 1.0):
		for entry in module_entries:
			var part: ShipPartDefinition = cat.resolve(entry.get("part_id", &"") as StringName)
			if not ModuleInfluence.is_drone_part(part):
				continue
			var stat: Dictionary = entry["stat"] as Dictionary
			stat["dps"] = float(stat.get("dps", 0.0)) * booster_multiplier
			stat["range"] = float(stat.get("range", 0.0)) * booster_multiplier
			stat["armor"] = float(stat.get("armor", 0.0)) * booster_multiplier

	# --- Influence-weighted HP distribution --------------------------------
	# Each module receives its fair share of the total HP pool; the pool is
	# the sum of all module HP, so every destroyed module shrinks the ship.
	var pool: float = ship_hp
	ModuleInfluence.distribute_hp(module_entries, pool)

	return {
		"hp": pool,
		"dps": ship_dps,
		"range": ship_range,
		"speed": BASE_SPEED * ship_speed_mult,
		"modules": module_entries,
		"booster_multiplier": booster_multiplier,
	}


static func _module_entry(part: ShipPartDefinition, slot_type: StringName, stat: Dictionary) -> Dictionary:
	return {
		"part_id": part.id if part != null else &"",
		"slot_type": slot_type,
		"trait": ModuleInfluence.trait_for_part(part),
		"weight": 0.0,
		"hp": 0.0,
		"max_hp": 0.0,
		"stat": stat.duplicate(),
	}


static func _parts_of(module_entries: Array, cat: ShipPartCatalog) -> Array[ShipPartDefinition]:
	var parts: Array[ShipPartDefinition] = []
	for entry in module_entries:
		var part: ShipPartDefinition = cat.resolve(entry.get("part_id", &"") as StringName)
		if part != null:
			parts.append(part)
	return parts

func transfer_speed_multiplier() -> float:
	return speed / 80.0 if ships.size() > 0 else 1.0

func copy() -> FleetSnapshot:
	return duplicate(true) as FleetSnapshot

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(fleet_id).is_empty():
		errors.append("fleet_id is empty")
	if String(faction).is_empty():
		errors.append("faction is empty")
	for ship in ships:
		if ship == null:
			errors.append("fleet contains a null ship assembly")
	return errors
