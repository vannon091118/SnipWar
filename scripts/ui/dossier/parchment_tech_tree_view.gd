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

func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "TreeScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.add_theme_stylebox_override("panel", _theme_config.make_style_box(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 0))
	add_child(scroll)
	_canvas = Control.new()
	_canvas.name = "TreeCanvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_connectors)
	scroll.add_child(_canvas)

func _layout_tree(state: Node) -> void:
	var depths: Dictionary = {}
	for tech in _catalog.resolve_all():
		_depth_of(tech.id, depths)
	var max_depth := 0
	for depth_value in depths.values():
		max_depth = maxi(max_depth, int(depth_value))
	var rows: Dictionary = {}
	var max_row := 0
	for tech in _catalog.resolve_all():
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
	button.name = "TechNode_" + String(technology.id)
	button.text = "%s\n%d %s" % [technology.display_name, technology.cost_amount, String(technology.cost_resource)]
	button.position = center - Vector2(NODE_W * 0.5, NODE_H * 0.5)
	button.size = Vector2(NODE_W, NODE_H)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not state.can_research_technology(GameState.FACTION_PLAYER, technology.id, _catalog)
	button.tooltip_text = technology.description + "\n" + technology.mechanic_description + _disabled_reason(technology, state)
	button.add_theme_font_size_override("font_size", _theme_config.small_font_size)
	button.add_theme_stylebox_override("normal", UIBaseUtils.style_box(_theme_config, _theme_config.card_background, _theme_config.panel_border, 1, _theme_config.panel_corner_radius))
	button.add_theme_stylebox_override("hover", UIBaseUtils.style_box(_theme_config, _theme_config.input_hover_background, _theme_config.panel_border, 1, _theme_config.panel_corner_radius))
	button.add_theme_stylebox_override("disabled", UIBaseUtils.style_box(_theme_config, _theme_config.button_disabled_background, _theme_config.panel_border, 1, _theme_config.panel_corner_radius))
	button.pressed.connect(_research.bind(technology.id))
	return button

## Sprint 6 (G7): explains WHY a tech node is greyed out (missing prerequisite
## or funds) instead of leaving the player to guess.
func _disabled_reason(technology: TechnologyDefinition, state: Node) -> String:
	if state == null or technology == null or state.can_research_technology(GameState.FACTION_PLAYER, technology.id, _catalog):
		return ""
	var lines := ""
	if not String(technology.prerequisite_tech_id).is_empty() or not (technology.prerequisite_tech_ids as Array).is_empty():
		var missing_prereq: StringName = &""
		var candidates: Array[StringName] = []
		if not String(technology.prerequisite_tech_id).is_empty():
			candidates.append(technology.prerequisite_tech_id)
		elif not (technology.prerequisite_tech_ids as Array).is_empty():
			candidates.append_array(technology.prerequisite_tech_ids as Array)
		for prereq_id in candidates:
			if not state.has_technology(GameState.FACTION_PLAYER, prereq_id):
				missing_prereq = prereq_id
				break
		if not String(missing_prereq).is_empty() and _catalog != null:
			var prereq: TechnologyDefinition = _catalog.resolve(missing_prereq)
			lines = "\nVoraussetzung fehlt: %s" % (prereq.display_name if prereq != null else String(missing_prereq))
	var funds_ok := true
	if state.has_method("get_faction_resource") and int(state.get_faction_resource(GameState.FACTION_PLAYER, technology.cost_resource)) < technology.cost_amount:
		funds_ok = false
	if technology.credit_cost > 0 and state.has_method("get_faction_credits") and int(state.get_faction_credits(GameState.FACTION_PLAYER)) < technology.credit_cost:
		funds_ok = false
	if not funds_ok:
		lines += "\nRessourcen fehlen"
	return lines

func _research(technology_id: StringName) -> void:
	if _state == null or _catalog == null:
		return
	_state.research_technology(GameState.FACTION_PLAYER, technology_id, _catalog)
	refresh(_state)

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
		var from: Vector2 = _positions[technology.prerequisite_tech_id] as Vector2
		var to: Vector2 = _positions[technology.id] as Vector2
		var elbow := Vector2(to.x, from.y)
		_canvas.draw_line(from, elbow, line_color, 2.0, true)
		_canvas.draw_line(elbow, to, line_color, 2.0, true)
