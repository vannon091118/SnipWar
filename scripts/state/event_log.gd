extends Node

signal message_pushed(category: StringName, text: String)

const DEFAULT_UPGRADE_CATALOG: PlanetUpgradeCatalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")
const DEFAULT_TECHNOLOGY_CATALOG: TechnologyCatalog = preload("res://resources/config/technology_catalog_default.tres")
const DEFAULT_RESOURCE_POOL: ResourcePool = preload("res://resources/config/resource_pool_default.tres")
const PLAYER_LOG_PATH: String = "user://player.log"

var _max_entries: int = 200
var _entries: Array[Dictionary] = []

func _ready() -> void:
	_connect_event_bus.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		export_to_player_log()

func _connect_event_bus() -> void:
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal("game_event"):
		if not bus.game_event.is_connected(_on_game_event):
			bus.game_event.connect(_on_game_event)
		return
	_connect_game_state()

func _on_game_event(type: StringName, data: Dictionary) -> void:
	match type:
		&"faction_changed":
			_on_faction_changed(data.get("planet_id", &""), data.get("old_faction", &""), data.get("new_faction", &""))
		&"planet_discovered":
			_on_planet_discovered(data.get("faction", &""), data.get("planet_id", &""))
		&"planet_scanned":
			_on_planet_scanned(data.get("faction", &""), data.get("planet_id", &""), data.get("resource_id", &""), data.get("size_id", &""), data.get("build_slots", 0))
		&"planet_upgraded":
			_on_planet_upgraded(data.get("planet_id", &""), data.get("upgrade_id", &""))
		&"technology_researched":
			_on_technology_researched(data.get("faction", &""), data.get("technology_id", &""))
		&"planet_technology_researched":
			_on_planet_technology_researched(data.get("planet_id", &""), data.get("technology_id", &""))
		&"resource_generated":
			_on_resource_generated(data.get("planet_id", &""), data.get("resource_id", &""), data.get("amount", 0))
		&"resources_collected":
			_on_resources_collected(data.get("faction", &""), data.get("planet_id", &""), data.get("resource_id", &""), data.get("amount", 0))
		&"gathering_started":
			_on_gathering_started(data.get("faction", &""), data.get("planet_id", &""), data.get("workers", 0))
		&"gathering_withdrawn":
			_on_gathering_withdrawn(data.get("faction", &""), data.get("planet_id", &""), data.get("workers", 0))
		&"worker_factory_built":
			_on_worker_factory_built(data.get("planet_id", &""))
		&"ship_assembled":
			_on_ship_assembled(data.get("planet_id", &""), data.get("ship_id", &""))
		&"ship_launched":
			_on_ship_launched(data.get("planet_id", &""), data.get("ship_id", &""), data.get("role", &""))
		&"ship_lost":
			_on_ship_lost(data.get("planet_id", &""), data.get("ship_id", &""))
		&"milestone_reached":
			_on_milestone_reached(data.get("faction", &""), data.get("milestone_id", &""))
