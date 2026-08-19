class_name ShipBase
extends Node2D

const DEFAULT_SHIP_PART_CATALOG: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")

signal arrived(ship: Node2D)

var fleet: FleetSnapshot
var destination: Planet
var source_planet_id: StringName = &""
var mission_role: StringName = &""

var _route_path: Array[Vector2] = []
var _duration := 0.0
var _arrived := false
var _view: CompositeShipView

func configure(incoming_fleet: FleetSnapshot, destination_planet: Planet, route_path: Array[Vector2], duration: float, catalog: ShipPartCatalog = null, role: StringName = &"", source_id: StringName = &"") -> void:
	fleet = incoming_fleet
	destination = destination_planet
	mission_role = role if not String(role).is_empty() else (fleet.mission_role if fleet != null else &"")
	source_planet_id = source_id
	_route_path = route_path.duplicate() if route_path.size() >= 2 else []
	_duration = maxf(duration, 0.001)
	_rebuild_visual(catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG)

func start_flight() -> void:
	if _route_path.is_empty() or destination == null or not is_instance_valid(destination):
		_arrive()
		return
	global_position = _route_path[0]
	var total_length := PathUtils.distance(_route_path)
	var tween := create_tween()
	for index in range(1, _route_path.size()):
		var segment_length: float = _route_path[index - 1].distance_to(_route_path[index])
		var segment_duration: float = _duration * segment_length / total_length if total_length > 0.0 else 0.0
		tween.tween_property(self, "global_position", _route_path[index], segment_duration).set_trans(Tween.TRANS_LINEAR)
	tween.finished.connect(Callable(self, "_arrive"))

func flight_duration() -> float:
	return _duration

func has_arrived() -> bool:
	return _arrived

func _arrive() -> void:
	if _arrived:
		return
	_arrived = true
	arrived.emit(self)

func _rebuild_visual(catalog: ShipPartCatalog) -> void:
	if _view == null or not is_instance_valid(_view):
		_view = CompositeShipView.new()
		_view.name = "ShipVisual"
		add_child(_view)
	if fleet == null or fleet.ships.is_empty():
		_view.clear()
		return
	var ship_data: Dictionary = fleet.ships[0]
	var faction: StringName = fleet.faction
	var variants: Dictionary = ship_data.get("variants", {}) as Dictionary
	_view.setup_from_parts(
		_resolve_part(catalog, ship_data.get("hull", &"") as StringName),
		_resolve_part(catalog, ship_data.get("scanner", &"") as StringName),
		_resolve_part(catalog, ship_data.get("drive", &"") as StringName),
		_resolve_part(catalog, ship_data.get("weapon", &"") as StringName),
		_resolve_part(catalog, ship_data.get("shield", &"") as StringName),
		_resolve_modules(catalog, ship_data.get("modules", []) as Array),
		faction,
		null,
		_resolve_view_variants(catalog, ship_data, variants)
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

func _resolve_view_variants(catalog: ShipPartCatalog, ship_data: Dictionary, variants: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for slot_name in [&"hull", &"drive", &"weapon", &"shield", &"scanner"]:
		var part: ShipPartDefinition = catalog.resolve(ship_data.get(slot_name, &"") as StringName)
		var variant: ShipComponentVariant = catalog.resolve_variant(part, variants.get(slot_name, &"") as StringName)
		if variant != null:
			result[slot_name] = variant
	var module_ids: Array = ship_data.get("modules", []) as Array
	var stored_utility: Array = variants.get(&"utility", []) as Array
	var module_variants: Array[ShipComponentVariant] = []
	for index in range(module_ids.size()):
		var module_part: ShipPartDefinition = catalog.resolve(module_ids[index] as StringName)
		var utility_variant_id: StringName = stored_utility[index] as StringName if index < stored_utility.size() else &""
		module_variants.append(catalog.resolve_variant(module_part, utility_variant_id))
	result[&"utility"] = module_variants
	return result
