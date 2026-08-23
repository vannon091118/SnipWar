class_name ShipBase
extends Node2D

const DEFAULT_SHIP_PART_CATALOG: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")
const SELECTION_RING_COLOR := Color(0.6, 0.85, 1.0, 0.9)
const SELECTION_RING_RADIUS := 36.0

signal arrived(ship: Node2D)
signal ship_selected(ship: Node2D)
signal ship_hovered(ship: Node2D)
signal ship_unhovered(ship: Node2D)

var fleet: FleetSnapshot
var destination: Planet
var source_planet_id: StringName = &""
var mission_role: StringName = &""
var transit_id: StringName = &""

var _route_path: Array[Vector2] = []
var _duration := 0.0
var _arrived := false
var _view: CompositeShipView
var _flight_tween: Tween
var _selected := false

@onready var _click_area: Area2D = get_node_or_null("ClickArea") as Area2D
@onready var _selection_ring: Sprite2D = get_node_or_null("SelectionRing") as Sprite2D
@onready var _transit_label: Label = get_node_or_null("TransitLabel") as Label
@onready var _route_line: Line2D = get_node_or_null("RouteLine") as Line2D

func _ready() -> void:
	if _click_area != null:
		_click_area.input_event.connect(_on_click_area_input_event)
		_click_area.mouse_entered.connect(_on_click_area_mouse_entered)
		_click_area.mouse_exited.connect(_on_click_area_mouse_exited)
	if _selection_ring != null:
		_draw_selection_ring()
		_selection_ring.position = Vector2.ZERO
	_update_transit_label()

