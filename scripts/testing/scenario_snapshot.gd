class_name ScenarioSnapshot
extends Resource

## READ-Only scenario snapshot. Wraps a RunSaveData with metadata about
## which game mechanics this scenario exercises. The snapshot itself is
## immutable — the loader applies it to GameState without mutation of
## the resource.
##
## Convention: scenario files live in res://resources/scenarios/
## Naming: scenario_<phase>_<variant>.tres  (e.g. scenario_mid_basic.tres)

## --- Metadata ---

@export var scenario_id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var phase: StringName = &""  ## "early", "mid", "late", "crisis", "custom"
@export var mechanics_covered: Array[StringName] = []  ## Signal names this scenario exercises
@export var tags: Array[StringName] = []  ## Filter tags: "economy", "combat", "tech", etc.

## --- Snapshot Data ---

## The actual game state snapshot. READ-ONLY after creation.
@export var save_data: RunSaveData = null

## --- Seed Override ---

## If set, the loader applies this seed before restoring the snapshot.
## Useful for deterministic scenario replay.
@export var layout_seed_override: int = -1

## --- Validation ---

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(scenario_id).is_empty():
		errors.append("scenario_id is empty")
	if display_name.is_empty():
		errors.append("display_name is empty")
	if save_data == null:
		errors.append("save_data is null (no snapshot to load)")
	if phase.is_empty():
		errors.append("phase is empty")
	return errors

func is_valid() -> bool:
	return validate().is_empty()

## --- Helpers ---

func has_mechanic(mechanic_id: StringName) -> bool:
	return mechanic_id in mechanics_covered

func covers_domain(domain: StringName) -> bool:
	for tag in tags:
		if tag == domain:
			return true
	return false

func summary() -> String:
	var mech_count := mechanics_covered.size()
	var tag_list := ", ".join(tags)
	return "[%s] %s — %d mechanics, tags: %s" % [String(phase), display_name, mech_count, tag_list]
