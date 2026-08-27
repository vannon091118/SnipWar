@tool
extends VBoxContainer
class_name McpDock

## QA-Live-Dock: Ein Knopf (Spiel starten +MCP), eine Live-Pipeline.
## Der Editor-Server (9091) startet automatisch im Plugin — hier gibt es
## nichts mehr zu konfigurieren. Alles in diesem Dock ist Live-Anzeige:
## Verbindungszustand, Agent-Pipeline (Calls ok/Fehler), letzter Frame
## als Bild, OCR-Zeile, Events, Log.
## Play-Goal (player/qa/dev) wählt den Spieler-Vertrag vor dem Spielstart
## (siehe PLAYTEST_HANDOFF.md).

## Spielstart über das Plugin: play_main_scene startet das Spiel als
## separaten Prozess; der Runtime-MCP-Server bootet im Spiel-SceneTree
## (MCP_EMBEDDED-Env). Der Dock verbindet sich automatisch auf 9090.
signal runtime_launch_requested(profile: String)

const RUNTIME_CLIENT_PATH := "res://addons/gdscript_mcp/editor/mcp_runtime_client.gd"
const PROFILE_CONFIG_PATH := "user://gdscript_mcp_profile.cfg"
const RUNTIME_PORT := 9090
const AUTO_CONNECT_RETRY_SECONDS := 0.35
## Context-Roots, in denen der Runtime-Server Screenshots ablegt
## (<context_id>.png) — die Kachel probiert sie in dieser Reihenfolge.
const EVIDENCE_ROOTS: Array[String] = [
	"user://mcp_context/runtime",
	"user://mcp_context",
]

@onready var _status_label: Label = %StatusIndicator
@onready var _clear_log_btn: Button = %ClearLogBtn
@onready var _log_container: VBoxContainer = %LogContainer
@onready var _log_scroll: ScrollContainer = %LogScroll

@onready var _profile_select: OptionButton = %ProfileSelect
@onready var _launch_btn: Button = %LaunchGameBtn
@onready var _disconnect_btn: Button = %DisconnectRuntimeBtn
@onready var _goal_input: LineEdit = %GoalInput
@onready var _goal_set_btn: Button = %GoalSetBtn
@onready var _contract_run_btn: Button = %ContractRunBtn
@onready var _runtime_status_label: Label = %RuntimeStatus
@onready var _agent_goal_label: Label = %AgentGoalLabel
@onready var _agent_stats_label: Label = %AgentStatsLabel
@onready var _tool_feed: RichTextLabel = %ToolFeed
@onready var _evidence_image: TextureRect = %EvidenceImage
@onready var _evidence_label: Label = %EvidenceLabel
@onready var _event_feed: Label = %EventFeed

var _runtime_client: RefCounted = null
var _runtime_connected := false
var _status_accumulator := 0.0
var _auto_connect_in := -1.0
var _auto_connect_attempts := 0
var _pipeline_accumulator := 0.0
var _last_evidence_path := ""
var _log_cursor := 0
var _contract_running := false


func _ready() -> void:
	_clear_log_btn.pressed.connect(_on_clear_log)
	_launch_btn.pressed.connect(_launch_runtime_game)
	_disconnect_btn.pressed.connect(_disconnect_runtime)
	_profile_select.item_selected.connect(_on_profile_selected)
	_goal_set_btn.pressed.connect(_on_goal_set_pressed)
	_goal_input.text_submitted.connect(func(_t: String): _on_goal_set_pressed())
	_contract_run_btn.pressed.connect(_on_contract_run_pressed)

	# OptionButton-Items idempotent per Code befüllen: Die `items`-Zeile der
	# .tscn wird von Godot 4 nur als Array[Dictionary] rekonstruiert; ein
	# String-Array (alter Dock-Umbau) lädt zu item_count == 0 → leere
	# Dropdowns ohne Play-Goal-Auswahl.
	if _profile_select != null and _profile_select.item_count == 0:
		_profile_select.add_item("player")
		_profile_select.add_item("qa")
		_profile_select.add_item("dev")

	_load_profile()
	_update_runtime_buttons()
	# Runtime-MCP startet im SPIELprozess (McpRuntime-Autoload + MCP_EMBEDDED
	# beim Editor-Play). Der Dock verbindet sich dauerhaft automatisch, sobald
	# ein Spiel läuft — kein Timeout, kein manueller Verbinden-Knopf.
	_auto_connect_in = 0.0
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
		if _auto_connect_in > 0.0:
			_auto_connect_in -= _delta
		elif _runtime_client == null or not _runtime_client.is_ready():
			_connect_runtime()
			_auto_connect_attempts += 1
			if _auto_connect_attempts == 6:
				add_log("Kein Runtime-MCP auf 9090 — Retry läuft im Hintergrund, bis ein Spiel startet")
			_auto_connect_in = AUTO_CONNECT_RETRY_SECONDS if _auto_connect_attempts < 12 else 3.0