func _draw_selection_ring() -> void:
	if _selection_ring == null:
		return
	# Create a procedural circle texture for the selection ring
	var radius := SELECTION_RING_RADIUS
	var image := Image.create(int(radius * 2.0) + 4, int(radius * 2.0) + 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var center := Vector2(float(image.get_width()) * 0.5, float(image.get_height()) * 0.5)
	# Draw dashed ring segments
	var segment_count := 12
	var gap_ratio := 0.25
	var segment_angle := TAU / float(segment_count)
	var filled_angle := segment_angle * (1.0 - gap_ratio)
	for i in segment_count:
		var start_a := float(i) * segment_angle - TAU * 0.25
		var end_a := start_a + filled_angle
		var steps := 8
		for s in steps:
			var a := start_a + (end_a - start_a) * float(s) / float(steps)
			var x := int(center.x + cos(a) * radius)
			var y := int(center.y + sin(a) * radius)
			if x >= 0 and x < image.get_width() and y >= 0 and y < image.get_height():
				image.set_pixel(x, y, SELECTION_RING_COLOR)
	var tex := ImageTexture.create_from_image(image)
	_selection_ring.texture = tex
	_selection_ring.centered = true

func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			ship_selected.emit(self)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Right-click on a ship centers the camera on it and selects it
			ship_selected.emit(self)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.pressed:
		ship_selected.emit(self)
		get_viewport().set_input_as_handled()

func _on_click_area_mouse_entered() -> void:
	ship_hovered.emit(self)
	_show_route(true)

func _on_click_area_mouse_exited() -> void:
	ship_unhovered.emit(self)
	if not _selected:
		_show_route(false)

func set_selected(enabled: bool) -> void:
	_selected = enabled
	if is_instance_valid(_selection_ring):
		_selection_ring.visible = enabled
	if is_instance_valid(_transit_label):
		_transit_label.visible = enabled
	if is_instance_valid(_route_line):
		_route_line.visible = enabled
	if not enabled and is_instance_valid(_route_line):
		_route_line.visible = false
	if enabled:
		_update_transit_label()
		_update_route_line()

func is_selected() -> bool:
	return _selected

func _show_route(show: bool) -> void:
	if is_instance_valid(_route_line) and not _selected:
		_route_line.visible = show
	if is_instance_valid(_transit_label) and not _selected:
		_transit_label.visible = show

func _update_transit_label() -> void:
	if _transit_label == null:
		return
	if _arrived:
		var dest_name := "Homeworld"
		if destination != null and is_instance_valid(destination):
			dest_name = UIBaseUtils.planet_display_name(destination)
		_transit_label.text = "Stationiert bei %s" % dest_name
	else:
		var remaining: float = _duration * (1.0 - _flight_progress())
		_transit_label.text = "Unterwegs · %.1f s" % maxf(remaining, 0.0)

func _update_route_line() -> void:
	if _route_line == null:
		return
	_route_line.clear_points()
	if _arrived or _route_path.is_empty():
		return
	# Convert world-space route to local points
	for wp in _route_path:
		_route_line.add_point(to_local(wp))
	# Draw from current position to first remaining waypoint
	_route_line.set_point_position(0, Vector2.ZERO)

func _flight_progress() -> float:
	return get_meta(&"flight_elapsed", 0.0) / maxf(_duration, 0.001)

# --- Original API (unchanged) ---

func configure(incoming_fleet: FleetSnapshot, destination_planet: Planet, incoming_route_path: Array[Vector2], duration: float, catalog: ShipPartCatalog = null, role: StringName = &"", source_id: StringName = &"") -> void:
	fleet = incoming_fleet
	destination = destination_planet
	mission_role = role if not String(role).is_empty() else (fleet.mission_role if fleet != null else &"")
	source_planet_id = source_id
	_route_path = incoming_route_path.duplicate() if incoming_route_path.size() >= 2 else []
	_duration = maxf(duration, 0.001)
	_rebuild_visual(catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG)
	_update_transit_label()
	_update_route_line()

func configure_idle(incoming_fleet: FleetSnapshot, location: Planet, catalog: ShipPartCatalog = null, role: StringName = &"", source_id: StringName = &"") -> void:
	fleet = incoming_fleet
	destination = location
	mission_role = role if not String(role).is_empty() else (fleet.mission_role if fleet != null else &"")
	source_planet_id = source_id
	_route_path.clear()
	_duration = 0.0
	_arrived = true
	_rebuild_visual(catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG)
	_update_transit_label()

func start_flight() -> void:
	start_flight_from_elapsed(0.0)

func start_flight_from_elapsed(elapsed: float) -> void:
	set_meta(&"flight_elapsed", elapsed)
	if _route_path.is_empty() or destination == null or not is_instance_valid(destination):
		_arrive()
		return
	if _flight_tween != null and _flight_tween.is_valid():
		_flight_tween.kill()
	var progress := clampf(elapsed / maxf(_duration, 0.001), 0.0, 1.0)
	if progress >= 1.0:
		_arrive()
		return
	var total_length := PathUtils.distance(_route_path)
	var target_distance := progress * total_length
	var segment_index := 0
	var segment_offset := 0.0
	var travelled := 0.0
	for index in range(_route_path.size() - 1):
		var segment_length: float = _route_path[index].distance_to(_route_path[index + 1])
		if travelled + segment_length >= target_distance:
			segment_index = index
			segment_offset = target_distance - travelled
			break
		travelled += segment_length
	global_position = _route_path[segment_index].lerp(
		_route_path[segment_index + 1],
		segment_offset / maxf(_route_path[segment_index].distance_to(_route_path[segment_index + 1]), 0.001)
	)
	var tween := create_tween()
	_flight_tween = tween
	var remaining_duration := _duration * (1.0 - progress)
	var remaining_distance := maxf(total_length - target_distance, 0.0)
	if remaining_distance <= 0.0:
		_arrive()
		return
	var first_segment_remaining := _route_path[segment_index].distance_to(_route_path[segment_index + 1]) - segment_offset
	tween.tween_property(self, "global_position", _route_path[segment_index + 1], remaining_duration * first_segment_remaining / remaining_distance).set_trans(Tween.TRANS_LINEAR)
	for index in range(segment_index + 1, _route_path.size() - 1):
		var segment_length: float = _route_path[index].distance_to(_route_path[index + 1])
		tween.tween_property(self, "global_position", _route_path[index + 1], remaining_duration * segment_length / remaining_distance).set_trans(Tween.TRANS_LINEAR)
	tween.finished.connect(Callable(self, "_arrive"))
	_update_transit_label()
	_update_route_line()

func stop_flight() -> void:
	if _flight_tween != null and _flight_tween.is_valid():
		_flight_tween.kill()

func route_path() -> Array[Vector2]:
	return _route_path.duplicate()

func flight_duration() -> float:
	return _duration

func has_arrived() -> bool:
	return _arrived

func _arrive() -> void:
	if _flight_tween != null and _flight_tween.is_valid():
		_flight_tween.kill()
	if _arrived:
		return
	_arrived = true
	_update_transit_label()
	arrived.emit(self)

func _rebuild_visual(catalog: ShipPartCatalog) -> void:
	if _view == null or not is_instance_valid(_view):
		_view = CompositeShipView.new()
		_view.name = "ShipVisual"
		add_child(_view)
		# Move visual below ClickArea in the scene tree order
		if _click_area != null:
			move_child(_view, 0)
	if fleet == null or fleet.ships.is_empty():
		_view.clear()
		return
	var assembly: ShipAssembly = fleet.ships[0]
	var faction: StringName = fleet.faction
	_view.setup_from_parts(
		_resolve_part(catalog, assembly.hull_id),
		_resolve_part(catalog, assembly.scanner_id),
		_resolve_part(catalog, assembly.drive_id),
		_resolve_part(catalog, assembly.weapon_id),
		_resolve_part(catalog, assembly.shield_id),
		_resolve_modules(catalog, assembly.module_ids),
		faction,
		null,
		_resolve_view_variants(catalog, assembly)
	)

func _resolve_part(catalog: ShipPartCatalog, part_id: StringName) -> ShipPartDefinition:
	return catalog.resolve(part_id)

func _resolve_modules(catalog: ShipPartCatalog, module_ids: Array) -> Array[ShipPartDefinition]:
	var result: Array[ShipPartDefinition] = []
	for module_id in module_ids:
		var part: ShipPartDefinition = catalog.resolve(module_id as StringName)
		if part != null:
			result.append(part)
	return result

func _resolve_view_variants(catalog: ShipPartCatalog, assembly: ShipAssembly) -> Dictionary:
	var result: Dictionary = {}
	var slot_types: Array[StringName] = [ShipPartDefinition.SLOT_HULL, ShipPartDefinition.SLOT_DRIVE, ShipPartDefinition.SLOT_WEAPON, ShipPartDefinition.SLOT_SHIELD, ShipPartDefinition.SLOT_SCANNER]
	for slot_type in slot_types:
		var part_id: StringName = assembly.hull_id
		match slot_type:
			ShipPartDefinition.SLOT_DRIVE:
				part_id = assembly.drive_id
			ShipPartDefinition.SLOT_WEAPON:
				part_id = assembly.weapon_id
			ShipPartDefinition.SLOT_SHIELD:
				part_id = assembly.shield_id
			ShipPartDefinition.SLOT_SCANNER:
				part_id = assembly.scanner_id
		var part: ShipPartDefinition = catalog.resolve(part_id)
		var variant: ShipComponentVariant = catalog.resolve_variant(part, assembly.variant_id_for(slot_type))
		if variant != null:
			result[slot_type] = variant
	var module_variants: Array[ShipComponentVariant] = []
	for index in range(assembly.module_ids.size()):
		var module_part: ShipPartDefinition = catalog.resolve(assembly.module_ids[index])
		module_variants.append(catalog.resolve_variant(module_part, assembly.variant_id_for(ShipPartDefinition.SLOT_UTILITY, index)))
	result[ShipPartDefinition.SLOT_UTILITY] = module_variants
	return result