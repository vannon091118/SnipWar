class_name ParchmentTechTreeView
extends Control

## Fullscreen parchment research tree: technologies are laid out by prerequisite
## depth and connected with hand-drawn elbow connectors. Research buttons drive
## the same timed-research path as the compact tech panel.

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

const NODE_W := 210.0
const NODE_H := 100.0
const COL_W := 280.0
const ROW_H := 160.0
const PAD := 48.0

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _ship_manager: ShipManager
var _catalog: TechnologyCatalog
var _state: Node
var _canvas: Control
var _positions: Dictionary = {}
var _node_controls: Dictionary = {}
var _tree_scroll: ScrollContainer
var _parallax_offset := Vector2.ZERO
var _mouse_position := Vector2.ZERO

func setup(ship_manager: ShipManager, theme_config: UIThemeConfig = null) -> void:
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_ship_manager = ship_manager
	_catalog = ship_manager.get_technology_catalog() if ship_manager != null else null
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func refresh(state: Node) -> void:
	_state = state
	_positions.clear()
	_node_controls.clear()
	if _canvas == null:
		return
	for child in _canvas.get_children():
		_canvas.remove_child(child)
		child.queue_free()
	if _catalog == null or state == null:
		_canvas.queue_redraw()
		return
	_layout_tree(state)
	_canvas.queue_redraw()

## Kontext-gated: WASD/Pfeile + Bild Auf/Ab scrollen den Baum, solange der
## Forschungsbaum offen ist. Die Kamera ist waehrenddessen blockiert, WASD
## kollidiert also nicht mit der Welt-Steuerung.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var handled := true
	var step_x := 120
	var step_y := 90
	match event.keycode:
		KEY_LEFT, KEY_A:
			if _tree_scroll != null:
				_tree_scroll.scroll_horizontal = maxi(_tree_scroll.scroll_horizontal - step_x, 0)
		KEY_RIGHT, KEY_D:
			if _tree_scroll != null:
				_tree_scroll.scroll_horizontal = mini(_tree_scroll.scroll_horizontal + step_x, _tree_scroll.get_h_scroll_bar().max_value)
		KEY_UP, KEY_W:
			if _tree_scroll != null:
				_tree_scroll.scroll_vertical = maxi(_tree_scroll.scroll_vertical - step_y, 0)
		KEY_DOWN, KEY_S:
			if _tree_scroll != null:
				_tree_scroll.scroll_vertical = mini(_tree_scroll.scroll_vertical + step_y, _tree_scroll.get_v_scroll_bar().max_value)
		KEY_PAGEUP:
			if _tree_scroll != null:
				_tree_scroll.scroll_vertical = maxi(_tree_scroll.scroll_vertical - int(_tree_scroll.size.y * 0.8), 0)
		KEY_PAGEDOWN:
			if _tree_scroll != null:
				_tree_scroll.scroll_vertical = mini(_tree_scroll.scroll_vertical + int(_tree_scroll.size.y * 0.8), _tree_scroll.get_v_scroll_bar().max_value)
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()
func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "TreeScroll"
	_tree_scroll = scroll
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.add_theme_stylebox_override("panel", _theme_config.make_style_box(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 0))
	add_child(scroll)
	_canvas = Control.new()
	_canvas.name = "TreeCanvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_connectors)
	scroll.add_child(_canvas)
	_build_status_legend()

## Farblegende: Grau ungelernt · Grün gelernt · Rot nicht lernbar · Gelb in Arbeit.
func _build_status_legend() -> void:
	var legend := PanelContainer.new()
	legend.name = "StatusLegend"
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend.add_theme_stylebox_override("panel", UIBaseUtils.style_box(_theme_config, Color(0.02, 0.03, 0.05, 0.85), _theme_config.panel_border, 1, _theme_config.panel_corner_radius))
	legend.set_anchors_preset(Control.PRESET_TOP_LEFT)
	legend.offset_left = 12.0
	legend.offset_top = 8.0
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	for entry in [
		[UIStatusUtils.STATE_LEARNED, "Gelernt"],
		[UIStatusUtils.STATE_AVAILABLE, "Lernbar"],
		[UIStatusUtils.STATE_IN_PROGRESS, "In Forschung"],
		[UIStatusUtils.STATE_LOCKED, "Nicht lernbar"],
	]:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 4)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.color = UIStatusUtils.state_color(entry[0], _theme_config)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_child(dot)
		chip.add_child(UIBaseUtils.make_label(String(entry[1]), _theme_config.secondary_text_color, _theme_config.small_font_size, false))
		box.add_child(chip)
	legend.add_child(box)
	add_child(legend)

