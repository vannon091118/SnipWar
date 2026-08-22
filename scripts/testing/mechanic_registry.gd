class_name MechanicRegistry
extends RefCounted

## READ-Only registry that discovers all game mechanics by reflecting on
## GameState signals. Each signal maps to a MechanicEntry with an optional
## test model path. New mechanics are automatically flagged as UNREGISTERED.
##
## Usage:
##   var registry := MechanicRegistry.new()
##   var unregistered := registry.discover_unregistered()
##   if not unregistered.is_empty():
##       push_warning("New mechanics found: " + str(unregistered))

## --- Mechanic Entry ---

class MechanicEntry extends RefCounted:
	var id: StringName           ## Signal name = mechanic identifier
	var description: String      ## Human-readable description
	var domain: StringName       ## Which domain owns this (economy, tech, ship, faction, world, combat, ui)
	var test_model_path: String  ## Path to test model resource, "" = none
	var verified: bool           ## Has a test model been validated?

	func _init(p_id: StringName = &"", p_desc: String = "", p_domain: StringName = &"", p_test_path: String = "") -> void:
		id = p_id
		description = p_desc
		domain = p_domain
		test_model_path = p_test_path
		verified = false

	func has_test_model() -> bool:
		return not test_model_path.is_empty()

	func to_dict() -> Dictionary:
		return {
			"id": String(id),
			"description": description,
			"domain": String(domain),
			"test_model": test_model_path,
			"verified": verified,
		}

## --- Registry State ---

var _entries: Dictionary = {}  ## id -> MechanicEntry
var _domain_hints: Dictionary = {}  ## signal_name -> domain hint (pre-populated)

func _init() -> void:
	_populate_domain_hints()
	_discover_from_game_state()

## --- Public API ---

## Returns all registered mechanics.
func get_all() -> Array[MechanicEntry]:
	var result: Array[MechanicEntry] = []
	for id in _entries:
		result.append(_entries[id] as MechanicEntry)
	return result

## Returns mechanics for a specific domain.
func get_by_domain(domain: StringName) -> Array[MechanicEntry]:
	var result: Array[MechanicEntry] = []
	for id in _entries:
		var entry: MechanicEntry = _entries[id] as MechanicEntry
		if entry.domain == domain:
			result.append(entry)
	return result

## Returns mechanics that have NO test model.
func discover_unregistered() -> Array[MechanicEntry]:
	var result: Array[MechanicEntry] = []
	for id in _entries:
		var entry: MechanicEntry = _entries[id] as MechanicEntry
		if not entry.has_test_model():
			result.append(entry)
	return result

## Returns mechanics whose test model path points to a non-existent file.
func discover_broken_models() -> Array[MechanicEntry]:
	var result: Array[MechanicEntry] = []
	for id in _entries:
		var entry: MechanicEntry = _entries[id] as MechanicEntry
		if entry.has_test_model() and not ResourceLoader.exists(entry.test_model_path):
			result.append(entry)
	return result

## Returns the total count of discovered mechanics.
func count() -> int:
	return _entries.size()

## Returns the count of mechanics with test models.
func count_registered() -> int:
	var n := 0
	for id in _entries:
		var entry: MechanicEntry = _entries[id] as MechanicEntry
		if entry.has_test_model():
			n += 1
	return n

## Summary string for reporting.
func summary() -> String:
	var total := count()
	var registered := count_registered()
	var unregistered := total - registered
	return "%d mechanics discovered, %d registered, %d unregistered" % [total, registered, unregistered]

## --- Discovery ---

func _discover_from_game_state() -> void:
	# Use the GameState autoload class to reflect signals.
	# We instantiate a temporary node to call get_signal_list() on.
	var gs_script: Script = preload("res://scripts/state/game_state.gd") as Script
	if gs_script == null:
		push_warning("MechanicRegistry: Cannot load GameState script")
		return
	var tmp: Node = gs_script.new() as Node
	if tmp == null:
		push_warning("MechanicRegistry: Cannot instantiate GameState for reflection")
		return
	# Use get_script_signal_list() to only get signals declared in GameState
	# (not inherited ones from Node/Object)
	var signals: Array[Dictionary] = tmp.get_script().get_script_signal_list()
	for sig in signals:
		var sig_name: StringName = sig.get("name", &"") as StringName
		if String(sig_name).is_empty():
			continue
		if _entries.has(sig_name):
			continue
		var domain: StringName = _domain_hints.get(sig_name, &"unknown") as StringName
		var desc := _describe_signal(sig_name)
		var test_path := _auto_test_path(sig_name)
		var entry := MechanicEntry.new(sig_name, desc, domain, test_path)
		_entries[sig_name] = entry
	tmp.queue_free()

