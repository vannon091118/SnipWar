@tool
class_name RunSession
extends Resource

## Typed context bridge for the current run.
##
## Owned by GameState and serialized into RunSaveData. It is the single
## handover record between scenes: the world scene rebuilds itself from
## (scenario_id, layout_seed, infinite_world) via reconnect_world(), while
## battle/conquest scenes receive their payload through BattleContext.

@export var run_id: StringName = &""
@export var scenario_id: StringName = &""
@export var layout_seed: int = 0
@export var infinite_world: bool = false
@export var started_at: int = 0
## Save slot this run was restored from (-1 = not bound to a slot).
@export var save_slot: int = -1
## Deterministic future start candidates for the active run. Candidates do not
## imply ownership or a selected homeworld.
@export var start_roster: Array[Dictionary] = []

func copy() -> RunSession:
	return duplicate(true) as RunSession