# Sobald _runtime_client.is_ready() true ist, wird alle 1 s der Status und
# alle 2 s die Agent-Pipeline aktualisiert — echte Live-Daten aus dem
# Runtime-MCP-Server, keine statischen Platzhalter.

# ═══════════════════════════════════════════════════════════════════════════
# Profil / Play-Goal
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
		add_log("Persistente MCP-Verbindung aktiv (ein Handshake, jeder Call = genau eine Aktion)")
		_status_label.text = "● Spiel live (9090)"
		_status_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.3, 1))
		_update_runtime_buttons()
		_refresh_runtime_status()
	else:
		_runtime_status_label.text = "○ nicht verbunden"
		_runtime_status_label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4, 1))
		_status_label.text = "○ Spiel offline — ▶ starten"
		_status_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2, 1))
		_update_runtime_buttons()
		# Der Runtime-Server kann sich neu starten (Profilwechsel): Der
		# dauerhafte Auto-Connect verbindet automatisch neu.
		if _auto_connect_in < 0.0:
			_auto_connect_in = AUTO_CONNECT_RETRY_SECONDS

func _on_runtime_error(message: String) -> void:
	if _auto_connect_attempts == 1:
		add_log("Runtime: " + message, true)
	if not _runtime_connected and _auto_connect_in < 0.0:
		_auto_connect_in = AUTO_CONNECT_RETRY_SECONDS

func _update_runtime_buttons() -> void:
	_disconnect_btn.disabled = not _runtime_connected
	_contract_run_btn.disabled = not (_runtime_client != null and _runtime_connected and bool(_runtime_client.call("is_ready")))
	# Pipeline-Anzeige startet sofort, sobald verbunden.
	if _runtime_client != null and _runtime_connected and bool(_runtime_client.call("is_ready")):
		_refresh_agent_pipeline()

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
	parts.append("profil=" + str(data.get("profile", "?")))
	parts.append("tools=" + str(data.get("tool_count", "?")))
	parts.append("clients=" + str(data.get("client_count", 0)))
	var last_tool: Variant = data.get("last_tool", {})
	if last_tool is Dictionary:
		parts.append("last=" + str((last_tool as Dictionary).get("name", "?")) + " " + str(snappedf(float((last_tool as Dictionary).get("latency_ms", 0.0)), 0.1)) + "ms")
	parts.append("avg=" + str(snappedf(float(data.get("tool_latency_avg_ms", 0.0)), 0.1)) + "ms")
	_runtime_status_label.text = "● " + " · ".join(parts)
	# Farbcodierung: grün nur bei LAUFENDEM SPIEL (game_running), gelb, wenn
	# der Server lebt, aber das Spiel nicht offen ist.
	var is_live := bool(data.get("game_running", false)) and int(data.get("tool_count", 0)) > 0
	_runtime_status_label.add_theme_color_override("font_color",
		Color(0.2, 0.8, 0.3, 1) if is_live else Color(0.9, 0.7, 0.2, 1))
	if not is_live:
		_runtime_status_label.tooltip_text = "Server läuft, aber kein Spiel offen. Starte ein Spiel über ▶ Spiel starten +MCP."

# ═══════════════════════════════════════════════════════════════════════════
# Agent-Pipeline (live)
# ═══════════════════════════════════════════════════════════════════════════

## Pipeline-Refresh: Agent-Ziel, Tool-Call-Feed, OCR-Evidence, Events.
func _refresh_agent_pipeline() -> void:
	_call_runtime("runtime_agent_activity", {"limit": 14}, _on_activity_response)
	# Server-Session-Log live (Cursor-inkrementell) — der Log-Bereich im Dock
	# bleibt nicht mehr stehen, sobald der Server läuft.
	_call_runtime("editor_logs_read", {"cursor": _log_cursor, "limit": 40, "include_file": false}, _on_logs_response)
	# capture:true — der Dock befüllt den Evidence-Cache selbst (Screenshot +
	# OCR im Hintergrund des Spiels), damit die Bild-Kachel live läuft.
	_call_runtime("runtime_visual_evidence", {"wait_ms": 0, "capture": true}, _on_evidence_response)
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
		text += " · OCR: „" + ocr_text.substr(0, 140) + "“ (conf " + str(snappedf(conf, 1)) + ")"
	else:
		text += " · OCR: n/a"
	_evidence_label.text = text
	_evidence_label.tooltip_text = ocr_text
	_update_evidence_image(str(shot.get("context_id", "")))

