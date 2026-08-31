class_name HistorySimulator
extends RefCounted

## Die Weltgeschichts-Simulation für SnipWar (Sprint 2.5: Historical Causality).
## Basiert auf World Pressures, Ressourcen-Bilanzen, Figuren-Agency und expliziten Kausalitätsketten.
## Erzeugt eine emergente, nachvollziehbare Vorgeschichte.

var events: Array[HistoryEvent] = []
var biographies: Dictionary = {}  # char_id → CharacterBiography
var final_relationships: Dictionary = {}

## Kriegs-Archiv der letzten Simulation (chain = truth für ChainDetector).
## Wird von world_chronicle.gd nach simulate_with_snapshots() gelesen.
var war_archive: Array[Dictionary] = []

var _event_factory: HistoryEventFactory
var _faction_ai: FactionAI
var _figure_catalog: FigureCatalog

## Letzte signifikante Ereignisse (für Ursachensuche / Kausalitätsketten)
var _recent_events: Array[HistoryEvent] = []
var _last_significant_event_by_faction: Dictionary = {}  # fid → HistoryEvent


func _init() -> void:
	_event_factory = HistoryEventFactory.new()
	_faction_ai = FactionAI.new()


func simulate(
	initial_factions: Dictionary,
	initial_planets: Dictionary,
	seed: int,
	years: int = 300,
	figure_catalog: FigureCatalog = null
) -> Dictionary:
	return _simulate_internal(initial_factions, initial_planets, seed, years, figure_catalog, 0)


## Wie simulate(), erzeugt zusätzlich eine Snapshot-Reihe für die
## Historical-Presentation (Playback/Renderer). Die Snapshot-Ableitung ist
## AUSSCHLIESSLICH lesend (kein RNG-Zugriff, keine Event-Mutation) — damit
## bleibt die Event-Folge byte-identisch zu simulate().
func simulate_with_snapshots(
	initial_factions: Dictionary,
	initial_planets: Dictionary,
	seed: int,
	years: int = 300,
	figure_catalog: FigureCatalog = null,
	snapshot_interval: int = 25
) -> Dictionary:
	return _simulate_internal(initial_factions, initial_planets, seed, years, figure_catalog, maxi(snapshot_interval, 1))


func _simulate_internal(
	initial_factions: Dictionary,
	initial_planets: Dictionary,
	seed: int,
	years: int,
	figure_catalog: FigureCatalog,
	snapshot_interval: int
) -> Dictionary:
	_figure_catalog = figure_catalog
	events.clear()
	biographies.clear()
	final_relationships.clear()
	_recent_events.clear()
	_last_significant_event_by_faction.clear()

	var snapshots: Array[HistoricalSnapshot] = []

	var world := WorldState.new()
	world.reset(initial_factions, initial_planets, -years)
	war_archive = world.war_archive

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	# 1. Initiale Gründer-Generation an Figuren erzeugen
	_spawn_initial_characters(world, rng)

	# 2. 300-Jahre Simulations-Schleife
	for y in range(years):
		world.year = -years + y

		# A. Ressourcen & Unterhalt verrechnen
		world.process_economy_turn()

		# B. World Pressures (Ressourcen, Grenzen, Militär, Isolation) aktualisieren
		world.update_pressures()

		# C. Figuren altern, sterben und Nachfolger ernennen
		_process_character_lifecycle(world, rng)

		# D. Fraktionsentscheidungen treffen und ausführen
		for fid in world.faction_ids():
			var actions: Array[Dictionary] = _faction_ai.decide_turn(fid, world, rng, _recent_events)
			for action in actions:
				_execute_action(_normalize_action(action, world), world, rng)

		# E. Stimmungen der Fraktionen anpassen
		_update_faction_moods(world)

		# Snapshot nur lesend ableiten (Determinismus-Vertrag: kein RNG, keine Mutation)
		if snapshot_interval > 0 and ((y + 1) % snapshot_interval == 0 or y == years - 1):
			snapshots.append(_capture_snapshot(world))

	# 3. Finale Beziehungen erfassen
	for fid_a in world.faction_ids():
		for fid_b in world.faction_ids():
			if fid_a != fid_b:
				var key: String = "%s→%s" % [String(fid_a), String(fid_b)]
				final_relationships[key] = world.get_relationship(fid_a, fid_b)

	# 4. Biografien synchronisieren
	_sync_biographies(world)

	var result := {
		"events": events,
		"biographies": biographies,
		"final_relationships": final_relationships,
	}
	if snapshot_interval > 0:
		result["snapshots"] = snapshots
	return result


