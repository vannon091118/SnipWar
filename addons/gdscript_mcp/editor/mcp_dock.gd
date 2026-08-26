@tool
extends VBoxContainer
class_name McpDock

## UI Dock for GDScript MCP Bridge — zwei Sessions nebeneinander:
##   ✏️ Editor (9091):   Editor-Server (Start/Stop/Config) in-process.
##   🎮 Runtime (9090):  das laufende Spiel. Persistenter TCP-Client (ein
##                       Handshake, dann genau ein tools/call pro Aktion) mit
##                       sichtbaren Aktionen: Spiel starten, verbinden,
##                       UI-Scan, Screenshot, Maus/Klick/Taste, Freeze/Step,
##                       E2E-Szenarien direkt im laufenden Spiel.
## Das Play-Goal (player/qa/dev) wählt, welcher Spieler-Vertrag gilt
## (siehe PLAYTEST_HANDOFF.md) und wird vor dem Spielstart geschrieben.

signal start_server_requested(config: Dictionary)
signal stop_server_requested()
signal config_changed(config: Dictionary)

const RUNTIME_CLIENT_PATH := "res://addons/gdscript_mcp/editor/mcp_runtime_client.gd"
const PROFILE_CONFIG_PATH := "user://gdscript_mcp_profile.cfg"
const RUNTIME_PORT := 9090

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

# Runtime (Spiel) section
@onready var _profile_select: OptionButton = %ProfileSelect
@onready var _launch_btn: Button = %LaunchGameBtn
@onready var _connect_btn: Button = %ConnectRuntimeBtn
@onready var _disconnect_btn: Button = %DisconnectRuntimeBtn
@onready var _open_artifacts_btn: Button = %OpenArtifactsBtn
@onready var _runtime_status_label: Label = %RuntimeStatus
@onready var _click_x_spin: SpinBox = %ClickXSpin
@onready var _click_y_spin: SpinBox = %ClickYSpin
@onready var _mouse_move_btn: Button = %MouseMoveBtn
@onready var _click_btn: Button = %ClickBtn
@onready var _key_edit: LineEdit = %KeyEdit
@onready var _key_btn: Button = %KeyBtn
@onready var _scan_btn: Button = %UIScanBtn
@onready var _shot_btn: Button = %ScreenshotBtn
@onready var _freeze_btn: Button = %FreezeBtn
@onready var _step_btn: Button = %StepBtn
@onready var _unfreeze_btn: Button = %UnfreezeBtn
@onready var _e2e_refresh_btn: Button = %E2ERefreshBtn
@onready var _e2e_container: VBoxContainer = %E2EContainer
@onready var _e2e_run_btn: Button = %E2ERunBtn

var _server_running = false
var _runtime_client: RefCounted = null
var _runtime_connected := false
var _status_accumulator := 0.0
var _auto_connect_in := -1.0
var _last_artifact_path := ""
var _e2e_scenarios: Array = []
var _e2e_checks: Array = []

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

	_launch_btn.pressed.connect(_launch_runtime_game)
	_connect_btn.pressed.connect(_connect_runtime)
	_disconnect_btn.pressed.connect(_disconnect_runtime)
	_open_artifacts_btn.pressed.connect(_open_artifacts_folder)
	_profile_select.item_selected.connect(_on_profile_selected)
	_mouse_move_btn.pressed.connect(_on_runtime_mouse_move)
	_click_btn.pressed.connect(_on_runtime_click)
	_key_btn.pressed.connect(_on_runtime_key)
	_scan_btn.pressed.connect(_on_runtime_scan)
	_shot_btn.pressed.connect(_on_runtime_screenshot)
	_freeze_btn.pressed.connect(_on_runtime_freeze)
	_step_btn.pressed.connect(_on_runtime_step)
	_unfreeze_btn.pressed.connect(_on_runtime_unfreeze)
	_e2e_refresh_btn.pressed.connect(_refresh_e2e_list)
	_e2e_run_btn.pressed.connect(_run_selected_e2e)
	_key_edit.text_submitted.connect(func(_text): _on_runtime_key())

	_load_config()
	_load_profile()
	_update_runtime_buttons()
	set_process(true)

