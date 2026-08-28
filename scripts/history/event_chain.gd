@tool
class_name EventChain
extends Resource

## Zusammenhängende Ereignis-Arc (z.B. "Der Krieg um Krypton").
## Wird von ChainDetector erkannt und gruppiert.
## Enthält eine geordnete Liste von Event-IDs und Metadaten.

## Eindeutige Chain-ID (z.B. "chain_003").
@export var chain_id: StringName = &""

## Anzeigetitel (z.B. "Der Krieg um Krypton").
@export var title: String = ""

## Geordnete Event-IDs (chronologisch).
@export var events: Array[StringName] = []

## Startjahr der Kette.
@export var start_year: int = 0

## Endjahr der Kette.
@export var end_year: int = 0

## Auflösung: victory_a, victory_b, stalemate, collapse, peace, unresolved.
@export var resolution: StringName = &""

## Beteiligte Figuren/Fraktionen.
@export var participants: Array[StringName] = []


func duration_years() -> int:
	return end_year - start_year


func add_event(event_id: StringName, year: int) -> void:
	if not events.has(event_id):
		events.append(event_id)
	if events.size() == 1 or year < start_year:
		start_year = year
	if events.size() == 1 or year > end_year:
		end_year = year


func is_active_at(year: int) -> bool:
	return year >= start_year and year <= end_year


func event_count() -> int:
	return events.size()


func copy() -> EventChain:
	var c := EventChain.new()
	c.chain_id = chain_id
	c.title = title
	c.events = events.duplicate()
	c.start_year = start_year
	c.end_year = end_year
	c.resolution = resolution
	c.participants = participants.duplicate()
	return c


func to_dict() -> Dictionary:
	return {
		"chain_id": String(chain_id),
		"title": title,
		"events": events.map(func(e): return String(e)),
		"start_year": start_year,
		"end_year": end_year,
		"resolution": String(resolution),
		"participants": participants.map(func(p): return String(p)),
	}


static func from_dict(data: Dictionary) -> EventChain:
	var c := EventChain.new()
	c.chain_id = StringName(str(data.get("chain_id", "")))
	c.title = str(data.get("title", ""))
	var raw_events: Array = data.get("events", [])
	var typed_events: Array[StringName] = []
	for e in raw_events:
		typed_events.append(StringName(str(e)))
	c.events = typed_events
	c.start_year = int(data.get("start_year", 0))
	c.end_year = int(data.get("end_year", 0))
	c.resolution = StringName(str(data.get("resolution", "")))
	var raw_participants: Array = data.get("participants", [])
	var typed_participants: Array[StringName] = []
	for p in raw_participants:
		typed_participants.append(StringName(str(p)))
	c.participants = typed_participants
	return c