## Lesende Snapshot-Ableitung: Ownership aus WorldState, Events bis zum
## aktuellen Jahr, plus Kriegs-/Truce-Truth (Schema v3). Verändert weder
## WorldState noch events (Determinismus).
func _capture_snapshot(world: WorldState) -> HistoricalSnapshot:
	var snapshot := HistoricalSnapshot.new()
	snapshot.year = world.year
	for pid in world.planets:
		snapshot.ownership[pid] = world.planet_owner(pid as StringName)
		snapshot.visual_state[pid] = _derive_planet_visual_state(pid as StringName, world)
	for fid in world.faction_ids():
		var faction_data: Dictionary = world.factions.get(fid, {})
		snapshot.economy_state[fid] = {
			"stock": float(faction_data.get("economy_stock", 0.0)),
			"income": float(faction_data.get("economy_income", 0.0)),
			"upkeep": float(faction_data.get("military_upkeep", 0.0)),
			"net": float(faction_data.get("economy_income", 0.0)) - float(faction_data.get("military_upkeep", 0.0)),
			"territory": int(faction_data.get("territory", 0)),
		}
	# Kriegs-Truth, ausschließlich lesend: laufende Kriege aus active_wars,
	# abgeschlossene aus war_archive (status über end_year determiniert).
	for war in world.active_wars.values():
		snapshot.wars.append(_war_snapshot(war, "ongoing"))
	for war in world.war_archive:
		var status: String = "ended" if int(war.get("end_year", 0)) <= world.year else "ongoing"
		snapshot.wars.append(_war_snapshot(war, status))
	for key in world.truces:
		if world.year < int(world.truces[key]):
			snapshot.truces[key] = int(world.truces[key])
	return snapshot


## Ein Kriegs-Dictionary für den Snapshot (nur Felder, keine Referenzen).
func _war_snapshot(war: Dictionary, status: String) -> Dictionary:
	return {
		"war_id": str(war.get("war_id", "")),
		"attacker": str(war.get("attacker", "")),
		"defender": str(war.get("defender", "")),
		"goal_planet": str(war.get("goal_planet", "")),
		"start_year": int(war.get("start_year", 0)),
		"end_year": war.get("end_year"),
		"status": status,
		"battles": int(war.get("battles", 0)),
		"attacker_losses": int(war.get("attacker_losses", 0)),
		"defender_losses": int(war.get("defender_losses", 0)),
		"war_exhaustion": float(war.get("war_exhaustion", 0.0)),
		"outcome": str(war.get("outcome", "")),
	}


func _derive_planet_visual_state(planet_id: StringName, world: WorldState) -> Dictionary:
	var owner: StringName = world.planet_owner(planet_id)
	var faction_territory: int = world.faction_territory(owner) if not String(owner).is_empty() else 0
	var technology_count: int = world.faction_technology_count(owner) if not String(owner).is_empty() else 0
	var event_count_for_planet: int = 0
	var construction_count: int = 0
	for event in events:
		if event.target == planet_id:
			event_count_for_planet += 1
			if event.event_type in [&"build", &"colony", &"conquest"]:
				construction_count += 1
	return {
		"owner": owner,
		"colony_level": 1 if not String(owner).is_empty() else 0,
		"industry_level": mini(construction_count, 3),
		"research_level": mini(technology_count, 3),
		"defense_level": mini(faction_territory, 3),
		"event_count": event_count_for_planet,
	}


