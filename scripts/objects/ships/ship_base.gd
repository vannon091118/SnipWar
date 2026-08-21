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
