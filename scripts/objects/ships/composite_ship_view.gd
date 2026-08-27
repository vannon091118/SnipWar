@tool
class_name CompositeShipView
extends Node2D

const DEFAULT_TRANSFORMER_CONFIG: TransformerConfig = preload("res://resources/config/transformer_default.tres")
const PAPER_OUTLINE_SHADER: Shader = preload("res://assets/shaders/paper_outline.gdshader")
const DEFAULT_PAPER_STYLE: PaperStyleConfig = preload("res://resources/config/paper_style_default.tres")

@export var transformer_config: TransformerConfig = DEFAULT_TRANSFORMER_CONFIG

var _hull_sprite: Sprite2D
var _scanner_sprite: Sprite2D
var _weapon_overlay: Sprite2D
var _engine_overlay: Sprite2D
var _shield_overlay: Sprite2D
var _modules_container: Node2D

func _ready() -> void:
	_ensure_structure()

func _ensure_structure() -> void:
	_hull_sprite = _ensure_sprite("HullSprite", _hull_sprite)
	_engine_overlay = _ensure_sprite("EngineOverlay", _engine_overlay)
	_weapon_overlay = _ensure_sprite("WeaponOverlay", _weapon_overlay)
	_shield_overlay = _ensure_sprite("ShieldOverlay", _shield_overlay)
	_scanner_sprite = _ensure_sprite("ScannerSprite", _scanner_sprite)

	if _modules_container == null or not is_instance_valid(_modules_container):
		_modules_container = get_node_or_null("ModulesContainer") as Node2D
		if _modules_container == null:
			_modules_container = Node2D.new()
			_modules_container.name = "ModulesContainer"
			add_child(_modules_container)

	_hull_sprite.z_index = 0
	_engine_overlay.z_index = -1
	_weapon_overlay.z_index = 1
	_shield_overlay.z_index = 2
	_scanner_sprite.z_index = 3
	_modules_container.z_index = 2

func _ensure_sprite(sprite_name: StringName, current: Sprite2D) -> Sprite2D:
	var sprite: Sprite2D = current
	if sprite == null or not is_instance_valid(sprite):
		sprite = get_node_or_null(NodePath(sprite_name)) as Sprite2D
		if sprite == null:
			sprite = Sprite2D.new()
			sprite.name = sprite_name
			add_child(sprite)
	return sprite

func setup(hull_tex: Texture2D, scanner_tex: Texture2D, module_textures: Array[Texture2D], faction: StringName = &"a", config: TransformerConfig = null) -> void:
	_setup_visuals(hull_tex, scanner_tex, null, null, null, module_textures, faction, config, {}, {})

## Configures a complete assembled build. Each non-null part contributes its own
## visual asset and trait metadata; weapon, drive, and shield are rendered as
## separate overlays so the build can be read without opening its data panel.
func setup_from_parts(
	hull: ShipPartDefinition,
	scanner: ShipPartDefinition,
	drive: ShipPartDefinition,
	weapon: ShipPartDefinition,
	shield: ShipPartDefinition,
	modules: Array[ShipPartDefinition],
	faction: StringName = &"a",
	config: TransformerConfig = null,
	variants: Dictionary = {}
) -> void:
	var module_textures: Array[Texture2D] = []
	for part in modules:
		if part != null:
			module_textures.append(part.visual_asset)
	_setup_visuals(
		hull.visual_asset if hull != null else null,
		scanner.visual_asset if scanner != null else null,
		drive,
		weapon,
		shield,
		module_textures,
		faction,
		config,
		{
			&"hull": hull,
			&"scanner": scanner,
			&"drive": drive,
			&"weapon": weapon,
			&"shield": shield,
			&"modules": modules,
		},
		variants
	)

