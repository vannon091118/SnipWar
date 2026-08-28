extends Node

## WorldChronicle — Autoload für die Weltgeschichte.
## Verbindet Simulation, Live-Events und Chronik-Projektion.
## Pattern analog zu EventLog: hört auf EventBus, erzeugt Events.

## --- Konstanten ---
const DATA_DIR: String = "res://scripts/history/data"
const LOCALE_DIR: String = "res://resources/locale"
const SIMULATION_YEARS: int = 300

## --- Signale ---
signal chronicle_ready()
signal live_event_recorded(event: HistoryEvent)

## --- Services ---
var _simulator: HistorySimulator
var _importance_eval: ImportanceEvaluator
var _chain_detector: ChainDetector
var _cause_tracker: CauseTracker
var _template_resolver: ChronicleTemplateResolver
var _perspective: HistoricalPerspective
var _figure_catalog: FigureCatalog

## --- Daten ---
var _save: ChronicleSaveData
var _current_locale: String = "de"
var _is_ready: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_simulator = HistorySimulator.new()
	_importance_eval = ImportanceEvaluator.new()
	_chain_detector = ChainDetector.new()
	_cause_tracker = CauseTracker.new()
	_perspective = HistoricalPerspective.new()
	_figure_catalog = FigureCatalog.new(DATA_DIR)
	_template_resolver = ChronicleTemplateResolver.new(LOCALE_DIR, _current_locale)
	_save = ChronicleSaveData.new()
	_connect_event_bus.call_deferred()


func _connect_event_bus() -> void:
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal("game_event"):
		if not bus.game_event.is_connected(_on_game_event):
			bus.game_event.connect(_on_game_event)
		return
	# Fallback: direkte GameState-Signale
	var state: Node = get_node_or_null("/root/GameState")
	if state != null:
		if state.has_signal("faction_changed") and not state.faction_changed.is_connected(_on_faction_changed):
			state.faction_changed.connect(_on_faction_changed)
		if state.has_signal("technology_researched") and not state.technology_researched.is_connected(_on_technology_researched):
			state.technology_researched.connect(_on_technology_researched)
		if state.has_signal("milestone_reached") and not state.milestone_reached.is_connected(_on_milestone_reached):
			state.milestone_reached.connect(_on_milestone_reached)


## --- Lifecycle ---

## Wird aufgerufen wenn ein neues Spiel gestartet wird.
## Empfängt das run_started Signal via EventBus.
func reset(seed: int, faction_data: Dictionary = {}, planet_data: Dictionary = {}) -> void:
	_is_ready = false
	_save = ChronicleSaveData.new()

	# Falls keine Daten übergeben, minimale Defaults verwenden
	if faction_data.is_empty():
		faction_data = _default_factions()
	if planet_data.is_empty():
		planet_data = _default_planets()

	# Simulation starten
	var sim_seed: int = seed + 7919  # Separater Seed für Historische Simulation
	var result: Dictionary = _simulator.simulate(
		faction_data,
		planet_data,
		sim_seed,
		SIMULATION_YEARS,
		_figure_catalog
	)

	# Events bewerten
	var sim_events: Array[HistoryEvent] = result.get("events", [])
	_importance_eval.evaluate_all(sim_events)

	# In SaveData übernehmen
	_save.backstory_events = sim_events
	var bio_dict: Dictionary = result.get("biographies", {})
	_save.biographies.clear()
	for cid in bio_dict:
		_save.biographies.append(bio_dict[cid])
	_save.relationships = result.get("final_relationships", {})

	# Chains erkennen
	_save.chains = _chain_detector.detect_chains(sim_events)

	# Kausalitäten verknüpfen
	_cause_tracker.auto_link(sim_events)

	# Epochen emergent aus Welt-Metriken klassifizieren
	var classifier := EraClassifier.new()
	_save.eras = classifier.classify_eras(sim_events, SIMULATION_YEARS)

	# Names-Mapping erstellen
	_save.locale = _current_locale

	# Sortiere Events chronologisch
	_save.backstory_events.sort_custom(func(a, b): return a.year < b.year)

	_is_ready = true
	chronicle_ready.emit()
	print("WorldChronicle: %d backstory events, %d biographies, %d chains, %d eras" % [
		_save.backstory_events.size(),
		_save.biographies.size(),
		_save.chains.size(),
		_save.eras.size()
	])


## --- Live-Event-Handling ---

func _on_game_event(type: StringName, data: Dictionary) -> void:
	match type:
		&"faction_changed":
			_on_faction_changed(data.get("planet_id", &""), data.get("old_faction", &""), data.get("new_faction", &""))
		&"technology_researched":
			_on_technology_researched(data.get("faction", &""), data.get("technology_id", &""))
		&"milestone_reached":
			_on_milestone_reached(data.get("faction", &""), data.get("milestone_id", &""))


