@tool
class_name PlanetGridConfig
extends Resource

## Layout + geometry for a planet's buildable grid. Axial hex coordinates are
## the canonical representation; rectangular mode maps (q, r) directly.

@export_enum("hexagonal", "rectangular") var grid_type: String = "hexagonal"
@export_range(1, 12, 1) var grid_radius: int = 3
@export_range(1, 16, 1) var grid_width: int = 6
@export_range(1, 16, 1) var grid_height: int = 6
@export var cell_size: Vector2 = Vector2(24, 24)
@export_range(0.0, 16.0, 0.5) var cell_spacing: float = 2.0

## Pointy-top axial → pixel position (center of the cell). Rectangular
## grids map (q, r) directly to a plain lattice.
func cell_to_pixel(q: int, r: int) -> Vector2:
	if grid_type == "rectangular":
		return Vector2(float(q) * (cell_size.x + cell_spacing), float(r) * (cell_size.y + cell_spacing))
	var spacing := cell_size.x + cell_spacing
	var x := spacing * sqrt(3.0) * (float(q) + 0.5 * float(r))
	var y := spacing * 1.5 * float(r)
	return Vector2(x, y)

func axial_distance(aq: int, ar: int, bq: int, br: int) -> int:
	return int((absi(aq - bq) + absi(aq + ar - bq - br) + absi(ar - br)) * 0.5)

func in_bounds(q: int, r: int) -> bool:
	if grid_type == "rectangular":
		return q >= 0 and r >= 0 and q < grid_width and r < grid_height
	return axial_distance(q, r, 0, 0) <= grid_radius

## Six axial neighbor offsets for the hex grid (used by BFS pathfinding).
func axial_neighbors(q: int, r: int) -> Array[Vector2i]:
	if grid_type == "rectangular":
		return [
			Vector2i(q + 1, r),
			Vector2i(q - 1, r),
			Vector2i(q, r + 1),
			Vector2i(q, r - 1),
		]
	return [
		Vector2i(q + 1, r),
		Vector2i(q - 1, r),
		Vector2i(q, r + 1),
		Vector2i(q, r - 1),
		Vector2i(q + 1, r - 1),
		Vector2i(q - 1, r + 1),
	]

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if grid_type != "hexagonal" and grid_type != "rectangular":
		errors.append("planet grid grid_type is invalid")
	if grid_radius < 1:
		errors.append("planet grid grid_radius must be positive")
	if grid_width < 1 or grid_height < 1:
		errors.append("planet grid dimensions must be positive")
	if cell_size.x <= 0.0 or cell_size.y <= 0.0:
		errors.append("planet grid cell_size must be positive")
	if cell_spacing < 0.0:
		errors.append("planet grid cell_spacing cannot be negative")
	return errors
