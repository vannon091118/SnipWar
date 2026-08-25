class_name LayoutCoordinator
extends Node

## Sprint 6 (S6): owns every ControlField and computes non-overlapping bounds
## for the current viewport. Zones:
##   field_map                full rect (mouse-transparent)
##   field_dossier_left       left column (planet/tech/workshop)
##   field_fleet_right_top    right column, top (fleet overview)
##   field_economy_right_bottom  right column, bottom (economy)
##   field_vault_top          left strip (always-visible vault bar)
## On viewport resize every field is re-laid out proportionally; below a
## narrow breakpoint the side fields shrink so the map is never covered.

const COLLAPSE_WIDTH := 1024.0

var _fields: Dictionary = {}

func setup() -> void:
	if get_viewport() != null and not get_viewport().size_changed.is_connected(recalculate):
		get_viewport().size_changed.connect(recalculate)

func register_field(field: ControlField, zone: StringName) -> void:
	if field == null or _fields.has(zone):
		return
	field.field_id = zone
	_fields[zone] = field
	if field.get_parent() == null:
		add_child(field)
	recalculate()

func unregister_field(zone: StringName) -> void:
	if _fields.has(zone):
		var field: ControlField = _fields[zone] as ControlField
		if field != null and is_instance_valid(field):
			field.queue_free()
		_fields.erase(zone)

func get_field(zone: StringName) -> ControlField:
	return _fields.get(zone, null) as ControlField

func has_field(zone: StringName) -> bool:
	return _fields.has(zone)

func recalculate() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var vp_size: Vector2 = viewport.get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	var narrow := vp_size.x < COLLAPSE_WIDTH
	var margin := 8.0
	var top := 8.0
	var bottom_pad := 8.0
	var side_width := clampf(vp_size.x * 0.36, 260.0, 460.0)
	if narrow:
		side_width = 220.0
	var right_x := vp_size.x - side_width - margin

	var fleet_h := clampf(vp_size.y * 0.38, 160.0, 320.0)
	if narrow:
		fleet_h = 140.0
	var economy_top := top + fleet_h + margin
	var economy_h := maxf(80.0, vp_size.y - bottom_pad - economy_top)

	var vault_w := minf(vp_size.x * 0.30, 480.0)

	_apply(&"field_dossier_left", Rect2(margin, top, side_width, vp_size.y - top - bottom_pad))
	_apply(&"field_fleet_right_top", Rect2(right_x, top, side_width, fleet_h))
	_apply(&"field_economy_right_bottom", Rect2(right_x, economy_top, side_width, economy_h))
	_apply(&"field_vault_top", Rect2(margin, top, vault_w, 56.0))
	_apply(&"field_map", Rect2(0.0, 0.0, vp_size.x, vp_size.y))

func _apply(zone: StringName, bounds: Rect2) -> void:
	var field: ControlField = get_field(zone)
	if field == null:
		return
	field.apply_bounds(bounds)