func _spawn_initial_characters(world: WorldState, rng: RandomNumberGenerator) -> void:
	for fid in world.faction_ids():
		var roles: Array[StringName] = [&"governor", &"general", &"diplomat", &"scientist"]
		for role in roles:
			_create_character_for_role(fid, role, world, rng, world.year)


func _create_character_for_role(
	fid: StringName,
	role: StringName,
	world: WorldState,
	rng: RandomNumberGenerator,
	current_year: int
) -> StringName:
	var char_name: String = ""
	if _figure_catalog != null:
		char_name = _figure_catalog.pick_random_name("first_names", rng)
	else:
		char_name = "Figur_%d" % rng.randi_range(100, 999)

	var rank: String = "Pionier"
	match role:
		&"general": rank = "Kommandant"
		&"diplomat": rank = "Gesandter"
		&"scientist": rank = "Forscher"
		&"governor": rank = "Gouverneur"

	var traits := {
		"courage": rng.randi_range(3, 9),
		"caution": rng.randi_range(3, 9),
		"ambition": rng.randi_range(4, 10),
		"loyalty": rng.randi_range(4, 9)
	}

	var birth_year: int = current_year - rng.randi_range(20, 35)
	var cid: StringName = world.create_character(char_name, fid, birth_year, role, rank, traits)

	var bio := CharacterBiography.new()
	bio.char_id = cid
	bio.name = char_name
	bio.faction = fid
	bio.birth_year = birth_year
	bio.current_rank = rank
	bio.add_rank(current_year, rank)
	biographies[cid] = bio

	return cid


func _process_character_lifecycle(world: WorldState, rng: RandomNumberGenerator) -> void:
	for cid in world.characters.keys():
		var c: Dictionary = world.characters[cid]
		if not c.get("alive", false):
			continue

		var birth: int = int(c.get("birth_year", 0))
		var age: int = world.year - birth

		# Natürliches Altern & Sterberisiko
		var death_chance: float = 0.0
		if age > 75:
			death_chance = 0.25
		elif age > 65:
			death_chance = 0.08
		elif age > 55:
			death_chance = 0.02

		if age >= 85 or rng.randf() < death_chance:
			world.kill_character(cid, world.year, "Im hohen Alter friedlich verschieden")
			if biographies.has(cid):
				var bio: CharacterBiography = biographies[cid]
				bio.die(world.year)
				bio.add_achievement("Diente der Fraktion bis ins Alter von %d Jahren" % age)

	# Nachfolge sichern: Hat jede Fraktion für alle Kernrollen lebende Vertreter?
	for fid in world.faction_ids():
		var roles: Array[StringName] = [&"governor", &"general", &"diplomat", &"scientist"]
		for role in roles:
			var alive_in_role: Array[StringName] = world.alive_characters_by_role(fid, role)
			if alive_in_role.is_empty():
				_create_character_for_role(fid, role, world, rng, world.year)


