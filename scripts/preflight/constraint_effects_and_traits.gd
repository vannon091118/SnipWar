class_name PreflightConstraintEffectsAndTraits
extends RefCounted

## EffectDefinition, TraitDefinition and ShipPartDefinition validation.

func constraint_name() -> String:
	return "effects_and_traits"


func run(ctx: PreflightContext) -> bool:
	var invalid_effect := EffectDefinition.new()
	var invalid_errs := invalid_effect.validate()
	if not ctx.check(invalid_errs.size() >= 1, "unconfigured EffectDefinition should fail validation"):
		return false
	invalid_effect.target_stat = &"production"
	invalid_effect.operation = &"invalid_op"
	if not ctx.check(invalid_effect.validate().size() >= 1, "EffectDefinition with invalid operation should fail validation"):
		return false

	var mult_effect := EffectDefinition.new()
	mult_effect.target_stat = &"production"
	mult_effect.operation = EffectDefinition.OP_MULTIPLY
	mult_effect.value = 1.25
	mult_effect.description = "+25% Produktion"
	if not ctx.check(mult_effect.validate().is_empty(), "valid mult EffectDefinition should pass validation"):
		return false
	if not ctx.check(is_equal_approx(mult_effect.apply_to(100.0), 125.0), "EffectDefinition multiply apply_to calculation is wrong"):
		return false

	var add_effect := EffectDefinition.new()
	add_effect.target_stat = &"hull_hp"
	add_effect.operation = EffectDefinition.OP_ADD
	add_effect.value = 50.0
	add_effect.description = "+50 Hülle"
	if not ctx.check(add_effect.validate().is_empty(), "valid add EffectDefinition should pass validation"):
		return false
	if not ctx.check(is_equal_approx(add_effect.apply_to(100.0), 150.0), "EffectDefinition add apply_to calculation is wrong"):
		return false

	var trait_def := TraitDefinition.new()
	trait_def.id = &"trait_test"
	trait_def.display_name = "Test Trait"
	trait_def.production_boost = 0.5
	trait_def.gather_income_multiplier = 1.3
	trait_def.transfer_speed_multiplier = 1.2
	trait_def.hull_hp_bonus = 20
	trait_def.dps_bonus = 5.5
	trait_def.attack_range_bonus = 15.0

	var nested_effect := EffectDefinition.new()
	nested_effect.target_stat = &"hull_hp"
	nested_effect.operation = EffectDefinition.OP_ADD
	nested_effect.value = 10.0
	trait_def.effects.append(nested_effect)

	if not ctx.check(trait_def.validate().is_empty(), "TraitDefinition with effects should pass validation"):
		return false

	if not ctx.check(is_equal_approx(trait_def.get_stat_modifier(&"production", 10.0), 10.5), "TraitDefinition production modifier failed"):
		return false
	if not ctx.check(is_equal_approx(trait_def.get_stat_modifier(&"gather_income", 10.0), 13.0), "TraitDefinition gather-income modifier failed"):
		return false
	if not ctx.check(is_equal_approx(trait_def.get_stat_modifier(&"transfer_speed", 100.0), 120.0), "TraitDefinition transfer_speed modifier failed"):
		return false
	if not ctx.check(is_equal_approx(trait_def.get_stat_modifier(&"hull_hp", 100.0), 130.0), "TraitDefinition hull_hp modifier (bonus + effect) failed"):
		return false
	if not ctx.check(is_equal_approx(trait_def.get_stat_modifier(&"dps", 10.0), 15.5), "TraitDefinition dps modifier failed"):
		return false
	if not ctx.check(is_equal_approx(trait_def.get_stat_modifier(&"attack_range", 50.0), 65.0), "TraitDefinition attack_range modifier failed"):
		return false

	var ship_part := ShipPartDefinition.new()
	ship_part.id = &"part_test"
	ship_part.slot_type = ShipPartDefinition.SLOT_MODULE
	ship_part.display_name = "Test Modul"
	ship_part.cost_amount = 5
	ship_part.visual_asset = preload("res://assets/objects/meteors/meteor_03_metal.svg")
	ship_part.trait_definition = trait_def

	if not ctx.check(ship_part.validate().is_empty(), "ShipPartDefinition with valid trait_definition should pass validation"):
		return false

	var broken_trait := TraitDefinition.new()
	ship_part.trait_definition = broken_trait
	if not ctx.check(ship_part.validate().size() >= 1, "ShipPartDefinition with invalid trait_definition should fail validation"):
		return false

	return true
