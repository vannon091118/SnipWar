@tool
class_name BackgroundConfig
extends Resource

@export_range(0, 10000, 1) var star_count: int
@export_range(0, 10000, 1) var fold_count: int
@export_range(0, 10000, 1) var grain_count: int
@export_range(0, 10000, 1) var dust_count: int
@export_range(8, 128, 8) var batch_texture_size: int
@export var star_radius_range: Vector2
@export var star_alpha_range: Vector2
@export_range(0.0, 1.0, 0.01) var star_bright_chance: float
@export var star_layer_range: Vector2i
@export var fold_length_range: Vector2
@export var fold_bend_range: Vector2
@export var fold_strength_range: Vector2
@export var grain_length_range: Vector2
@export var grain_alpha_range: Vector2
@export var dust_radius_range: Vector2
@export var dust_alpha_range: Vector2
@export_range(2, 128, 1) var fold_point_count: int
@export_range(1, 32, 1) var nebula_layer_count: int
@export var nebula_radius_base: float
@export var nebula_radius_step: float
@export var nebula_alpha_base: float
@export var nebula_alpha_step: float
@export var far_star_alpha_multiplier: float
@export var near_star_radius_multiplier: float
@export var bright_star_vertical_ratio: float
@export var bright_star_horizontal_ratio: float
@export var background_color: Color
@export var fold_shadow_color: Color
@export var fold_highlight_color: Color
@export var grain_color: Color
@export var dust_color: Color
@export var star_color: Color
@export var fold_shadow_alpha: float
@export var fold_highlight_alpha: float
@export var fold_shadow_width: float
@export var fold_highlight_width: float
@export var grain_width: float
@export_range(1, 8, 1) var fold_alpha_bucket_count: int = 2
@export_range(1, 8, 1) var grain_alpha_bucket_count: int = 2
@export var nebula_clouds: Array[BackgroundNebulaDefinition] = []

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for range_value in [star_radius_range, star_alpha_range, fold_length_range, fold_bend_range, fold_strength_range, grain_length_range, grain_alpha_range, dust_radius_range, dust_alpha_range]:
		if range_value.x < 0.0 or range_value.y < range_value.x:
			errors.append("background range is invalid")
	if star_bright_chance < 0.0 or star_bright_chance > 1.0:
		errors.append("background star_bright_chance must be between zero and one")
	if star_layer_range.y < star_layer_range.x:
		errors.append("background star_layer_range is invalid")
	if fold_point_count < 2 or nebula_layer_count < 1:
		errors.append("background point and layer counts are invalid")
	if batch_texture_size < 8 or batch_texture_size > 128:
		errors.append("background batch_texture_size is invalid")
	if nebula_radius_base < 0.0 or nebula_radius_step < 0.0 or nebula_alpha_base < 0.0 or nebula_alpha_step < 0.0:
		errors.append("background nebula values cannot be negative")
	if far_star_alpha_multiplier < 0.0 or near_star_radius_multiplier <= 0.0:
		errors.append("background star layer multipliers are invalid")
	if bright_star_vertical_ratio <= 0.0 or bright_star_horizontal_ratio < 0.0:
		errors.append("background bright-star ratios are invalid")
	if fold_shadow_alpha < 0.0 or fold_highlight_alpha < 0.0 or fold_shadow_width <= 0.0 or fold_highlight_width <= 0.0 or grain_width <= 0.0:
		errors.append("background line styling is invalid")
	if fold_alpha_bucket_count < 1 or fold_alpha_bucket_count > 8 or grain_alpha_bucket_count < 1 or grain_alpha_bucket_count > 8:
		errors.append("background alpha bucket counts are invalid")
	if nebula_clouds.is_empty():
		errors.append("background must define at least one nebula cloud")
	for cloud in nebula_clouds:
		if cloud == null:
			errors.append("background contains a null nebula cloud")
			continue
		for cloud_error in cloud.validate():
			errors.append("background nebula: " + cloud_error)
	return errors
