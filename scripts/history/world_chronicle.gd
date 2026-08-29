extends Node

## WorldChronicle — Autoload für die Weltgeschichte.
## Verbindet Simulation, Live-Events und Chronik-Projektion.
##
## Signalfluss (Event-Boundary):
##   GameState → EventBus.game_event("run_started", {run_id, layout_seed})
##            → _on_game_event() → _on_run_started() → reset()
##   EventBus.game_event(type, data) → _on_game_event() → live events
##
## Kein direkter GameState-Import. Nur der zentrale EventBus.

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
	_connect_signals.call_deferred()


## --- Signal-Verbindungen ---
## Pattern analog zu EventLog: Start von GameState, Live von EventBus.

func _connect_signals() -> void:
	# Einziger Kopplungspunkt: EventBus.game_event (zentraler Gameplay-Eventstrom).
	# run_started und Live-Events kommen beide über diesen Kanal an.
	var bus := _get_event_bus()
	if bus != null and bus.has_signal("game_event"):
		if not bus.game_event.is_connected(_on_game_event):
			bus.game_event.connect(_on_game_event)


func _get_game_state() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	var tree: SceneTree = ml as SceneTree
	if tree == null:
		return null
	var tree_root: Node = tree.get_root()
	if tree_root == null:
		return null
	return tree_root.get_node_or_null("GameState")


func _get_event_bus() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	var tree: SceneTree = ml as SceneTree
	if tree == null:
		return null
	var tree_root: Node = tree.get_root()
	if tree_root == null:
		return null
	return tree_root.get_node_or_null("EventBus")


## --- Lifecycle ---

## Callback für run_started (via EventBus, data.run_id/layout_seed).
## Extrahiert echte GameState-Daten und startet die Simulation.
func _on_run_started(run_id: StringName, layout_seed: int) -> void:
	var state := _get_game_state()
	if state == null:
		push_warning("WorldChronicle: GameState not found, cannot start simulation")
		return

	# Echte Fraktionen und Planeten aus GameState extrahieren
	var faction_data := _extract_real_factions(state)
	var planet_data := _extract_real_planets(state)

	reset(layout_seed, faction_data, planet_data)


## Startet die historische Simulation.
## faction_data und planet_data müssen echte GameState-Daten sein
## oder explizite Headless-Defaults (s.u. _default_factions/planets).
func reset(seed: int, faction_data: Dictionary = {}, planet_data: Dictionary = {}) -> void:
	_is_ready = false
	_save = ChronicleSaveData.new()

	# Headless-Fallback: nur wenn keine echten Daten übergeben wurden
	if faction_data.is_empty():
		faction_data = _default_factions()
	if planet_data.is_empty():
		planet_data = _default_planets()

	# Simulation starten — deterministisch aus Run-Seed abgeleitet
	var sim_seed: int = seed + 7919
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


## --- GameState Data Extraction ---
## Trennt explizit echte Weltfakten von Simulationsinitialisierung.

## Extrahiert FRATIONEN aus GameState.
## Was ECHT aus dem Spiel stammt: faction IDs, territory (Planet Count).
## Was nur Simulationsinitialisierung ist: military, economy, science, mood Baselines.
## Nutzt die explizite GameState-Schnittstelle faction_planet_snapshot() —
## kein direkter Zugriff auf Domain-Interna.
func _extract_real_factions(state: Node) -> Dictionary:
	var factions := {}
	var snapshot: Dictionary = state.faction_planet_snapshot()

	# Für jede gefundene Fraktion: echte Daten + Simulations-Baselines
	for fid in snapshot:
		var territory: int = int(snapshot[fid].size())
		var is_player: bool = (fid == &"a" or fid == &"b")

		# --- ECHTE DATEN (aus GameState) ---
		#   territory = Anzahl besessener Planeten

		# --- SIMULATIONS-BASELINES (nicht aus GameState) ---
		#   Diese Werte initialisieren den Simulationskern. Sie sind deterministisch
		#   und konsistent, stammen aber NICHT aus GameState — SnipWar hat heute
		#   keine militärischen/ökonomischen/technischen Kräfte-Werte pro Fraktion.
		var military: float = 30.0 + float(territory) * 5.0
		var economy: float = 30.0 + float(territory) * 5.0
		var science: float = 25.0 + float(territory) * 3.0
		var mood: StringName = &"balanced"

		# Spezielle Profilierung für bekannte Fraktionen
		if fid == &"a":
			military = 35.0
			economy = 40.0
			science = 30.0
		elif fid == &"b":
			military = 50.0
			economy = 25.0
			science = 20.0
			mood = &"aggressive"

		factions[fid] = {
			"territory": territory,      # ECHT
			"military": military,         # SIM Baseline
			"economy": economy,           # SIM Baseline
			"science": science,           # SIM Baseline
			"mood": mood,                 # SIM Baseline
			"alive": true,
		}

	return factions if not factions.is_empty() else _default_factions()