## Lädt den letzten Frame als Bild in die Kachel: <context_id>.png im
## Context-Root des Runtime-Servers (persist_context=true legt das ab).
func _update_evidence_image(context_id: String) -> void:
	if context_id == "":
		_evidence_image.texture = null
		return
	for root in EVIDENCE_ROOTS:
		var path := ProjectSettings.globalize_path(root.path_join(context_id + ".png"))
		if FileAccess.file_exists(path):
			if path == _last_evidence_path and _evidence_image.texture != null:
				return
			var image := Image.load_from_file(path)
			if image != null:
				_evidence_image.texture = ImageTexture.create_from_image(image)
				_last_evidence_path = path
			return
	_evidence_image.texture = null


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


## Server-Session-Log live in den Dock-Log-Bereich (Cursor-inkrementell).
func _on_logs_response(response: Dictionary) -> void:
	var data := _extract_result(response)
	if data == null:
		return
	var entries: Array = data.get("entries", []) as Array
	for entry in entries:
		if entry is Dictionary:
			var level := str(entry.get("level", entry.get("type", "info")))
			add_log("[mcp] " + str(entry.get("message", "")), level == "error")
	_log_cursor = int(data.get("next_cursor", _log_cursor))


## Ziel-Vertrag: Der User gibt das Ziel IM Dock vor (runtime_agent_goal_set).
func _on_goal_set_pressed() -> void:
	if _runtime_client == null or not _runtime_client.is_ready():
		add_log("Nicht verbunden — Ziel kann erst nach dem Spielstart gesetzt werden", true)
		return
	var goal := _goal_input.text.strip_edges()
	if goal == "":
		add_log("Ziel ist leer — nichts zu setzen", true)
		return
	_goal_set_btn.disabled = true
	_call_runtime("runtime_agent_goal_set", {"goal": goal}, _on_goal_set_response)

func _on_goal_set_response(response: Dictionary) -> void:
	_goal_set_btn.disabled = false
	var data := _extract_result(response)
	if data == null:
		return
	add_log("Ziel gesetzt: " + str(data.get("goal", "?")))

## Vertrags-Run aus dem Dock (in-engine QA): Die versionierte Chain läuft
## gegen das echte Spiel; PASS gibt es nur bei echtem Durchlauf (fail-closed).
func _on_contract_run_pressed() -> void:
	if _contract_running:
		return
	if _runtime_client == null or not _runtime_client.is_ready():
		add_log("Nicht verbunden — Vertrags-Run braucht ein laufendes Spiel", true)
		return
	_contract_running = true
	_contract_run_btn.disabled = true
	add_log("Vertrags-Run gestartet (chain world_smoke) …")
	_call_runtime("runtime_chain_run", {"chain_id": "world_smoke"}, _on_contract_run_response)

func _on_contract_run_response(response: Dictionary) -> void:
	_contract_running = false
	_contract_run_btn.disabled = false
	var data := _extract_result(response)
	if data == null:
		return
	var failed_step := int(data.get("failed_step", -1))
	var verdict := "PASS"
	if failed_step >= 0:
		verdict = "FAIL@%d (%s)" % [failed_step, str(data.get("failure_reason", ""))]
	var step_count: int = (data.get("steps", []) as Array).size()
	add_log("Vertrags-Run '" + str(data.get("chain_id", "?")) + "': " + verdict +
		" — " + str(data.get("completed_steps", 0)) + "/" + str(step_count) + " Steps in " +
		str(data.get("duration_ms", 0)) + "ms", failed_step >= 0)

# ═══════════════════════════════════════════════════════════════════════════
# Call-Helfer
# ═══════════════════════════════════════════════════════════════════════════

func _call_runtime(tool_name: String, args: Dictionary, callback: Callable) -> void:
	if _runtime_client == null or not _runtime_client.is_ready():
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

# ═══════════════════════════════════════════════════════════════════════════
# Log
# ═══════════════════════════════════════════════════════════════════════════

func add_log(message: String, is_error: bool = false) -> void:
	var label = Label.new()
	label.text = "[" + Time.get_time_string_from_system(true) + "] " + message
	label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1) if is_error else Color(0.7, 0.8, 0.7, 1))
	label.add_theme_font_size_override("font_size", 10)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_log_container.add_child(label)
	call_deferred("_scroll_to_bottom")

func _scroll_to_bottom() -> void:
	_log_scroll.scroll_vertical = _log_scroll.get_v_scroll_bar().max_value

func _on_clear_log() -> void:
	for child in _log_container.get_children():
		child.queue_free()