func _on_faction_changed(planet_id: StringName, old_faction: StringName, new_faction: StringName) -> void:
	if not _is_ready:
		return
	var event := HistoryEvent.new()
	event.event_id = _save.next_live_event_id()
	event.year = maxi(_save.last_event_year + 1, 1)
	event.event_type = &"conquest"
	event.target = planet_id
	event.winner = new_faction
	event.loser = old_faction
	event.importance = 0.6
	event.trigger = "Planet wechselt die Fraktion"

	_record_live_event(event)


func _on_technology_researched(faction: StringName, technology_id: StringName) -> void:
	if not _is_ready:
		return
	var event := HistoryEvent.new()
	event.event_id = _save.next_live_event_id()
	event.year = maxi(_save.last_event_year + 1, 1)
	event.event_type = &"research"
	event.actors.append(faction)
	event.target = technology_id
	event.importance = 0.3
	event.trigger = "Forschung abgeschlossen"

	_record_live_event(event)


func _on_milestone_reached(faction: StringName, milestone_id: StringName) -> void:
	if not _is_ready:
		return
	var event := HistoryEvent.new()
	event.event_id = _save.next_live_event_id()
	event.year = maxi(_save.last_event_year + 1, 1)
	event.event_type = &"milestone"
	event.actors.append(faction)
	event.target = milestone_id
	event.importance = 0.5
	event.trigger = "Meilenstein erreicht"

	_record_live_event(event)


func _record_live_event(event: HistoryEvent) -> void:
	_save.add_live_event(event)
	live_event_recorded.emit(event)


## --- Query API ---

func set_locale(locale: String) -> void:
	if locale.is_empty() or _template_resolver == null:
		return
	_current_locale = locale
	_save.locale = locale if _save != null else locale


func get_locale() -> String:
	return _current_locale


func get_save() -> ChronicleSaveData:
	return _save


func get_events(filter: Dictionary = {}) -> Array[HistoryEvent]:
	if _save == null:
		return []

	var events: Array[HistoryEvent] = _save.all_events()

	# Filter anwenden
	var event_type: StringName = filter.get("event_type", &"") as StringName
	if not String(event_type).is_empty():
		events = events.filter(func(e): return e.event_type == event_type)

	var faction: StringName = filter.get("faction", &"") as StringName
	if not String(faction).is_empty():
		events = events.filter(func(e): return e.actors.has(faction))

	var min_year: int = int(filter.get("min_year", -9999))
	var max_year: int = int(filter.get("max_year", 9999))
	events = events.filter(func(e): return e.year >= min_year and e.year <= max_year)

	var min_importance: float = float(filter.get("min_importance", 0.0))
	events = events.filter(func(e): return e.importance >= min_importance)

	return events


func get_chains() -> Array[EventChain]:
	return _save.chains if _save != null else []


func get_biography(char_id: StringName) -> CharacterBiography:
	return _save.biography_for(char_id) if _save != null else null


func get_biographies() -> Array[CharacterBiography]:
	return _save.biographies if _save != null else []


func get_eras() -> Array[Dictionary]:
	return _save.eras if _save != null else []


func get_relationships() -> Dictionary:
	return _save.relationships if _save != null else {}


func resolve_text(event: HistoryEvent) -> String:
	if _template_resolver == null or _perspective == null:
		return String(event.trigger)

	var key: String = _perspective.perspective_key(event)
	var context: Dictionary = _perspective.build_context(event, _build_world_names())
	return _template_resolver.resolve(key, context, _current_locale)


func is_ready() -> bool:
	return _is_ready


## --- Persistenz ---

func snapshot() -> ChronicleSaveData:
	return _save


func restore(data: ChronicleSaveData) -> void:
	if data != null:
		_save = data
		_is_ready = true


## --- Internals ---

func _load_eras() -> void:
	var path: String = DATA_DIR.path_join("era_definitions.json")
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_save.eras = parsed.get("eras", [])


func _build_world_names() -> Dictionary:
	var names: Dictionary = {}
	if _save != null:
		for bio in _save.biographies:
			names[bio.char_id] = bio.name
	return names


func _default_factions() -> Dictionary:
	return {
		&"solari": {
			"territory": 1,
			"military": 30,
			"economy": 30,
			"science": 30,
			"mood": &"balanced",
			"alive": true,
		},
		&"vanguard": {
			"territory": 1,
			"military": 45,
			"economy": 20,
			"science": 20,
			"mood": &"aggressive",
			"alive": true,
		},
		&"krypton_miners": {
			"territory": 1,
			"military": 20,
			"economy": 45,
			"science": 25,
			"mood": &"expansionist",
			"alive": true,
		},
	}


func _default_planets() -> Dictionary:
	return {
		&"planet_alpha": { "owner": &"solari", "population": 100, "strategic_value": 1.0 },
		&"planet_beta": { "owner": &"vanguard", "population": 80, "strategic_value": 1.2 },
		&"planet_gamma": { "owner": &"krypton_miners", "population": 120, "strategic_value": 1.1 },
		&"planet_delta": { "owner": &"", "population": 0, "strategic_value": 0.8 },
		&"planet_epsilon": { "owner": &"", "population": 0, "strategic_value": 0.9 },
		&"planet_zeta": { "owner": &"", "population": 0, "strategic_value": 1.5 },
	}