func _layout_tree(state: Node) -> void:
	var visible_techs: Array = _visible_path_technologies(state)
	var depths: Dictionary = {}
	for tech in visible_techs:
		_depth_of(tech.id, depths)
	var max_depth := 0
	for depth_value in depths.values():
		max_depth = maxi(max_depth, int(depth_value))
	var rows: Dictionary = {}
	var max_row := 0
	for tech in visible_techs:
		var depth: int = int(depths.get(tech.id, 0))
		var row: int = int(rows.get(depth, 0))
		rows[depth] = row + 1
		max_row = maxi(max_row, row)
		var center := Vector2(PAD + float(depth) * COL_W + NODE_W * 0.5, PAD + float(row) * ROW_H + NODE_H * 0.5)
		_positions[tech.id] = center
		var node := _tech_node(tech, state, center)
		_node_controls[tech.id] = node
		_canvas.add_child(node)
	var canvas_size := Vector2(PAD * 2.0 + float(max_depth + 1) * COL_W, PAD * 2.0 + float(max_row + 1) * ROW_H)
	_canvas.custom_minimum_size = canvas_size
	_canvas.size = canvas_size

func _visible_path_technologies(state: Node) -> Array:
	if _catalog == null or state == null:
		return []
	var all: Array = _catalog.resolve_all()
	var visible_list: Array = []
	var frontier: Array[StringName] = []
	for technology in all:
		var tech_state: StringName = UIStatusUtils.research_state(GameState.FACTION_PLAYER, technology, state, _catalog)
		if tech_state == UIStatusUtils.STATE_IN_PROGRESS or tech_state == UIStatusUtils.STATE_AVAILABLE:
			frontier.append(technology.id)
	for technology in all:
		var learned: StringName = UIStatusUtils.research_state(GameState.FACTION_PLAYER, technology, state, _catalog)
		if learned == UIStatusUtils.STATE_LEARNED:
			visible_list.append(technology)
	for technology_id in frontier:
		var technology: TechnologyDefinition = _catalog.resolve(technology_id)
		if technology != null and not visible_list.has(technology):
			visible_list.append(technology)
	# Keep one readable next step per branch; locked distant nodes are hidden.
	for technology in all:
		if visible_list.size() >= 12:
			break
		if not visible_list.has(technology) and not String(technology.prerequisite_tech_id).is_empty() and visible_list.any(func(item): return item.id == technology.prerequisite_tech_id):
			visible_list.append(technology)
	return visible_list

func _depth_of(tech_id: StringName, memo: Dictionary) -> int:
	if memo.has(tech_id):
		return int(memo.get(tech_id, 0))
	var technology: TechnologyDefinition = _catalog.resolve(tech_id)
	if technology == null:
		memo[tech_id] = 0
		return 0
	# Mark as visited (0) BEFORE recursing to break potential cycles.
	memo[tech_id] = 0
	var depth := 0
	if not String(technology.prerequisite_tech_id).is_empty():
		depth = _depth_of(technology.prerequisite_tech_id, memo) + 1
	memo[tech_id] = depth
	return depth

