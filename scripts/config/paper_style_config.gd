@tool
class_name PaperStyleConfig
extends Resource

## Tunable parameters for the paper-comic visual layer (outlines, halftone,
## cell shading). Applied via ShaderMaterial uniforms by the scene renderers.

@export var outline_color: Color = Color(0.1, 0.1, 0.15)
@export_range(0.0, 16.0, 0.1) var outline_width: float = 2.0
@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.3)
@export var palette: Array[Color] = []
@export_range(0.0, 1.0, 0.05) var halftone_density: float = 0.5
@export_range(2, 16, 1) var cell_shading_levels: int = 4

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if outline_width < 0.0:
		errors.append("paper outline_width cannot be negative")
	if halftone_density < 0.0 or halftone_density > 1.0:
		errors.append("paper halftone_density must stay between zero and one")
	if cell_shading_levels < 2:
		errors.append("paper cell_shading_levels must be at least two")
	return errors
