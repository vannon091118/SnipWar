@tool
extends VBoxContainer
class_name McpDock

## UI Dock for GDScript MCP Bridge

signal start_server_requested(config: Dictionary)
signal stop_server_requested()
signal config_changed(config: Dictionary)

@onready var _status_label: Label = %StatusIndicator
@onready var _transport_select: OptionButton = %TransportSelect
@onready var _port_spin: SpinBox = %PortSpin
@onready var _auto_start_check: CheckButton = %AutoStartCheck
@onready var _auto_restart_check: CheckButton = %AutoRestartCheck
@onready var _allow_writes_check: CheckButton = %AllowWritesCheck
@onready var _start_btn: Button = %StartBtn
@onready var _stop_btn: Button = %StopBtn
@onready var _log_container: VBoxContainer = %LogContainer
@onready var _clear_log_btn: Button = %ClearLogBtn
@onready var _log_scroll: ScrollContainer = %LogScroll

var _server_running = false
var _scenario_checks: Array = []

const SCENARIO_DIR := "res://addons/gdscript_mcp/testing/scenarios/"
const TEST_CONFIG_PATH := "user://mcp_test_config.cfg"

func _ready() -> void:
	_start_btn.pressed.connect(_on_start_pressed)
	_stop_btn.pressed.connect(_on_stop_pressed)
	_clear_log_btn.pressed.connect(_on_clear_log)
	_transport_select.item_selected.connect(_on_config_changed_internal)
	_port_spin.value_changed.connect(_on_config_changed_internal)
	_auto_start_check.toggled.connect(_on_config_changed_internal)
	_auto_restart_check.toggled.connect(_on_config_changed_internal)
	_allow_writes_check.toggled.connect(_on_config_changed_internal)

	_load_config()
	_build_scenario_section()

func _load_config() -> void:
	var file = ConfigFile.new()
	var path = "user://gdscript_mcp_config.cfg"
	if file.load(path) == OK:
		var val = file.get_value("config", "settings", {})
		if val is Dictionary:
			_apply_config(val)

func _apply_config(config: Dictionary) -> void:
	if _transport_select and _transport_select.item_count > 0:
		var transport := str(config.get("transport", "stdio"))
		_transport_select.selected = 1 if transport == "tcp" else 0
	if _port_spin:
		var configured_port := int(config.get("port", 9091))
		_port_spin.value = 9091 if configured_port == 9090 else configured_port
	if _auto_start_check:
		_auto_start_check.button_pressed = config.get("auto_start", false)
	if _auto_restart_check:
		_auto_restart_check.button_pressed = config.get("auto_restart", true)
	if _allow_writes_check:
		_allow_writes_check.button_pressed = config.get("editor_write_enabled", false)

func _get_current_config() -> Dictionary:
	var transport := "stdio"
	if _transport_select and _transport_select.selected >= 0 and _transport_select.item_count > 0:
		transport = _transport_select.get_item_text(_transport_select.selected)
	return {
		"transport": transport,
		"port": int(_port_spin.value) if _port_spin else 9091,
		"auto_start": _auto_start_check.button_pressed if _auto_start_check else false,
		"auto_restart": _auto_restart_check.button_pressed if _auto_restart_check else true,
		"editor_write_enabled": _allow_writes_check.button_pressed if _allow_writes_check else false
	}

func _on_config_changed_internal(_unused: Variant = null) -> void:
	config_changed.emit(_get_current_config())

func _on_start_pressed() -> void:
	var config = _get_current_config()
	_start_btn.disabled = true
	_stop_btn.disabled = false
	if _transport_select: _transport_select.disabled = true
	_set_port_editable(false)
	if _auto_start_check: _auto_start_check.disabled = true
	if _auto_restart_check: _auto_restart_check.disabled = true
	if _allow_writes_check: _allow_writes_check.disabled = true
	_status_label.text = "● Starting..."
	_status_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2, 1))
	start_server_requested.emit(config)

func _on_stop_pressed() -> void:
	_stop_btn.disabled = true
	_start_btn.disabled = false
	if _transport_select: _transport_select.disabled = false
	_set_port_editable(true)
	if _auto_start_check: _auto_start_check.disabled = false
	if _auto_restart_check: _auto_restart_check.disabled = false
	if _allow_writes_check: _allow_writes_check.disabled = false
	_status_label.text = "● Stopping..."
	_status_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2, 1))
	stop_server_requested.emit()

func _set_port_editable(enabled: bool) -> void:
	if _port_spin:
		_port_spin.editable = enabled

