@tool
class_name ShipPartCatalog
extends Resource

@export var parts: Array[ShipPartDefinition] = []
@export var blueprints: Array[ShipBlueprint] = []
@export_range(0, 8, 1) var max_module_slots: int = 2

func resolve(part_id: StringName) -> ShipPartDefinition:
	for part in parts:
		if part != null and part.id == part_id:
			return part
	return null

func resolve_blueprint(blueprint_id: StringName) -> ShipBlueprint:
	if String(blueprint_id).is_empty():
		return default_blueprint()
	for blueprint in blueprints:
		if blueprint != null and blueprint.id == blueprint_id:
			return blueprint
	return null

func default_blueprint() -> ShipBlueprint:
	return blueprints[0] if not blueprints.is_empty() else null

func for_slot(slot_type: StringName) -> Array[ShipPartDefinition]:
	var result: Array[ShipPartDefinition] = []
	for part in parts:
		if part == null:
			continue
		if slot_type == ShipPartDefinition.SLOT_UTILITY:
			if ShipPartDefinition.is_utility_slot(part.slot_type):
				result.append(part)
		elif part.slot_type == slot_type:
			result.append(part)
	return result

## Resolves the dynamic slot layout of a hull part. Hulls without an explicit
## slot_schema fall back to the legacy layout (1 drive, 1 weapon, 1 shield,
## 1 scanner, max_module_slots utility). Returns a Dictionary keyed by
## slot type StringName -> count.
func slot_layout_for(hull: ShipPartDefinition) -> Dictionary:
	var layout := {
		ShipPartDefinition.SLOT_DRIVE: 1,
		ShipPartDefinition.SLOT_WEAPON: 1,
		ShipPartDefinition.SLOT_SHIELD: 1,
		ShipPartDefinition.SLOT_SCANNER: 1,
		ShipPartDefinition.SLOT_UTILITY: max_module_slots,
	}
	if hull == null or hull.slot_schema.is_empty():
		return layout
	layout = {
		ShipPartDefinition.SLOT_DRIVE: 0,
		ShipPartDefinition.SLOT_WEAPON: 0,
		ShipPartDefinition.SLOT_SHIELD: 0,
		ShipPartDefinition.SLOT_SCANNER: 0,
		ShipPartDefinition.SLOT_UTILITY: 0,
	}
	for entry in hull.slot_schema:
		var entry_type: StringName = entry.get("type", &"") as StringName
		layout[entry_type] = int(entry.get("count", 0))
	return layout

## Total number of slots a hull offers (core + utility).
func slot_count_for(hull: ShipPartDefinition) -> int:
	var layout := slot_layout_for(hull)
	var total := 0
	for key in layout:
		total += int(layout[key])
	return total

func select_variant(part: ShipPartDefinition, blueprint: ShipBlueprint, instance_seed: int, available_tier: int = -1, salt: StringName = &"") -> ShipComponentVariant:
	if part == null or blueprint == null:
		return null
	return select_variant_for_seed(part, blueprint.seed_base, instance_seed, available_tier, salt)

func select_variant_for_seed(part: ShipPartDefinition, blueprint_seed: int, instance_seed: int, available_tier: int = -1, salt: StringName = &"") -> ShipComponentVariant:
	if part == null or part.variant_pool.is_empty():
		return null
	var tier: int = part.tier if available_tier < 1 else available_tier
	var eligible: Array[ShipComponentVariant] = []
	var total_weight: float = 0.0
	for variant in part.variant_pool:
		if variant == null or variant.min_tier > tier or variant.weight <= 0.0:
			continue
		eligible.append(variant)
		total_weight += variant.weight
	if eligible.is_empty() or total_weight <= 0.0:
		return null

	var rng := RandomNumberGenerator.new()
	rng.seed = _variant_seed(blueprint_seed, instance_seed, part.id, salt)
	var pick: float = rng.randf() * total_weight
	for variant in eligible:
		pick -= variant.weight
		if pick < 0.0:
			return variant
	return eligible[eligible.size() - 1]

