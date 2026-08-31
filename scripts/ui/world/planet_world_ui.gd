class_name PlanetWorldUI
extends Node

## R-008: UI-Orchestrator für die Welt-Ansicht. Ünter PLANET_NETWORK_UI (Panel/
## Vault/Tooltipps) orchestriert diese Stufe alle übergreifenden UI-Module:
## Context-Menü, Dossier-Launcher, Hotkeys, Input-Hints, Flotten-Übersicht,
## Economy-Fenster, Message-Feed, Modal-/Layout-Koordinator, Tutorial und
## Dispatch-Vorschau.
##
## Der Knoten ist ein Kind von PlanetNetwork und bekommt die Netzwerk-/State-
## Referenzen in setup(); Intents (Ziel wählen, Mission setzen, Senden)
## laufen über die dokumentierten PlanetNetwork-Eintriegänge (_on_destination_
## selected, _on_planet_selected) — nie umgekehrt.

const _FlightTime := preload("res://scripts/flight_time.gd")
const _Dispatch := preload("res://scripts/dispatch.gd")
const PLANET_NETWORK_UI_SCRIPT: Script = preload("res://scripts/objects/planets/planet_network_ui.gd")
const MESSAGE_FEED_SCENE: PackedScene = preload("res://scenes/ui/message_feed.tscn")
const SELECTION_ACTION_TOOLTIP_SCRIPT: Script = preload("res://scripts/ui/selection_tooltip.gd")
const FLEET_OVERVIEW_SCRIPT: Script = preload("res://scripts/ui/fleet_overview.gd")
const ECONOMY_WINDOW_SCRIPT: Script = preload("res://scripts/ui/economy_window.gd")
const LAYOUT_COORDINATOR_SCRIPT: Script = preload("res://scripts/ui/layout_coordinator.gd")
const INPUT_HINT_OVERLAY_SCRIPT: Script = preload("res://scripts/ui/input_hint_overlay.gd")
const TUTORIAL_DIRECTOR_SCRIPT: Script = preload("res://scripts/ui/tutorial/tutorial_director.gd")

var _network: Node
var _field: Node
var _ui: PlanetNetworkUI
var _planets: Array[Node2D] = []
var _selection_service: SelectionService
var _worker_manager: Node
var _ship_manager: Node
var _conflict_manager: Node
var _map_camera: Node
var _theme_config: UIThemeConfig
var _transit_config: TransitConfig

var _context_menu: PopupMenu
var _context_active_planet: Node2D
var _action_tooltip: SelectionActionTooltip
var _context_disabled_reasons: Dictionary = {}
var _message_feed: MessageFeed
var _modal_coordinator: ModalCoordinator
var _layout_coordinator: LayoutCoordinator
var _input_hints: InputHintOverlay
var _fleet_overview: FleetOverview
var _economy_window: EconomyWindow
var _tutorial: TutorialDirector
var _tutorial_auto_started := false
var _selected_ship: ShipBase


func setup(
	network: Node,
	field: Node,
	ui: PlanetNetworkUI,
	planets: Array[Node2D],
	selection_service: SelectionService,
	worker_manager: Node,
	ship_manager: Node,
	conflict_manager: Node,
	map_camera: Node,
	theme_config: UIThemeConfig,
	transit_config: TransitConfig
) -> void:
	_network = network
	_field = field
	_ui = ui
	_planets = planets
	_selection_service = selection_service
	_worker_manager = worker_manager
	_ship_manager = ship_manager
	_conflict_manager = conflict_manager
	_map_camera = map_camera
	_theme_config = theme_config
	_transit_config = transit_config
	_create_context_menu()
	_create_message_feed.call_deferred()
	_create_modal_coordinator.call_deferred()


# --- Context menu ---


func _create_context_menu() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.name = "PlanetContextMenu"
	_context_menu.id_pressed.connect(on_context_action)
	_context_menu.id_focused.connect(on_context_item_focused)
	_ui.add_child(_context_menu)
	_create_action_tooltip()


func _create_action_tooltip() -> void:
	if _ui == null:
		return
	_action_tooltip = SELECTION_ACTION_TOOLTIP_SCRIPT.new() as SelectionActionTooltip
	_action_tooltip.name = "SelectionActionTooltip"
	_ui.add_child(_action_tooltip)


