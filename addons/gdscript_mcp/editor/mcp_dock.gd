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
## Spielstart über das Plugin: Das Spiel läuft IN-PROCESS im Editor
## (play_main_scene), der Runtime-MCP-Server des Plugins lauscht auf 9090.
signal runtime_launch_requested(profile: String)

const RUNTIME_CLIENT_PATH := "res://addons/gdscript_mcp/editor/mcp_runtime_client.gd"
const PROFILE_CONFIG_PATH := "user://gdscript_mcp_profile.cfg"
const RUNTIME_PORT := 9090
const AUTO_CONNECT_TIMEOUT_MS := 8000
const AUTO_CONNECT_RETRY_SECONDS := 0.35

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
@onready var _agent_goal_label: Label = %AgentGoalLabel
@onready var _agent_stats_label: Label = %AgentStatsLabel
@onready var _tool_feed: RichTextLabel = %ToolFeed
@onready var _evidence_label: Label = %EvidenceLabel
@onready var _event_feed: Label = %EventFeed

var _server_running = false
var _runtime_client: RefCounted = null
var _runtime_connected := false
var _status_accumulator := 0.0
var _auto_connect_in := -1.0
var _auto_connect_deadline_ms := 0
var _auto_connect_attempts := 0
var _pipeline_accumulator := 0.0

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

	# OptionButton-Items idempotent per Code befüllen: Die `items`-Zeile der
	# .tscn wird von Godot 4 nur als Array[Dictionary] rekonstruiert; ein
	# String-Array (alter Dock-Umbau) lädt zu item_count == 0 → leere
	# Dropdowns ohne Transport-Auswahl und Play-Goal.
	if _transport_select != null and _transport_select.item_count == 0:
		_transport_select.add_item("stdio")
		_transport_select.add_item("tcp")
	if _profile_select != null and _profile_select.item_count == 0:
		_profile_select.add_item("player")
		_profile_select.add_item("qa")
		_profile_select.add_item("dev")

	_load_config()
	_load_profile()
	_update_runtime_buttons()
	# Runtime-MCP startet im SPIELprozess (McpRuntime-Autoload + MCP_EMBEDDED
	# beim Editor-Play). Der Dock verbindet sich automatisch, sobald das Spiel
	# läuft — bis dahin wird höflich mit Retry probiert (honest: gelb).
	_auto_connect_in = 0.0
	_auto_connect_deadline_ms = Time.get_ticks_msec() + AUTO_CONNECT_TIMEOUT_MS
	_auto_connect_attempts = 0
	set_process(true)

func _process(_delta: float) -> void:
	if _runtime_client != null:
		_runtime_client.poll()
		_status_accumulator += _delta
		if _runtime_client.is_ready() and _status_accumulator >= 1.0:
			_status_accumulator = 0.0
			_refresh_runtime_status()
			_pipeline_accumulator += 1.0
			if _pipeline_accumulator >= 2.0:
				_pipeline_accumulator = 0.0
				_refresh_agent_pipeline()
	if _auto_connect_in >= 0.0:
		if _auto_connect_deadline_ms > 0 and Time.get_ticks_msec() >= _auto_connect_deadline_ms:
			_auto_connect_in = -1.0
			add_log("Runtime-MCP nach begrenzten Verbindungsversuchen nicht erreichbar", true)
		elif _auto_connect_in > 0.0:
			_auto_connect_in -= _delta
		elif _runtime_client == null or not _runtime_client.is_ready():
			_connect_runtime()
			_auto_connect_attempts += 1
			_auto_connect_in = AUTO_CONNECT_RETRY_SECONDS

