@tool
class_name FleetSnapshot
extends Resource

const DEFAULT_SHIP_PART_CATALOG: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")

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
static func calculate_ship_stats(ship: ShipAssembly, catalog: ShipPartCatalog = null) -> Dictionary:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	var ship_hp: float = 50.0
	var ship_dps: float = 10.0
	var ship_range: float = 100.0
	var ship_speed: float = 80.0
	if ship == null or cat == null:
		return {"hp": ship_hp, "dps": ship_dps, "range": ship_range, "speed": ship_speed}

	var hull_part: ShipPartDefinition = cat.resolve(ship.hull_id)
	var hull_variant: ShipComponentVariant = cat.resolve_variant(hull_part, ship.hull_variant_id)
	var hull_trait: TraitDefinition = cat.combined_trait(hull_part, hull_variant)
	if hull_part != null:
		ship_hp += float(hull_part.tier * 30)
		if hull_trait != null:
			ship_hp += float(hull_trait.hull_hp_bonus)
			ship_dps += hull_trait.dps_bonus
			ship_speed *= hull_trait.transfer_speed_multiplier

	var drive_part: ShipPartDefinition = cat.resolve(ship.drive_id)
	var drive_variant: ShipComponentVariant = cat.resolve_variant(drive_part, ship.drive_variant_id)
	var drive_trait: TraitDefinition = cat.combined_trait(drive_part, drive_variant)
	if drive_trait != null:
		ship_speed *= drive_trait.transfer_speed_multiplier

	var weapon_part: ShipPartDefinition = cat.resolve(ship.weapon_id)
	var weapon_variant: ShipComponentVariant = cat.resolve_variant(weapon_part, ship.weapon_variant_id)
	var weapon_trait: TraitDefinition = cat.combined_trait(weapon_part, weapon_variant)
	if weapon_part != null:
		ship_dps += float(weapon_part.tier * 5)
		if weapon_trait != null:
			ship_dps += weapon_trait.dps_bonus
			ship_range += weapon_trait.attack_range_bonus

	var shield_part: ShipPartDefinition = cat.resolve(ship.shield_id)
	var shield_variant: ShipComponentVariant = cat.resolve_variant(shield_part, ship.shield_variant_id)
	var shield_trait: TraitDefinition = cat.combined_trait(shield_part, shield_variant)
	if shield_part != null:
		ship_hp += float(shield_part.tier * 20)
		if shield_trait != null:
			ship_hp += float(shield_trait.hull_hp_bonus)

	var scanner_part: ShipPartDefinition = cat.resolve(ship.scanner_id)
	var scanner_variant: ShipComponentVariant = cat.resolve_variant(scanner_part, ship.scanner_variant_id)
	var scanner_trait: TraitDefinition = cat.combined_trait(scanner_part, scanner_variant)
	if scanner_part != null:
		ship_range += float(scanner_part.tier * 40)
		if scanner_trait != null:
			ship_range += scanner_trait.range_bonus

	for mod_index in range(ship.module_ids.size()):
		var mod_part: ShipPartDefinition = cat.resolve(ship.module_ids[mod_index])
		var mod_variant: ShipComponentVariant = cat.resolve_variant(mod_part, ship.variant_id_for(ShipPartDefinition.SLOT_UTILITY, mod_index))
		var mod_trait: TraitDefinition = cat.combined_trait(mod_part, mod_variant)
		if mod_part != null:
			ship_dps += float(mod_part.tier * 5)
			if mod_trait != null:
				ship_dps += mod_trait.dps_bonus
				ship_hp += float(mod_trait.hull_hp_bonus)

	return {"hp": ship_hp, "dps": ship_dps, "range": ship_range, "speed": ship_speed}

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