## Einstieg der PlanetNetwork-Shim: rechter Mausklick auf einen Planeten.
func show_context_menu(planet: Node2D, screen_position: Vector2) -> void:
	if _context_menu == null or not is_instance_valid(_context_menu):
		return
	# Right-click keeps the SelectionService primary (which acts as the
	# mission source) intact and treats the right-clicked planet as the
	# menu target. Promoting the primary on right-click would otherwise
	# collapse source==target and disable every mission action.
	_context_active_planet = planet
	build_context_menu_for(planet)
	_context_menu.popup(Rect2(screen_position, Vector2.ZERO))


func build_context_menu_for(planet: Node2D) -> void:
	if _context_menu == null or not is_instance_valid(_context_menu):
		return
	_context_active_planet = planet
	var result: Dictionary = ContextMenuBuilder.build_menu(
		_context_menu,
		planet,
		_selection_service,
		_game_state(),
		Callable(_network, "_is_neighbor"),
		{
			"OPEN": _network.ACTION_OPEN,
			"FOCUS": _network.ACTION_FOCUS,
			"ATTACK": _network.ACTION_ATTACK,
			"COLLECT": _network.ACTION_COLLECT,
			"COLONIZE": _network.ACTION_COLONIZE,
			"CLEAR": _network.ACTION_CLEAR_SELECTION,
		}
	)
	_context_disabled_reasons = result.get("disabled_reasons", {})


func on_context_item_focused(id: int) -> void:
	if _context_menu == null or not is_instance_valid(_context_menu):
		return
	var item_index: int = _context_menu.get_item_index(id)
	if item_index < 0 or _context_menu.is_item_disabled(item_index) == false:
		return
	var anchor_position: Vector2 = Vector2(_context_menu.position) + Vector2(8.0, float(item_index + 1) * 24.0)
	show_action_tooltip(id, anchor_position)


func on_context_action(id: int) -> void:
	var planet: Node2D = _context_active_planet
	_context_active_planet = null
	if _context_menu != null and is_instance_valid(_context_menu):
		var item_index: int = _context_menu.get_item_index(id)
		if item_index >= 0 and _context_menu.is_item_disabled(item_index):
			show_action_tooltip(id, _context_menu.position)
			return
	if planet == null or not is_instance_valid(_ui):
		return
	if id == _network.ACTION_OPEN:
		if _selection_service != null:
			_selection_service.handle_request(planet, {})
		else:
			_network._on_planet_selected(planet)
	elif id == _network.ACTION_FOCUS:
		_network._center_camera_on(planet)
	elif id == _network.ACTION_ATTACK:
		open_mission_for_target(planet, GameState.MISSION_MILITARY)
	elif id == _network.ACTION_COLLECT:
		open_mission_for_target(planet, GameState.MISSION_COLLECT)
	elif id == _network.ACTION_COLONIZE:
		open_mission_for_target(planet, GameState.MISSION_COLONY)
	elif id == _network.ACTION_CLEAR_SELECTION:
		if _selection_service != null:
			_selection_service.clear()


func open_mission_for_target(target: Node2D, mission_type: StringName) -> void:
	if target == null or not is_instance_valid(target) or not is_instance_valid(_ui):
		return
	var source: Node2D = _selection_service.get_primary() if _selection_service != null else _network.get_active_planet()
	if source == null or not is_instance_valid(source):
		return
	_ui.set_mission_type(mission_type)
	_network._on_planet_selected(source)
	var target_index: int = _network.get_active_destinations().find(target)
	if target_index >= 0:
		_network._on_destination_selected(target_index)


func show_action_tooltip(item_id: int, anchor_position: Vector2) -> void:
	if _action_tooltip == null or not is_instance_valid(_action_tooltip):
		return
	var reason: String = String(_context_disabled_reasons.get(item_id, "Diese Aktion ist aktuell nicht verfügbar."))
	_action_tooltip.show_text(reason, anchor_position)


# --- Message feed ---


