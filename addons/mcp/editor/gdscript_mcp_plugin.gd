@tool
extends EditorPlugin
class_name GDScriptMcpPlugin

## GDScript MCP Bridge — Editor Plugin (schlank).
## Der Editor hostet KEINEN MCP-Server mehr. Es gibt genau EINEN Server:
## den Runtime-MCP im Spiel-SceneTree (McpRuntime-Autoload + MCP_EMBEDDED-Env
## beim Spielstart, Port 9090). Das Plugin macht nur drei Dinge:
##   1. Registriert Autoloads/MCP-Settings im Projekt (idempotent).
##   2. Bietet den QA-Live-Dock an (Spiel starten, Live-Pipeline).
##   3. Startet das Spiel als separaten Prozess und wartet auf den Handshake.

const RUNTIME_CLIENT_SCRIPT = "res://addons/gdscript_mcp/editor/mcp_runtime_client.gd"

const RUNTIME_PORT := 9090

# Embedded-Runtime (OFFEN-1 gelöst): Der Runtime-MCP-Server wird NICHT vom
# Plugin im Editor-Prozess gehostet (der Editor-Kind-Server konnte die
# Scene-Tools nie auf den Spielbaum richten — Engine.get_main_loop() lieferte
# den Editor-Tree; zudem startet play_main_scene das Spiel in Godot 4 als
# SEPARATEN Prozess). Stattdessen setzt das Plugin Env-Flags und startet das
# Spiel; der McpRuntime-Autoload bootet den Server im Kind-Prozess (echter
# Spiel-SceneTree). Das Plugin wartet auf den Handshake des Spiel-Servers.
const EMBEDDED_ENV := "MCP_EMBEDDED"
const EMBEDDED_PORT_ENV := "MCP_EMBEDDED_PORT"
const EMBEDDED_PROFILE_ENV := "MCP_EMBEDDED_PROFILE"
const EMBEDDED_WRITES_ENV := "MCP_EMBEDDED_WRITES"

# ─── Projektagnostische Auto-Registrierung ───────────────────────
# Beim Aktivieren des Plugins (Project Settings → Plugins) richtet sich
# dieses Addon selbst im aktuellen Projekt ein: die für den Runtime-MCP
# nötigen Autoloads und die application/mcp/*-Settings werden ergänzt, falls
# sie fehlen. Keine manuelle project.godot-Editierung nötig.
#
# Die Autoloads sind inert ohne den Game-Start-Flag --mcp (mcp_runtime.gd
# _ready() kehrt früh zurück); GameState/EventLog bleiben projektseitig.
const AUTOLOADS := {
	"McpRuntime": "*res://addons/gdscript_mcp/runtime/host/mcp_runtime.gd",
	"McpProjectAdapter": "*res://addons/gdscript_mcp/runtime/core/mcp_project_adapter.gd",
}
# Achtung: Die beiden Pfade unter application/mcp/* sind DEFAULTS (SnipWar).
# Andere Projekte überschreiben sie in ihrer own project.godot — das Addon
# legt sie nur an, wenn sie noch nicht existieren.
const MCP_SETTINGS := {
	"application/mcp/preflight_script": {"value": "res://scripts/preflight.gd", "type": TYPE_STRING},
	"application/mcp/main_menu_scene": {"value": "res://scenes/main_menu/main_menu.tscn", "type": TYPE_STRING},
	"application/mcp/game_state_node": {"value": "", "type": TYPE_STRING},
	"application/mcp/event_log_node": {"value": "", "type": TYPE_STRING},
	"application/mcp/project_adapter_node": {"value": "", "type": TYPE_STRING},
	"application/mcp/game_state_script": {"value": "", "type": TYPE_STRING},
}

const EDITOR_CONFIG_PATH := "user://gdscript_mcp_config.cfg"

var _dock = null
var _runtime_profile := "player"

