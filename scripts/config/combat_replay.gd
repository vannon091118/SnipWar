@tool
class_name CombatReplay
extends Resource

const CURRENT_SCHEMA_VERSION: int = 1
const TYPE_BATTLE: StringName = &"battle"
const TYPE_CONQUEST: StringName = &"conquest"

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var simulation_type: StringName = &""
@export var duration: float = 0.0
@export var battle_seed: int = 1337
@export var conquest_seed: int = 42

@export_group("Battle")
@export var winner: StringName = &"neutral"
@export var survivors_a: Array[Dictionary] = []
@export var survivors_b: Array[Dictionary] = []
@export var events: Array[BattleEvent] = []

@export_group("Conquest")
@export var captured: bool = false
@export var surviving_attackers: int = 0
@export var surviving_garrison: int = 0
@export var attacker_initial_hp: float = 0.0
@export var attacker_initial_dps: float = 0.0
@export var defender_initial_hp: float = 0.0
@export var defender_initial_dps: float = 0.0
@export var attacker_workers: int = 0
@export var defending_workers: int = 0
@export var defense_rating: int = 0
@export var perimeter_slots: int = 0
@export var tower_count: int = 0
@export var defense_range: float = 0.0

@export_group("Planet Identity")
## Replays persist stable planet and asset identities, not a direct Texture2D
## reference. ConquestScene resolves the asset path first, then its catalog.
@export var planet_id: StringName = &""
@export var planet_name: String = ""
@export var planet_texture_path: String = ""

## Transitional compatibility only. Legacy dictionaries sometimes carried a
## direct texture reference; it is intentionally not exported or serialized.
var legacy_planet_texture: Texture2D


static func new_battle(seed_value: int = 1337) -> CombatReplay:
	var replay := CombatReplay.new()
	replay.simulation_type = TYPE_BATTLE
	replay.battle_seed = seed_value
	return replay


static func new_conquest(seed_value: int = 42) -> CombatReplay:
	var replay := CombatReplay.new()
	replay.simulation_type = TYPE_CONQUEST
	replay.conquest_seed = seed_value
	return replay


func is_battle() -> bool:
	return simulation_type == TYPE_BATTLE


func is_conquest() -> bool:
	return simulation_type == TYPE_CONQUEST


func copy() -> CombatReplay:
	return duplicate(true) as CombatReplay


## Accepts the typed contract or a legacy result Dictionary at a boundary. New
## producers and consumers should keep the returned CombatReplay typed; this
## adapter prevents older hand-authored replay callers from breaking at once.
static func coerce(value: Variant, fallback_type: StringName = &"") -> CombatReplay:
	if value is CombatReplay:
		return value as CombatReplay
	if value is Dictionary:
		return from_dictionary(value as Dictionary, fallback_type)
	return null