func _create_message_feed() -> void:
	var event_log: Node = get_tree().root.get_node_or_null("EventLog")
	if event_log == null:
		return
	_message_feed = MESSAGE_FEED_SCENE.instantiate() as MessageFeed
	add_child(_message_feed)
	_message_feed.setup(event_log, _theme_config)


# --- Modal / Layout / Hints / Tutorial / Launcher / Fleet / Economy ---


func _create_modal_coordinator() -> void:
	_modal_coordinator = ModalCoordinator.new()
	_modal_coordinator.name = "ModalCoordinator"
	add_child(_modal_coordinator)
	_modal_coordinator.setup(_map_camera, _theme_config)
	_create_layout_coordinator()
	_create_input_hints()
	_create_tutorial()
	_create_dossier_launcher()
	_create_fleet_overview.call_deferred()
	_create_economy_module.call_deferred()


## Sprint 6 (S6): fixed non-overlapping panel zones. The paper dossier stays a
## full-screen modal (it intentionally dims and freezes the world), while the
## persistent panels (fleet top-right, economy bottom-right) live inside their
## ControlField so nothing ever overlaps the map or the vault.
func _create_layout_coordinator() -> void:
	_layout_coordinator = LAYOUT_COORDINATOR_SCRIPT.new() as LayoutCoordinator
	_layout_coordinator.name = "LayoutCoordinator"
	add_child(_layout_coordinator)
	_layout_coordinator.setup()
	var map_field := ControlField.new()
	map_field.name = "FieldMap"
	map_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_coordinator.register_field(map_field, &"field_map")
	var vault_field := ControlField.new()
	vault_field.name = "FieldVaultTop"
	vault_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_coordinator.register_field(vault_field, &"field_vault_top")
	var dossier_field := ControlField.new()
	dossier_field.name = "FieldDossierLeft"
	dossier_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_coordinator.register_field(dossier_field, &"field_dossier_left")


func _create_dossier_launcher() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DossierLauncher"
	# Sits ABOVE the PaperDossier modal (layer 80) so the PLANET/WERKSTATT/
	# FORSCHUNG/ECONOMY buttons stay clickable while a dossier is open — the
	# modal's fullscreen dim would otherwise swallow every click and make
	# sub-tab switching impossible until the dossier is closed first.
	layer.layer = 85
	add_child(layer)
	var box := VBoxContainer.new()
	box.name = "LauncherBox"
	box.position = Vector2(12.0, 72.0)
	box.add_theme_constant_override("separation", 6)
	layer.add_child(box)
	_add_dossier_button(box, "PLANET", open_planet_dossier, "Planeten-Dossier: Gebäude, Hangar, planetare Forschung")
	_add_dossier_button(box, "WERKSTATT", open_workshop_dossier)
	_add_dossier_button(box, "FORSCHUNG", open_tech_tree_dossier)
	_add_dossier_button(box, "ECONOMY", _toggle_economy_module)
	_add_dossier_button(box, "TUTORIAL", restart_tutorial)


## Sprint 7: interaktives Onboarding. Auto-Start einmal pro Session; danach
## über den TUTORIAL-Launcher-Button jederzeit neu startbar.
func _create_tutorial() -> void:
	var ship_manager: ShipManager = _ship_manager as ShipManager
	_tutorial = TUTORIAL_DIRECTOR_SCRIPT.new() as TutorialDirector
	_tutorial.name = "TutorialDirector"
	# QA2-MCP-6: eindeutiger Name für runtime_ux_scan/find_child. Der Director
	# hängt am Viewport-Root (CanvasLayer), Pfad = /root/TutorialDirector.
	_tutorial.unique_name_in_owner = true
	# CanvasLayer muss zum Scene-Root (World) hinzugefügt werden, nicht zu PlanetNetwork
	# (Node2D mit Transform), sonst stimmt viewport.get_canvas_transform() nicht.
	var world_root := get_tree().root
	if world_root != null:
		world_root.add_child(_tutorial)
	else:
		add_child(_tutorial)  # Fallback
	_tutorial.setup(_theme_config)
	if not _tutorial_auto_started:
		_tutorial_auto_started = true
		_tutorial.start(self, ship_manager, _game_state(), _map_camera)


