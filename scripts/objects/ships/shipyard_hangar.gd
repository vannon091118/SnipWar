@tool
class_name ShipyardHangar
extends Node2D

const WORKER_UNIT_SCENE: PackedScene = preload("res://scenes/objects/workers/worker_unit.tscn")
const DEFAULT_SHIP_CONFIG: ShipConfig = preload("res://resources/config/ship_default.tres")

@export_range(1, 32, 1) var build_slot_count: int = 1
@export var worker_production_visible: bool = false

var _ship_config: ShipConfig = DEFAULT_SHIP_CONFIG
var _readback_label: Label

func configure(slot_count: int, worker_visible: bool, config: ShipConfig = null) -> void:
	build_slot_count = maxi(slot_count, 1)
	worker_production_visible = worker_visible
	_ship_config = config if config != null else DEFAULT_SHIP_CONFIG
	_rebuild_worker_slots()

func set_worker_production_visible(visible: bool) -> void:
	worker_production_visible = visible
	_rebuild_worker_slots()

func show_ship_parts(
	hull: ShipPartDefinition,
	scanner: ShipPartDefinition,
	drive: ShipPartDefinition,
	weapon: ShipPartDefinition,
	shield: ShipPartDefinition,
	modules: Array[ShipPartDefinition],
	faction: StringName = &"a",
	variants: Dictionary = {}
) -> void:
	var builder: Node2D = get_node_or_null("FutureShipBuilder") as Node2D
	if builder == null:
		return
	var view: CompositeShipView = _prepare_composite_view(builder)
	builder.visible = true
	view.visible = true
	view.scale = _view_scale(hull.visual_asset if hull != null else null)
	view.setup_from_parts(hull, scanner, drive, weapon, shield, modules, faction, null, variants)
	_ensure_readback_label()
	_readback_label.visible = true
	_readback_label.text = "SHIP READBACK"
	_readback_label.tooltip_text = "Montierter Loadout-Readback"

func hide_ship() -> void:
	var builder: Node2D = get_node_or_null("FutureShipBuilder") as Node2D
	if builder == null:
		return
	var view: CompositeShipView = builder.get_node_or_null("CompositeShipView") as CompositeShipView
	if view != null:
		view.clear()
		view.visible = false
	_clear_ship_visual(builder, view)
	if _readback_label != null and is_instance_valid(_readback_label):
		_readback_label.visible = false
	builder.visible = false

func _prepare_composite_view(builder: Node2D) -> CompositeShipView:
	var view: CompositeShipView = builder.get_node_or_null("CompositeShipView") as CompositeShipView
	if view == null:
		view = CompositeShipView.new()
		view.name = "CompositeShipView"
		builder.add_child(view)
	_clear_ship_visual(builder, view)
	return view

func _clear_ship_visual(builder: Node2D, keep: Node = null) -> void:
	for child in builder.get_children():
		if child == keep:
			continue
		builder.remove_child(child)
		child.queue_free()

func set_build_readback(title: String, tooltip: String, remaining: float = 0.0) -> void:
	_ensure_readback_label()
	_readback_label.visible = true
	_readback_label.text = title if remaining <= 0.0 else "%s (%.0f s)" % [title, remaining]
	_readback_label.tooltip_text = tooltip

func _ensure_readback_label() -> void:
	if _readback_label != null and is_instance_valid(_readback_label):
		return
	_readback_label = Label.new()
	_readback_label.name = "BuildReadback"
	_readback_label.position = Vector2(-64.0, -54.0)
	_readback_label.size = Vector2(128.0, 24.0)
	_readback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_readback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readback_label.add_theme_font_size_override("font_size", 9)
	_readback_label.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0, 0.95))
	add_child(_readback_label)

func _view_scale(hull_texture: Texture2D) -> Vector2:
	var config: ShipConfig = _ship_config if _ship_config != null else DEFAULT_SHIP_CONFIG
	var texture_width: float = float(hull_texture.get_width()) if hull_texture != null else 96.0
	return Vector2.ONE * (config.worker_visual_size * 2.0 / maxf(texture_width, 1.0))

func _ready() -> void:
	_rebuild_worker_slots()

func _rebuild_worker_slots() -> void:
	var slots: Node2D = get_node_or_null("BuilderSlots") as Node2D
	if slots == null:
		return
	for child in slots.get_children():
		slots.remove_child(child)
		child.queue_free()
	var resolved_config: ShipConfig = _ship_config if _ship_config != null else DEFAULT_SHIP_CONFIG
	for index in build_slot_count:
		var worker: Node2D = WORKER_UNIT_SCENE.instantiate() as Node2D
		worker.name = "WorkerSlot_%d" % index
		worker.position = Vector2(
			(float(index) - float(build_slot_count - 1) * 0.5) * resolved_config.hangar_slot_spacing,
			resolved_config.hangar_worker_offset.y
		)
		var sprite: Sprite2D = worker.get_node_or_null("Sprite2D") as Sprite2D
		if sprite != null:
			var texture_width: float = 1.0
			if sprite.texture != null:
				texture_width = float(sprite.texture.get_width())
			sprite.scale = Vector2.ONE * (resolved_config.worker_visual_size / maxf(texture_width, 1.0))
		worker.visible = worker_production_visible
		slots.add_child(worker)
