class_name ChainDetector
extends RefCounted

## Erkennt Zusammenhänge zwischen HistoryEvents und gruppiert sie zu aussagekräftigen EventChains.
## Erkennt: Kriegs-Verläufe, Diplomatie-Phasen, Figuren-Karrieren und Kolonisations-Wellen.

const MAX_CHAIN_GAP: int = 15


func detect_chains(events: Array[HistoryEvent]) -> Array[EventChain]:
	if events.is_empty():
		return []

	var chains: Array[EventChain] = []
	var used_events: Dictionary = {}

	var sorted_events: Array[HistoryEvent] = events.duplicate()
	sorted_events.sort_custom(func(a, b): return a.year < b.year)

	# 1. Kausal-Ketten aus expliziten cause_event_id Beziehungen
	var causal_chains: Array[EventChain] = _detect_causal_chains(sorted_events, used_events)
	chains.append_array(causal_chains)

	# 2. Kriegs-Verläufe
	var war_chains: Array[EventChain] = _detect_war_chains(sorted_events, used_events)
	chains.append_array(war_chains)

	# 3. Diplomatische Verläufe (Bündnisse, Verträge, Rivalitäten)
	var diplo_chains: Array[EventChain] = _detect_diplomatic_chains(sorted_events, used_events)
	chains.append_array(diplo_chains)

	# 4. Figuren-Schicksale (echte char_id)
	var char_chains: Array[EventChain] = _detect_character_chains(sorted_events, used_events)
	chains.append_array(char_chains)

	# Benennung
	_name_chains(chains, events)

	return chains


func _detect_causal_chains(events: Array[HistoryEvent], used: Dictionary) -> Array[EventChain]:
	var chains: Array[EventChain] = []

	for event in events:
		if used.has(event.event_id):
			continue
		if String(event.cause_event_id).is_empty():
			continue

		# Finde die Kausalitätskette rückwärts und vorwärts
		var chain_events: Array[HistoryEvent] = [event]
		var current_id: StringName = event.cause_event_id

		# Rückwärts
		while not String(current_id).is_empty():
			var prev: HistoryEvent = _find_event_by_id(events, current_id)
			if prev == null or used.has(prev.event_id) or chain_events.has(prev):
				break
			chain_events.push_front(prev)
			current_id = prev.cause_event_id

		if chain_events.size() >= 3:
			var chain := EventChain.new()
			chain.chain_id = StringName("chain_causal_%d" % chains.size())
			for ev in chain_events:
				chain.add_event(ev.event_id, ev.year)
				used[ev.event_id] = true
				for a in ev.actors:
					if not chain.participants.has(a):
						chain.participants.append(a)
			chains.append(chain)

	return chains


func _detect_war_chains(events: Array[HistoryEvent], used: Dictionary) -> Array[EventChain]:
	var chains: Array[EventChain] = []

	for event in events:
		if used.has(event.event_id):
			continue
		if event.event_type not in [&"war_declared", &"attack", &"conquest", &"defeat", &"peace_treaty"]:
			continue

		var chain := EventChain.new()
		chain.chain_id = StringName("chain_war_%d" % chains.size())
		chain.add_event(event.event_id, event.year)
		used[event.event_id] = true

		var factions: Array[StringName] = _extract_factions(event.actors)
		chain.participants = factions.duplicate()

		for other in events:
			if used.has(other.event_id):
				continue
			if other.event_type not in [&"war_declared", &"attack", &"conquest", &"defeat"]:
				continue

			var other_factions: Array[StringName] = _extract_factions(other.actors)
			if _share_actors(factions, other_factions) and absi(other.year - event.year) <= MAX_CHAIN_GAP:
				chain.add_event(other.event_id, other.year)
				used[other.event_id] = true
				for f in other_factions:
					if not chain.participants.has(f):
						chain.participants.append(f)

		if chain.event_count() >= 2:
			var last_event: HistoryEvent = _find_event_by_id(events, chain.events[chain.events.size() - 1])
			if last_event != null:
				if last_event.event_type == &"peace_treaty":
					chain.resolution = &"peace_treaty"
				elif last_event.event_type == &"conquest":
					chain.resolution = StringName("victory_%s" % String(last_event.winner))
				elif last_event.event_type == &"defeat":
					chain.resolution = &"stalemate"
				else:
					chain.resolution = &"unresolved"
			chains.append(chain)

	return chains