func set_server_running(running: bool) -> void:
	_server_running = running
	if running:
		var transport_text = "tcp"
		if _transport_select and _transport_select.selected >= 0 and _transport_select.item_count > 0:
			transport_text = _transport_select.get_item_text(_transport_select.selected)
		var port_val = int(_port_spin.value) if _port_spin else 9091
		_status_label.text = "● Running (" + transport_text + ":" + str(port_val) + ")"
		_status_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.3, 1))
		_start_btn.disabled = true
		_stop_btn.disabled = false
		if _transport_select: _transport_select.disabled = true
		_set_port_editable(false)
		if _auto_start_check: _auto_start_check.disabled = true
		if _auto_restart_check: _auto_restart_check.disabled = true
		if _allow_writes_check: _allow_writes_check.disabled = true
	else:
		_status_label.text = "● Stopped"
		_status_label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3, 1))
		_start_btn.disabled = false
		_stop_btn.disabled = true
		if _transport_select: _transport_select.disabled = false
		_set_port_editable(true)
		if _auto_start_check: _auto_start_check.disabled = false
		if _auto_restart_check: _auto_restart_check.disabled = false
		if _allow_writes_check: _allow_writes_check.disabled = false

func set_status_text(text: String) -> void:
	if _status_label.text.begins_with("● Running") or _status_label.text == "● Stopped":
		return
	_status_label.text = text

func add_log(message: String, is_error: bool = false) -> void:
	var label = Label.new()
	label.text = "[" + Time.get_time_string_from_system(true) + "] " + message
	label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1) if is_error else Color(0.7, 0.8, 0.7, 1))
	label.add_theme_font_size_override("font_size", 10)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_constant_override("margin_left", 4)
	label.add_theme_constant_override("margin_right", 4)
	_log_container.add_child(label)

	call_deferred("_scroll_to_bottom")

func _scroll_to_bottom() -> void:
	_log_scroll.scroll_vertical = _log_scroll.get_v_scroll_bar().max_value

func _on_clear_log() -> void:
	for child in _log_container.get_children():
		child.queue_free()

# ═══════════════════════════════════════════════════════════════
# Test Scenario Section (dynamic checkboxes)
# ═══════════════════════════════════════════════════════════════

func _build_scenario_section() -> void:
	var sep = HSeparator.new()
	add_child(sep)
	var header = Label.new()
	header.text = "Test-Szenarien"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8, 1))
	header.add_theme_constant_override("margin_top", 6)
	header.add_theme_constant_override("margin_left", 4)
	add_child(header)
	var scenarios = _discover_scenarios()
	if scenarios.is_empty():
		var el = Label.new()
		el.text = "  (keine Szenarien gefunden)"
		el.add_theme_font_size_override("font_size", 10)
		el.add_theme_constant_override("margin_left", 8)
		add_child(el)
		return
	for sc in scenarios:
		var check = CheckBox.new()
		check.text = " " + sc.description
		check.tooltip_text = "ID: " + sc.id
		check.add_theme_font_size_override("font_size", 10)
		check.add_theme_constant_override("margin_left", 8)
		check.button_pressed = _is_scenario_enabled(sc.id)
		check.set_meta("scenario_id", sc.id)
		check.toggled.connect(_on_scenario_toggled)
		add_child(check)
		_scenario_checks.append(check)
	var run_btn = Button.new()
	run_btn.text = "Tests ausfuhren"
	run_btn.add_theme_font_size_override("font_size", 10)
	run_btn.add_theme_constant_override("margin_top", 4)
	run_btn.add_theme_constant_override("margin_left", 4)
	run_btn.pressed.connect(_on_run_tests_pressed)
	add_child(run_btn)

func _discover_scenarios() -> Array:
	var result = []
	var da = DirAccess.open(SCENARIO_DIR)
	if not da:
		return result
	da.list_dir_begin()
	var entry = da.get_next()
	while entry != "":
		if entry.ends_with(".tres") and not entry.begins_with("."):
			var path = SCENARIO_DIR + entry
			var res = load(path)
			if res is Resource:
				result.append({
					"id": res.get("id") if "id" in res else entry,
					"description": res.get("description") if "description" in res else entry,
					"scene_path": res.get("scene_path") if "scene_path" in res else "",
				})
		entry = da.get_next()
	da.list_dir_end()
	return result

func _is_scenario_enabled(id: String) -> bool:
	var cfg = ConfigFile.new()
	if cfg.load(TEST_CONFIG_PATH) == OK:
		return cfg.get_value("scenarios", id, true)
	return true

func _on_scenario_toggled(pressed: bool) -> void:
	# Find the checkbox whose new pressed state differs from stored config
	for check in _scenario_checks:
		var id: String = check.get_meta("scenario_id", "")
		if id == "":
			continue
		if check.button_pressed == pressed and _is_scenario_enabled(id) != pressed:
			var cfg = ConfigFile.new()
			cfg.load(TEST_CONFIG_PATH)
			cfg.set_value("scenarios", id, pressed)
			cfg.save(TEST_CONFIG_PATH)
			return

func _on_run_tests_pressed() -> void:
	add_log("Live-MCP tests require the game to be running in a visible window. Start the game with -- --mcp and connect via TCP.", false)