func _tech_node(technology: TechnologyDefinition, state: Node, center: Vector2) -> Control:
	var button := Button.new()
	var research_state_id: StringName = UIStatusUtils.research_state(GameState.FACTION_PLAYER, technology, state, _catalog)
	var accent: Color = UIStatusUtils.state_color(research_state_id, _theme_config)
	button.name = "TechNode_" + String(technology.id)
	var status_mark := ""
	match research_state_id:
		UIStatusUtils.STATE_LEARNED:
			status_mark = "✓ "
		UIStatusUtils.STATE_IN_PROGRESS:
			status_mark = "⟳ "
		UIStatusUtils.STATE_LOCKED:
			status_mark = "✗ "
	button.text = "%s%s\n%d %s" % [status_mark, technology.display_name, technology.cost_amount, String(technology.cost_resource)]
	button.position = center - Vector2(NODE_W * 0.5, NODE_H * 0.5)
	button.set_meta("tree_center", center)
	button.size = Vector2(NODE_W, NODE_H)
	button.focus_mode = Control.FOCUS_NONE
	# Der Rahmen kommuniziert den Zustand farblich (Grau/Grün/Rot/Gelb).
	button.add_theme_stylebox_override("normal", UIBaseUtils.style_box(_theme_config, _theme_config.card_background, accent, 2, _theme_config.panel_corner_radius))
	button.add_theme_stylebox_override("hover", UIBaseUtils.style_box(_theme_config, _theme_config.input_hover_background, accent.lightened(0.2), 2, _theme_config.panel_corner_radius))
	button.add_theme_stylebox_override("disabled", UIBaseUtils.style_box(_theme_config, _theme_config.button_disabled_background, accent.darkened(0.25), 2, _theme_config.panel_corner_radius))
	button.add_theme_font_size_override("font_size", _theme_config.small_font_size)
	button.add_theme_color_override("font_color", accent)
	button.add_theme_color_override("font_hover_color", accent.lightened(0.2))
	button.add_theme_color_override("font_pressed_color", accent)
	button.add_theme_color_override("font_disabled_color", accent.darkened(0.1))
	button.tooltip_text = technology.description + "\n" + technology.mechanic_description + _disabled_reason(technology, state)
	button.pressed.connect(_research.bind(technology.id))
	if research_state_id == UIStatusUtils.STATE_IN_PROGRESS:
		button.disabled = true
		button.tooltip_text += "\nLäuft bereits — Fortschritt läuft ohne weitere Klicks."
	return button

## Sprint 6 (G7): explains WHY a tech node is greyed out. Logic is centralized
## in UIStatusUtils.locked_reason so every view shares one implementation.
func _disabled_reason(technology: TechnologyDefinition, state: Node) -> String:
	return UIStatusUtils.locked_reason(technology, state, _catalog)

func _research(technology_id: StringName) -> void:
	if _state == null or _catalog == null:
		return
	_state.research_technology(GameState.FACTION_PLAYER, technology_id, _catalog)
	refresh(_state)

func _process(_delta: float) -> void:
	if _canvas == null or not is_visible_in_tree():
		return
	_mouse_position = get_local_mouse_position()
	var viewport_size := size
	var normalized := Vector2.ZERO
	if viewport_size.x > 0.0 and viewport_size.y > 0.0:
		normalized = (_mouse_position / viewport_size - Vector2(0.5, 0.5)) * 2.0
	_parallax_offset = normalized.clamp(Vector2(-1.0, -1.0), Vector2.ONE) * 10.0
	for technology_id in _node_controls:
		var node: Control = _node_controls[technology_id] as Control
		if node != null and is_instance_valid(node):
			var center: Vector2 = node.get_meta("tree_center", node.position + Vector2(NODE_W * 0.5, NODE_H * 0.5))
			node.position = center - Vector2(NODE_W * 0.5, NODE_H * 0.5) + _parallax_offset * (0.45 + float(center.x) / maxf(_canvas.size.x, 1.0) * 0.55)
		_canvas.queue_redraw()

func _draw_connectors() -> void:
	if _catalog == null:
		return
	var line_color := _theme_config.muted_text_color
	line_color.a = 0.8
	for technology in _catalog.resolve_all():
		if technology == null or String(technology.prerequisite_tech_id).is_empty():
			continue
		if not _positions.has(technology.id) or not _positions.has(technology.prerequisite_tech_id):
			continue
		var from := _live_node_center(technology.prerequisite_tech_id)
		var to := _live_node_center(technology.id)
		var elbow := Vector2(to.x, from.y)
		_canvas.draw_line(from, elbow, line_color, 2.0, true)
		_canvas.draw_line(elbow, to, line_color, 2.0, true)

## Connectors must end at their bubbles' live parallax positions. Deriving
## endpoints from base coordinates plus fixed offsets lets the drawn lines
## drift away from the nodes they belong to whenever mouse parallax moves
## buttons by their depth-scaled factors.
func _live_node_center(technology_id: StringName) -> Vector2:
	if _node_controls.has(technology_id):
		var node: Control = _node_controls[technology_id] as Control
		if node != null and is_instance_valid(node):
			return node.position + Vector2(NODE_W * 0.5, NODE_H * 0.5)
	return (_positions.get(technology_id, Vector2.ZERO) as Vector2)