func _connect_game_state() -> void:
	var state: Node = get_node_or_null("/root/GameState")
	if state == null:
		return
	if not state.faction_changed.is_connected(_on_faction_changed):
		state.faction_changed.connect(_on_faction_changed)
	if not state.planet_discovered.is_connected(_on_planet_discovered):
		state.planet_discovered.connect(_on_planet_discovered)
	if state.has_signal("planet_scanned") and not state.planet_scanned.is_connected(_on_planet_scanned):
		state.planet_scanned.connect(_on_planet_scanned)
	if not state.planet_upgraded.is_connected(_on_planet_upgraded):
		state.planet_upgraded.connect(_on_planet_upgraded)
	if not state.technology_researched.is_connected(_on_technology_researched):
		state.technology_researched.connect(_on_technology_researched)
	if state.has_signal("planet_technology_researched") and not state.planet_technology_researched.is_connected(_on_planet_technology_researched):
		state.planet_technology_researched.connect(_on_planet_technology_researched)
	if not state.resource_generated.is_connected(_on_resource_generated):
		state.resource_generated.connect(_on_resource_generated)
	if state.has_signal("resources_collected") and not state.resources_collected.is_connected(_on_resources_collected):
		state.resources_collected.connect(_on_resources_collected)
	if state.has_signal("gathering_started") and not state.gathering_started.is_connected(_on_gathering_started):
		state.gathering_started.connect(_on_gathering_started)
	if state.has_signal("gathering_withdrawn") and not state.gathering_withdrawn.is_connected(_on_gathering_withdrawn):
		state.gathering_withdrawn.connect(_on_gathering_withdrawn)
	if state.has_signal("worker_factory_built") and not state.worker_factory_built.is_connected(_on_worker_factory_built):
		state.worker_factory_built.connect(_on_worker_factory_built)
	if state.has_signal("ship_assembled") and not state.ship_assembled.is_connected(_on_ship_assembled):
		state.ship_assembled.connect(_on_ship_assembled)
	if state.has_signal("ship_launched") and not state.ship_launched.is_connected(_on_ship_launched):
		state.ship_launched.connect(_on_ship_launched)
	if state.has_signal("ship_lost") and not state.ship_lost.is_connected(_on_ship_lost):
		state.ship_lost.connect(_on_ship_lost)
	if state.has_signal("milestone_reached") and not state.milestone_reached.is_connected(_on_milestone_reached):
		state.milestone_reached.connect(_on_milestone_reached)

# Push = toast + log. Use for discrete, meaningful events.
func push(category: StringName, text: String) -> void:
	if text.is_empty():
		return
	_record(category, text, true)
	message_pushed.emit(category, text)

# Log = silent history only (e.g. periodic resource pulses).
func log_silent(category: StringName, text: String) -> void:
	if text.is_empty():
		return
	_record(category, text, false)

func set_max_entries(limit: int) -> void:
	_max_entries = maxi(limit, 1)

func get_entries() -> Array[Dictionary]:
	return _entries.duplicate()