func restart_tutorial() -> void:
	if _tutorial != null and is_instance_valid(_tutorial):
		_tutorial.restart()
	else:
		_create_tutorial()


func _create_fleet_overview() -> void:
	_fleet_overview = FLEET_OVERVIEW_SCRIPT.new() as FleetOverview
	_fleet_overview.name = "FleetOverview"
	var layer := CanvasLayer.new()
	layer.name = "FleetOverviewLayer"
	layer.layer = 38
	add_child(layer)
	_fleet_overview.setup(_theme_config, _map_camera)
	_fleet_overview.focus_requested.connect(_on_fleet_overview_focus)
	_fleet_overview.ship_drop_requested.connect(_on_ship_drop_requested)
	# Dock the overview into its ControlField zone (no manual offset anymore).
	if _layout_coordinator != null:
		var fleet_field := ControlField.new()
		fleet_field.name = "FieldFleetRightTop"
		fleet_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(fleet_field)
		fleet_field.add_child(_fleet_overview)
		_layout_coordinator.register_field(fleet_field, &"field_fleet_right_top")
	else:
		_fleet_overview.position = Vector2(12.0, 220.0)
		_fleet_overview.custom_minimum_size = Vector2(190.0, 0.0)
		layer.add_child(_fleet_overview)


func _create_economy_module() -> void:
	_economy_window = ECONOMY_WINDOW_SCRIPT.new() as EconomyWindow
	_economy_window.name = "EconomyWindow"
	var layer := CanvasLayer.new()
	layer.name = "EconomyWindowLayer"
	layer.layer = 65
	add_child(layer)
	_economy_window.setup(_theme_config)
	# Economy lives in its own zone bottom-right; the standard floating window
	# keeps its own positioning when the coordinator is unavailable.
	if _layout_coordinator != null:
		var economy_field := ControlField.new()
		economy_field.name = "FieldEconomyRightBottom"
		economy_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(economy_field)
		economy_field.add_child(_economy_window)
		_layout_coordinator.register_field(economy_field, &"field_economy_right_bottom")
	else:
		layer.add_child(_economy_window)


func get_economy_window() -> EconomyWindow:
	return _economy_window


func _toggle_economy_module() -> void:
	if _economy_window != null and is_instance_valid(_economy_window):
		_economy_window.toggle()


func open_economy_module() -> void:
	if _economy_window != null and is_instance_valid(_economy_window):
		_economy_window.open()


func _create_input_hints() -> void:
	_input_hints = INPUT_HINT_OVERLAY_SCRIPT.new() as InputHintOverlay
	_input_hints.name = "InputHintOverlay"
	add_child(_input_hints)
	_input_hints.setup(_theme_config)


func _add_dossier_button(box: VBoxContainer, text: String, pressed: Callable, tooltip: String = "") -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	if tooltip != "":
		button.tooltip_text = tooltip
	UIBaseUtils.apply_button_theme(button, _theme_config)
	button.pressed.connect(pressed)
	box.add_child(button)


# --- Dossiers ---


func _close_overlay_panels() -> void:
	if is_instance_valid(_ui):
		_ui.close_panel()


func open_planet_dossier() -> void:
	if _modal_coordinator == null or not is_instance_valid(_modal_coordinator):
		return
	var active_planet: Node2D = _network.get_active_planet()
	if active_planet == null or not is_instance_valid(active_planet):
		return
	var view := PlanetDossierView.new()
	view.setup(_theme_config)
	view.populate(active_planet as Planet, _game_state())
	_close_overlay_panels()
	_modal_coordinator.open_view(view, "PLANETEN-DOSSIER")


func open_workshop_dossier() -> void:
	if _modal_coordinator == null or not is_instance_valid(_modal_coordinator):
		return
	var ship_manager: ShipManager = _ship_manager as ShipManager
	if ship_manager == null:
		return
	var view := WorkshopView.new()
	view.setup(ship_manager, _theme_config)
	view.refresh(_game_state(), ship_manager.get_planets())
	_close_overlay_panels()
	_modal_coordinator.open_view(view, "WERKSTATT / HANGAR")