## Übersetzt FactionAI-Payload (actor_faction/target_faction/…) in das interne Format
## das _execute_action erwartet (actor/target/leader_char_id/leader_name)
func _normalize_action(action: Dictionary, world: WorldState) -> Dictionary:
	var normalized: Dictionary = action.duplicate()

	# actor: actor_faction → actor
	if not normalized.has("actor") and normalized.has("actor_faction"):
		normalized["actor"] = normalized["actor_faction"]

	# target: zuerst target_planet, dann target_faction
	if not normalized.has("target"):
		var tp: StringName = normalized.get("target_planet", &"") as StringName
		var tf: StringName = normalized.get("target_faction", &"") as StringName
		normalized["target"] = tp if not String(tp).is_empty() else tf

	# leader_char_id / leader_name
	if not normalized.has("leader_char_id") and normalized.has("acting_character"):
		var cid: StringName = normalized["acting_character"] as StringName
		normalized["leader_char_id"] = cid
		normalized["leader_name"] = world.character_name(cid)

	# type: FactionAI verwendet erweiterte Namen — normalisiere auf interne Konstanten
	var t: StringName = normalized.get("type", &"") as StringName
	match t:
		&"EXPEDITION":           normalized["type"] = &"COLONIZE"
		&"BUILD_INFRASTRUCTURE": normalized["type"] = &"BUILD"
		&"FORM_ALLIANCE":        normalized["type"] = &"ALLY"
		&"DECLARE_RIVALRY":      normalized["type"] = &"RIVAL"
		&"TRADE_TREATY":         normalized["type"] = &"TRADE"
		# ATTACK, DECLARE_WAR, PEACE_TREATY, RESEARCH bleiben unverändert

	# trigger: trigger_context → trigger_reason (für EventFactory)
	if not normalized.has("trigger_reason") and normalized.has("trigger_context"):
		normalized["trigger_reason"] = normalized["trigger_context"]

	return normalized


