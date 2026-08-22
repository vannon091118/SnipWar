class_name FleetOverview
extends Control

## Quick-access sidebar showing active ships in transit and recently selected
## planets so the player never needs to scroll through menus to find units.

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")
const DEFAULT_TRANSFORMER: TransformerConfig = preload("res://resources/config/transformer_default.tres")

signal focus_requested(target: Node2D)
signal ship_drop_requested(ship: ShipBase, destination_planet: Node2D)

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _ships: Array[ShipBase] = []
var _planets: Array[Node2D] = []
var _state: Node
var _collapsed := false
var _camera: MapCamera
var _drag_ghost: Label
var _dragging_ship: ShipBase
var _drag_active := false
var _button_ship_map: Dictionary = {}
var _part_catalog: ShipPartCatalog

const ICON_SIZE := 18.0

var _title: Label
var _ships_header: Label
var _ships_list: VBoxContainer
var _planets_header: Label
var _planets_list: VBoxContainer
var _no_ships_label: Label
var _no_planets_label: Label
var _collapse_button: Button

func setup(theme_config: UIThemeConfig = null, camera: MapCamera = null) -> void:
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_camera = camera
	_build_content()

func set_part_catalog(catalog: ShipPartCatalog) -> void:
	_part_catalog = catalog

func _build_content() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "Content"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header)

	_title = Label.new()
	_title.text = "FLOTTENÜBERSICHT"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", _theme_config.section_font_size)
	_title.add_theme_color_override("font_color", _theme_config.accent_text_color)
	header.add_child(_title)

	_collapse_button = Button.new()
	_collapse_button.text = "◂"
	_collapse_button.focus_mode = Control.FOCUS_NONE
	_collapse_button.custom_minimum_size = Vector2(24.0, 24.0)
	_collapse_button.add_theme_font_size_override("font_size", _theme_config.small_font_size)
	_collapse_button.pressed.connect(_toggle_collapse)
	header.add_child(_collapse_button)

	_ships_header = _make_header("UNTERWEGS:")
	vbox.add_child(_ships_header)

	_no_ships_label = _make_dim_label("Keine aktiven Schiffe")
	vbox.add_child(_no_ships_label)

	_ships_list = VBoxContainer.new()
	_ships_list.name = "ShipsList"
	_ships_list.add_theme_constant_override("separation", 2)
	vbox.add_child(_ships_list)

	_planets_header = _make_header("PLANETEN:")
	vbox.add_child(_planets_header)

	_no_planets_label = _make_dim_label("Keine ausgewählten Planeten")
	vbox.add_child(_no_planets_label)

	_planets_list = VBoxContainer.new()
	_planets_list.name = "PlanetsList"
	_planets_list.add_theme_constant_override("separation", 2)
	vbox.add_child(_planets_list)

	_apply_style()
	_create_drag_ghost()

func _create_drag_ghost() -> void:
	_drag_ghost = Label.new()
	_drag_ghost.name = "DragGhost"
	_drag_ghost.visible = false
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.z_index = 100
	_drag_ghost.add_theme_font_size_override("font_size", _theme_config.small_font_size)
	_drag_ghost.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0, 0.85))
	_drag_ghost.modulate.a = 0.8
	add_child(_drag_ghost)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_begin_drag(event.position)
			else:
				_end_drag(event.position)
	elif event is InputEventMouseMotion and _drag_active:
		_update_drag_ghost(event.position)

func _try_begin_drag(screen_position: Vector2) -> void:
	if _ships_list == null or not _ships_list.visible:
		return
	for row in _button_ship_map:
		if not is_instance_valid(row):
			continue
		var global_pos: Vector2 = (row as Control).global_position
		var row_rect := Rect2(global_pos, (row as Control).size)
		if row_rect.has_point(screen_position):
			_dragging_ship = _button_ship_map[row] as ShipBase
			_drag_active = true
			_drag_ghost.text = "↗ %s" % _ship_label(_dragging_ship)
			_drag_ghost.visible = true
			_update_drag_ghost(screen_position)
			return

func _update_drag_ghost(screen_position: Vector2) -> void:
	if _drag_ghost == null or not _drag_ghost.visible:
		return
	_drag_ghost.global_position = screen_position + Vector2(14.0, -_drag_ghost.size.y * 0.5)

func _end_drag(screen_position: Vector2) -> void:
	if not _drag_active:
		return
	_drag_active = false
	if _drag_ghost != null:
		_drag_ghost.visible = false
	if _dragging_ship == null or not is_instance_valid(_dragging_ship):
		return
	if _camera == null or not is_instance_valid(_camera):
		return
	# Convert from FleetOverview-local to viewport-global screen coords.
	var global_pos := get_global_mouse_position()
	var target: Node2D = _camera.planet_at_screen(global_pos)
	if target != null:
		ship_drop_requested.emit(_dragging_ship, target)
	_dragging_ship = null

func _make_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _theme_config.tab_font_size)
	label.add_theme_color_override("font_color", _theme_config.heading_text_color)
	return label

func _make_dim_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _theme_config.small_font_size)
	label.add_theme_color_override("font_color", _theme_config.muted_text_color)
	return label

func _apply_style() -> void:
	queue_redraw()

func _draw() -> void:
	var box: StyleBoxFlat = _theme_config.make_style_box(Color(0.04, 0.05, 0.08, 0.92), _theme_config.panel_border, 1, _theme_config.panel_corner_radius)
	box.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))

func update_ships(ships: Array[ShipBase]) -> void:
	_ships = ships.duplicate() as Array[ShipBase]
	_rebuild_ships_list()

