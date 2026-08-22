@tool
class_name SectorFlavor
extends Resource

## Density-field flavor describing one spatial zone of the world. New sector
## types are authored purely as .tres presets — no code changes required.

@export var id: StringName = &""
@export var display_name: String = ""
## Multiplier applied to local planet density/spacing within this flavor.
@export_range(0.01, 10.0, 0.01) var density_multiplier: float = 1.0
## Preferred size class (variable | l | xl) for planets inside this sector.
@export var size_class_bias: StringName = &"variable"
## 0.0 = no bias, 1.0 = always use size_class_bias.
@export_range(0.0, 1.0, 0.05) var size_class_bias_strength: float = 0.0
@export_range(0.0, 200.0, 0.1) var min_intra_distance: float = 3.0
@export_range(0.0, 400.0, 0.1) var max_intra_distance: float = 12.0
## Boundary noise amplitude for this sector (keeps edges organic).
@export_range(0.0, 1.0, 0.05) var noise_amplitude: float = 0.3
@export var visual_edge_color: Color = Color(0.5, 0.5, 0.5)

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("sector flavor id is empty")
	if density_multiplier <= 0.0:
		errors.append("sector flavor density_multiplier must be positive")
	if min_intra_distance < 0.0 or max_intra_distance < min_intra_distance:
		errors.append("sector flavor intra distances are invalid")
	if size_class_bias_strength < 0.0 or size_class_bias_strength > 1.0:
		errors.append("sector flavor size_class_bias_strength must stay between zero and one")
	if noise_amplitude < 0.0 or noise_amplitude > 1.0:
		errors.append("sector flavor noise_amplitude must stay between zero and one")
	return errors