# Hinweis: Sobald _runtime_client.is_ready() true ist, wird alle 1 s der Status
# und alle 2 s die Agent-Pipeline aktualisiert — echte Live-Daten aus dem
# Runtime-MCP-Server, keine statischen Platzhalter. Wenn der Server keine
# Agent-Aktivität registriert hat, antwortet `runtime_agent_activity` mit
# {entries:[]} und der Dock zeigt "— keine Tool-Calls sichtbar —". Das ist
# ein ehrlicher Live-Zustand, kein Mock.

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
	if _runtime_client != null:
		_runtime_client.close()
		_runtime_client = null
		_runtime_connected = false
		_update_runtime_buttons()
	var profile := "player"
	if _profile_select != null and _profile_select.selected >= 0 and _profile_select.item_count > 0:
		profile = _profile_select.get_item_text(_profile_select.selected).to_lower()
	runtime_launch_requested.emit(profile)
	_auto_connect_in = 0.2
	_auto_connect_deadline_ms = Time.get_ticks_msec() + AUTO_CONNECT_TIMEOUT_MS
	_auto_connect_attempts = 0

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
	if connected:
		_auto_connect_in = -1.0
		_auto_connect_deadline_ms = 0
		add_log("Persistente MCP-Verbindung aktiv (ein Handshake, jeder Call = genau eine Aktion)")
		_update_runtime_buttons()
		_refresh_runtime_status()
	else:
		_runtime_status_label.text = "○ nicht verbunden"
		_runtime_status_label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4, 1))
		_update_runtime_buttons()
		# Der Runtime-Server kann sich neu starten (Profilwechsel). Dann
		# verbindet der Dock automatisch neu, solange ein Spielstart aktiv war.
		if _auto_connect_deadline_ms > 0 or _auto_connect_attempts > 0:
			_auto_connect_in = AUTO_CONNECT_RETRY_SECONDS

func _on_runtime_error(message: String) -> void:
	add_log("Runtime: " + message, true)
	if _auto_connect_deadline_ms > 0 and not _runtime_connected:
		_auto_connect_in = AUTO_CONNECT_RETRY_SECONDS

func _update_runtime_buttons() -> void:
	var ready: bool = _runtime_client != null and bool(_runtime_client.call("is_ready"))
	_disconnect_btn.disabled = not _runtime_connected
	# Pipeline-Anzeige startet sofort, sobald verbunden.
	if ready and _runtime_connected:
		_refresh_agent_pipeline()

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
	# Echte Live-Werte: renderer + clients zeigen, ob der Server tatsächlich
	# im Spiel-Kontext läuft. Im Editor-In-Process ohne Spiel ist renderer
	# trotzdem "visible" — aber game_running=false ist wichtig für den User.
	if data.has("client_count"):
		parts.append("clients=" + str(data.get("client_count", 0)))
	var last_tool: Variant = data.get("last_tool", {})
	if last_tool is Dictionary:
		parts.append("last=" + str(last_tool.get("name", "?")) + " " + str(snappedf(float(last_tool.get("latency_ms", 0.0)), 0.1)) + "ms")
	parts.append("avg=" + str(snappedf(float(data.get("tool_latency_avg_ms", 0.0)), 0.1)) + "ms")
	var max_dict: Variant = data.get("max", {})
	if max_dict is Dictionary:
		parts.append("max=" + str(snappedf(float((max_dict as Dictionary).get("latency_ms", 0.0)), 0.1)) + "ms")
	_runtime_status_label.text = "● " + " · ".join(parts)
	# Farbcodierung: grün nur bei LAUFENDEM SPIEL (game_running), gelb wenn der
	# Server lebt aber das Spiel nicht offen ist (Dock-Verbindung steht, Tools
	# blockiert mit "Game not running"). game_running ist die echte Quelle —
	# renderer ist im Editor-In-Process auch ohne Spiel "visible".
	var is_live := bool(data.get("game_running", false)) and int(data.get("tool_count", 0)) > 0
	_runtime_status_label.add_theme_color_override("font_color",
		Color(0.2, 0.8, 0.3, 1) if is_live else Color(0.9, 0.7, 0.2, 1))
	if not is_live:
		_runtime_status_label.tooltip_text = "Server läuft, aber kein Spiel offen. Starte ein Spiel über ▶ Spiel starten +MCP."

# ═══════════════════════════════════════════════════════════════════════════
# Runtime: sichtbare Aktionen
# ═══════════════════════════════════════════════════════════════════════════

