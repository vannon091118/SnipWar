class_name HistoricalSnapshot
extends RefCounted

## Reine Datenklasse: Zustand der Weltsimulation zu einem Zeitpunkt.
## Wird vom HistorySimulator abgeleitet (ausschließlich lesend — kein
## RNG-Zugriff, keine Event-Mutation) und vom PlaybackController bzw.
## HistoricalRenderer konsumiert.
##
## Enthält KEINE Narrative-Regeln und KEINE Simulator-Referenz: Der Renderer
## darf nur diese Klasse kennen (Presentation-Boundary, §14).

const SCHEMA_VERSION: int = 2

var year: int = 0
var ownership: Dictionary = {}        # planet_id → faction_id
var events: Array[HistoryEvent] = []  # Events bis einschließlich year
var visual_state: Dictionary = {}     # planet_id → derived presentation state


func to_dict() -> Dictionary:
	var serialized_events: Array[Dictionary] = []
	for event in events:
		serialized_events.append(event.to_dict())
	return {
		"schema_version": SCHEMA_VERSION,
		"year": year,
		"ownership": ownership.duplicate(true),
		"events": serialized_events,
		"visual_state": visual_state.duplicate(true),
	}


static func from_dict(data: Dictionary) -> HistoricalSnapshot:
	var snapshot := HistoricalSnapshot.new()
	snapshot.year = int(data.get("year", 0))
	snapshot.ownership = data.get("ownership", {}).duplicate(true)
	snapshot.visual_state = data.get("visual_state", {}).duplicate(true)
	for raw_event in data.get("events", []):
		if raw_event is Dictionary:
			snapshot.events.append(HistoryEvent.from_dict(raw_event))
	return snapshot


func event_count() -> int:
	return events.size()


func owner_of(planet_id: StringName) -> StringName:
	return ownership.get(planet_id, &"") as StringName


func faction_planets(fid: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for pid in ownership:
		if ownership[pid] == fid:
			result.append(pid as StringName)
	return result