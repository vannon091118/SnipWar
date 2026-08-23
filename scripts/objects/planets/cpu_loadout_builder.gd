class_name CpuLoadoutBuilder
extends RefCounted

## Deterministic CPU loadout construction for the module-based ship model.
##
## Builds hull-aware loadouts from the researched techs of the CPU faction
## plus a seeded RNG, so the opponent visibly uses the module meta instead of
## fixed presets: twin drives on drive-rich hulls (hull_t2/t3), weapons only
## for military roles, and drone modules (repair/combat/booster) once the
## drone tech branches are researched. Every part is tech-gated; with no
## research the builder returns an empty loadout (the CPU must research first).

const DRONE_REPAIR_PARTS: Array[StringName] = [&"repair_drone_t1", &"repair_drone_t2", &"repair_drone_t3"]
const DRONE_COMBAT_PARTS: Array[StringName] = [&"combat_drone_t1", &"combat_drone_t2"]
const DRONE_BOOSTER_PARTS: Array[StringName] = [&"drone_booster_t1", &"drone_booster_t2"]
const LEGACY_MODULES: Array[StringName] = [&"module_reactor", &"module_reinforced", &"module_sensor_array"]

## Builds one loadout as {hull_id, drive_id, weapon_id, shield_id, scanner_id,
## module_ids}. Returns an empty Dictionary when nothing is researchable.
static func build_loadout(catalog: ShipPartCatalog, researched_techs: Array, rng: RandomNumberGenerator, role: StringName) -> Dictionary:
	if catalog == null:
		return {}
	var hull: ShipPartDefinition = _pick_hull(catalog, researched_techs, rng, role)
	if hull == null:
		return {}
	var layout: Dictionary = catalog.slot_layout_for(hull)
	var drive: ShipPartDefinition = _best_part(catalog, ShipPartDefinition.SLOT_DRIVE, researched_techs, rng)
	var shield: ShipPartDefinition = _best_part(catalog, ShipPartDefinition.SLOT_SHIELD, researched_techs, rng)
	var scanner: ShipPartDefinition = _best_part(catalog, ShipPartDefinition.SLOT_SCANNER, researched_techs, rng)
	if drive == null or shield == null or scanner == null:
		return {}
	var military: bool = role == GameState.MISSION_MILITARY
	var weapon: ShipPartDefinition = _best_part(catalog, ShipPartDefinition.SLOT_WEAPON, researched_techs, rng)

	var module_ids: Array[StringName] = []
	# Twin drives: fill every drive slot the hull schema offers.
	var drive_cap := int(layout.get(ShipPartDefinition.SLOT_DRIVE, 1))
	for _i in range(maxi(drive_cap - 1, 0)):
		module_ids.append(drive.id)
	# Weapons in extra weapon slots only for military loadouts.
	if weapon != null and military:
		var weapon_cap := int(layout.get(ShipPartDefinition.SLOT_WEAPON, 1))
		for _i in range(maxi(weapon_cap - 1, 0)):
			module_ids.append(weapon.id)
	# Utility slots: drones (role-aware) before legacy modules.
	var drone_parts: Array[StringName] = []
	if military:
		drone_parts.append_array(_researched_parts(catalog, DRONE_COMBAT_PARTS, researched_techs))
		var boosters := _researched_parts(catalog, DRONE_BOOSTER_PARTS, researched_techs)
		if not boosters.is_empty():
			drone_parts.append(boosters.back())
	else:
		drone_parts.append_array(_researched_parts(catalog, DRONE_REPAIR_PARTS, researched_techs))
	drone_parts.append_array(_researched_parts(catalog, LEGACY_MODULES, researched_techs))
	var utility_cap := int(layout.get(ShipPartDefinition.SLOT_UTILITY, 0))
	var slot_index := 0
	while module_ids.size() < utility_cap and slot_index < drone_parts.size():
		module_ids.append(drone_parts[slot_index])
		slot_index += 1

	return {
		"hull_id": hull.id,
		"drive_id": drive.id,
		"weapon_id": weapon.id if weapon != null and military else &"",
		"shield_id": shield.id,
		"scanner_id": scanner.id,
		"module_ids": module_ids,
	}


## Prefers drive-rich hulls for military roles (survivability), the most
## advanced hull otherwise; ties are broken by the seeded RNG.
static func _pick_hull(catalog: ShipPartCatalog, researched_techs: Array, rng: RandomNumberGenerator, role: StringName) -> ShipPartDefinition:
	var candidates: Array[ShipPartDefinition] = []
	for part in catalog.for_slot(ShipPartDefinition.SLOT_HULL):
		if part == null or not _is_researched(part, researched_techs):
			continue
		candidates.append(part)
	if candidates.is_empty():
		return null
	var military: bool = role == GameState.MISSION_MILITARY
	var best: ShipPartDefinition = candidates[0]
	var best_score := -1.0
	for candidate in candidates:
		var layout: Dictionary = catalog.slot_layout_for(candidate)
		var drive_cap := int(layout.get(ShipPartDefinition.SLOT_DRIVE, 1))
		var utility_cap := int(layout.get(ShipPartDefinition.SLOT_UTILITY, 0))
		var score := float(candidate.tier) * 10.0
		if military:
			score += float(drive_cap) * 4.0 + float(utility_cap) * 0.5
		if score > best_score:
			best = candidate
			best_score = score
		elif is_equal_approx(score, best_score) and rng != null and rng.randf() < 0.5:
			best = candidate
	return best


## Highest-tier researched part of a slot; ties are broken by the RNG.
static func _best_part(catalog: ShipPartCatalog, slot_type: StringName, researched_techs: Array, rng: RandomNumberGenerator) -> ShipPartDefinition:
	var best: ShipPartDefinition = null
	var best_tier := -1
	for part in catalog.for_slot(slot_type):
		if part == null or not _is_researched(part, researched_techs):
			continue
		if part.tier > best_tier:
			best = part
			best_tier = part.tier
		elif part.tier == best_tier and rng != null and rng.randf() < 0.5:
			best = part
	return best


static func _researched_parts(catalog: ShipPartCatalog, part_ids: Array[StringName], researched_techs: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for part_id in part_ids:
		var part: ShipPartDefinition = catalog.resolve(part_id) if catalog != null else null
		if _is_researched(part, researched_techs):
			result.append(part_id)
	return result


static func _is_researched(part: ShipPartDefinition, researched_techs: Array) -> bool:
	if part == null:
		return false
	if String(part.required_tech_id).is_empty():
		return true
	return researched_techs.has(part.required_tech_id)