func _process(_delta: float) -> void:
	if _runtime_client != null:
		_runtime_client.poll()
		_status_accumulator += _delta
		if _runtime_client.is_ready() and _status_accumulator >= 1.0:
			_status_accumulator = 0.0
			_refresh_runtime_status()
	if _auto_connect_in > 0.0:
		_auto_connect_in -= _delta
		if _auto_connect_in <= 0.0:
			_connect_runtime()

# ═══════════════════════════════════════════════════════════════════════════
# Profile / Play-Goal
# ═══════════════════════════════════════════════════════════════════════════

func _load_profile() -> void:
	if _profile_select == null or _profile_select.item_count == 0:
		return
	var file := ConfigFile.new()
	var stored := "player"
	if file.load(PROFILE_CONFIG_PATH) == OK:
		stored = str(file.get_value("profile", "name", "player")).to_lower()
	for i in range(_profile_select.item_count):
		if _profile_select.get_item_text(i).to_lower() == stored:
			_profile_select.selected = i
			return

func _on_profile_selected(index: int) -> void:
	if _profile_select == null:
		return
	var profile := _profile_select.get_item_text(index).to_lower()
	var file := ConfigFile.new()
	file.set_value("profile", "name", profile)
	file.save(PROFILE_CONFIG_PATH)
	var note := "Play-Goal-Profil '" + profile + "' gespeichert"
	if _runtime_connected:
		note += " — wirkt beim nächsten Spielstart (Runtime-Profil wird beim Boot gelesen)"
	add_log(note)

# ═══════════════════════════════════════════════════════════════════════════
# Runtime: Spiel starten / verbinden
# ═══════════════════════════════════════════════════════════════════════════

func _launch_runtime_game() -> void:
	var exec_path := OS.get_executable_path()
	if exec_path == "":
		add_log("Godot binary path nicht verfügbar", true)
		return
	var project_dir := ProjectSettings.globalize_path("res://")
	var args := PackedStringArray(["--path", project_dir, "--", "--mcp", "--mcp-port", str(RUNTIME_PORT), "--mcp-virtual-mouse"])
	var pid := OS.create_process(exec_path, args, false)
	if pid <= 0:
		add_log("Spielstart fehlgeschlagen (pid=" + str(pid) + ")", true)
		return
	add_log("Spiel sichtbar gestartet (pid=" + str(pid) + ") mit --mcp auf Port " + str(RUNTIME_PORT) + " — verbinde in 2.5 s …")
	_auto_connect_in = 2.5

func _connect_runtime() -> void:
	if _runtime_client != null:
		_disconnect_runtime()
	var script: Resource = load(RUNTIME_CLIENT_PATH)
	if script == null:
		add_log("Runtime-Client-Skript nicht gefunden", true)
		return
	_runtime_client = script.new()
	_runtime_client.connect_to("127.0.0.1", RUNTIME_PORT)
	_add_runtime_signal_handlers()
	add_log("Verbinde zu 127.0.0.1:" + str(RUNTIME_PORT) + " …")

func _disconnect_runtime() -> void:
	if _runtime_client != null:
		_runtime_client.close()
	_runtime_client = null
	_runtime_connected = false
	_runtime_status_label.text = "○ nicht verbunden"
	_runtime_status_label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4, 1))
	_update_runtime_buttons()
	add_log("Runtime-Trennung")

func _add_runtime_signal_handlers() -> void:
	if _runtime_client == null:
		return
	_runtime_client.connect("connected_changed", Callable(self, "_on_runtime_connected_changed"))
	_runtime_client.connect("error_occurred", Callable(self, "_on_runtime_error"))

func _on_runtime_connected_changed(connected: bool) -> void:
	_runtime_connected = connected
	_update_runtime_buttons()
	if connected:
		add_log("Persistente MCP-Verbindung aktiv (ein Handshake, jeder Call = genau eine Aktion)")
		_refresh_runtime_status()
	else:
		_runtime_status_label.text = "○ nicht verbunden"
		_runtime_status_label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4, 1))