func export_to_player_log(path: String = PLAYER_LOG_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	for entry in _entries:
		file.store_line("[%s][%s] %s" % [String(entry.get("stamp", "")), String(entry.get("category", "")), String(entry.get("text", ""))])
	file.close()
	return true

func _record(category: StringName, text: String, visible: bool) -> void:
	_entries.append({
		"category": category,
		"text": text,
		"stamp": Time.get_datetime_string_from_system(),
		"visible": visible,
	})
	if _entries.size() > _max_entries:
		_entries.pop_front()

func _on_faction_changed(planet_id: StringName, _old_faction: StringName, new_faction: StringName) -> void:
	push(&"military", "%s fiel unter die Kontrolle von %s." % [_planet_name(planet_id), _faction_name(new_faction)])

func _on_planet_discovered(_faction: StringName, planet_id: StringName) -> void:
	push(&"discovery", "Scout-Signatur erfasst: %s wurde kartografiert." % _planet_name(planet_id))

func _on_planet_scanned(_faction: StringName, planet_id: StringName, resource_id: StringName, size_id: StringName, build_slots: int) -> void:
	push(&"discovery", "Scanbericht %s: %s, Größe %s, %d Bauplätze." % [_planet_name(planet_id), _resource_name(resource_id), String(size_id).to_upper(), build_slots])

func _on_planet_upgraded(planet_id: StringName, upgrade_id: StringName) -> void:
	push(&"economy", "%s: %s errichtet." % [_planet_name(planet_id), _upgrade_name(upgrade_id)])

func _on_technology_researched(faction: StringName, technology_id: StringName) -> void:
	# Nur die eigene Forschung ist ein Spieler-Event: Die CPU erforscht parallel
	# (z.B. "Orbitales Werft-Design" direkt nach Weltstart). Deren Abschluss darf
	# nicht als "Forschung abgeschlossen"-Toast des Spielers erscheinen, sondern
	# geht nur still ins Log ein.
	if faction != &"a":
		log_silent(&"tech", "Forschung abgeschlossen: %s (%s)." % [_technology_name(technology_id), _faction_name(faction)])
		return
	push(&"tech", "Forschung abgeschlossen: %s." % _technology_name(technology_id))

func _on_planet_technology_researched(planet_id: StringName, technology_id: StringName) -> void:
	push(&"tech", "%s: Planetare Technologie %s aktiviert." % [_planet_name(planet_id), _technology_name(technology_id)])

func _on_resource_generated(planet_id: StringName, resource_id: StringName, amount: int) -> void:
	log_silent(&"economy", "%s lieferte %d %s." % [_planet_name(planet_id), amount, _resource_name(resource_id)])

func _on_resources_collected(_faction: StringName, planet_id: StringName, resource_id: StringName, amount: int) -> void:
	log_silent(&"economy", "Sammeltrupp auf %s barg %d %s." % [_planet_name(planet_id), amount, _resource_name(resource_id)])

func _on_gathering_started(_faction: StringName, planet_id: StringName, workers: int) -> void:
	push(&"economy", "Sammeltrupp auf %s begonnen: %d Worker ernten fortan Rohstoffe." % [_planet_name(planet_id), workers])

func _on_gathering_withdrawn(_faction: StringName, planet_id: StringName, workers: int) -> void:
	push(&"economy", "Sammeltrupp von %s abgezogen: %d Worker kehrten heim." % [_planet_name(planet_id), workers])

func _on_worker_factory_built(planet_id: StringName) -> void:
	push(&"economy", "%s: Worker-Fertiger in der Werft aktiviert." % _planet_name(planet_id))

func _on_ship_assembled(planet_id: StringName, ship_id: StringName) -> void:
	push(&"tech", "%s: Schiff %s ist fertig montiert." % [_planet_name(planet_id), String(ship_id)])

func _on_ship_launched(planet_id: StringName, ship_id: StringName, role: StringName) -> void:
	push(&"military", "%s: %s %s gestartet." % [_planet_name(planet_id), String(role).capitalize(), String(ship_id)])

func _on_ship_lost(planet_id: StringName, ship_id: StringName) -> void:
	push(&"military", "%s: Schiff %s wurde verloren." % [_planet_name(planet_id), String(ship_id)])

func _on_milestone_reached(_faction: StringName, milestone_id: StringName) -> void:
	if milestone_id == &"first_colony":
		push(&"discovery", "Meilenstein erreicht: Erste Kolonie gegründet!")
	else:
		push(&"discovery", "Meilenstein erreicht: %s." % String(milestone_id))

func _planet_name(planet_id: StringName) -> String:
	var text := String(planet_id)
	if text.is_empty():
		return "Unbekannter Planet"
	return text.substr(0, 1).to_upper() + text.substr(1)

func _faction_name(faction: StringName) -> String:
	match faction:
		&"a":
			return "der Spieler-Fraktion"
		&"b":
			return "der CPU-Fraktion"
		&"neutral":
			return "neutralen Kontrolle"
		_:
			return String(faction)

func _resource_name(resource_id: StringName) -> String:
	var resource := DEFAULT_RESOURCE_POOL.resource_for(resource_id)
	if resource != null and not resource.display_name.is_empty():
		return resource.display_name
	return String(resource_id)

func _upgrade_name(upgrade_id: StringName) -> String:
	var definition := DEFAULT_UPGRADE_CATALOG.resolve(upgrade_id)
	if definition != null and not definition.display_name.is_empty():
		return definition.display_name
	return String(upgrade_id)

func _technology_name(technology_id: StringName) -> String:
	var definition := DEFAULT_TECHNOLOGY_CATALOG.resolve(technology_id)
	if definition != null and not definition.display_name.is_empty():
		return definition.display_name
	return String(technology_id)
