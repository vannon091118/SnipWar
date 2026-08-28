class_name HistoricalPerspective
extends RefCounted

## Wählt basierend auf importance den richtigen Template-Key.
## Verbindet ImportanceEvaluator mit ChronicleTemplateResolver.

## Template-Key-Generierung basierend auf Event-Typ und importance.
func perspective_key(event: HistoryEvent) -> String:
	var category: String = _categorize_event(event.event_type)
	var tier: String = _importance_tier(event.importance)
	return "%s.%s" % [category, tier]


## Baut den vollständigen Kontext für die Template-Ersetzung.
func build_context(event: HistoryEvent, world_names: Dictionary = {}) -> Dictionary:
	var context: Dictionary = {}

	# Grundlegende Fakten
	context["year"] = event.year
	context["event_type"] = String(event.event_type)

	# Akteure (Namen auflösen)
	if event.actors.size() > 0:
		context["actor"] = _resolve_name(event.actors[0], world_names)
		context["faction"] = context["actor"]
	if event.actors.size() > 1:
		context["target_faction"] = _resolve_name(event.actors[1], world_names)
		context["faction_a"] = context["actor"]
		context["faction_b"] = context["target_faction"]

	# Ziel
	context["target"] = _resolve_name(event.target, world_names)
	context["planet"] = context["target"]

	# Konflikt-spezifisch
	if not String(event.winner).is_empty():
		context["winner"] = _resolve_name(event.winner, world_names)
	if not String(event.loser).is_empty():
		context["loser"] = _resolve_name(event.loser, world_names)
	if event.casualties > 0:
		context["casualties"] = event.casualties

	# Figuren
	if event.context_dict.has("character_name"):
		context["character"] = event.context_dict["character_name"]
	if event.context_dict.has("commander"):
		context["commander"] = event.context_dict["commander"]
	if event.context_dict.has("rank"):
		context["rank"] = event.context_dict["rank"]

	# Technologie
	if event.context_dict.has("technology"):
		context["technology"] = event.context_dict["technology"]

	return context


func _categorize_event(event_type: StringName) -> String:
	match event_type:
		&"conquest", &"attack", &"defeat", &"war_declared":
			return "conquest"
		&"colony":
			return "colony"
		&"research":
			return "research"
		&"trade":
			return "trade"
		&"alliance":
			return "alliance"
		&"rivalry":
			return "rivalry"
		&"build":
			return "build"
		&"explore":
			return "explore"
		&"die":
			return "character"
		_:
			return String(event_type)


func _importance_tier(importance: float) -> String:
	if importance >= 0.90:
		return "turning_point"
	elif importance >= 0.70:
		return "major"
	elif importance >= 0.45:
		return "normal"
	else:
		return "minor"


func _resolve_name(id: StringName, world_names: Dictionary) -> String:
	if world_names.has(id):
		return str(world_names[id])
	return String(id)