func _on_runtime_error(message: String) -> void:
	add_log("Runtime: " + message, true)

func _update_runtime_buttons() -> void:
	var ready: bool = _runtime_client != null and bool(_runtime_client.call("is_ready"))
	_scan_btn.disabled = not ready
	_shot_btn.disabled = not ready
	_mouse_move_btn.disabled = not ready
	_click_btn.disabled = not ready
	_key_btn.disabled = not ready
	_freeze_btn.disabled = not ready
	_step_btn.disabled = not ready
	_unfreeze_btn.disabled = not ready
	_e2e_refresh_btn.disabled = not ready
	_e2e_run_btn.disabled = not ready
	_disconnect_btn.disabled = not _runtime_connected

func _open_artifacts_folder() -> void:
	var dir := ProjectSettings.globalize_path("user://mcp_context")
	DirAccess.make_dir_recursive_absolute(dir)
	OS.shell_open(dir)
	add_log("Artefakt-Ordner geöffnet: " + dir)

# ═══════════════════════════════════════════════════════════════════════════
# Runtime: Live-Status
# ═══════════════════════════════════════════════════════════════════════════

func _refresh_runtime_status() -> void:
	_call_runtime("runtime_mcp_status", {}, _on_status_response)

func _on_status_response(response: Dictionary) -> void:
	var data := _extract_result(response)
	if data == null:
		return
	var parts := PackedStringArray()
	parts.append("state=" + str(data.get("state", "?")))
	parts.append("profile=" + str(data.get("profile", "?")))
	parts.append("tools=" + str(data.get("tool_count", "?")))
	parts.append("violations=" + str(data.get("contract_violations", 0)))
	var last_tool: Variant = data.get("last_tool", {})
	if last_tool is Dictionary:
		parts.append("last=" + str(last_tool.get("name", "?")) + " " + str(snappedf(float(last_tool.get("latency_ms", 0.0)), 0.1)) + "ms")
	parts.append("avg=" + str(snappedf(float(data.get("tool_latency_avg_ms", 0.0)), 0.1)) + "ms")
	if data.has("max") and data.get("max") is Dictionary:
		parts.append("max=" + str(snappedf(float(data.get("max", {}).get("latency_ms", 0.0)), 0.1)) + "ms")
	_runtime_status_label.text = "● " + " · ".join(parts)
	_runtime_status_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.3, 1))

# ═══════════════════════════════════════════════════════════════════════════
# Runtime: sichtbare Aktionen
# ═══════════════════════════════════════════════════════════════════════════

func _on_runtime_mouse_move() -> void:
	var x := int(_click_x_spin.value)
	var y := int(_click_y_spin.value)
	_call_runtime("runtime_mouse_move", {"x": x, "y": y}, func(response): _log_tool_result("runtime_mouse_move", response))

func _on_runtime_click() -> void:
	var x := int(_click_x_spin.value)
	var y := int(_click_y_spin.value)
	_call_runtime("runtime_click", {"x": x, "y": y, "hold_frames": 1}, func(response): _log_tool_result("runtime_click", response))

func _on_runtime_key() -> void:
	var name := _key_edit.text.strip_edges()
	if name == "":
		add_log("Bitte Taste angeben (z.B. P, ESCAPE, SPACE)", true)
		return
	var keycode := _keycode_from_name(name)
	if keycode <= 0:
		add_log("Unbekannte Taste: " + name, true)
		return
	_call_runtime("runtime_key", {"keycode": keycode, "pressed": true}, func(response): _log_tool_result("runtime_key", response))
	_call_runtime("runtime_key", {"keycode": keycode, "pressed": false}, func(response): _log_tool_result("runtime_key release", response))

func _on_runtime_scan() -> void:
	_call_runtime("runtime_ux_scan", {"max_controls": 120}, _on_scan_response)

