extends Node

signal message_pushed(category: StringName, text: String)

const DEFAULT_UPGRADE_CATALOG: PlanetUpgradeCatalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")
const DEFAULT_TECHNOLOGY_CATALOG: TechnologyCatalog = preload("res://resources/config/technology_catalog_default.tres")
const DEFAULT_RESOURCE_POOL: ResourcePool = preload("res://resources/config/resource_pool_default.tres")
const PLAYER_LOG_PATH: String = "user://player.log"
const MAX_ENTRIES: int = 200

var _entries: Array[Dictionary] = []

func _ready() -> void:
	_connect_game_state.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		export_to_player_log()

func _exit_tree() -> void:
	export_to_player_log()

func _connect_game_state() -> void:
	var state: Node = get_node_or_null("/root/GameState")
	if state == null:
		return
	if not state.faction_changed.is_connected(_on_faction_changed):
		state.faction_changed.connect(_on_faction_changed)
	if not state.planet_discovered.is_connected(_on_planet_discovered):
		state.planet_discovered.connect(_on_planet_discovered)
	if not state.planet_upgraded.is_connected(_on_planet_upgraded):
		state.planet_upgraded.connect(_on_planet_upgraded)
	if not state.technology_researched.is_connected(_on_technology_researched):
		state.technology_researched.connect(_on_technology_researched)
	if state.has_signal("planet_technology_researched") and not state.planet_technology_researched.is_connected(_on_planet_technology_researched):
		state.planet_technology_researched.connect(_on_planet_technology_researched)
	if not state.resource_generated.is_connected(_on_resource_generated):
		state.resource_generated.connect(_on_resource_generated)

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
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()

func _on_faction_changed(planet_id: StringName, _old_faction: StringName, new_faction: StringName) -> void:
	push(&"military", "%s fiel unter die Kontrolle von %s." % [_planet_name(planet_id), _faction_name(new_faction)])

func _on_planet_discovered(_faction: StringName, planet_id: StringName) -> void:
	push(&"discovery", "Scout-Signatur erfasst: %s wurde kartografiert." % _planet_name(planet_id))

func _on_planet_upgraded(planet_id: StringName, upgrade_id: StringName) -> void:
	push(&"economy", "%s: %s errichtet." % [_planet_name(planet_id), _upgrade_name(upgrade_id)])

func _on_technology_researched(_faction: StringName, technology_id: StringName) -> void:
	push(&"tech", "Forschung abgeschlossen: %s." % _technology_name(technology_id))

func _on_planet_technology_researched(planet_id: StringName, technology_id: StringName) -> void:
	push(&"tech", "%s: Planetare Technologie %s aktiviert." % [_planet_name(planet_id), _technology_name(technology_id)])

func _on_resource_generated(planet_id: StringName, resource_id: StringName, amount: int) -> void:
	log_silent(&"economy", "%s lieferte %d %s." % [_planet_name(planet_id), amount, _resource_name(resource_id)])

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
