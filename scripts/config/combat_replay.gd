@tool
class_name CombatReplay
extends Resource

const TYPE_BATTLE: StringName = &"battle"
const TYPE_CONQUEST: StringName = &"conquest"

@export var simulation_type: StringName = &""
@export var duration: float = 0.0
@export var battle_seed: int = 1337
@export var conquest_seed: int = 42

@export_group("Battle")
@export var winner: StringName = &"neutral"
@export var survivors_a: Array[ShipAssembly] = []
@export var survivors_b: Array[ShipAssembly] = []
@export var events: Array[BattleEvent] = []
@export var route_a: Array[Vector2] = []
@export var route_b: Array[Vector2] = []
@export var engagement_point: Vector2 = Vector2.ZERO
@export var engagement_type: StringName = &""
@export var engagement_time_a: float = 0.0
@export var engagement_time_b: float = 0.0

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

@export_group("Grid Conquest")
@export var base_hp_history: Array[float] = []
@export var wave_events: Array[BattleEvent] = []
@export var grid_snapshots: Array[Dictionary] = []

@export_group("Planet Identity")
## Replays carry stable planet and asset identities, not a direct Texture2D
## reference. ConquestScene resolves the asset path first, then its catalog.
@export var planet_id: StringName = &""
@export var planet_name: String = ""
@export var planet_texture_path: String = ""


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


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
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