func _detect_diplomatic_chains(events: Array[HistoryEvent], used: Dictionary) -> Array[EventChain]:
	var chains: Array[EventChain] = []

	for event in events:
		if used.has(event.event_id):
			continue
		if event.event_type not in [&"trade", &"alliance", &"rivalry"]:
			continue

		var chain := EventChain.new()
		chain.chain_id = StringName("chain_diplo_%d" % chains.size())
		chain.add_event(event.event_id, event.year)
		used[event.event_id] = true
		chain.participants = _extract_factions(event.actors)

		for other in events:
			if used.has(other.event_id):
				continue
			if other.event_type not in [&"trade", &"alliance", &"rivalry"]:
				continue
			var other_factions: Array[StringName] = _extract_factions(other.actors)
			if _share_actors(chain.participants, other_factions) and absi(other.year - event.year) <= MAX_CHAIN_GAP:
				chain.add_event(other.event_id, other.year)
				used[other.event_id] = true
				for f in other_factions:
					if not chain.participants.has(f):
						chain.participants.append(f)

		if chain.event_count() >= 2:
			chains.append(chain)

	return chains


func _detect_character_chains(events: Array[HistoryEvent], used: Dictionary) -> Array[EventChain]:
	var chains: Array[EventChain] = []
	var char_events: Dictionary = {}

	for event in events:
		var cid: String = event.context_dict.get("leader_char_id", "")
		if cid.is_empty():
			for a in event.actors:
				if String(a).begins_with("char_"):
					cid = String(a)
					break
		if cid.is_empty():
			continue

		var cname_key: StringName = StringName(cid)
		if not char_events.has(cname_key):
			char_events[cname_key] = []
		(char_events[cname_key] as Array).append(event)

	for cid in char_events:
		var evts: Array = char_events[cid]
		if evts.size() < 2:
			continue

		evts.sort_custom(func(a, b): return a.year < b.year)
		var chain := EventChain.new()
		chain.chain_id = StringName("chain_char_%s" % String(cid))
		for ev in evts:
			chain.add_event((ev as HistoryEvent).event_id, (ev as HistoryEvent).year)
		chain.participants.append(cid)
		chains.append(chain)

	return chains


func _name_chains(chains: Array[EventChain], events: Array[HistoryEvent]) -> void:
	for chain in chains:
		if not chain.title.is_empty():
			continue

		var first_event: HistoryEvent = _find_event_by_id(events, chain.events[0])
		var target_name: String = String(first_event.target) if first_event != null else ""

		if String(chain.chain_id).begins_with("chain_war"):
			if not target_name.is_empty():
				chain.title = "Der Konflikt um %s (%d–%d)" % [target_name, chain.start_year, chain.end_year]
			else:
				chain.title = "Kriegerische Auseinandersetzung (%d–%d)" % [chain.start_year, chain.end_year]
		elif String(chain.chain_id).begins_with("chain_diplo"):
			chain.title = "Diplomatische Verhandlungen (%d–%d)" % [chain.start_year, chain.end_year]
		elif String(chain.chain_id).begins_with("chain_char"):
			var leader_name: String = ""
			if first_event != null:
				leader_name = first_event.context_dict.get("leader_name", "")
			if not leader_name.is_empty():
				chain.title = "Das Wirken von %s (%d–%d)" % [leader_name, chain.start_year, chain.end_year]
			else:
				chain.title = "Historische Biografie (%d–%d)" % [chain.start_year, chain.end_year]
		else:
			chain.title = "Kausalitätsbogen (%d–%d)" % [chain.start_year, chain.end_year]


func _extract_factions(actors: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for a in actors:
		if not String(a).begins_with("char_"):
			result.append(a)
	return result


func _share_actors(actors_a: Array[StringName], actors_b: Array[StringName]) -> bool:
	for a in actors_a:
		if actors_b.has(a):
			return true
	return false


func _find_event_by_id(events: Array[HistoryEvent], event_id: StringName) -> HistoryEvent:
	for event in events:
		if event.event_id == event_id:
			return event
	return null
