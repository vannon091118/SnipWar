class_name HistoryEventFactory
extends RefCounted

## Erzeugt strukturierte HistoryEvent-Objekte aus Aktionsergebnissen.
## Verknüpft handelnde Figuren, Zielwelten, explizite Kausalitätsanker und Kontext.

func create_event(
	action: Dictionary,
	world: WorldState,
	result_type: StringName,  # "success", "failure", "partial"
	cause_event_id: StringName = &"",
	cause_type: StringName = &""
) -> HistoryEvent:
	var event := HistoryEvent.new()
	event.event_id = world.next_event_id()
	event.year = world.year

	var actor_fid: StringName = action.get("actor", &"") as StringName
	event.actors.append(actor_fid)

	# Handelnde Figur als sekundärer Akteur
	var leader_cid: StringName = action.get("leader_char_id", &"") as StringName
	if not String(leader_cid).is_empty():
		event.actors.append(leader_cid)
		event.context_dict["leader_char_id"] = String(leader_cid)
		event.context_dict["leader_name"] = action.get("leader_name", "Unbekannt")
		event.context_dict["commander"] = action.get("leader_name", "Unbekannt")
		event.context_dict["character_name"] = action.get("leader_name", "Unbekannt")

	event.target = action.get("target", &"") as StringName
	var action_type: StringName = action.get("type", &"") as StringName

	match action_type:
		&"COLONIZE":
			_configure_colonize_event(event, action, world, result_type)
		&"BUILD":
			_configure_build_event(event, action, world, result_type)
		&"RESEARCH":
			_configure_research_event(event, action, world, result_type)
		&"TRADE":
			_configure_trade_event(event, action, world, result_type)
		&"ATTACK":
			_configure_attack_event(event, action, world, result_type)
		&"DECLARE_WAR":
			_configure_war_declared_event(event, action, world)
		&"PEACE_TREATY":
			_configure_peace_treaty_event(event, action, world)
		&"ALLY":
			_configure_ally_event(event, action, world)
		&"RIVAL":
			_configure_rival_event(event, action, world)

	# Kausalität
	if not String(cause_event_id).is_empty():
		event.cause_event_id = cause_event_id
		event.cause_type = cause_type
	elif action.has("cause_event_id"):
		event.cause_event_id = action.get("cause_event_id", &"") as StringName
		event.cause_type = action.get("cause_type", &"pressure") as StringName

	return event


func _configure_colonize_event(event: HistoryEvent, action: Dictionary, _world: WorldState, result_type: StringName) -> void:
	event.event_type = &"colony"
	if result_type == &"success":
		event.importance = 0.55
		event.territory_change = event.target
		event.trigger = action.get("trigger_reason", "Kolonie gegründet zur Rohstoffsicherung")
		event.relationship_change = -20  # Nachbarn betrachten Expansion mit Argwohn
	else:
		event.importance = 0.2
		event.trigger = "Kolonisierung gescheitert an feindlicher Umwelt"


func _configure_build_event(event: HistoryEvent, action: Dictionary, _world: WorldState, result_type: StringName) -> void:
	event.event_type = &"build"
	if result_type == &"success":
		event.importance = 0.25
		event.trigger = action.get("trigger_reason", "Infrastruktur ausgebaut")
	else:
		event.importance = 0.05
		event.trigger = "Bauprojekt durch Ressourcenengpass verzögert"


func _configure_research_event(event: HistoryEvent, action: Dictionary, _world: WorldState, result_type: StringName) -> void:
	event.event_type = &"research"
	if result_type == &"success":
		event.importance = 0.45
		event.trigger = action.get("trigger_reason", "Technologischer Durchbruch erzielt")
	else:
		event.importance = 0.1
		event.trigger = "Forschungsprogramm ergebnislos abgeschlossen"