func open_tech_tree_dossier() -> void:
	if _modal_coordinator == null or not is_instance_valid(_modal_coordinator):
		return
	var ship_manager: ShipManager = _ship_manager as ShipManager
	if ship_manager == null:
		return
	var view := ParchmentTechTreeView.new()
	view.setup(ship_manager, _theme_config)
	view.refresh(_game_state())
	_close_overlay_panels()
	_modal_coordinator.open_view(view, "FORSCHUNGSBAUM")


# --- Hotkeys ---


## Sprint 6 (S2): direct Dossier hotkeys (P/W/F/R, ESC handled by ui_cancel).
## Kept in _unhandled_input so the world view reacts without stealing focus.
func _unhandled_input(event: InputEvent) -> void:
	if _modal_coordinator != null and is_instance_valid(_modal_coordinator) and _modal_coordinator.is_open():
		return
	if event.is_action_pressed(&"open_planet"):
		open_planet_dossier()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"open_workshop"):
		open_workshop_dossier()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"open_research"):
		open_tech_tree_dossier()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"open_economy"):
		_toggle_economy_module()
		get_viewport().set_input_as_handled()


# --- Fleet overview ---


func connect_ship_selection(ship: ShipBase) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	if not ship.ship_selected.is_connected(_on_ship_clicked):
		ship.ship_selected.connect(_on_ship_clicked)


func on_ship_dispatched(ship: ShipBase) -> void:
	connect_ship_selection(ship)
	update_fleet_overview()


func on_ship_arrived() -> void:
	update_fleet_overview.call_deferred()


func update_fleet_overview() -> void:
	if _fleet_overview == null or not is_instance_valid(_fleet_overview):
		return
	# Keep the part catalog fresh so ship rows can render composition icons.
	var ship_manager: ShipManager = _ship_manager as ShipManager
	if ship_manager != null and _fleet_overview.has_method("set_part_catalog"):
		_fleet_overview.set_part_catalog(ship_manager.get_part_catalog())
	var conflict_manager: Node = _conflict_manager
	var ships: Array[ShipBase] = []
	if conflict_manager != null:
		if conflict_manager.has_method("get_active_ships"):
			for ship in conflict_manager.get_active_ships() as Array[ShipBase]:
				ships.append(ship)
		if conflict_manager.has_method("get_idle_ships"):
			for ship in conflict_manager.get_idle_ships() as Array[ShipBase]:
				ships.append(ship)
	_fleet_overview.update_ships(ships)
	if _selection_service != null:
		_fleet_overview.update_planets(_selection_service.get_selection())


func _on_fleet_overview_focus(target: Node2D) -> void:
	_network._center_camera_on(target)
	if target is Planet:
		_deselect_current_ship()
		if _selection_service != null:
			_selection_service.handle_request(target, {})
		else:
			_network._on_planet_selected(target)
	elif target is ShipBase:
		_deselect_current_ship()
		if _selection_service != null:
			_selection_service.clear()
		target.set_selected(true)
		_selected_ship = target as ShipBase


func _on_ship_drop_requested(ship: ShipBase, destination_planet: Node2D) -> void:
	if ship == null or destination_planet == null or not is_instance_valid(ship):
		return
	# Only dispatch idle/arrived ships; in-flight ones just get camera focus.
	var source_planet := _find_planet_by_id(ship.source_planet_id)
	if ship.has_arrived() and source_planet != null and source_planet != destination_planet:
		var conflict_manager: Node = _conflict_manager
		if conflict_manager != null and conflict_manager.has_method("dispatch_ship"):
			var ship_id: StringName = &""
			if ship.fleet != null and not ship.fleet.ships.is_empty():
				ship_id = ship.fleet.ships[0].ship_id
			if not String(ship_id).is_empty():
				var result: ShipBase = conflict_manager.call("dispatch_ship", source_planet, destination_planet, ship_id, ship.mission_role) as ShipBase
				if result != null:
					var event_log: Node = get_node_or_null("/root/EventLog")
					if event_log != null and event_log.has_method("push"):
						event_log.push("Schiff entsendet nach %s" % UIBaseUtils.planet_display_name(destination_planet))
					update_fleet_overview.call_deferred()
					return
	# Fallback: centre camera and select the destination planet.
	_network._center_camera_on(destination_planet)
	if _selection_service != null:
		_selection_service.handle_request(destination_planet, {})
	else:
		_network._on_planet_selected(destination_planet)