## Extrahiert PLANETEN aus GameState.
## Was ECHT aus dem Spiel stammt: planet_id, owner (Fraktions-ID).
## Was nur Simulationsinitialisierung ist: population, strategic_value.
## Nutzt die explizite GameState-Schnittstelle faction_planet_snapshot() —
## kein direkter Zugriff auf Domain-Interna.
func _extract_real_planets(state: Node) -> Dictionary:
	var planets := {}
	var snapshot: Dictionary = state.faction_planet_snapshot()

	for fid in snapshot:
		for pid in snapshot[fid]:
			# --- ECHTE DATEN (aus GameState) ---
			#   planet_id, owner

			# --- SIMULATIONS-BASELINES (nicht aus GameState) ---
			#   SnipWar hat heute keine planetaren Population/Strategische-Werte,
			#   die der History-Simulation bekannt sind.
			planets[pid] = {
				"owner": fid,                  # ECHT
				"population": 100,             # SIM Baseline
				"strategic_value": 1.0,        # SIM Baseline
			}

	return planets if not planets.is_empty() else _default_planets()


## --- Live-Event-Handling ---

func _on_game_event(type: StringName, data: Dictionary) -> void:
	match type:
		&"run_started":
			# Event-Boundary-Pfad: run_started kommt jetzt über den EventBus an.
			_on_run_started(
				StringName(str(data.get("run_id", ""))),
				int(data.get("layout_seed", 0))
			)
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
	if _save != null:
		_save.locale = locale


func get_locale() -> String:
	return _current_locale


func get_save() -> ChronicleSaveData:
	return _save


func get_events(filter: Dictionary = {}) -> Array[HistoryEvent]:
	if _save == null:
		return []

	var events: Array[HistoryEvent] = _save.all_events()

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
	return _template_resolver.resolve(key, context, _save.locale if _save != null else _current_locale)


func is_ready() -> bool:
	return _is_ready


## --- Persistenz ---
## snapshot() und restore() nutzen .copy() für Deep Copies.
## ChronicleSaveData.copy() serialisiert über snapshot_dict() → from_snapshot_dict(),
## was ALLE HistoryEvents, Biografien, Chains und Eras vollständig reconstructiert.

func snapshot() -> ChronicleSaveData:
	if _save == null:
		_save = ChronicleSaveData.new()
	return _save.copy()


func restore(data: ChronicleSaveData) -> void:
	if data == null:
		return
	_save = data.copy()
	_is_ready = true


## --- Internals ---

func _build_world_names() -> Dictionary:
	var names: Dictionary = {}
	if _save != null:
		for bio in _save.biographies:
			names[bio.char_id] = bio.name
	return names


## Default-Fraktionen für Headless-Tests.
## Verwendet echte SnipWar-Fraktions-IDs ("a", "b"),
## nicht die historischen Testnamen (solari, vanguard, etc.).
func _default_factions() -> Dictionary:
	return {
		&"a": {
			"territory": 1,
			"military": 35,
			"economy": 40,
			"science": 30,
			"mood": &"balanced",
			"alive": true,
		},
		&"b": {
			"territory": 1,
			"military": 50,
			"economy": 25,
			"science": 20,
			"mood": &"aggressive",
			"alive": true,
		},
	}


func _default_planets() -> Dictionary:
	return {
		&"planet_alpha": { "owner": &"a", "population": 100, "strategic_value": 1.0 },
		&"planet_beta": { "owner": &"b", "population": 80, "strategic_value": 1.2 },
		&"planet_gamma": { "owner": &"", "population": 0, "strategic_value": 0.8 },
	}