func _execute_action(action: Dictionary, world: WorldState, rng: RandomNumberGenerator) -> void:
	var action_type: StringName = action.get("type", &"") as StringName
	var actor: StringName = action.get("actor", &"") as StringName
	var target: StringName = action.get("target", &"") as StringName
	var leader_cid: StringName = action.get("leader_char_id", &"") as StringName
	var traits: Dictionary = action.get("leader_traits", {})
	if traits.is_empty() and not String(leader_cid).is_empty():
		traits = world.character_traits(leader_cid)
	var ambition: int = int(traits.get("ambition", 5))
	var courage: int = int(traits.get("courage", 5))
	var caution: int = int(traits.get("caution", 5))

	var result_type: StringName = &"failure"
	var cause_event_id: StringName = _find_immediate_cause(actor, action_type, target)
	var cause_type: StringName = &"pressure"

	match action_type:
		&"COLONIZE":
			var econ: int = world.faction_economy(actor)
			var success_prob: float = 0.60 + float(ambition) * 0.03
			if econ >= 20 and rng.randf() < success_prob:
				result_type = &"success"
				world.set_planet_owner(target, actor)
				world.add_faction_territory(actor, 1)
				world.set_faction_attribute(String(actor), "economy", econ - 15)

				# Grenzreibung zu allen anderen Fraktionen
				for other in world.faction_ids():
					if other != actor:
						world.modify_relationship(actor, other, -20)

				_record_character_achievement(leader_cid, "Führte die erfolgreiche Kolonisierung von %s an" % String(target))
			else:
				result_type = &"failure"

		&"BUILD":
			var econ: int = world.faction_economy(actor)
			if econ >= 10:
				result_type = &"success"
				world.set_faction_attribute(String(actor), "economy", econ - 10)
				# Bau stärkt langfristige Wirtschaft und Verteidigung
				world.set_faction_attribute(String(actor), "military", world.faction_military(actor) + 3)
				_record_character_achievement(leader_cid, "Leitete den infrastrukturellen Ausbau von %s" % String(target))

		&"RESEARCH":
			var science: int = world.faction_science(actor)
			var success_prob: float = 0.55 + float(courage) * 0.04
			if rng.randf() < success_prob:
				result_type = &"success"
				world.set_faction_attribute(String(actor), "science", science + 15)
				var tech_id: StringName = StringName("tech_tier_%d" % rng.randi_range(1, 10))
				world.add_technology(actor, tech_id)
				_record_character_achievement(leader_cid, "Erzielte Durchbruch bei der Erforschung von %s" % String(tech_id))

		&"TRADE":
			result_type = &"success"
			world.modify_relationship(actor, target, 15)
			world.modify_relationship(target, actor, 15)
			world.set_faction_attribute(String(actor), "economy", world.faction_economy(actor) + 8)
			world.set_faction_attribute(String(target), "economy", world.faction_economy(target) + 8)
			_record_character_achievement(leader_cid, "Handelte vorteilhaften Vertrag mit %s aus" % String(target))

		&"ALLY":
			result_type = &"success"
			world.modify_relationship(actor, target, 30)
			world.modify_relationship(target, actor, 30)
			_record_character_achievement(leader_cid, "Schmiedete das Verteidigungsbündnis mit %s" % String(target))

		&"RIVAL":
			result_type = &"success"
			world.modify_relationship(actor, target, -25)
			world.modify_relationship(target, actor, -25)
			_record_character_failure(leader_cid, "Eskalierte diplomatische Feindseligkeiten mit %s" % String(target))

		&"DECLARE_WAR":
			# Krieg ist ein Fraktion-Fraktion-Akt: der Gegner steht in target_faction,
			# target/target_planet ist nur das Kriegsziel (goal_planet).
			var defender_fid: StringName = action.get("target_faction", target) as StringName
			result_type = &"success"
			world.modify_relationship(actor, defender_fid, -60)
			world.modify_relationship(defender_fid, actor, -60)
			_record_character_failure(leader_cid, "Eröffnete die Kriegshandlungen gegen %s" % String(defender_fid))
			# Krieg im WorldState registrieren — unter dem FAKTIONSPAAR, nicht dem
			# Kriegsziel-Planeten. Sonst findet is_at_war/record_war_battle/end_war
			# den Krieg nie wieder (Zombie-Krieg ohne Lifecycle).
			var goal_planet: StringName = action.get("target_planet", &"") as StringName
			# Event erst erzeugen, dann start_war mit der neuen Event-ID
			var decl_event: HistoryEvent = _event_factory.create_event(action, world, result_type, cause_event_id, cause_type)
			_record_event(decl_event, world)
			world.start_war(actor, defender_fid, goal_planet, decl_event.event_id)
			return  # Event schon gespeichert, kein zweites Mal unten

		&"ATTACK":
			var defender_fid: StringName = world.planet_owner(target)
			var att_mil: int = world.faction_military(actor)
			var def_mil: int = world.faction_military(defender_fid)

			# Modifikatoren durch General
			var combat_mod: float = 1.0 + (float(courage) - float(caution)) * 0.05
			var effective_att: float = float(att_mil) * combat_mod

			if effective_att > float(def_mil) * 1.15:
				result_type = &"success"
				world.set_planet_owner(target, actor)
				world.add_faction_territory(actor, 1)
				world.add_faction_territory(defender_fid, -1)
				world.set_faction_attribute(String(actor), "military", maxi(10, att_mil - def_mil / 4))
				world.set_faction_attribute(String(defender_fid), "military", maxi(5, def_mil / 2))
				world.modify_relationship(actor, defender_fid, -40)
				world.modify_relationship(defender_fid, actor, -40)

				_record_character_achievement(leader_cid, "Eroberte %s im Sturm" % String(target))
				world.promote_character(leader_cid, "Kriegsherr")
				_handle_combat_casualties(leader_cid, defender_fid, target, world, rng, false)
			elif effective_att > float(def_mil) * 0.85:
				result_type = &"partial"
				world.set_faction_attribute(String(actor), "military", maxi(10, att_mil - att_mil / 4))
				world.set_faction_attribute(String(defender_fid), "military", maxi(10, def_mil - def_mil / 4))
				world.modify_relationship(actor, defender_fid, -25)
				_record_character_failure(leader_cid, "Schlacht um %s endete in verlustreichem Patt" % String(target))
				_handle_combat_casualties(leader_cid, defender_fid, target, world, rng, true)
			else:
				result_type = &"failure"
				world.set_faction_attribute(String(actor), "military", maxi(5, att_mil / 2))
				world.modify_relationship(actor, defender_fid, -30)
				_record_character_failure(leader_cid, "Erleidet schwere Niederlage bei %s" % String(target))
				_handle_combat_casualties(leader_cid, defender_fid, target, world, rng, true)

			# Schlachtdaten im aktiven Krieg vermerken — Battle-Event zuerst erzeugen und
			# registrieren, damit last_battle_event_id auf die Schlacht selbst zeigt
			# (nicht auf deren Ursache).
			var att_loss: int = maxi(0, att_mil - world.faction_military(actor))
			var def_loss: int = maxi(0, def_mil - world.faction_military(defender_fid))
			var battle_event: HistoryEvent = _event_factory.create_event(action, world, result_type, cause_event_id, cause_type)
			_record_event(battle_event, world)
			world.record_war_battle(actor, defender_fid, battle_event.event_id, att_loss, def_loss)
			return  # Event schon gespeichert, kein zweites Mal unten

		&"PEACE_TREATY":
			# Kriegserschöpfung oder Totaleroberung → Waffenstillstand
			var target_fid: StringName = action.get("target_faction", target) as StringName
			result_type = &"success"
			var war_data: Dictionary = world.end_war(actor, target_fid, 20)
			var battles_fought: int = int(war_data.get("battles", 0))
			_record_character_achievement(leader_cid,
				"Handelte Friedensvertrag mit %s aus nach %d Schlachten" % [String(target_fid), battles_fought])
			# Kausaler Anker: die letzte Schlacht des Krieges (Fallback: die Kriegserklärung)
			var war_anchor: StringName = war_data.get("last_battle_event_id", war_data.get("declaration_event_id", &"")) as StringName
			if not String(war_anchor).is_empty():
				cause_event_id = war_anchor
			cause_type = &"war_exhaustion"
			# Frieden wirkt diplomatisch (Event deklariert relationship_change = 20)
			world.modify_relationship(actor, target_fid, 20)
			world.modify_relationship(target_fid, actor, 20)
			# Kriegs-Truth: Friedens-Event-ID im Archiv-Eintrag verankern, damit
			# ChainDetector die Kette exakt abschließen kann (peace_event_id).
			var peace_event: HistoryEvent = _event_factory.create_event(action, world, result_type, cause_event_id, cause_type)
			_record_event(peace_event, world)
			if world.war_archive:
				(world.war_archive[-1] as Dictionary)["peace_event_id"] = peace_event.event_id
			return  # Event schon gespeichert, kein zweites Mal unten

	var event: HistoryEvent = _event_factory.create_event(action, world, result_type, cause_event_id, cause_type)
	_record_event(event, world)


