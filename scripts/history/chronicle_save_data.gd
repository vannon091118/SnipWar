@tool
class_name ChronicleSaveData
extends Resource

## Persistenz-Resource für die Weltchronik.
## Wird in RunSaveData.chronicle eingebettet.
## Ein Save = ein Run = eine Wahrheit.

## Historische Events (Vorgeschichte + Live).
@export var backstory_events: Array[HistoryEvent] = []
@export var live_events: Array[HistoryEvent] = []

## Figuren-Biografien.
@export var biographies: Array[CharacterBiography] = []

## Ereignisketten.
@export var chains: Array[EventChain] = []

## Epochen-Definitionen.
@export var eras: Array[Dictionary] = []

## Beziehungs-Matrix (finale Beziehungen nach Vorgeschichte).
@export var relationships: Dictionary = {}

## Jahr des letzten Events.
@export var last_event_year: int = 0

## Aktuelle Locale.
@export var locale: String = "de"

## Monotonically increasing live-event counter. Backstory event IDs and live
## event IDs share this counter to prevent collisions after save/load.
@export var next_live_event_index: int = 0


## Creates a deep copy suitable for RunSaveData snapshots.
func copy() -> ChronicleSaveData:
	return from_snapshot_dict(snapshot_dict())


func all_events() -> Array[HistoryEvent]:
	var result: Array[HistoryEvent] = []
	result.append_array(backstory_events)
	result.append_array(live_events)
	return result


func events_sorted() -> Array[HistoryEvent]:
	var all: Array[HistoryEvent] = all_events()
	all.sort_custom(func(a, b): return a.year < b.year)
	return all


func events_by_era(era_start: int, era_end: int) -> Array[HistoryEvent]:
	var result: Array[HistoryEvent] = []
	for event in all_events():
		if event.year >= era_start and event.year <= era_end:
			result.append(event)
	return result


func events_by_type(event_type: StringName) -> Array[HistoryEvent]:
	var result: Array[HistoryEvent] = []
	for event in all_events():
		if event.event_type == event_type:
			result.append(event)
	return result


func events_by_faction(fid: StringName) -> Array[HistoryEvent]:
	var result: Array[HistoryEvent] = []
	for event in all_events():
		if event.actors.has(fid):
			result.append(event)
	return result


func biography_for(char_id: StringName) -> CharacterBiography:
	for bio in biographies:
		if bio.char_id == char_id:
			return bio
	return null


func chain_for(chain_id: StringName) -> EventChain:
	for chain in chains:
		if chain.chain_id == chain_id:
			return chain
	return null


func add_live_event(event: HistoryEvent) -> void:
	if event == null:
		return
	live_events.append(event)
	last_event_year = maxi(last_event_year, event.year)


func next_live_event_id() -> StringName:
	next_live_event_index += 1
	return StringName("live_%06d" % next_live_event_index)


func snapshot_dict() -> Dictionary:
	return {
		"backstory_events": backstory_events.map(func(e): return e.to_dict()),
		"live_events": live_events.map(func(e): return e.to_dict()),
		"biographies": biographies.map(func(b): return b.to_dict()),
		"chains": chains.map(func(c): return c.to_dict()),
		"eras": eras.duplicate(true),
		"relationships": relationships.duplicate(true),
		"last_event_year": last_event_year,
		"locale": locale,
		"next_live_event_index": next_live_event_index,
	}


static func from_snapshot_dict(data: Dictionary) -> ChronicleSaveData:
	var save := ChronicleSaveData.new()
	var raw_backstory: Array = data.get("backstory_events", [])
	var typed_backstory: Array[HistoryEvent] = []
	for d in raw_backstory:
		typed_backstory.append(HistoryEvent.from_dict(d))
	save.backstory_events = typed_backstory
	var raw_live: Array = data.get("live_events", [])
	var typed_live: Array[HistoryEvent] = []
	for d in raw_live:
		typed_live.append(HistoryEvent.from_dict(d))
	save.live_events = typed_live
	var raw_bios: Array = data.get("biographies", [])
	var typed_bios: Array[CharacterBiography] = []
	for d in raw_bios:
		typed_bios.append(CharacterBiography.from_dict(d))
	save.biographies = typed_bios
	var raw_chains: Array = data.get("chains", [])
	var typed_chains: Array[EventChain] = []
	for d in raw_chains:
		typed_chains.append(EventChain.from_dict(d))
	save.chains = typed_chains
	save.eras = data.get("eras", []).duplicate(true)
	save.relationships = data.get("relationships", {}).duplicate(true)
	save.last_event_year = int(data.get("last_event_year", 0))
	save.locale = str(data.get("locale", "de"))
	save.next_live_event_index = int(data.get("next_live_event_index", save.live_events.size()))
	return save
