@tool
class_name FleetSnapshot
extends Resource

const DEFAULT_SHIP_PART_CATALOG: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")

@export var fleet_id: StringName = &""
@export var faction: StringName = &"a"
@export var source_planet_id: StringName = &""
@export var destination_planet_id: StringName = &""
@export var ships: Array[Dictionary] = []

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
		var hull_id: StringName = ship.get("hull", &"") as StringName
		var scanner_id: StringName = ship.get("scanner", &"") as StringName
		var modules: Array = ship.get("modules", [])

		var ship_hp := 50.0
		var ship_dps := 10.0
		var ship_range := 100.0
		var ship_speed := 80.0

		if cat != null:
			var hull_part := cat.resolve(hull_id)
			if hull_part != null:
				ship_hp += float(hull_part.tier * 30)
				if hull_part.trait_definition != null:
					ship_hp += float(hull_part.trait_definition.hull_hp_bonus)
					ship_dps += hull_part.trait_definition.dps_bonus
					ship_speed *= hull_part.trait_definition.transfer_speed_multiplier

			var scanner_part := cat.resolve(scanner_id)
			if scanner_part != null:
				ship_range += float(scanner_part.tier * 40)
				if scanner_part.trait_definition != null:
					ship_range += scanner_part.trait_definition.range_bonus

			for mod_val in modules:
				var mod_part := cat.resolve(mod_val as StringName)
				if mod_part != null:
					ship_dps += float(mod_part.tier * 5)
					if mod_part.trait_definition != null:
						ship_dps += mod_part.trait_definition.dps_bonus
						ship_hp += float(mod_part.trait_definition.hull_hp_bonus)

		total_hull_hp += ship_hp
		total_dps += ship_dps
		if ship_range > max_range:
			max_range = ship_range
		if ship_speed < min_speed:
			min_speed = ship_speed

	effective_range = max_range
	speed = min_speed if ships.size() > 0 else 80.0

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(fleet_id).is_empty():
		errors.append("fleet_id is empty")
	if String(faction).is_empty():
		errors.append("faction is empty")
	return errors