func _on_scan_response(response: Dictionary) -> void:
	var data := _extract_result(response)
	if data == null:
		return
	var interactables: Array = data.get("interactables", [])
	var texts: Array = []
	for ctrl in interactables:
		if ctrl is Dictionary:
			var text := str(ctrl.get("text", ""))
			if text != "":
				texts.append(text)
	add_log("UI-Scan: scene=" + str(data.get("scene", "?")) + " controls=" + str(data.get("control_count", 0)) +
		" interaktive=" + str(interactables.size()) + " → " + str(texts.slice(0, 8)))

func _on_runtime_screenshot() -> void:
	_call_runtime("runtime_screenshot", {"format": "png"}, _on_screenshot_response)

func _on_screenshot_response(response: Dictionary) -> void:
	var data := _extract_result(response)
	if data == null:
		return
	var context: Variant = data.get("context", {})
	if context is Dictionary:
		_last_artifact_path = str(context.get("absolute_path", ""))
	add_log("Screenshot: " + str(data.get("context_id", "?")) + " @ " + _last_artifact_path +
		" (" + str(data.get("width", "?")) + "×" + str(data.get("height", "?")) + ")")
	_open_artifacts_btn.tooltip_text = _last_artifact_path

func _on_runtime_freeze() -> void:
	_call_runtime("runtime_freeze", {}, func(response): _log_tool_result("runtime_freeze", response))

func _on_runtime_step() -> void:
	_call_runtime("runtime_step_frames", {"count": 5}, func(response): _log_tool_result("runtime_step_frames", response))

func _on_runtime_unfreeze() -> void:
	_call_runtime("runtime_unfreeze", {}, func(response): _log_tool_result("runtime_unfreeze", response))

# ═══════════════════════════════════════════════════════════════════════════
# Runtime: E2E-Szenarien direkt im laufenden Spiel
# ═══════════════════════════════════════════════════════════════════════════

func _refresh_e2e_list() -> void:
	_call_runtime("runtime_e2e_list", {}, _on_e2e_list_response)

func _on_e2e_list_response(response: Dictionary) -> void:
	var data := _extract_result(response)
	if data == null:
		return
	_e2e_scenarios = data.get("scenarios", []) as Array
	for child in _e2e_container.get_children():
		child.queue_free()
	_e2e_checks.clear()
	if _e2e_scenarios.is_empty():
		var none := Label.new()
		none.text = "  (keine Szenarien)"
		none.add_theme_font_size_override("font_size", 10)
		_e2e_container.add_child(none)
		return
	for scenario in _e2e_scenarios:
		var check := CheckBox.new()
		check.text = " " + str(scenario.get("id", "?")) + " — " + str(scenario.get("description", ""))
		check.tooltip_text = "ID: " + str(scenario.get("id", ""))
		check.add_theme_font_size_override("font_size", 10)
		check.add_theme_constant_override("margin_left", 8)
		check.button_pressed = true
		check.set_meta("scenario_id", str(scenario.get("id", "")))
		_e2e_container.add_child(check)
		_e2e_checks.append(check)
	add_log("E2E-Szenarien geladen: " + str(_e2e_scenarios.size()))

func _run_selected_e2e() -> void:
	if not _runtime_connected or _runtime_client == null or not _runtime_client.is_ready():
		add_log("Keine Runtime-Verbindung — Spiel starten und verbinden", true)
		return
	var selected: Array = []
	for check in _e2e_checks:
		if check is CheckBox and (check as CheckBox).button_pressed:
			selected.append(str(check.get_meta("scenario_id", "")))
	if selected.is_empty():
		add_log("Kein Szenario ausgewählt", true)
		return
	for scenario_id in selected:
		add_log("▶ E2E '" + scenario_id + "' läuft sichtbar im Spiel …")
		_call_runtime("runtime_e2e_run", {"scenario_id": scenario_id},
			Callable(self, "_on_e2e_run_response").bind(scenario_id))

