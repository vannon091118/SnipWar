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
@export_range(0.0, 0.15, 0.005) var grain_strength: float = 0.04
@export_range(0.0, 1.0, 0.05) var vignette_strength: float = 0.35
@export_range(0.2, 1.0, 0.05) var vignette_radius: float = 0.65
@export_range(0.01, 0.5, 0.01) var vignette_softness: float = 0.25

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if outline_width < 0.0:
		errors.append("paper outline_width cannot be negative")
	if halftone_density < 0.0 or halftone_density > 1.0:
		errors.append("paper halftone_density must stay between zero and one")
	if cell_shading_levels < 2:
		errors.append("paper cell_shading_levels must be at least two")
	if grain_strength < 0.0 or grain_strength > 0.15:
		errors.append("paper grain_strength must stay between zero and 0.15")
	if vignette_strength < 0.0 or vignette_strength > 1.0:
		errors.append("paper vignette_strength must stay between zero and one")
	if vignette_radius < 0.2 or vignette_radius > 1.0:
		errors.append("paper vignette_radius must stay between 0.2 and one")
	if vignette_softness < 0.01 or vignette_softness > 0.5:
		errors.append("paper vignette_softness must stay between 0.01 and 0.5")
	return errors
