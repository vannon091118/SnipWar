class_name HistoricalSnapshot
extends RefCounted

## Reine Datenklasse: Zustand der Weltsimulation zu einem Zeitpunkt.
## Wird vom HistorySimulator abgeleitet (ausschließlich lesend — kein
## RNG-Zugriff, keine Event-Mutation) und vom PlaybackController bzw.
## HistoricalRenderer konsumiert.
##
## Enthält KEINE Narrative-Regeln und KEINE Simulator-Referenz: Der Renderer
## darf nur diese Klasse kennen (Presentation-Boundary, §14).

var year: int = 0
var ownership: Dictionary = {}        # planet_id → faction_id
var events: Array[HistoryEvent] = []  # Events bis einschließlich year


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