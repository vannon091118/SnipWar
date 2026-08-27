class_name WorkshopView
extends Control

## Fullscreen workshop/hangar: a millimeter-paper backdrop hosts the existing
## TechShipBuilderView (parts shop, assembly, disassembly, fleet launch) in a
## roomy scroll area instead of the compact right-edge tech panel.

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

var _theme_config: UIThemeConfig = DEFAULT_THEME
var _ship_manager: ShipManager
var _state: Node
var _builder := TechShipBuilderView.new()
var _research_ship_view := TechResearchShipView.new()
var _content: VBoxContainer
var _workshop_scroll: ScrollContainer
var _refresh_accumulator := 0.0
const REFRESH_INTERVAL := 0.5

func setup(ship_manager: ShipManager, theme_config: UIThemeConfig = null) -> void:
	_theme_config = theme_config if theme_config != null else DEFAULT_THEME
	_ship_manager = ship_manager
	_builder.setup(ship_manager, _theme_config)
	_research_ship_view.setup(ship_manager, _theme_config)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func refresh(state: Node, planets: Array[Planet]) -> void:
	_state = state
	if _content == null:
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_builder.clear_state()
	_research_ship_view.worker_source = null
	_research_ship_view.worker_button = null
	if state == null or _ship_manager == null:
		return
	_content.add_child(UIBaseUtils.make_label("WERKBANK — SCHIFFSMONTAGE", _theme_config.heading_text_color, _theme_config.section_font_size))
	_content.add_child(UIBaseUtils.make_label("Teile kaufen, im Hangar montieren, starten oder wieder zerlegen.", _theme_config.muted_text_color, _theme_config.small_font_size))
	_builder.build_ship_builder_section(_content, state, planets, Callable(self, "_refresh_from_builder").bind(state, planets))
	_research_ship_view.build_research_ship_and_worker_section(_content, state, planets, Callable(self, "_refresh_from_builder").bind(state, planets))

## Live-Countdowns für Forschungsaufträge (Scan/Explore) aktualisieren,
## ohne die gesamte Werkstatt bei jedem Tick neu aufzubauen.
func _process(delta: float) -> void:
	_refresh_accumulator += delta
	if _refresh_accumulator < REFRESH_INTERVAL:
		return
	_refresh_accumulator = 0.0
	if _state == null or not is_visible_in_tree():
		return
	for progress in find_children("ResearchTaskProgress", "ProgressBar", true, false):
		var bar: ProgressBar = progress as ProgressBar
		if bar == null:
			continue
		var remaining: float = float(bar.get_meta("remaining", 0.0))
		var duration: float = float(bar.get_meta("duration", 1.0))
		remaining -= REFRESH_INTERVAL
		bar.set_meta("remaining", remaining)
		bar.value = clampf(duration - remaining, 0.0, duration)
		if remaining <= 0.0:
			_refresh_from_builder(_state, _ship_manager.get_planets() if _ship_manager != null else [])
			return

## Kontext-gated: Pfeile + Bild Auf/Ab scrollen die Werkstatt, solange sie
## offen ist.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var handled := true
	match event.keycode:
		KEY_UP, KEY_W:
			if _workshop_scroll != null:
				_workshop_scroll.scroll_vertical = maxi(_workshop_scroll.scroll_vertical - 90, 0)
		KEY_DOWN, KEY_S:
			if _workshop_scroll != null:
				_workshop_scroll.scroll_vertical = mini(_workshop_scroll.scroll_vertical + 90, _workshop_scroll.get_v_scroll_bar().max_value)
		KEY_PAGEUP:
			if _workshop_scroll != null:
				_workshop_scroll.scroll_vertical = maxi(_workshop_scroll.scroll_vertical - int(_workshop_scroll.size.y * 0.8), 0)
		KEY_PAGEDOWN:
			if _workshop_scroll != null:
				_workshop_scroll.scroll_vertical = mini(_workshop_scroll.scroll_vertical + int(_workshop_scroll.size.y * 0.8), _workshop_scroll.get_v_scroll_bar().max_value)
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()
func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "WorkshopScroll"
	_workshop_scroll = scroll
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.add_theme_stylebox_override("panel", _theme_config.make_style_box(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 0))
	add_child(scroll)
	_content = VBoxContainer.new()
	_content.name = "WorkshopContent"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", _theme_config.content_separation)
	scroll.add_child(_content)

func _refresh_from_builder(state: Node, planets: Array[Planet]) -> void:
	_state = state
	refresh(state, planets)

func _draw() -> void:
	# Millimeter-paper grid backdrop behind the scroll area.
	var grid_color := Color(0.2, 0.42, 0.5, 0.10)
	var step := 16.0
	if step <= 0.0:
		return
	var x := 0.0
	while x <= size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), grid_color, 1.0, true)
		x += step
	var y := 0.0
	while y <= size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), grid_color, 1.0, true)
		y += step