func _on_e2e_run_response(scenario_id: String, response: Dictionary) -> void:
	var data := _extract_result(response)
	if data == null:
		add_log("E2E '" + scenario_id + "': kein Ergebnis (Verbindung/Profil?)", true)
		return
	if data.has("error"):
		add_log("E2E '" + scenario_id + "': " + str(data.get("error", "?")) +
			" — ggf. Profil auf QA/Debug stellen (E2E ist kein Spieler-Atom)", true)
		return
	add_log("E2E '" + scenario_id + "' → " + str(data.get("verdict", "?")) +
		" | Schritte=" + str(data.get("steps", []).size()) +
		" | Failures=" + str(data.get("failures", 0)) +
		" | Anomalien=" + str(data.get("anomalies", []).size()) +
		" | " + str(snappedf(float(data.get("elapsed_seconds", 0.0)), 0.1)) + "s",
		str(data.get("verdict", "FAIL")) != "PASS")

# ═══════════════════════════════════════════════════════════════════════════
# Runtime: Call-Helfer
# ═══════════════════════════════════════════════════════════════════════════

func _call_runtime(tool_name: String, args: Dictionary, callback: Callable) -> void:
	if _runtime_client == null or not _runtime_client.is_ready():
		add_log("Runtime nicht verbunden — Spiel starten + Verbinden drücken", true)
		return
	var id: int = _runtime_client.call_tool(tool_name, args, callback)
	if id < 0:
		add_log("Call '" + tool_name + "' konnte nicht gesendet werden", true)

## Extrahiert das Tool-Result-JSON aus einer MCP-Response; null bei Fehler.
func _extract_result(response: Dictionary) -> Variant:
	if response.has("error"):
		var error_info: Dictionary = response.get("error", {})
		add_log("MCP-Fehler: " + str(error_info.get("message", "?")) +
			" (" + str(error_info.get("code", "?")) + ")", true)
		return null
	var result: Variant = response.get("result", {})
	if result is Dictionary and bool((result as Dictionary).get("isError", false)):
		add_log("Tool-Fehler: " + str((result as Dictionary).get("content", [])), true)
		return null
	if not (result is Dictionary):
		add_log("Unerwartetes MCP-Result: " + str(result), true)
		return null
	for content in (result as Dictionary).get("content", []):
		if content is Dictionary and str(content.get("type", "")) == "text":
			var parsed: Variant = JSON.parse_string(str(content.get("text", "")))
			if parsed is Dictionary:
				return parsed
			add_log("Result-Text nicht JSON: " + str(content.get("text", "")).substr(0, 200), true)
			return null
	return {}

func _log_tool_result(tool_name: String, response: Dictionary) -> void:
	var data := _extract_result(response)
	if data == null:
		return
	var keys: Array = []
	for key in data:
		keys.append(str(key))
	if data.has("error"):
		add_log(tool_name + " → " + str(data.get("error", "?")), true)
	else:
		add_log(tool_name + " → ok (" + ", ".join(keys.slice(0, 6)) + ")")

func _keycode_from_name(name: String) -> int:
	var key := name.to_upper()
	if key.length() == 1:
		var char_code := int(key.unicode_at(0))
		if char_code >= 65 and char_code <= 90:
			return char_code
		if char_code >= 48 and char_code <= 57:
			return char_code
	match key:
		"ESCAPE", "ESC": return KEY_ESCAPE
		"ENTER", "RETURN": return KEY_ENTER
		"SPACE": return KEY_SPACE
		"TAB": return KEY_TAB
		"BACKSPACE": return KEY_BACKSPACE
		"DELETE", "DEL": return KEY_DELETE
		"LEFT": return KEY_LEFT
		"RIGHT": return KEY_RIGHT
		"UP": return KEY_UP
		"DOWN": return KEY_DOWN
		"HOME": return KEY_HOME
		"END": return KEY_END
		"PAGEUP": return KEY_PAGEUP
		"PAGEDOWN": return KEY_PAGEDOWN
		"SHIFT": return KEY_SHIFT
		"CTRL", "CONTROL": return KEY_CTRL
		"ALT": return KEY_ALT
	for i in range(1, 13):
		if key == "F" + str(i):
			return KEY_F1 + i - 1
	return 0

# ═══════════════════════════════════════════════════════════════════════════
# Editor-Server Config (unverändert)
# ═══════════════════════════════════════════════════════════════════════════

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