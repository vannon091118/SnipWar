class_name ControlField
extends Control

## Sprint 6 (S6): a fixed, non-overlapping layout zone hosted by the
## LayoutCoordinator. Each persistent panel (fleet, economy, vault, map) gets
## one ControlField; the coordinator computes an exact bounding rect so no two
## fields ever overlap, and recalculates on viewport resize.

@export var field_id: StringName = &""
@export var width_ratio: float = 0.35
@export var height_ratio: float = 0.85
@export var min_width: int = 280
@export var max_width: int = 520
@export var collapse_on_narrow: bool = true

## Assigned by the LayoutCoordinator; persists across resize.
var resolved_rect: Rect2 = Rect2()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func apply_bounds(bounds: Rect2) -> void:
	resolved_rect = bounds
	position = bounds.position
	size = bounds.size

func fields_close(point: Vector2) -> bool:
	return resolved_rect.has_point(point)