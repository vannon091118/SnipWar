@tool
class_name RunSaveData
extends Resource

## Full serializable snapshot of a run. Pure data only — never Node instances.
## The four GameState domains, the transit records, the chunk-world cache and
## the pacing timers are all captured here and restored via GameState.restore_run().
##
## Saved with ResourceSaver as user://saves/run_<slot>.tres. save_version gates
## future migrations.

const SAVE_VERSION: int = 1

@export var save_version: int = SAVE_VERSION
@export var session: RunSession

# --- Faction domain ---
@export var ownership: Dictionary = {}
@export var homeworlds: Dictionary = {}
@export var starting_workers: Dictionary = {}
@export var known_planets: Dictionary = {}
@export var scanned_planets: Dictionary = {}
@export var scan_intel: Dictionary = {}
@export var milestones: Dictionary = {}

# --- Economy domain ---
@export var faction_vaults: Dictionary = {}
@export var faction_credits: Dictionary = {}
@export var worker_reservations: Dictionary = {}
@export var upgrade_build_jobs: Dictionary = {}
@export var planet_resources: Dictionary = {}
@export var planet_upgrades: Dictionary = {}
@export var worker_factories: Dictionary = {}
@export var gathering_workers: Dictionary = {}
@export var gathering_sources: Dictionary = {}
@export var local_vaults: Dictionary = {}
@export var trade_routes: Dictionary = {}
@export var planet_buildings: Dictionary = {}
@export var building_jobs: Dictionary = {}
@export var local_seeded_planets: Dictionary = {}
@export var worker_transport_records: Dictionary = {}
@export var next_trade_route_index: int = 0
@export var next_worker_transport_index: int = 0

# --- Tech domain ---
@export var researched_techs: Dictionary = {}
@export var planet_technologies: Dictionary = {}
@export var research_jobs: Dictionary = {}

# --- Ship domain ---
@export var ship_part_inventory: Dictionary = {}
@export var ship_assemblies: Dictionary = {}
@export var ship_build_jobs: Dictionary = {}
## ship_id -> {faction, mission_role, current_planet_id, status,
##             active_mission_id, fleet: FleetSnapshot}
@export var persistent_ships: Dictionary = {}
## mission_id -> {mission_id, target_planet_id, task_type, duration, remaining, status}
@export var research_missions: Dictionary = {}
@export var next_ship_index: int = 0
@export var next_research_mission_index: int = 0

# --- Transits ---
@export var transits: Array[TransitRecord] = []
@export var next_transit_index: int = 0

# --- Infinite chunk world ---
@export var chunk_data: ChunkSaveData

# --- Pacing timers (economy/gather tick remaining, seconds) ---
@export var timers: Dictionary = {}

## Canonical, comparable representation of the snapshot. Normalizes
## String/StringName differences and float precision introduced by the .tres
## roundtrip, so save_game_roundtrip can assert lossless equality.
static func comparable(data: RunSaveData) -> Dictionary:
	if data == null:
		return {}
	var result := {}
	for prop in data.get_property_list():
		var prop_name: String = String(prop.name)
		if prop_name == "script" or prop_name.begins_with("_"):
			continue
		if not (prop.usage & PROPERTY_USAGE_STORAGE):
			continue
		result[prop_name] = _canonical(data.get(prop.name))
	return result

static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key in value:
			out[String(key)] = _canonical(value[key])
		return out
	if value is Array:
		var out := []
		for item in value:
			out.append(_canonical(item))
		return out
	if value is StringName:
		return String(value)
	if value is float:
		return roundf(value * 10000.0) / 10000.0
	if value is Resource:
		var out := {}
		for prop in value.get_property_list():
			var prop_name: String = String(prop.name)
			if prop_name == "script" or prop_name.begins_with("_") or prop_name == "resource_path" or prop_name == "resource_name" or prop_name == "resource_local_to_scene":
				continue
			if not (prop.usage & PROPERTY_USAGE_STORAGE):
				continue
			out[prop_name] = _canonical(value.get(prop.name))
		return out
	return value

static func restore_dict(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source:
		var new_key: Variant = key
		if key is String:
			new_key = StringName(key)
		var value: Variant = source[key]
		if value is Dictionary:
			value = restore_dict(value)
		elif value is Array:
			value = restore_array(value)
		result[new_key] = value
	return result

static func restore_array(source: Array) -> Array:
	var result := []
	for item in source:
		if item is Dictionary:
			result.append(restore_dict(item))
		elif item is Array:
			result.append(restore_array(item))
		else:
			result.append(item)
	return result