## Maps signal names to domains based on known architecture.
func _populate_domain_hints() -> void:
	# Economy Domain
	_domain_hints[&"faction_resources_changed"] = &"economy"
	_domain_hints[&"credits_changed"] = &"economy"
	_domain_hints[&"workers_reserved"] = &"economy"
	_domain_hints[&"workers_released"] = &"economy"
	_domain_hints[&"planet_upgraded"] = &"economy"
	_domain_hints[&"resource_generated"] = &"economy"
	_domain_hints[&"resources_collected"] = &"economy"
	_domain_hints[&"gathering_started"] = &"economy"
	_domain_hints[&"gathering_withdrawn"] = &"economy"
	_domain_hints[&"worker_factory_built"] = &"economy"
	_domain_hints[&"refinery_converted"] = &"economy"
	_domain_hints[&"local_resources_changed"] = &"economy"
	_domain_hints[&"resource_transferred"] = &"economy"
	_domain_hints[&"building_placed"] = &"economy"
	_domain_hints[&"building_removed"] = &"economy"
	_domain_hints[&"planet_building_placed"] = &"economy"
	_domain_hints[&"planet_building_destroyed"] = &"economy"
	_domain_hints[&"worker_transport_started"] = &"economy"
	_domain_hints[&"worker_transport_phase_changed"] = &"economy"
	# Faction Domain
	_domain_hints[&"faction_changed"] = &"faction"
	_domain_hints[&"planet_discovered"] = &"faction"
	_domain_hints[&"planet_scanned"] = &"faction"
	_domain_hints[&"milestone_reached"] = &"faction"
	# Tech Domain
	_domain_hints[&"technology_researched"] = &"tech"
	_domain_hints[&"planet_technology_researched"] = &"tech"
	_domain_hints[&"research_started"] = &"tech"
	# Ship Domain
	_domain_hints[&"ship_part_purchased"] = &"ship"
	_domain_hints[&"ship_assembled"] = &"ship"
	_domain_hints[&"ship_disassembled"] = &"ship"
	_domain_hints[&"ship_launched"] = &"ship"
	_domain_hints[&"ship_lost"] = &"ship"
	_domain_hints[&"ship_build_started"] = &"ship"
	_domain_hints[&"research_ship_task_completed"] = &"ship"
	_domain_hints[&"research_ship_idle"] = &"ship"
	_domain_hints[&"persistent_ship_changed"] = &"ship"
	# Transit
	_domain_hints[&"transit_changed"] = &"world"
	_domain_hints[&"run_started"] = &"world"
	# Combat
	_domain_hints[&"battle_context_changed"] = &"combat"
	_domain_hints[&"mid_game_started"] = &"world"
	# World
	_domain_hints[&"catalog_reset"] = &"world"

## Auto-generates a test model path based on convention.
func _auto_test_path(signal_name: StringName) -> String:
	# Convention: res://resources/test_models/mechanic_<signal_name>.tres
	# Returns empty string if no model exists yet.
	var path := "res://resources/test_models/mechanic_%s.tres" % String(signal_name)
	if ResourceLoader.exists(path):
		return path
	return ""

## Human-readable description for each known signal.
func _describe_signal(sig_name: StringName) -> String:
	match sig_name:
		&"faction_resources_changed": return "Faction vault resource amount changed"
		&"credits_changed": return "Faction credits changed"
		&"workers_reserved": return "Workers reserved for a job on a planet"
		&"workers_released": return "Workers released from a job"
		&"planet_upgraded": return "Planet upgrade completed"
		&"resource_generated": return "Resources generated on a planet"
		&"resources_collected": return "Resources collected by a gatherer"
		&"gathering_started": return "Gathering workers assigned to a planet"
		&"gathering_withdrawn": return "Gathering workers withdrawn"
		&"worker_factory_built": return "Worker factory constructed on a planet"
		&"refinery_converted": return "Refinery converted resources"
		&"local_resources_changed": return "Planet local resource vault changed"
		&"resource_transferred": return "Resource transferred between planets"
		&"building_placed": return "Building placed on planet grid"
		&"building_removed": return "Building removed from planet grid"
		&"faction_changed": return "Planet ownership changed between factions"
		&"planet_discovered": return "Planet discovered by a faction"
		&"planet_scanned": return "Planet scanned revealing intel"
		&"milestone_reached": return "Faction milestone reached"
		&"technology_researched": return "Global technology researched"
		&"planet_technology_researched": return "Planet-specific technology researched"
		&"research_started": return "Research job started"
		&"ship_part_purchased": return "Ship part purchased"
		&"ship_assembled": return "Ship assembled from parts"
		&"ship_disassembled": return "Ship disassembled into parts"
		&"ship_launched": return "Ship dispatched from a planet"
		&"ship_lost": return "Ship destroyed"
		&"ship_build_started": return "Ship build job started"
		&"research_ship_task_completed": return "Research ship completed a task"
		&"research_ship_idle": return "Research ship returned to idle"
		&"persistent_ship_changed": return "Persistent ship status changed"
		&"transit_changed": return "Worker or ship transit state changed"
		&"run_started": return "New run session started"
		&"planet_building_placed": return "Building placed on planet grid"
		&"planet_building_destroyed": return "Building destroyed on planet grid"
		&"worker_transport_started": return "Worker transport dispatched"
		&"worker_transport_phase_changed": return "Worker transport phase changed"
		&"battle_context_changed": return "Battle context prepared for Layer 2/3"
		&"mid_game_started": return "Mid-game phase triggered"
		&"catalog_reset": return "Planet catalog reset (new run or seed change)"
		_: return "Unknown mechanic — add description to _describe_signal()"