func resolve_variant(part: ShipPartDefinition, variant_id: StringName) -> ShipComponentVariant:
	if part == null or String(variant_id).is_empty():
		return null
	for variant in part.variant_pool:
		if variant != null and variant.id == variant_id:
			return variant
	return null

func combined_trait(part: ShipPartDefinition, variant: ShipComponentVariant = null) -> TraitDefinition:
	if part == null:
		return null
	var base: TraitDefinition = part.trait_definition
	var modifier: TraitDefinition = variant.trait_modifiers if variant != null else null
	if base == null and modifier == null:
		return null
	var merged: TraitDefinition = base.duplicate(true) as TraitDefinition if base != null else TraitDefinition.new()
	if modifier == null:
		return merged

	merged.id = StringName("%s_%s" % [String(part.id), String(variant.id)])
	merged.display_name = variant.display_name if not variant.display_name.is_empty() else merged.display_name
	merged.description = modifier.description if not modifier.description.is_empty() else merged.description
	merged.production_boost += modifier.production_boost
	merged.gather_income_multiplier *= modifier.gather_income_multiplier
	merged.worker_spawn_bonus += modifier.worker_spawn_bonus
	merged.cluster_tier_bonus += modifier.cluster_tier_bonus
	merged.defense_rating += modifier.defense_rating
	merged.perimeter_slots_bonus += modifier.perimeter_slots_bonus
	merged.range_bonus += modifier.range_bonus
	merged.transfer_speed_multiplier *= modifier.transfer_speed_multiplier
	if not String(modifier.maintenance_cost_resource).is_empty():
		merged.maintenance_cost_resource = modifier.maintenance_cost_resource
	merged.maintenance_cost_amount += modifier.maintenance_cost_amount
	merged.hull_hp_bonus += modifier.hull_hp_bonus
	merged.dps_bonus += modifier.dps_bonus
	merged.attack_range_bonus += modifier.attack_range_bonus
	for effect in modifier.effects:
		if effect != null:
			merged.effects.append(effect)
	return merged

func _variant_seed(blueprint_seed: int, instance_seed: int, part_id: StringName, salt: StringName) -> int:
	return hash("%d:%d:%s:%s" % [blueprint_seed, instance_seed, String(part_id), String(salt)])

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if parts.is_empty():
		errors.append("ship part catalog is empty")
		return errors
	var ids: Dictionary = {}
	for part in parts:
		if part == null:
			errors.append("ship part catalog contains a null entry")
			continue
		errors.append_array(part.validate())
		if ids.has(part.id):
			errors.append("duplicate ship part id: %s" % part.id)
		ids[part.id] = true
	if max_module_slots < 0:
		errors.append("ship part catalog max_module_slots cannot be negative")
	# Every hull with an explicit slot schema must keep drive/shield/scanner
	# capacities so assembled ships stay flyable and the builder renders slots.
	for part in parts:
		if part == null or part.slot_type != ShipPartDefinition.SLOT_HULL or part.slot_schema.is_empty():
			continue
		var layout := slot_layout_for(part)
		if int(layout.get(ShipPartDefinition.SLOT_DRIVE, 0)) < 1:
			errors.append("hull %s slot_schema must offer at least one drive slot" % part.id)
		if int(layout.get(ShipPartDefinition.SLOT_SHIELD, 0)) < 1:
			errors.append("hull %s slot_schema must offer at least one shield slot" % part.id)
		if int(layout.get(ShipPartDefinition.SLOT_SCANNER, 0)) < 1:
			errors.append("hull %s slot_schema must offer at least one scanner slot" % part.id)
	var blueprint_ids: Dictionary = {}
	for blueprint in blueprints:
		if blueprint == null:
			errors.append("ship part catalog contains a null blueprint")
			continue
		errors.append_array(blueprint.validate())
		if blueprint_ids.has(blueprint.id):
			errors.append("duplicate ship blueprint id: %s" % blueprint.id)
		blueprint_ids[blueprint.id] = true
		for slot_name in blueprint.default_components:
			var default_part_id: StringName = blueprint.default_components[slot_name] as StringName
			if not String(default_part_id).is_empty() and resolve(default_part_id) == null:
				errors.append("blueprint %s references missing default component %s" % [blueprint.id, default_part_id])
	return errors