## Findet ein passendes unmittelbares Vorgänger-Event für die Kausalitätskette
func _find_immediate_cause(fid: StringName, action_type: StringName, target: StringName) -> StringName:
	# Suche rückwärts in den letzten Events
	for i in range(_recent_events.size() - 1, -1, -1):
		var prev: HistoryEvent = _recent_events[i]
		if prev == null:
			continue
		# Reagiert auf Kriegserklärung
		if action_type == &"ATTACK" and prev.event_type == &"war_declared" and prev.actors.has(fid):
			return prev.event_id
		# Reagiert auf Grenzprovokation/Rivalität
		if action_type in [&"DECLARE_WAR", &"ATTACK"] and prev.event_type == &"rivalry" and prev.actors.has(fid):
			return prev.event_id
		# Reagiert auf territoriale Provokation: Kolonie-Gründung ODER Eroberung
		if action_type in [&"RIVAL", &"DECLARE_WAR"] and prev.event_type in [&"colony", &"conquest"]:
			return prev.event_id
		# Reagiert auf frühere Schlacht
		if action_type == &"ATTACK" and prev.event_type in [&"conquest", &"defeat"] and prev.target == target:
			return prev.event_id
	return &""


func _handle_combat_casualties(
	leader_cid: StringName,
	defender_fid: StringName,
	planet: StringName,
	world: WorldState,
	rng: RandomNumberGenerator,
	is_attacker_loss_or_stalemate: bool
) -> void:
	# Angreifer-General: Situatives Verwundungs- oder Todesrisiko bei Niederlage
	if is_attacker_loss_or_stalemate and not String(leader_cid).is_empty():
		var traits: Dictionary = world.character_traits(leader_cid)
		var courage: int = int(traits.get("courage", 5))
		var caution: int = int(traits.get("caution", 5))

		# Mehr Mut + weniger Vorsicht erhöht Todesrisiko an vorderster Front
		var death_risk: float = 0.15 + (float(courage) - float(caution)) * 0.03
		if rng.randf() < death_risk:
			world.kill_character(leader_cid, world.year, "Gefallen im Gefecht um %s" % String(planet))
			if biographies.has(leader_cid):
				var bio: CharacterBiography = biographies[leader_cid]
				bio.die(world.year)
				bio.add_failure("Fiel in der Schlacht um %s" % String(planet))
		else:
			world.wound_character(leader_cid)
			if biographies.has(leader_cid):
				(biographies[leader_cid] as CharacterBiography).add_failure("Verwundet im Raumkampf um %s" % String(planet))

	# Verteidiger-Offiziere prüfen
	var def_commanders: Array[StringName] = world.alive_characters_by_role(defender_fid, &"general")
	for cid in def_commanders:
		if rng.randf() < 0.20:
			world.kill_character(cid, world.year, "Fiel bei der Verteidigung von %s" % String(planet))
			if biographies.has(cid):
				var bio: CharacterBiography = biographies[cid]
				bio.die(world.year)
				bio.add_failure("Gefallen bei der Verteidigung von %s" % String(planet))


