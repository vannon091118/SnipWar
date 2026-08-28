class_name CauseTracker
extends RefCounted

## Verknüpft HistoryEvents über Kausalitätsketten.
## Jedes Event kann eine Ursache (cause_event_id) haben.
## Diese Klasse baut die Verknüpfungen auf und stellt Nachfolger-Abfragen bereit.

## Erkennt automatisch Kausalitäten basierend auf Zeitfenster und Actor-Overlap.
func auto_link(events: Array[HistoryEvent], window_years: int = 10) -> void:
	if events.is_empty():
		return

	var sorted: Array[HistoryEvent] = events.duplicate()
	sorted.sort_custom(func(a, b): return a.year < b.year)

	for i in range(sorted.size()):
		var event: HistoryEvent = sorted[i]
		if not String(event.cause_event_id).is_empty():
			continue  # Bereits verknüpft

		# Suche nach einer passenden Ursache im Zeitfenster
		var cause: HistoryEvent = _find_cause(event, sorted, i, window_years)
		if cause != null:
			event.cause_event_id = cause.event_id
			if String(event.cause_type).is_empty():
				event.cause_type = _infer_cause_type(cause, event)


## Gibt alle Nachfolger eines Events zurück.
func get_successors(event_id: StringName, events: Array[HistoryEvent]) -> Array[HistoryEvent]:
	var result: Array[HistoryEvent] = []
	for event in events:
		if event.cause_event_id == event_id:
			result.append(event)
	return result


## Gibt die vollständige Kausalitätskette zurück (Vorgänger → Event → Nachfolger).
func get_chain(event_id: StringName, events: Array[HistoryEvent]) -> Array[HistoryEvent]:
	var chain: Array[HistoryEvent] = []
	var visited: Dictionary = {}

	# Rückwärts: Vorgänger finden
	var current_id: StringName = event_id
	while not String(current_id).is_empty():
		if visited.has(current_id):
			break
		visited[current_id] = true
		var event: HistoryEvent = _find_by_id(events, current_id)
		if event == null:
			break
		chain.push_front(event)
		current_id = event.cause_event_id

	# Vorwärts: Nachfolger finden
	current_id = event_id
	while not String(current_id).is_empty():
		if visited.has(current_id):
			break
		visited[current_id] = true
		var successors: Array[HistoryEvent] = get_successors(current_id, events)
		if successors.is_empty():
			break
		var next_event: HistoryEvent = successors[0]  # Erster Nachfolger
		chain.append(next_event)
		current_id = next_event.event_id

	return chain


func _find_cause(event: HistoryEvent, sorted: Array[HistoryEvent], current_index: int, window: int) -> HistoryEvent:
	# Suche rückwärts im Zeitfenster nach einem passenden Vorgänger
	for i in range(current_index - 1, maxi(current_index - 50, -1), -1):
		if i < 0:
			break
		var candidate: HistoryEvent = sorted[i]
		if event.year - candidate.year > window:
			break
		if _is_likely_cause(candidate, event):
			return candidate
	return null


func _is_likely_cause(cause: HistoryEvent, effect: HistoryEvent) -> bool:
	# Gleiche Fraktionen beteiligt
	if _share_actors(cause.actors, effect.actors):
		return true
	# Territorialer Zusammenhang
	if not String(cause.territory_change).is_empty() and cause.territory_change == effect.target:
		return true
	# Beziehungs-Kette (Rivalität → Krieg)
	if cause.event_type == &"rivalry" and effect.event_type == &"war_declared":
		return true
	if cause.event_type == &"war_declared" and effect.event_type in [&"attack", &"conquest", &"defeat"]:
		return true
	return false


func _infer_cause_type(cause: HistoryEvent, _effect: HistoryEvent) -> StringName:
	if cause.event_type in [&"trade", &"alliance", &"rivalry"]:
		return &"relationship"
	if cause.event_type == &"research":
		return &"technology"
	if not String(cause.territory_change).is_empty():
		return &"territory"
	return &"event"


func _share_actors(actors_a: Array[StringName], actors_b: Array[StringName]) -> bool:
	for a in actors_a:
		if actors_b.has(a):
			return true
	return false


func _find_by_id(events: Array[HistoryEvent], event_id: StringName) -> HistoryEvent:
	for event in events:
		if event.event_id == event_id:
			return event
	return null
