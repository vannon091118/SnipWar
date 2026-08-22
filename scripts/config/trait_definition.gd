@tool
class_name TraitDefinition
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var production_boost: float = 0.0
@export var gather_income_multiplier: float = 1.0
@export var worker_spawn_bonus: int = 0
@export var cluster_tier_bonus: int = 0
@export var defense_rating: int = 0
@export var perimeter_slots_bonus: int = 0
@export var range_bonus: float = 0.0
@export var transfer_speed_multiplier: float = 1.0
## Extends the owning planet's field-of-view radius (chunk cells).
@export_range(0, 20, 1) var fov_radius_bonus: int = 0
@export var maintenance_cost_resource: StringName = &""
@export var maintenance_cost_amount: int = 0
@export var maintenance_credit_cost: int = 0

@export_group("Combat / Unit Stats")
@export var hull_hp_bonus: int = 0
@export var dps_bonus: float = 0.0
@export var attack_range_bonus: float = 0.0
@export var effects: Array[EffectDefinition] = []

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("trait id is empty")
	if display_name.is_empty():
		errors.append("trait display_name is empty")
	if cluster_tier_bonus < 0:
		errors.append("trait cluster_tier_bonus cannot be negative")
	if maintenance_credit_cost < 0:
		errors.append("trait maintenance_credit_cost cannot be negative")
	if gather_income_multiplier <= 0.0:
		errors.append("trait gather_income_multiplier must be positive")
	for effect in effects:
		if effect == null:
			errors.append("trait %s contains null effect" % id)
		else:
			errors.append_array(effect.validate())
	return errors

func get_stat_modifier(stat_name: StringName, base_val: float) -> float:
	var result: float = base_val
	match stat_name:
		&"production", &"production_boost":
			result += production_boost
		&"gather_income", &"gather_income_multiplier":
			result *= gather_income_multiplier
		&"spawn_rate", &"worker_spawn_bonus":
			result += float(worker_spawn_bonus)
		&"defense", &"defense_rating":
			result += float(defense_rating)
		&"cluster_tier_bonus":
			result += float(cluster_tier_bonus)
		&"perimeter_slots", &"perimeter_slots_bonus":
			result += float(perimeter_slots_bonus)
		&"range", &"range_bonus":
			result += range_bonus
		&"transfer_speed", &"transfer_speed_multiplier":
			result *= transfer_speed_multiplier
		&"hull_hp", &"hull_hp_bonus":
			result += float(hull_hp_bonus)
		&"dps", &"dps_bonus":
			result += dps_bonus
		&"attack_range", &"attack_range_bonus":
			result += attack_range_bonus

	for effect in effects:
		if effect != null and effect.target_stat == stat_name:
			result = effect.apply_to(result)

	return result