func _find_planet_by_id(planet_id: StringName) -> Planet:
	if String(planet_id).is_empty():
		return null
	for child in _field.get_children():
		var planet := child as Planet
		if planet != null and planet.get("planet_id") == planet_id:
			return planet
	return null


func _on_ship_clicked(ship: ShipBase) -> void:
	_deselect_current_ship()
	if _selection_service != null:
		_selection_service.clear()
	ship.set_selected(true)
	_selected_ship = ship
	_network._center_camera_on(ship)


func _deselect_current_ship() -> void:
	if _selected_ship != null and is_instance_valid(_selected_ship):
		_selected_ship.set_selected(false)
	_selected_ship = null


# --- Dispatch preview / slider / lock (UI-Seite) ---


func on_planet_selected(planet: Node2D, destinations: Array[Node2D], default_destination: Node2D) -> void:
	if not is_instance_valid(_ui):
		return
	_ui.show_planet(planet, destinations, default_destination)
	_update_selected_count()
	refresh_slider_bounds()
	refresh_dispatch_lock()
	if _input_hints != null:
		_input_hints.show_context(&"planet")
	if _ui.has_selectable_amount():
		_ui.reset_amount()
	update_preview()


func update_count(planet: Node2D) -> void:
	if is_instance_valid(_ui):
		_ui.update_count(planet)


func refresh_selected_count() -> void:
	_update_selected_count()


func _update_selected_count() -> void:
	var active_planet: Node2D = _network.get_active_planet()
	if active_planet == null or not is_instance_valid(_ui):
		return
	_ui.set_selected_count(int(active_planet.get("worker_count")))


func on_selection_group_changed(selection: Array[Node2D]) -> void:
	if _ui == null or not is_instance_valid(_ui):
		return
	if _ui.has_method("refresh_selection_overview"):
		_ui.refresh_selection_overview(selection)
	if _fleet_overview != null and is_instance_valid(_fleet_overview):
		_fleet_overview.update_planets(selection)


func set_selection_count(count: int) -> void:
	if _ui == null or not is_instance_valid(_ui):
		return
	if _ui.has_method("set_selection_count"):
		_ui.set_selection_count(count)


func close_panel() -> void:
	if is_instance_valid(_ui):
		_ui.close_panel()