static func from_dictionary(source: Dictionary, fallback_type: StringName = &"") -> CombatReplay:
	var inferred_type: StringName = _string_name(source.get("simulation_type", fallback_type), fallback_type)
	if String(inferred_type).is_empty():
		inferred_type = TYPE_CONQUEST if source.has("captured") else TYPE_BATTLE
	var replay := CombatReplay.new()
	replay.schema_version = int(source.get("schema_version", CURRENT_SCHEMA_VERSION))
	replay.simulation_type = inferred_type
	replay.duration = float(source.get("duration", 0.0))
	replay.battle_seed = int(source.get("battle_seed", 1337))
	replay.conquest_seed = int(source.get("conquest_seed", 42))
	replay.winner = _string_name(source.get("winner", &"neutral"), &"neutral")
	replay.captured = bool(source.get("captured", false))
	replay.surviving_attackers = int(source.get("surviving_attackers", 5))
	replay.surviving_garrison = int(source.get("surviving_garrison", 1))
	replay.attacker_initial_hp = float(source.get("attacker_initial_hp", 0.0))
	replay.attacker_initial_dps = float(source.get("attacker_initial_dps", 0.0))
	replay.defender_initial_hp = float(source.get("defender_initial_hp", 0.0))
	replay.defender_initial_dps = float(source.get("defender_initial_dps", 0.0))
	replay.attacker_workers = int(source.get("attacker_workers", 0))
	replay.defending_workers = int(source.get("defending_workers", 0))
	replay.defense_rating = int(source.get("defense_rating", 0))
	replay.perimeter_slots = int(source.get("perimeter_slots", 3))
	replay.tower_count = int(source.get("tower_count", replay.perimeter_slots))
	replay.defense_range = float(source.get("defense_range", 150.0))
	replay.planet_id = _string_name(source.get("planet_id", &""))
	replay.planet_name = String(source.get("planet_name", ""))

	var raw_survivors_a: Array = source.get("survivors_a", []) as Array
	for survivor_value in raw_survivors_a:
		if survivor_value is Dictionary:
			replay.survivors_a.append((survivor_value as Dictionary).duplicate(true))
	var raw_survivors_b: Array = source.get("survivors_b", []) as Array
	for survivor_value in raw_survivors_b:
		if survivor_value is Dictionary:
			replay.survivors_b.append((survivor_value as Dictionary).duplicate(true))

	var raw_events: Array = source.get("events", []) as Array
	for event_value in raw_events:
		if event_value is BattleEvent:
			replay.events.append(event_value as BattleEvent)
		elif event_value is Dictionary:
			replay.events.append(BattleEvent.from_dictionary(event_value as Dictionary))

	var legacy_texture: Variant = source.get("planet_texture", null)
	if legacy_texture is Texture2D:
		replay.legacy_planet_texture = legacy_texture as Texture2D
		replay.planet_texture_path = (legacy_texture as Texture2D).resource_path
	var source_texture_path: Variant = source.get("planet_texture_path", null)
	if source_texture_path is String:
		replay.planet_texture_path = source_texture_path as String
	return replay


## Converts only the stable, serializable contract fields to a plain data
## representation for compatibility/debug output. Texture2D references are not
## included; planet_id is the portable visual identity.
func to_dictionary() -> Dictionary:
	var serialized_events: Array[Dictionary] = []
	for event in events:
		if event != null:
			serialized_events.append(event.to_dictionary())
	return {
		"schema_version": schema_version,
		"simulation_type": simulation_type,
		"duration": duration,
		"battle_seed": battle_seed,
		"conquest_seed": conquest_seed,
		"winner": winner,
		"survivors_a": survivors_a.duplicate(true),
		"survivors_b": survivors_b.duplicate(true),
		"events": serialized_events,
		"captured": captured,
		"surviving_attackers": surviving_attackers,
		"surviving_garrison": surviving_garrison,
		"attacker_initial_hp": attacker_initial_hp,
		"attacker_initial_dps": attacker_initial_dps,
		"defender_initial_hp": defender_initial_hp,
		"defender_initial_dps": defender_initial_dps,
		"attacker_workers": attacker_workers,
		"defending_workers": defending_workers,
		"defense_rating": defense_rating,
		"perimeter_slots": perimeter_slots,
		"tower_count": tower_count,
		"defense_range": defense_range,
		"planet_id": planet_id,
		"planet_name": planet_name,
		"planet_texture_path": planet_texture_path,
	}


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if schema_version < 1:
		errors.append("combat replay schema_version must be at least 1")
	if simulation_type != TYPE_BATTLE and simulation_type != TYPE_CONQUEST:
		errors.append("combat replay simulation_type is invalid: %s" % simulation_type)
	if duration < 0.0:
		errors.append("combat replay duration cannot be negative")
	for event in events:
		if event == null:
			errors.append("combat replay contains a null battle event")
	if is_conquest():
		if surviving_attackers < 0 or surviving_garrison < 0:
			errors.append("combat replay survivor counts cannot be negative")
		if perimeter_slots < 0 or tower_count < 0:
			errors.append("combat replay defense counts cannot be negative")
	return errors


static func _string_name(value: Variant, fallback: StringName = &"") -> StringName:
	if value is StringName:
		return value as StringName
	if value is String and not (value as String).is_empty():
		return StringName(value as String)
	return fallback
