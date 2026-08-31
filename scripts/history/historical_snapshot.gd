class_name HistoricalSnapshot
extends RefCounted

## Reine Datenklasse: Zustand der Weltsimulation zu einem Zeitpunkt.
## Wird vom HistorySimulator abgeleitet (ausschließlich lesend — kein
## RNG-Zugriff, keine Event-Mutation) und vom PlaybackController bzw.
## HistoricalRenderer konsumiert.
##
## Enthält KEINE Narrative-Regeln und KEINE Simulator-Referenz: Der Renderer
## darf nur diese Klasse kennen (Presentation-Boundary, §14).

const SCHEMA_VERSION: int = 3

var year: int = 0
var ownership: Dictionary = {}        # planet_id → faction_id
var events: Array[HistoryEvent] = []  # Events bis einschließlich year
var visual_state: Dictionary = {}     # planet_id → derived presentation state
var wars: Array[Dictionary] = []      # Kriegs-Truth je Snapshot (v3): status ongoing/ended
var truces: Dictionary = {}           # Kriegsschlüssel → end_year, nur aktive (v3)
var economy_state: Dictionary = {}     # faction_id → deterministic economy values


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
		"wars": wars.duplicate(true),
		"truces": truces.duplicate(true),
		"economy_state": economy_state.duplicate(true),
	}


static func from_dict(data: Dictionary) -> HistoricalSnapshot:
	var snapshot := HistoricalSnapshot.new()
	snapshot.year = int(data.get("year", 0))
	snapshot.ownership = data.get("ownership", {}).duplicate(true)
	snapshot.visual_state = data.get("visual_state", {}).duplicate(true)
	# v2 → v3 Migration: fehlende wars/truces = leer (alte Saves laden fehlerfrei).
	var raw_wars: Array = data.get("wars", [])
	for raw_war in raw_wars:
		if raw_war is Dictionary:
			snapshot.wars.append(raw_war.duplicate(true))
	snapshot.truces = data.get("truces", {}).duplicate(true)
	snapshot.economy_state = data.get("economy_state", {}).duplicate(true)
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