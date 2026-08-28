@tool
class_name HistoryEvent
extends Resource

## Sprachunabhängiger historischer Fakten-Datensatz.
## Erzeugt von HistorySimulator via HistoryEventFactory.
## Enthält KEINEN lokalisierter Text — nur strukturierte Fakten.
## Lokalisierung erfolgt über ChronicleTemplateResolver + locale CSV.

## Eindeutige Event-ID (z.B. "evt_004821").
@export var event_id: StringName = &""

## Jahr (negativ = Vorgeschichte, 0 = Spielstart).
@export var year: int = 0

## Event-Typ: conquest, defeat, research, colony, trade, alliance,
## rivalry, war_declared, attack, defend, capture, abandon, die, succeed, fail.
@export var event_type: StringName = &""

## Beteiligte Akteure (Fraktion-IDs oder Figuren-IDs).
@export var actors: Array[StringName] = []

## Ziel-Objekt (Planeten-ID, Technologie, etc.).
@export var target: StringName = &""

## Gewinner bei Konflikt-Events.
@export var winner: StringName = &""

## Verlierer bei Konflikt-Events.
@export var loser: StringName = &""

## Verluste bei militärischen Events.
@export var casualties: int = 0

## Beziehungsänderung (-100 bis +100).
@export var relationship_change: int = 0

## Territoriumswechsel (Planeten-ID).
@export var territory_change: StringName = &""

## Wichtigkeit 0.0..1.0 (berechnet von ImportanceEvaluator).
@export var importance: float = 0.0

## Zugehörige Ereigniskette (leer = isoliertes Ereignis).
@export var chain_id: StringName = &""

## Ursachen-Event (Kausalitätskette).
@export var cause_event_id: StringName = &""

## Art der Ursache: relationship, resource, technology, territory, character.
@export var cause_type: StringName = &""

## Textbeschreibung der Ursache (nur für Chronik-Referenz).
@export var trigger: String = ""

## Zusätzlicher Kontext (variabel je nach Event-Typ).
@export var context_dict: Dictionary = {}


func is_empty() -> bool:
	return String(event_id).is_empty()


func is_conflict() -> bool:
	return event_type in [&"conquest", &"defeat", &"attack", &"defend", &"capture", &"war_declared"]


func is_diplomatic() -> bool:
	return event_type in [&"trade", &"alliance", &"rivalry"]


func is_cultural() -> bool:
	return event_type in [&"research", &"colony", &"succeed", &"die"]


func copy() -> HistoryEvent:
	var e := HistoryEvent.new()
	e.event_id = event_id
	e.year = year
	e.event_type = event_type
	e.actors = actors.duplicate()
	e.target = target
	e.winner = winner
	e.loser = loser
	e.casualties = casualties
	e.relationship_change = relationship_change
	e.territory_change = territory_change
	e.importance = importance
	e.chain_id = chain_id
	e.cause_event_id = cause_event_id
	e.cause_type = cause_type
	e.trigger = trigger
	e.context_dict = context_dict.duplicate(true)
	return e


func to_dict() -> Dictionary:
	return {
		"event_id": String(event_id),
		"year": year,
		"event_type": String(event_type),
		"actors": actors.map(func(a): return String(a)),
		"target": String(target),
		"winner": String(winner),
		"loser": String(loser),
		"casualties": casualties,
		"relationship_change": relationship_change,
		"territory_change": String(territory_change),
		"importance": importance,
		"chain_id": String(chain_id),
		"cause_event_id": String(cause_event_id),
		"cause_type": String(cause_type),
		"trigger": trigger,
		"context_dict": context_dict.duplicate(true),
	}


static func from_dict(data: Dictionary) -> HistoryEvent:
	var e := HistoryEvent.new()
	e.event_id = StringName(str(data.get("event_id", "")))
	e.year = int(data.get("year", 0))
	e.event_type = StringName(str(data.get("event_type", "")))
	var raw_actors: Array = data.get("actors", [])
	var typed_actors: Array[StringName] = []
	for a in raw_actors:
		typed_actors.append(StringName(str(a)))
	e.actors = typed_actors
	e.target = StringName(str(data.get("target", "")))
	e.winner = StringName(str(data.get("winner", "")))
	e.loser = StringName(str(data.get("loser", "")))
	e.casualties = int(data.get("casualties", 0))
	e.relationship_change = int(data.get("relationship_change", 0))
	e.territory_change = StringName(str(data.get("territory_change", "")))
	e.importance = float(data.get("importance", 0.0))
	e.chain_id = StringName(str(data.get("chain_id", "")))
	e.cause_event_id = StringName(str(data.get("cause_event_id", "")))
	e.cause_type = StringName(str(data.get("cause_type", "")))
	e.trigger = str(data.get("trigger", ""))
	e.context_dict = data.get("context_dict", {}).duplicate(true)
	return e
