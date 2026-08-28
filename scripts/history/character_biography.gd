@tool
class_name CharacterBiography
extends Resource

## Lebenslauf einer historischen Figur in der Weltgeschichte.
## Wird von HistorySimulator erzeugt und im Laufe der Simulation aktualisiert.
## Enthält Karriere, Beziehungen, Errungenschaften und Ruhm.

## Eindeutige Figuren-ID (z.B. "char_17").
@export var char_id: StringName = &""

## Anzeigename (z.B. "Kael", "Nera").
@export var name: String = ""

## Zugehörige Fraktion (Fraktion-ID).
@export var faction: StringName = &""

## Geburtsjahr (negativ = Vorgeschichte).
@export var birth_year: int = 0

## Todesjahr (-99999 = noch am Leben).
@export var death_year: int = -99999

## Rang-Verlauf: [{year: int, rank: String}]
@export var rank_history: Array[Dictionary] = []

## Bekannte Ereignisse (Event-IDs).
@export var known_events: Array[StringName] = []

## Errungenschaften (freier Text, nur für Chronik-Referenz).
@export var achievements: Array[String] = []

## Fehler/Niederlagen (freier Text).
@export var failures: Array[String] = []

## Beziehungen zu anderen Figuren: {char_id: int (-100..+100)}
@export var relationships: Dictionary = {}

## Ruf/Reputation: -1.0 (gehasst) bis 1.0 (verehrt).
@export var reputation: float = 0.0

## Aktueller Rang (zuletzt aus rank_history).
@export var current_rank: String = ""


func is_alive() -> bool:
	return death_year == -99999


func is_dead_at(year: int) -> bool:
	return death_year != -99999 and death_year <= year


func lifetime_years() -> int:
	if death_year == -99999:
		return 0
	return death_year - birth_year


func add_rank(year: int, rank: String) -> void:
	rank_history.append({"year": year, "rank": rank})
	current_rank = rank


func add_event(event_id: StringName) -> void:
	if not known_events.has(event_id):
		known_events.append(event_id)


func add_achievement(text: String) -> void:
	if not achievements.has(text):
		achievements.append(text)


func add_failure(text: String) -> void:
	if not failures.has(text):
		failures.append(text)


func set_relationship(other_char_id: StringName, sentiment: int) -> void:
	relationships[String(other_char_id)] = clampi(sentiment, -100, 100)


func get_relationship(other_char_id: StringName) -> int:
	return int(relationships.get(String(other_char_id), 0))


func die(year: int) -> void:
	if death_year == -99999:
		death_year = year


func copy() -> CharacterBiography:
	var b := CharacterBiography.new()
	b.char_id = char_id
	b.name = name
	b.faction = faction
	b.birth_year = birth_year
	b.death_year = death_year
	b.rank_history = rank_history.duplicate(true)
	b.known_events = known_events.duplicate()
	b.achievements = achievements.duplicate()
	b.failures = failures.duplicate()
	b.relationships = relationships.duplicate(true)
	b.reputation = reputation
	b.current_rank = current_rank
	return b


func to_dict() -> Dictionary:
	return {
		"char_id": String(char_id),
		"name": name,
		"faction": String(faction),
		"birth_year": birth_year,
		"death_year": death_year,
		"rank_history": rank_history.duplicate(true),
		"known_events": known_events.map(func(e): return String(e)),
		"achievements": achievements.duplicate(),
		"failures": failures.duplicate(),
		"relationships": relationships.duplicate(true),
		"reputation": reputation,
		"current_rank": current_rank,
	}


static func from_dict(data: Dictionary) -> CharacterBiography:
	var b := CharacterBiography.new()
	b.char_id = StringName(str(data.get("char_id", "")))
	b.name = str(data.get("name", ""))
	b.faction = StringName(str(data.get("faction", "")))
	b.birth_year = int(data.get("birth_year", 0))
	b.death_year = int(data.get("death_year", -99999))
	b.rank_history = data.get("rank_history", []).duplicate(true)
	var raw_events: Array = data.get("known_events", [])
	b.known_events = raw_events.map(func(e): return StringName(str(e)))
	b.achievements = data.get("achievements", []).duplicate()
	b.failures = data.get("failures", []).duplicate()
	b.relationships = data.get("relationships", {}).duplicate(true)
	b.reputation = float(data.get("reputation", 0.0))
	b.current_rank = str(data.get("current_rank", ""))
	return b
