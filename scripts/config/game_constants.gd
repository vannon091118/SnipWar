@tool
class_name GameConstants
extends RefCounted

## Dependency-free canonical identifiers shared by Resource definitions and
## runtime domains. Keep values synchronized with GameState for compatibility.

const FACTION_PLAYER: StringName = &"a"
const FACTION_CPU: StringName = &"b"
const FACTION_NEUTRAL: StringName = &"neutral"
const FACTION_UNINHABITED: StringName = &"uninhabited"

const MISSION_MILITARY: StringName = &"military"
const MISSION_CARGO: StringName = &"cargo"
const MISSION_COLONY: StringName = &"colony"
const MISSION_COLLECT: StringName = &"collect"
const TECH_WORKER_AUTOMATION: StringName = &"worker_automation"

const RES_ENERGY: StringName = &"energy"
const RES_BIOMASS: StringName = &"biomass"
const RES_RARE: StringName = &"rare"
const RES_MATERIAL: StringName = &"material"
const RES_VOLATILE: StringName = &"volatile"

const ALL_RESOURCES: Array[StringName] = [
	RES_ENERGY,
	RES_BIOMASS,
	RES_RARE,
	RES_MATERIAL,
	RES_VOLATILE,
]

static func is_valid_resource(resource_id: StringName) -> bool:
	return resource_id in ALL_RESOURCES