func _record_character_achievement(cid: StringName, text: String) -> void:
	if not String(cid).is_empty() and biographies.has(cid):
		(biographies[cid] as CharacterBiography).add_achievement(text)


func _record_character_failure(cid: StringName, text: String) -> void:
	if not String(cid).is_empty() and biographies.has(cid):
		(biographies[cid] as CharacterBiography).add_failure(text)


func _record_event(event: HistoryEvent, _world: WorldState) -> void:
	events.append(event)
	_recent_events.append(event)
	if _recent_events.size() > 40:
		_recent_events.pop_front()

	for actor in event.actors:
		if biographies.has(actor):
			(biographies[actor] as CharacterBiography).add_event(event.event_id)
		_last_significant_event_by_faction[actor] = event


func _update_faction_moods(world: WorldState) -> void:
	for fid in world.faction_ids():
		var pressures: Dictionary = world.get_pressures(fid)
		var mil_p: float = float(pressures.get("military", 0.0))
		var border_p: float = float(pressures.get("border", 0.0))
		var res_p: float = float(pressures.get("resource", 0.0))
		var diplo_p: float = float(pressures.get("diplomatic", 0.0))

		if border_p > 0.6 or mil_p > 0.6:
			world.set_faction_attribute(String(fid), "mood", &"aggressive")
		elif res_p > 0.6 and world.unowned_planets().size() > 0:
			world.set_faction_attribute(String(fid), "mood", &"expansionist")
		elif diplo_p > 0.5:
			world.set_faction_attribute(String(fid), "mood", &"diplomatic")
		elif mil_p > 0.4:
			world.set_faction_attribute(String(fid), "mood", &"defensive")
		else:
			world.set_faction_attribute(String(fid), "mood", &"balanced")


func _sync_biographies(world: WorldState) -> void:
	for cid in world.characters:
		var c: Dictionary = world.characters[cid]
		if not biographies.has(cid):
			var bio := CharacterBiography.new()
			bio.char_id = cid
			bio.name = str(c.get("name", "Unknown"))
			bio.faction = str(c.get("faction", "")) as StringName
			bio.birth_year = int(c.get("birth_year", 0))
			bio.current_rank = str(c.get("rank", ""))
			biographies[cid] = bio

		var bio: CharacterBiography = biographies[cid]
		bio.current_rank = str(c.get("rank", bio.current_rank))
		if not c.get("alive", true) and bio.death_year == -99999:
			bio.die(int(c.get("death_year", world.year)))