func _enter_tree() -> void:
	_register_project_integration()

	_dock = preload("res://addons/gdscript_mcp/editor/mcp_dock.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_LEFT_UL, _dock)
	_dock.runtime_launch_requested.connect(_on_runtime_launch_requested)

func _exit_tree() -> void:
	_clear_embedded_env()
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null

## Legt fehlende Autoloads und application/mcp/*-Settings im aktuellen
## Projekt an (idempotent: nur wenn abweichend). Schreibt project.godot nur,
## wenn sich tatsächlich etwas ändert — kein Dirty-State bei reinen Starts.
func _register_project_integration() -> void:
	var changed := false

	# 1. Autoloads registrieren (McpRuntime + McpProjectAdapter)
	for autoload_name: String in AUTOLOADS:
		var setting := "autoload/" + autoload_name
		var desired: String = AUTOLOADS[autoload_name]
		var current: Variant = ProjectSettings.get_setting(setting, null)
		if str(current) != desired or current == null:
			ProjectSettings.set_setting(setting, desired)
			changed = true
			push_warning("[GDScriptMcp] Autoload hinzugefügt: " + autoload_name)

	# 2. application/mcp/*-Settings ergänzen (nur fehlende)
	for setting: String in MCP_SETTINGS:
		if not ProjectSettings.has_setting(setting):
			var info: Dictionary = MCP_SETTINGS[setting]
			ProjectSettings.set_setting(setting, info.get("value"))
			changed = true
			push_warning("[GDScriptMcp] Setting gesetzt: " + setting)

	if changed:
		ProjectSettings.save()

func _dock_log(message: String, is_error: bool = false) -> void:
	if _dock != null and _dock.has_method("add_log"):
		_dock.add_log(message, is_error)

func _on_runtime_launch_requested(profile: String) -> void:
	if get_editor_interface().is_playing_scene():
		get_editor_interface().stop_playing_scene()
	var result: Dictionary = await _run_project("", true, profile, RUNTIME_PORT)
	if not bool(result.get("started", false)):
		_dock_log("Spielstart fehlgeschlagen: " + str(result.get("error", "?")), true)
	else:
		_dock_log("Spiel sichtbar gestartet (eigener Prozess, Profil " + str(result.get("profile", "player")) + ") — Runtime-MCP auf Port " + str(RUNTIME_PORT) + ", verbinde …")

func _run_project(scene_path: String, with_mcp: bool = false, profile: String = "", port: int = RUNTIME_PORT, wait_for_mcp: bool = true, startup_timeout_ms: int = 6000) -> Variant:
	if scene_path != "" and not _is_project_resource_path(scene_path):
		return {"started": false, "error": "scene path must stay inside the project"}
	if with_mcp:
		# EMBEDDED-WECHSEL (OFFEN-1): play_main_scene startet das Spiel in
		# Godot 4 als SEPARATEN Prozess. Der Runtime-MCP-Server bootet NICHT im
		# Editor — der McpRuntime-Autoload im Spielprozess startet ihn im
		# echten Spiel-SceneTree, sobald MCP_EMBEDDED gesetzt ist (der
		# Child-Prozess erbt die Env-Variablen). Damit zeigt
		# Engine.get_main_loop() im Server auf den SPIEL-Baum, und alle
		# Scene-/UX-/Input-Tools arbeiten auf dem echten Spiel. Das Plugin
		# setzt die Env-Flags, startet das Spiel und wartet auf den Handshake.
		var safe_profile := profile.strip_edges().to_lower()
		if safe_profile != "" and safe_profile not in ["player", "qa", "dev"]:
			return {"started": false, "mcp": false, "error": "profile must be player, qa, or dev"}
		if safe_profile == "":
			safe_profile = _runtime_profile
		if safe_profile == "":
			safe_profile = _read_dock_profile()
		if safe_profile == "":
			safe_profile = "player"
		var safe_port := clampi(port, 1024, 65535)
		_runtime_profile = safe_profile
		_set_embedded_env(safe_profile, safe_port)
		if scene_path != "":
			get_editor_interface().play_custom_scene(scene_path)
		else:
			get_editor_interface().play_main_scene()
		if wait_for_mcp:
			var liveness: Dictionary = await _wait_for_runtime_mcp(safe_port, startup_timeout_ms)
			return {
				"started": true,
				"mcp": true,
				"in_process": false,
				"separate_process": true,
				"embedded": true,
				"port": safe_port,
				"profile": safe_profile,
				"scene": scene_path,
				"mcp_ready": bool(liveness.get("ready", false)),
				"mcp_liveness": liveness,
			}
		return {
			"started": true,
			"mcp": true,
			"in_process": false,
			"separate_process": true,
			"embedded": true,
			"port": safe_port,
			"profile": safe_profile,
			"scene": scene_path,
		}
	if scene_path != "":
		get_editor_interface().play_custom_scene(scene_path)
	else:
		get_editor_interface().play_main_scene()
	return {"started": true, "mcp": false, "scene": scene_path}


## Setzt die Env-Flags für den Embedded-Runtime: Der McpRuntime-Autoload im
## Spiel-SceneTree bootet den MCP-Server mit Profil/Port/Write-Gate.
func _set_embedded_env(profile: String, port: int) -> void:
	OS.set_environment(EMBEDDED_ENV, "1")
	OS.set_environment(EMBEDDED_PORT_ENV, str(port))
	OS.set_environment(EMBEDDED_PROFILE_ENV, profile)
	OS.set_environment(EMBEDDED_WRITES_ENV, "1" if _read_editor_writes_enabled() else "0")


## Das Write-Gate (Autonomy-Writes im Spiel) bleibt ein Contract: default aus,
## explizit in der Editor-Config freischaltbar (config/settings.editor_write_enabled).
func _read_editor_writes_enabled() -> bool:
	var file := ConfigFile.new()
	if file.load(EDITOR_CONFIG_PATH) != OK:
		return false
	var settings: Variant = file.get_value("config", "settings", {})
	if settings is Dictionary:
		return bool((settings as Dictionary).get("editor_write_enabled", false))
	return false


func _clear_embedded_env() -> void:
	OS.set_environment(EMBEDDED_ENV, "")
	OS.set_environment(EMBEDDED_PORT_ENV, "")
	OS.set_environment(EMBEDDED_PROFILE_ENV, "")
	OS.set_environment(EMBEDDED_WRITES_ENV, "")


## Wartet auf den Runtime-MCP-Server IM SPIEL (Liveness-Probe mit demselben
## persistenten Client, den auch der Dock nutzt). Kein Editor-Server-Hosting.
func _wait_for_runtime_mcp(port: int, timeout_ms: int) -> Dictionary:
	var script: Resource = load(RUNTIME_CLIENT_SCRIPT)
	if script == null:
		return {"ready": false, "error": "runtime client script missing"}
	var probe: RefCounted = script.new()
	var connect_result: int = probe.connect_to("127.0.0.1", port)
	if connect_result != OK:
		probe.close()
		return {"ready": false, "error": "runtime connect failed: %s" % error_string(connect_result)}
	var receipt: Dictionary = await probe.wait_until_ready(maxi(1000, timeout_ms))
	probe.close()
	return receipt


func _stop_project() -> Dictionary:
	var result := {"stopped": false, "mode": "embedded"}
	_clear_embedded_env()
	if get_editor_interface().is_playing_scene():
		get_editor_interface().stop_playing_scene()
		result["editor_scene_stopped"] = true
		result["stopped"] = true
	else:
		result["reason"] = "no editor play session active"
	return result


func _project_status() -> Dictionary:
	var embedded := OS.get_environment(EMBEDDED_ENV) == "1"
	return {
		"in_process": false,
		"separate_process": true,
		"embedded": embedded,
		"runtime_server_running": embedded,
		"runtime_mcp_ready": embedded and get_editor_interface().is_playing_scene(),
		"port": RUNTIME_PORT,
		"profile": _runtime_profile,
		"editor_playing": get_editor_interface().is_playing_scene(),
		"playing_scene": get_editor_interface().get_playing_scene(),
	}


func _read_dock_profile() -> String:
	var file := ConfigFile.new()
	if file.load("user://gdscript_mcp_profile.cfg") == OK:
		var stored := str(file.get_value("profile", "name", "")).strip_edges().to_lower()
		if stored in ["player", "qa", "dev"]:
			return stored
	return ""


func _is_project_resource_path(path: String) -> bool:
	var normalized := path.strip_edges().simplify_path()
	return normalized.begins_with("res://") and not normalized.contains("..")
