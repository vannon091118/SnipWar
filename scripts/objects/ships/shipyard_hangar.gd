@tool
class_name ShipyardHangar
extends Node2D

const WORKER_UNIT_SCENE: PackedScene = preload("res://scenes/objects/workers/worker_unit.tscn")
const DEFAULT_SHIP_CONFIG: ShipConfig = preload("res://resources/config/ship_default.tres")

@export_range(1, 32, 1) var build_slot_count: int = 1
@export var worker_production_visible: bool = false

var _ship_config: ShipConfig = DEFAULT_SHIP_CONFIG

func configure(slot_count: int, worker_visible: bool, config: ShipConfig = null) -> void:
	build_slot_count = maxi(slot_count, 1)
	worker_production_visible = worker_visible
	_ship_config = config if config != null else DEFAULT_SHIP_CONFIG
	_rebuild_worker_slots()

func set_worker_production_visible(visible: bool) -> void:
	worker_production_visible = visible
	_rebuild_worker_slots()

func show_ship(hull_texture: Texture2D, scanner_texture: Texture2D, module_textures: Array[Texture2D]) -> void:
	var builder: Node2D = get_node_or_null("FutureShipBuilder") as Node2D
	if builder == null:
		return
	_clear_ship_visual(builder)
	builder.visible = true
	var config: ShipConfig = _ship_config if _ship_config != null else DEFAULT_SHIP_CONFIG
	if hull_texture != null:
		_add_ship_sprite(builder, "HullSprite", hull_texture, Vector2.ZERO, config.worker_visual_size * 2.0)
	if scanner_texture != null:
		_add_ship_sprite(builder, "ScannerSprite", scanner_texture, config.scanner_offset * 2.0, config.worker_visual_size)
	for index in module_textures.size():
		var lateral := (float(index) - float(module_textures.size() - 1) * 0.5) * config.hangar_slot_spacing
		_add_ship_sprite(builder, "ModuleSprite_%d" % index, module_textures[index], Vector2(lateral, config.hangar_worker_offset.y), config.worker_visual_size)

func hide_ship() -> void:
	var builder: Node2D = get_node_or_null("FutureShipBuilder") as Node2D
	if builder == null:
		return
	_clear_ship_visual(builder)
	builder.visible = false

func _clear_ship_visual(builder: Node2D) -> void:
	for child in builder.get_children():
		builder.remove_child(child)
		child.queue_free()

func _add_ship_sprite(builder: Node2D, sprite_name: String, texture: Texture2D, offset: Vector2, target_width: float) -> void:
	var sprite := Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	var texture_width: float = texture.get_width() if texture != null else 1.0
	sprite.scale = Vector2.ONE * (target_width / maxf(texture_width, 1.0))
	sprite.position = offset
	builder.add_child(sprite)

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
			var texture_width: float = sprite.texture.get_width() if sprite.texture != null else 1.0
			sprite.scale = Vector2.ONE * (resolved_config.worker_visual_size / maxf(texture_width, 1.0))
		worker.visible = worker_production_visible
		slots.add_child(worker)
