class_name ImportanceEvaluator
extends RefCounted

## Bewertet jedes HistoryEvent auf importance = 0.0 .. 1.0.
## Bestimmt welche Events in die Chronik aufgenommen werden und welche nicht.

## Gewichtungsfaktoren.
const W_TERRITORY: float = 0.25
const W_CASUALTIES: float = 0.20
const W_FACTION_CHANGE: float = 0.20
const W_TECH_SIGNIFICANCE: float = 0.15
const W_CHARACTER_SIGNIFICANCE: float = 0.10
const W_RELATIONSHIP: float = 0.10

## Schwellenwerte für Chronik-Aufnahme.
const THRESHOLD_INVISIBLE: float = 0.20
const THRESHOLD_MINOR: float = 0.45
const THRESHOLD_NORMAL: float = 0.70
const THRESHOLD_MAJOR: float = 0.90
const THRESHOLD_TURNING_POINT: float = THRESHOLD_MAJOR


## Berechnet die importance für ein einzelnes Event.
func evaluate(event: HistoryEvent, world: WorldState = null) -> float:
	var score: float = 0.0

	# Territoriumswechsel
	if not String(event.territory_change).is_empty():
		score += W_TERRITORY

	# Verluste
	if event.casualties > 0:
		var normalized: float = clampf(float(event.casualties) / 100.0, 0.0, 1.0)
		score += W_CASUALTIES * normalized

	# Fraktionswechsel (Krieg erklärt, Bündnis, Rivalität)
	if event.event_type in [&"war_declared", &"alliance", &"rivalry"]:
		score += W_FACTION_CHANGE

	# Technologische Signifikanz
	if event.event_type == &"research" and event.importance >= 0.3:
		score += W_TECH_SIGNIFICANCE

	# Figuren-Signifikanz (Tod einer Figur, neue Ränge)
	if event.event_type == &"die" or event.context_dict.has("rank_change"):
		score += W_CHARACTER_SIGNIFICANCE

	# Beziehungsimpact
	var rel_impact: float = absf(float(event.relationship_change)) / 100.0
	score += W_RELATIONSHIP * clampf(rel_impact, 0.0, 1.0)

	# Bonus für bereits hohe importance aus Factory
	score = maxf(score, event.importance)

	return clampf(score, 0.0, 1.0)


## Bewertet alle Events und setzt importance.
func evaluate_all(events: Array[HistoryEvent], world: WorldState = null) -> void:
	for event in events:
		event.importance = evaluate(event, world)


## Kategorisiert importance in Chronik-Relevanz.
func categorize(importance: float) -> StringName:
	if importance >= THRESHOLD_MAJOR:
		return &"turning_point"
	elif importance >= THRESHOLD_NORMAL:
		return &"major"
	elif importance >= THRESHOLD_MINOR:
		return &"normal"
	elif importance >= THRESHOLD_INVISIBLE:
		return &"minor"
	else:
		return &"invisible"


## Gibt true zurück wenn das Event in die Chronik aufgenommen werden soll.
func should_include(importance: float) -> bool:
	return importance >= THRESHOLD_INVISIBLE


## Filtert Events nach Relevanz.
func relevant_events(events: Array[HistoryEvent]) -> Array[HistoryEvent]:
	var result: Array[HistoryEvent] = []
	for event in events:
		if should_include(event.importance):
			result.append(event)
	return result