## Pipeline-Refresh: Agent-Ziel, Tool-Call-Feed, OCR-Evidence, Events.
func _refresh_agent_pipeline() -> void:
	_call_runtime("runtime_agent_activity", {"limit": 14}, _on_activity_response)
	_call_runtime("runtime_visual_evidence", {"wait_ms": 0}, _on_evidence_response)
	_call_runtime("runtime_mcp_events", {"cursor": 0, "limit": 8}, _on_events_response)


func _on_activity_response(response: Dictionary) -> void:
	var data := _extract_result(response)
	if data == null:
		return
	var goal := str(data.get("goal", ""))
	_agent_goal_label.text = "🎯 Ziel: " + (goal if goal != "" else "—")
	_agent_goal_label.tooltip_text = goal
	var entries: Array = data.get("entries", []) as Array
	var total_calls := int(data.get("total_calls", entries.size()))
	var ok_count := 0
	var err_count := 0
	for entry in entries:
		if entry is Dictionary:
			if bool(entry.get("ok", false)):
				ok_count += 1
			else:
				err_count += 1
	var parts := PackedStringArray()
	parts.append("Calls: " + str(total_calls))
	parts.append("ok: " + str(ok_count))
	parts.append("Fehler: " + str(err_count))
	_agent_stats_label.text = " · ".join(parts)
	var bb := ""
	if entries.is_empty():
		# Leerer Feed ≠ Platzhalter: ehrliches Live-Signal "noch nichts passiert".
		# Der User weiß jetzt, dass er einen Agenten braucht (oder selbst Tools
		# über die Bridge callen muss), damit hier etwas erscheint.
		if total_calls == 0:
			bb = "[color=#9a9aa5]⏳ Warte auf Agent-Aktivität …\n(MCP-Bridge starten oder Vision-Worker attachen)[/color]"
		else:
			bb = "[color=#9a9aa5]— keine Tool-Calls sichtbar —[/color]"
	else:
		var lines := PackedStringArray()
		for entry in entries.slice(-10):
			if not (entry is Dictionary):
				continue
			var label := str(entry.get("label", "?"))
			var dur := float(entry.get("duration_ms", 0.0))
			var ok := bool(entry.get("ok", false))
			var err := str(entry.get("error", ""))
			var color := "#4caf50" if ok else "#e57373"
			var icon := "✓" if ok else "✗"
			var line := "[color=" + color + "]" + icon + "[/color] " + label
			line += " [color=#8a8a95]" + str(snappedf(dur, 0.1)) + "ms[/color]"
			if err != "":
				line += " [color=#e57373]" + err.substr(0, 60) + "[/color]"
			lines.append(line)
		bb = "\n".join(lines)
	_tool_feed.text = bb


func _on_evidence_response(response: Dictionary) -> void:
	var data := _extract_result(response)
	if data == null:
		return
	var status := str(data.get("status", "none"))
	if status == "none":
		_evidence_label.text = "— kein Screenshot/OCR ausgewertet —"
		return
	var evidence: Dictionary = data.get("evidence", {})
	var ocr: Dictionary = evidence.get("ocr", {}) if evidence.get("ocr") is Dictionary else {}
	var shot: Dictionary = evidence.get("screenshot", {}) if evidence.get("screenshot") is Dictionary else {}
	var ocr_text := str(ocr.get("text", ""))
	var conf := float(ocr.get("confidence", 0.0))
	var text := "🖼 " + str(shot.get("width", "?")) + "×" + str(shot.get("height", "?"))
	if status == "pending":
		text += " · Analyse läuft …"
	elif ocr_text != "":
		text += " · OCR: „" + ocr_text.substr(0, 140) + "…\" (conf " + str(snappedf(conf, 1)) + ")"
	else:
		text += " · OCR: n/a"
	_evidence_label.text = text
	_evidence_label.tooltip_text = ocr_text


func _on_events_response(response: Dictionary) -> void:
	var data := _extract_result(response)
	if data == null:
		return
	var entries: Array = data.get("entries", []) as Array
	if entries.is_empty():
		_event_feed.text = "Events: —"
		return
	var lines := PackedStringArray()
	for entry in entries.slice(-5):
		if entry is Dictionary:
			lines.append(str(entry.get("type", "?")) + ": " + str(entry.get("message", "")))
	_event_feed.text = "Events: " + " | ".join(lines)


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