func update_planets(planets: Array[Node2D]) -> void:
	_planets = planets.duplicate() as Array[Node2D]
	_rebuild_planets_list()

func _rebuild_ships_list() -> void:
	if _ships_list == null:
		return
	for child in _ships_list.get_children():
		child.queue_free()
	_button_ship_map.clear()
	queue_redraw()
	_ships_list.visible = not _collapsed and not _ships.is_empty()
	if _ships_header != null:
		_ships_header.visible = not _collapsed
	if _no_ships_label != null:
		_no_ships_label.visible = not _collapsed and _ships.is_empty()
	if _ships.is_empty():
		return

	for ship in _ships:
		var row := _make_ship_row(ship)
		_ships_list.add_child(row)

func _make_ship_row(ship: ShipBase) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	# Render small part icons: hull → drive → weapon → shield
	var assembly: ShipAssembly = ship.fleet.ships[0] if (ship.fleet != null and not ship.fleet.ships.is_empty()) else null
	if assembly != null and _part_catalog != null:
		for part_id in [assembly.hull_id, assembly.drive_id, assembly.weapon_id, assembly.shield_id]:
			if String(part_id).is_empty():
				continue
			var part: ShipPartDefinition = _part_catalog.resolve(part_id)
			if part == null or part.visual_asset == null:
				continue
			var icon := TextureRect.new()
			icon.texture = part.visual_asset
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.tooltip_text = part.display_name
			row.add_child(icon)

	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text = "  " + _ship_label(ship)
	btn.flat = true
	btn.mouse_default_cursor_shape = Control.CURSOR_MOVE
	btn.pressed.connect(Callable(self, "_on_ship_focus").bind(ship))
	btn.add_theme_font_size_override("font_size", _theme_config.small_font_size)
	btn.add_theme_color_override("font_hover_color", _theme_config.accent_text_color)
	row.add_child(btn)
	_button_ship_map[row] = ship
	return row

func _rebuild_planets_list() -> void:
	if _planets_list == null:
		return
	for child in _planets_list.get_children():
		child.queue_free()
	queue_redraw()
	_planets_list.visible = not _collapsed and not _planets.is_empty()
	if _planets_header != null:
		_planets_header.visible = not _collapsed
	if _no_planets_label != null:
		_no_planets_label.visible = not _collapsed and _planets.is_empty()
	if _planets.is_empty():
		return

	for planet in _planets:
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = _planet_label(planet)
		btn.pressed.connect(Callable(self, "_on_planet_focus").bind(planet))
		btn.add_theme_font_size_override("font_size", _theme_config.small_font_size)
		_planets_list.add_child(btn)

func _ship_label(ship: ShipBase) -> String:
	var faction_mark := "[A]" if (ship.fleet != null and ship.fleet.faction == GameState.FACTION_PLAYER) else ("[B]" if (ship.fleet != null and ship.fleet.faction == GameState.FACTION_CPU) else "[·]")
	var name_text: String = _resolve_ship_display_name(ship)
	if ship.has_arrived():
		var dest_name := "?"
		if ship.destination != null and is_instance_valid(ship.destination):
			dest_name = UIBaseUtils.planet_display_name(ship.destination)
		return "%s  %s  |  Bei %s" % [faction_mark, name_text, dest_name]
	return "%s  %s  |  Unterwegs" % [faction_mark, name_text]

func _planet_label(planet: Node2D) -> String:
	if _state == null:
		_state = get_tree().root.get_node_or_null("GameState")
	var state: Node = _state
	var planet_id: StringName = planet.get("planet_id") if planet.get("planet_id") != null else &""
	var faction_id: StringName = GameState.FACTION_NEUTRAL
	if state != null:
		faction_id = state.faction_of(planet_id)
	var faction_mark := "[A]" if faction_id == GameState.FACTION_PLAYER else ("[B]" if faction_id == GameState.FACTION_CPU else "[·]")
	var name_text := UIBaseUtils.planet_display_name(planet)
	var workers: int = int(planet.get("worker_count"))
	return "%s  %s  ·  %d Einheiten" % [faction_mark, name_text, workers]

func _resolve_ship_display_name(ship: ShipBase) -> String:
	if ship.fleet == null or ship.fleet.ships.is_empty():
		return String(ship.mission_role)
	var assembly: ShipAssembly = ship.fleet.ships[0]
	# Prefer the human-readable ship_id, then the blueprint_id, then mission_role.
	if not String(assembly.ship_id).is_empty():
		return String(assembly.ship_id).capitalize().replace("_", " ")
	if not String(assembly.blueprint_id).is_empty():
		return String(assembly.blueprint_id).capitalize().replace("_", " ")
	return String(ship.mission_role)

func _on_ship_focus(ship: ShipBase) -> void:
	focus_requested.emit(ship)

func _on_planet_focus(planet: Node2D) -> void:
	focus_requested.emit(planet)

func _toggle_collapse() -> void:
	_collapsed = not _collapsed
	if _collapse_button != null:
		_collapse_button.text = "▸" if _collapsed else "◂"
	if _ships_header != null:
		_ships_header.visible = not _collapsed
	if _ships_list != null:
		_ships_list.visible = not _collapsed and not _ships.is_empty()
	if _planets_header != null:
		_planets_header.visible = not _collapsed
	if _planets_list != null:
		_planets_list.visible = not _collapsed and not _planets.is_empty()
	if _no_ships_label != null:
		_no_ships_label.visible = not _collapsed and _ships.is_empty()
	if _no_planets_label != null:
		_no_planets_label.visible = not _collapsed and _planets.is_empty()