func _configure_trade_event(event: HistoryEvent, action: Dictionary, _world: WorldState, result_type: StringName) -> void:
	event.event_type = &"trade"
	var partner: StringName = action.get("target", &"") as StringName
	if not event.actors.has(partner):
		event.actors.append(partner)

	if result_type == &"success":
		event.importance = 0.35
		event.relationship_change = 12
		event.trigger = action.get("trigger_reason", "Handelsabkommen zur gegenseitigen Versorgung")
	else:
		event.importance = 0.15
		event.relationship_change = -5
		event.trigger = "Handelsverhandlungen über Zölle gescheitert"


func _configure_attack_event(event: HistoryEvent, action: Dictionary, world: WorldState, result_type: StringName) -> void:
	var target_planet: StringName = action.get("target", &"") as StringName
	var defender_fid: StringName = world.planet_owner(target_planet)

	if not event.actors.has(defender_fid):
		event.actors.append(defender_fid)
	event.loser = defender_fid
	event.winner = action.get("actor", &"") as StringName

	if result_type == &"success":
		event.event_type = &"conquest"
		event.territory_change = target_planet
		event.casualties = maxi(10, world.faction_military(defender_fid) / 3)
		event.importance = 0.75
		event.relationship_change = -35
		event.trigger = "Planet nach erbitterter Raumschlacht erobert"
	elif result_type == &"partial":
		event.event_type = &"defeat"
		event.casualties = maxi(5, world.faction_military(event.winner) / 4)
		event.importance = 0.50
		event.relationship_change = -20
		event.trigger = "Angriff auf orbitalen Verteidigungsgürtel abgewehrt"
	else:
		event.event_type = &"defeat"
		event.casualties = maxi(15, world.faction_military(event.winner) / 2)
		event.importance = 0.45
		event.relationship_change = -25
		event.trigger = "Angriffsflotte im Abwehrfeuer zersprengt"


func _configure_war_declared_event(event: HistoryEvent, action: Dictionary, _world: WorldState) -> void:
	event.event_type = &"war_declared"
	# Kriegsparteien sind Fraktionen: bei DECLARE_WAR ist target/target_planet das
	# Kriegsziel (Planet), der Gegner steht in target_faction.
	var target_fid: StringName = action.get("target_faction", action.get("target", &"")) as StringName
	if not event.actors.has(target_fid):
		event.actors.append(target_fid)
	event.importance = 0.85
	event.relationship_change = -50
	event.trigger = action.get("trigger_reason", "Offizielle Kriegserklärung wegen Grenzverletzungen")


func _configure_ally_event(event: HistoryEvent, action: Dictionary, _world: WorldState) -> void:
	event.event_type = &"alliance"
	var target_fid: StringName = action.get("target", &"") as StringName
	if not event.actors.has(target_fid):
		event.actors.append(target_fid)
	event.importance = 0.60
	event.relationship_change = 30
	event.trigger = action.get("trigger_reason", "Verteidigungs- und Beistandspakt besiegelt")


func _configure_rival_event(event: HistoryEvent, action: Dictionary, _world: WorldState) -> void:
	event.event_type = &"rivalry"
	var target_fid: StringName = action.get("target", &"") as StringName
	if not event.actors.has(target_fid):
		event.actors.append(target_fid)
	event.importance = 0.40
	event.relationship_change = -20
	event.trigger = action.get("trigger_reason", "Ansprüche auf Grenzsektoren und diplomatische Schikane")


func _configure_peace_treaty_event(event: HistoryEvent, action: Dictionary, _world: WorldState) -> void:
	event.event_type = &"peace_treaty"
	var target_fid: StringName = action.get("target_faction", action.get("target", &"")) as StringName
	if not event.actors.has(target_fid):
		event.actors.append(target_fid)
	event.importance = 0.70
	event.relationship_change = 20
	event.trigger = action.get("trigger_reason", "Kriegserschöpfung erzwingt Waffenstillstand und Verhandlungen")
