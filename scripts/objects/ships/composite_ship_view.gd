@tool
class_name CompositeShipView
extends Node2D

const DEFAULT_TRANSFORMER_CONFIG: TransformerConfig = preload("res://resources/config/transformer_default.tres")

@export var transformer_config: TransformerConfig = DEFAULT_TRANSFORMER_CONFIG

var _hull_sprite: Sprite2D
var _scanner_sprite: Sprite2D
var _modules_container: Node2D

func _ready() -> void:
	_ensure_structure()

func _ensure_structure() -> void:
	if _hull_sprite == null or not is_instance_valid(_hull_sprite):
		_hull_sprite = get_node_or_null("HullSprite") as Sprite2D
		if _hull_sprite == null:
			_hull_sprite = Sprite2D.new()
			_hull_sprite.name = "HullSprite"
			add_child(_hull_sprite)

	if _scanner_sprite == null or not is_instance_valid(_scanner_sprite):
		_scanner_sprite = get_node_or_null("ScannerSprite") as Sprite2D
		if _scanner_sprite == null:
			_scanner_sprite = Sprite2D.new()
			_scanner_sprite.name = "ScannerSprite"
			add_child(_scanner_sprite)

	if _modules_container == null or not is_instance_valid(_modules_container):
		_modules_container = get_node_or_null("ModulesContainer") as Node2D
		if _modules_container == null:
			_modules_container = Node2D.new()
			_modules_container.name = "ModulesContainer"
			add_child(_modules_container)

func setup(hull_tex: Texture2D, scanner_tex: Texture2D, module_textures: Array[Texture2D], faction: StringName = &"a", config: TransformerConfig = null) -> void:
	_ensure_structure()
	var active_config: TransformerConfig = config if config != null else (transformer_config if transformer_config != null else DEFAULT_TRANSFORMER_CONFIG)
	var faction_tint: Color = active_config.resolve_tint(&"faction", faction) if active_config != null else Color.WHITE

	if hull_tex != null:
		_hull_sprite.texture = hull_tex
		_hull_sprite.modulate = faction_tint
		_hull_sprite.visible = true
	else:
		_hull_sprite.texture = null
		_hull_sprite.visible = false

	if scanner_tex != null:
		_scanner_sprite.texture = scanner_tex
		_scanner_sprite.position = active_config.ship_scanner_offset if active_config != null else Vector2(8.0, -6.0)
		_scanner_sprite.scale = active_config.ship_scanner_scale if active_config != null else Vector2(0.5, 0.5)
		_scanner_sprite.modulate = Color.WHITE
		_scanner_sprite.visible = true
	else:
		_scanner_sprite.texture = null
		_scanner_sprite.visible = false

	for child in _modules_container.get_children():
		_modules_container.remove_child(child)
		child.queue_free()

	var offsets: Array[Vector2] = active_config.ship_module_offsets if active_config != null else [Vector2(-10.0, 6.0), Vector2(10.0, 6.0)]
	var module_scale: Vector2 = active_config.ship_module_scale if active_config != null else Vector2(0.4, 0.4)

	for i in range(module_textures.size()):
		var mod_tex: Texture2D = module_textures[i]
		if mod_tex == null:
			continue
		var mod_sprite := Sprite2D.new()
		mod_sprite.name = "Module_%d" % i
		mod_sprite.texture = mod_tex
		mod_sprite.scale = module_scale
		if i < offsets.size():
			mod_sprite.position = offsets[i]
		else:
			mod_sprite.position = Vector2(float(i * 12 - 12), 8.0)
		mod_sprite.modulate = faction_tint
		_modules_container.add_child(mod_sprite)

func clear() -> void:
	_ensure_structure()
	if _hull_sprite != null:
		_hull_sprite.texture = null
		_hull_sprite.visible = false
	if _scanner_sprite != null:
		_scanner_sprite.texture = null
		_scanner_sprite.visible = false
	if _modules_container != null:
		for child in _modules_container.get_children():
			_modules_container.remove_child(child)
			child.queue_free()