func _setup_visuals(
	hull_tex: Texture2D,
	scanner_tex: Texture2D,
	drive: ShipPartDefinition,
	weapon: ShipPartDefinition,
	shield: ShipPartDefinition,
	module_textures: Array[Texture2D],
	faction: StringName,
	config: TransformerConfig,
	components: Dictionary,
	variants: Dictionary
) -> void:
	_ensure_structure()
	var active_config: TransformerConfig = config if config != null else (transformer_config if transformer_config != null else DEFAULT_TRANSFORMER_CONFIG)
	var faction_tint: Color = active_config.resolve_tint(&"faction", faction) if active_config != null else Color.WHITE
	var hull_variant: ShipComponentVariant = variants.get(&"hull", null) as ShipComponentVariant
	var scanner_variant: ShipComponentVariant = variants.get(&"scanner", null) as ShipComponentVariant
	var resolved_hull_texture: Texture2D = _variant_visual(components.get(&"hull") as ShipPartDefinition, hull_tex, hull_variant)
	var hull_relative_scale: float = _hull_relative_scale(resolved_hull_texture)

	_set_texture(_hull_sprite, resolved_hull_texture, faction_tint, Vector2.ZERO, Vector2.ONE)
	_hull_sprite.set_meta("variant_id", hull_variant.id if hull_variant != null else &"")
	_set_texture(
		_scanner_sprite,
		_variant_visual(components.get(&"scanner") as ShipPartDefinition, scanner_tex, scanner_variant),
		Color.WHITE,
		active_config.ship_scanner_offset if active_config != null else Vector2(8.0, -6.0),
		active_config.ship_scanner_scale if active_config != null else Vector2(0.5, 0.5)
	)
	_scanner_sprite.set_meta("variant_id", scanner_variant.id if scanner_variant != null else &"")
	_configure_overlay(
		_engine_overlay,
		drive,
		variants.get(&"drive", null) as ShipComponentVariant,
		(active_config.ship_engine_offset if active_config != null else Vector2(0.0, 10.0)) * hull_relative_scale,
		(active_config.ship_engine_scale if active_config != null else Vector2(0.34, 0.34)) * hull_relative_scale,
		faction_tint
	)
	_configure_overlay(
		_weapon_overlay,
		weapon,
		variants.get(&"weapon", null) as ShipComponentVariant,
		(active_config.ship_weapon_offset if active_config != null else Vector2(0.0, -4.0)) * hull_relative_scale,
		(active_config.ship_weapon_scale if active_config != null else Vector2(0.28, 0.28)) * hull_relative_scale,
		faction_tint
	)
	_configure_overlay(
		_shield_overlay,
		shield,
		variants.get(&"shield", null) as ShipComponentVariant,
		(active_config.ship_shield_offset if active_config != null else Vector2.ZERO) * hull_relative_scale,
		(active_config.ship_shield_scale if active_config != null else Vector2(0.62, 0.62)) * hull_relative_scale,
		active_config.ship_shield_overlay_tint if active_config != null else Color(0.75, 0.9, 1.0, 0.72)
	)

	for child in _modules_container.get_children():
		_modules_container.remove_child(child)
		child.queue_free()

	var offsets: Array[Vector2] = active_config.ship_module_offsets if active_config != null else [Vector2(-10.0, 6.0), Vector2(10.0, 6.0)]
	var module_scale: Vector2 = active_config.ship_module_scale if active_config != null else Vector2(0.4, 0.4)
	var module_parts: Array = components.get(&"modules", []) as Array
	var module_variants: Array = variants.get(&"utility", []) as Array
	for i in range(module_textures.size()):
		var mod_tex: Texture2D = module_textures[i]
		var module_part: ShipPartDefinition = module_parts[i] as ShipPartDefinition if i < module_parts.size() else null
		var module_variant: ShipComponentVariant = module_variants[i] as ShipComponentVariant if i < module_variants.size() else null
		mod_tex = _variant_visual(module_part, mod_tex, module_variant)
		if mod_tex == null:
			continue
		var mod_sprite: Sprite2D = Sprite2D.new()
		mod_sprite.name = "Module_%d" % i
		mod_sprite.texture = mod_tex
		mod_sprite.scale = module_scale
		mod_sprite.position = offsets[i] if i < offsets.size() else Vector2(float(i * 12 - 12), 8.0)
		mod_sprite.modulate = faction_tint
		mod_sprite.set_meta("part_id", module_part.id if module_part != null else &"")
		mod_sprite.set_meta("variant_id", module_variant.id if module_variant != null else &"")
		_modules_container.add_child(mod_sprite)
	apply_paper_outline()

## Applies the comic outline shader to every sprite of this ship view.
func apply_paper_outline(config: PaperStyleConfig = null) -> void:
	_ensure_structure()
	var style := config if config != null else DEFAULT_PAPER_STYLE
	if style == null:
		return
	var sprites: Array[Sprite2D] = [_hull_sprite, _scanner_sprite, _engine_overlay, _weapon_overlay, _shield_overlay]
	for sprite in sprites:
		if sprite == null:
			continue
		var outline_material := ShaderMaterial.new()
		outline_material.shader = PAPER_OUTLINE_SHADER
		outline_material.set_shader_parameter("outline_color", style.outline_color)
		outline_material.set_shader_parameter("outline_width", style.outline_width)
		sprite.material = outline_material

func _hull_relative_scale(hull_tex: Texture2D) -> float:
	if hull_tex == null:
		return 1.0
	return maxf(float(hull_tex.get_width()) / 96.0, 0.1)

func _variant_visual(part: ShipPartDefinition, fallback: Texture2D, variant: ShipComponentVariant) -> Texture2D:
	if variant != null and variant.visual_asset != null:
		return variant.visual_asset
	return part.visual_asset if part != null and part.visual_asset != null else fallback

func _set_texture(sprite: Sprite2D, texture: Texture2D, tint: Color, offset: Vector2, sprite_scale: Vector2) -> void:
	sprite.texture = texture
	sprite.position = offset
	sprite.scale = sprite_scale
	sprite.modulate = tint
	sprite.visible = texture != null
	sprite.set_meta("part_id", &"")
	sprite.set_meta("trait_id", &"")

func _configure_overlay(sprite: Sprite2D, part: ShipPartDefinition, variant: ShipComponentVariant, offset: Vector2, sprite_scale: Vector2, tint: Color) -> void:
	var texture: Texture2D = _variant_visual(part, null, variant)
	sprite.texture = texture
	sprite.position = offset
	sprite.scale = sprite_scale
	sprite.modulate = tint
	sprite.visible = part != null and texture != null
	sprite.set_meta("part_id", part.id if part != null else &"")
	sprite.set_meta("trait_id", part.trait_definition.id if part != null and part.trait_definition != null else &"")
	sprite.set_meta("variant_id", variant.id if variant != null else &"")

func clear() -> void:
	_ensure_structure()
	_set_texture(_hull_sprite, null, Color.WHITE, Vector2.ZERO, Vector2.ONE)
	_set_texture(_scanner_sprite, null, Color.WHITE, Vector2.ZERO, Vector2.ONE)
	_configure_overlay(_engine_overlay, null, null, Vector2.ZERO, Vector2.ONE, Color.WHITE)
	_configure_overlay(_weapon_overlay, null, null, Vector2.ZERO, Vector2.ONE, Color.WHITE)
	_configure_overlay(_shield_overlay, null, null, Vector2.ZERO, Vector2.ONE, Color.WHITE)
	for child in _modules_container.get_children():
		_modules_container.remove_child(child)
		child.queue_free()