func update_preview() -> void:
	if not is_instance_valid(_ui):
		return
	var active_planet: Node2D = _network.get_active_planet()
	if active_planet == null or not _ui.has_selectable_amount():
		_ui.set_preview("Keine Einheiten verfügbar")
		_ui.set_dispatch_preview({"summary": "Keine Einheiten verfügbar."})
		return
	var destination: Node2D = _network.get_destination(active_planet) as Node2D
	if destination == null:
		_ui.set_preview("Kein Ziel verfügbar")
		_ui.set_dispatch_preview({"summary": "Kein Ziel verfügbar — Auftrag kann nicht gestartet werden."})
		return
	var source: Planet = active_planet as Planet
	var destination_planet: Planet = destination as Planet
	var state: Node = _game_state()
	var available: int = int(source.get("worker_count"))
	var selected_amount: int = clampi(_ui.selected_amount(), 1, maxi(available, 1))
	var route_path: Array[Vector2] = _network.get_route_path(source, destination)
	var distance := PathUtils.distance(route_path)
	var speed_multiplier: float = source.get_transfer_speed_multiplier()
	var seconds := _FlightTime.seconds_for(distance, selected_amount, _transit_config, speed_multiplier)
	var mission_type: StringName = _ui.selected_mission_type()
	var destination_faction: StringName = destination_planet.get_faction() if destination_planet != null else GameState.FACTION_NEUTRAL
	var destination_known: bool = false
	if state != null and destination_planet != null:
		destination_known = state.is_known(destination_planet.planet_id, GameState.FACTION_PLAYER)
	var destination_name: String = UIBaseUtils.planet_display_name(destination_planet) if destination_planet != null and destination_known else "Unbekanntes Ziel"
	var summary_lines: Array[String] = [
		"%s · %s" % [UIBaseUtils.mission_display_name(mission_type), destination_name],
		"Sende: %d / %d Einheiten · Danach verfügbar: %d" % [selected_amount, available, maxi(0, available - selected_amount)],
		"Transit: %.1f s" % seconds,
	]
	match mission_type:
		GameState.MISSION_COLLECT:
			var resource_id: StringName = state.resource_of(destination_planet.planet_id) if destination_planet != null and destination_known else &""
			var local_stock: int = state.get_local_resource(destination_planet.planet_id, resource_id) if state != null and destination_planet != null and not String(resource_id).is_empty() else 0
			var base_amount: int = destination_planet.get_size_profile().resource_base if destination_planet != null else 1
			var possible_cargo: int = mini(selected_amount * maxi(base_amount, 1), local_stock)
			if not String(resource_id).is_empty():
				summary_lines.append("Rückkehrladung: bis zu %d %s" % [possible_cargo, UIBaseUtils.resource_display_name(resource_id)])
			else:
				summary_lines.append("Rückkehrladung: Zielressource noch unbekannt")
		GameState.MISSION_MILITARY:
			if destination_faction != source.get_faction():
				summary_lines.append("Risiko: Konflikt möglich")
			else:
				summary_lines.append("Einsatz: Verstärkung der eigenen Welt")
		GameState.MISSION_CARGO:
			if destination_faction == source.get_faction():
				summary_lines.append("Wirkung: Verstärkt die Zielwelt")
			else:
				summary_lines.append("Hinweis: Transport ist nur zu einer eigenen Welt gültig")
		GameState.MISSION_COLONY:
			if destination_faction == GameState.FACTION_NEUTRAL:
				summary_lines.append("Wirkung: Besiedelt die neutrale Zielwelt")
			else:
				summary_lines.append("Hinweis: Ziel muss neutral sein")
	# Keep the compact preview parseable for existing replay/preflight tooling;
	# the sticky footer carries the richer consequence summary.
	var preview_text: String = "Flugzeit: %.1f s" % seconds
	_ui.set_preview(preview_text)
	_ui.set_dispatch_preview({"summary": "\n".join(summary_lines), "seconds": seconds, "amount": selected_amount, "available": available})


func refresh_slider_bounds() -> void:
	var active_planet: Node2D = _network.get_active_planet()
	if active_planet == null or not is_instance_valid(_ui):
		return
	var bounds := _Dispatch.amount_range(int(active_planet.get("worker_count")))
	_ui.set_amount_bounds(bounds)
	update_preview()


func refresh_dispatch_lock() -> void:
	if _ui == null or not is_instance_valid(_ui) or _worker_manager == null:
		return
	if not _network.has_method("_dispatch_locked_for_destination"):
		return
	var locked: bool = _network._dispatch_locked_for_destination()
	var send_button: Button = _ui.get_send_button()
	if send_button != null:
		if locked and send_button.disabled == false:
			send_button.disabled = true
		elif not locked and send_button.disabled and _ui.has_selectable_amount():
			send_button.disabled = false
	if locked and _ui.has_method("set_preview"):
		_ui.set_preview("Ziel bereits unter Auftrag — warte auf Ankunft")


func on_planet_hovered(planet: Node2D) -> void:
	if is_instance_valid(_ui):
		_ui.show_planet_tooltip(planet)


func on_planet_unhovered() -> void:
	if is_instance_valid(_ui):
		_ui.hide_planet_tooltip()


# --- Getter für PlanetNetwork-Shims ---


func get_context_menu() -> PopupMenu:
	return _context_menu


func get_context_disabled_reasons() -> Dictionary:
	return _context_disabled_reasons


func get_context_active_planet() -> Node2D:
	return _context_active_planet


func set_context_active_planet(planet: Node2D) -> void:
	_context_active_planet = planet


func get_modal_coordinator() -> ModalCoordinator:
	return _modal_coordinator


func get_message_feed() -> MessageFeed:
	return _message_feed


func get_fleet_overview() -> FleetOverview:
	return _fleet_overview


func _game_state() -> Node:
	return GameStateAccess.autoload(self)