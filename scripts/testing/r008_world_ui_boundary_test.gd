extends SceneTree

## R-008-Gate: Beweist die UI/Logik-Boundary zwischen PlanetNetwork und
## PlanetWorldUI auf Quelltext-Ebene (im Stil der grep-Gates):
##   1. planet_network.gd enthält KEINE UI-Modul-Konstruktion mehr
##      (PopupMenu/EconomyWindow/FleetOverview/MessageFeed/LayoutCoordinator/
##      InputHintOverlay/TutorialDirector/DossierLauncher direkt via .new()).
##   2. planet_network.gd behält die Netzwerk-/Render-/Fog-API
##      (_draw, _process, _refresh_fog_of_war, get_neighbors,
##      _dispatch_locked_for_destination).
##   3. planet_world_ui.gd existiert und trägt die Orchestrierung
##      (show_context_menu, open_workshop_dossier, update_preview,
##      _create_message_feed, _create_modal_coordinator).
##   4. planet_network.gd delegiert an _world_ui (Shims vorhanden).
##
## Echte Assertions mit Failure-Path; Exit 1 bei Abweichung, kein Print-only.

var _failures: Array[String] = []

const NETWORK_PATH := "res://scripts/objects/planets/planet_network.gd"
const WORLD_UI_PATH := "res://scripts/ui/world/planet_world_ui.gd"

# UI-Modul-Konstruktionen, die NUR noch in planet_world_ui.gd leben dürfen.
const UI_CONSTRUCTORS: Array[String] = [
	"PopupMenu.new()",
	"ECONOMY_WINDOW_SCRIPT.new()",
	"FLEET_OVERVIEW_SCRIPT.new()",
	"MESSAGE_FEED_SCENE.instantiate()",
	"LAYOUT_COORDINATOR_SCRIPT.new()",
	"INPUT_HINT_OVERLAY_SCRIPT.new()",
	"TUTORIAL_DIRECTOR_SCRIPT.new()",
	"ModalCoordinator.new()",
]

# Netzwerk-/Render-API, die im Network bleiben muss.
const NETWORK_API: Array[String] = [
	"func _draw()",
	"func _process(delta: float)",
	"func _refresh_fog_of_war()",
	"func get_neighbors(planet: Node2D)",
	"func _dispatch_locked_for_destination()",
	"func get_route_path(",
	"func get_mission_destinations(",
]

# UI-Orchestrierung, die in der Welt-UI leben muss.
const WORLD_UI_API: Array[String] = [
	"func show_context_menu(",
	"func build_context_menu_for(",
	"func open_workshop_dossier()",
	"func open_planet_dossier()",
	"func update_preview()",
	"func _create_message_feed()",
	"func _create_modal_coordinator()",
	"func _create_dossier_launcher()",
	"func _create_tutorial()",
	"func refresh_dispatch_lock()",
	"func on_planet_selected(",
]


func _init() -> void:
	call_deferred("_run")


func _fail(what: String) -> void:
	_failures.append(what)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _run() -> void:
	var network_text := _read(NETWORK_PATH)
	var world_ui_text := _read(WORLD_UI_PATH)

	if network_text.is_empty():
		_fail("planet_network.gd konnte nicht gelesen werden")
	if world_ui_text.is_empty():
		_fail("planet_world_ui.gd fehlt oder konnte nicht gelesen werden")

	# 1. Keine UI-Konstruktion mehr im Network.
	for constructor in UI_CONSTRUCTORS:
		if network_text.contains(constructor):
			_fail("planet_network.gd konstruiert UI weiterhin direkt: %s" % constructor)

	# Network darf keine eigenen UI-Scripts preloaden (nur die Welt-UI + Panel-Szene).
	for forbidden_preload in [
		"selection_tooltip.gd",
		"fleet_overview.gd",
		"economy_window.gd",
		"layout_coordinator.gd",
		"input_hint_overlay.gd",
		"tutorial_director.gd",
		"message_feed.tscn",
	]:
		if network_text.contains(preload_marker(forbidden_preload)):
			_fail("planet_network.gd preloadet weiterhin UI-Modul: %s" % forbidden_preload)

	# 2. Netzwerk-/Render-API bleibt im Network.
	for api in NETWORK_API:
		if not network_text.contains(api):
			_fail("planet_network.gd verliert Netzwerk-API: %s" % api)

	# 3. UI-Orchestrierung lebt in planet_world_ui.gd.
	for api in WORLD_UI_API:
		if not world_ui_text.contains(api):
			_fail("planet_world_ui.gd fehlt Orchestrierung: %s" % api)

	# 4. Network delegiert via _world_ui-Shims.
	if "_world_ui." not in network_text:
		_fail("planet_network.gd besitzt keine _world_ui-Delegationsshims")

	if not _failures.is_empty():
		for failure in _failures:
			printerr("[R-008-FAIL] " + failure)
		print("R-008 WORLD-UI BOUNDARY: FAIL (%d failures)" % _failures.size())
		quit(1)
		return
	print("R-008 WORLD-UI BOUNDARY: PASS (UI-Konstruktion in PlanetWorldUI, Network-API intakt)")
	quit(0)


func preload_marker(rel_path: String) -> String:
	return 'preload("res://scripts/' + rel_path + '")' if rel_path.ends_with(".gd") else 'preload("res://scenes/ui/' + rel_path + '")'