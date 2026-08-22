class_name PlanetGridCell
extends RefCounted

## Lightweight runtime state for one buildable grid cell. Pure data — owned by
## PlanetGrid, mutated by building placement and combat.

var axial_q: int = 0
var axial_r: int = 0
var state: StringName = &"empty"
var building: BuildingDefinition
var current_hp: int = 0

func pixel_position(config: PlanetGridConfig) -> Vector2:
	return config.cell_to_pixel(axial_q, axial_r)

func key() -> Vector2i:
	return Vector2i(axial_q, axial_r)
