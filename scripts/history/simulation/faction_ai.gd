class_name FactionAI
extends RefCounted

## FactionAI — Druck- und Figuren-gesteuerte Entscheidungsfindung.
##
## Echte Kausalität:
## 1. Figuren-Einfluss (Pre-Decision):
##    Die Persönlichkeiten der lebenden Anführer (General, Diplomat, Gouverneur, Forscher)
##    modifizieren die Aktions-Gewichte vor der Entscheidung (Agency).
## 2. Kriegs-Lifecycle:
##    Keine Dauer-Kriegserklärungen mehr. Aktive Kriege führen zu Feldzügen (ATTACK)
##    oder bei hoher Kriegsmüdigkeit zu Friedensschlüssen (PEACE_TREATY) mit Waffenstillstand (Truce).

const WAR_THRESHOLD := -45
const ALLIANCE_THRESHOLD := 40


func decide_turn(
	fid: StringName,
	world: WorldState,
	rng: RandomNumberGenerator,
	recent_events: Array[HistoryEvent]
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if not world.is_faction_alive(fid):
		return actions

	# 1. Prüfe bestehende Kriege (Kriegs-Lifecycle)
	var war_action := _evaluate_active_wars(fid, world, rng)
	if not war_action.is_empty():
		actions.append(war_action)
		return actions

	# 2. Prüfe Krisen-Dilemmas (Neuer Krieg, Grenzkonflikt, Bankrott)
	var crisis_action := _evaluate_crisis_dilemma(fid, world, rng, recent_events)
	if not crisis_action.is_empty():
		actions.append(crisis_action)
		return actions

	# 3. Standard-Entscheidungsfindung mit Figuren-Einfluss
	var weights: Dictionary = _calculate_action_weights(fid, world)

	# Figuren-Agency modifiziert Gewichte vor der Wahl
	_apply_character_agency_weights(fid, world, weights)

	var chosen_action: StringName = _weighted_choice(weights, rng)
	var action_dict := _build_action_payload(fid, chosen_action, world, rng)
	if not action_dict.is_empty():
		actions.append(action_dict)

	return actions


# --- 1. Aktive Kriege & Kriegs-Lifecycle ---

func _evaluate_active_wars(fid: StringName, world: WorldState, rng: RandomNumberGenerator) -> Dictionary:
	for other_fid in world.faction_ids():
		if other_fid == fid:
			continue
		if world.is_at_war(fid, other_fid):
			var war: Dictionary = world.get_active_war(fid, other_fid)
			var exhaustion: float = float(war.get("war_exhaustion", 0.0))
			var my_mil: float = float(world.factions[fid].get("military_strength", 10.0))

			# Friedensschluss bei Erschöpfung oder völliger Unterlegenheit
			if exhaustion >= 0.70 or my_mil < 8.0:
				var diplomat_cid := _resolve_acting_character(fid, &"diplomat", world, rng)
				return {
					"type": &"PEACE_TREATY",
					"actor_faction": fid,
					"acting_character": diplomat_cid,
					"target_faction": other_fid,
					"target_planet": &"",
					"trigger_context": "Kriegsmüdigkeit und hohe Verluste zwingen zu Friedensverhandlungen"
				}

			# Kriegszug / Offensive fortsetzen — Angriffe nur auf FEINDliches Territorium.
			# Ist das Kriegsziel nicht mehr im Feindbesitz (erobert, Drittpartei),
			# wird ein feindlicher Planet als neues Ziel gewählt.
			var general_cid := _resolve_acting_character(fid, &"general", world, rng)
			var target_planet: StringName = war.get("goal_planet", &"")
			if String(target_planet).is_empty() or world.planet_owner(target_planet) != other_fid:
				var enemy_planets := world.owned_planets(other_fid)
				if not enemy_planets.is_empty():
					target_planet = enemy_planets[rng.randi() % enemy_planets.size()]

			if not String(target_planet).is_empty() and world.planet_owner(target_planet) == other_fid:
				return {
					"type": &"ATTACK",
					"actor_faction": fid,
					"acting_character": general_cid,
					"target_faction": other_fid,
					"target_planet": target_planet,
					"trigger_context": "Militäroffensive im laufenden Krieg"
				}

			# Kein angreifbares Ziel mehr: der Gegner besitzt kein Territorium.
			# Totaleroberung beendet den Krieg zwangsläufig — sonst bleibt der Krieg
			# für immer aktiv (Deadlock: weder ATTACK noch PEACE möglich).
			var peace_cid := _resolve_acting_character(fid, &"diplomat", world, rng)
			return {
				"type": &"PEACE_TREATY",
				"actor_faction": fid,
				"acting_character": peace_cid,
				"target_faction": other_fid,
				"target_planet": &"",
				"trigger_context": "Totaleroberung beendet den Krieg — keine feindlichen Ziele verbleiben"
			}

	return {}


# --- 2. Krisen-Dilemmas ---

func _evaluate_crisis_dilemma(
	fid: StringName,
	world: WorldState,
	rng: RandomNumberGenerator,
	_recent_events: Array[HistoryEvent]
) -> Dictionary:
	var econ_p: float = world.get_pressure(fid, "economic")
	var border_p: float = world.get_pressure(fid, "border")
	var mil_p: float = world.get_pressure(fid, "military")

	# A) Budgetkrise
	if econ_p > 0.75 and world.faction_economy(fid) < 15:
		for other_fid in world.faction_ids():
			if other_fid != fid and world.get_relationship(fid, other_fid) > -10:
				var dip_cid := _resolve_acting_character(fid, &"diplomat", world, rng)
				return {
					"type": &"TRADE_TREATY",
					"actor_faction": fid,
					"acting_character": dip_cid,
					"target_faction": other_fid,
					"target_planet": &"",
					"trigger_context": "Akute Budgetkrise erzwingt wirtschaftliche Annäherung"
				}

	# B) Neuer Kriegsausbruch (NUR wenn kein Waffenstillstand und nicht bereits im Krieg!)
	for other_fid in world.faction_ids():
		if other_fid == fid:
			continue
		if world.is_at_war(fid, other_fid) or world.has_truce(fid, other_fid):
			continue

		var rel: int = world.get_relationship(fid, other_fid)
		if rel <= WAR_THRESHOLD and (border_p > 0.6 or mil_p > 0.6):
			var enemy_planets := world.owned_planets(other_fid)
			# Fraktion ohne Territorium ist kein gültiges Kriegsziel — sonst:
			# Krieg erklären → sofort Totaleroberungs-Frieden → Deklarations-Ping-Pong.
			if enemy_planets.is_empty():
				continue
			var gen_cid := _resolve_acting_character(fid, &"general", world, rng)
			var goal_p: StringName = enemy_planets[0]

			if rng.randf() < 0.40:
				return {
					"type": &"DECLARE_WAR",
					"actor_faction": fid,
					"acting_character": gen_cid,
					"target_faction": other_fid,
					"target_planet": goal_p,
					"trigger_context": "Eskalation der Grenzspannungen und unüberbrückbare Feindschaft"
				}

	return {}


# --- 3. Figuren-Agency (Pre-Decision Einfluss) ---

func _apply_character_agency_weights(fid: StringName, world: WorldState, weights: Dictionary) -> void:
	# General-Einfluss
	var generals := world.alive_characters_by_role(fid, &"general")
	if not generals.is_empty():
		var gen_traits: Dictionary = world.character_traits(generals[0])
		var courage: int = int(gen_traits.get("courage", 5))
		var ambition: int = int(gen_traits.get("ambition", 5))
		var caution: int = int(gen_traits.get("caution", 5))

		if courage > 6 and ambition > 6:
			weights[&"ATTACK"] = float(weights.get(&"ATTACK", 0.0)) * 1.5
			weights[&"BUILD"] = float(weights.get(&"BUILD", 0.0)) * 1.3
		elif caution > 6:
			weights[&"DEFEND"] = float(weights.get(&"DEFEND", 0.0)) * 1.6
			weights[&"ATTACK"] = float(weights.get(&"ATTACK", 0.0)) * 0.5

	# Diplomat-Einfluss
	var diplomats := world.alive_characters_by_role(fid, &"diplomat")
	if not diplomats.is_empty():
		var dip_traits: Dictionary = world.character_traits(diplomats[0])
		var loyalty: int = int(dip_traits.get("loyalty", 5))
		var caution: int = int(dip_traits.get("caution", 5))
		var ambition: int = int(dip_traits.get("ambition", 5))

		if loyalty > 6 and caution > 6:
			weights[&"ALLIANCE"] = float(weights.get(&"ALLIANCE", 0.0)) * 1.6
			weights[&"TRADE"] = float(weights.get(&"TRADE", 0.0)) * 1.4
			weights[&"RIVAL"] = float(weights.get(&"RIVAL", 0.0)) * 0.4
		elif ambition > 7:
			weights[&"RIVAL"] = float(weights.get(&"RIVAL", 0.0)) * 1.5

	# Forscher-Einfluss
	var scientists := world.alive_characters_by_role(fid, &"scientist")
	if not scientists.is_empty():
		var sci_traits: Dictionary = world.character_traits(scientists[0])
		var caution: int = int(sci_traits.get("caution", 5))
		if caution > 6:
			weights[&"RESEARCH"] = float(weights.get(&"RESEARCH", 0.0)) * 1.4


# --- Basis-Gewichte ---

func _calculate_action_weights(fid: StringName, world: WorldState) -> Dictionary:
	var res_p: float = world.get_pressure(fid, "resource")
	var border_p: float = world.get_pressure(fid, "border")
	var mil_p: float = world.get_pressure(fid, "military")
	var diplo_p: float = world.get_pressure(fid, "diplomatic")
	var unowned_count: int = world.unowned_planets().size()

	var weights: Dictionary = {
		&"EXPEDITION": 0.0,
		&"BUILD": 2.0,
		&"RESEARCH": 2.0,
		&"TRADE": 1.0,
		&"ALLIANCE": 1.0,
		&"RIVAL": 1.0,
		&"ATTACK": 0.0,
		&"DEFEND": 1.0
	}

	if unowned_count > 0 and res_p > 0.4:
		weights[&"EXPEDITION"] = 4.0 * res_p

	if mil_p > 0.5:
		weights[&"BUILD"] += 3.0 * mil_p
		weights[&"ALLIANCE"] += 2.5 * diplo_p

	if border_p > 0.5 and diplo_p > 0.4:
		weights[&"RIVAL"] += 3.0 * border_p

	return weights


func _weighted_choice(weights: Dictionary, rng: RandomNumberGenerator) -> StringName:
	var total: float = 0.0
	for k in weights:
		total += float(weights[k])
	if total <= 0.001:
		return &"BUILD"

	var roll: float = rng.randf() * total
	var accum: float = 0.0
	for k in weights:
		accum += float(weights[k])
		if roll <= accum:
			return k as StringName
	return &"BUILD"


func _build_action_payload(
	fid: StringName,
	action_type: StringName,
	world: WorldState,
	rng: RandomNumberGenerator
) -> Dictionary:
	match action_type:
		&"EXPEDITION":
			var unowned := world.unowned_planets()
			if unowned.is_empty():
				return {}
			var gov_cid := _resolve_acting_character(fid, &"governor", world, rng)
			return {
				"type": &"EXPEDITION",
				"actor_faction": fid,
				"acting_character": gov_cid,
				"target_planet": unowned[rng.randi() % unowned.size()],
				"target_faction": &"",
				"trigger_context": "Ressourcenknappheit zwingt zur kolonialen Expansion"
			}

		&"ALLIANCE":
			var best_target: StringName = &""
			var highest_rel: int = -999
			for other in world.faction_ids():
				if other != fid and not world.is_at_war(fid, other):
					var rel: int = world.get_relationship(fid, other)
					if rel > highest_rel and rel >= 0:
						highest_rel = rel
						best_target = other
			if String(best_target).is_empty():
				return {}
			var dip_cid := _resolve_acting_character(fid, &"diplomat", world, rng)
			return {
				"type": &"FORM_ALLIANCE",
				"actor_faction": fid,
				"acting_character": dip_cid,
				"target_faction": best_target,
				"target_planet": &"",
				"trigger_context": "Gemeinsame Sicherheitsinteressen stärken das Bündnis"
			}

		&"RIVAL":
			var worst_target: StringName = &""
			var lowest_rel: int = 999
			for other in world.faction_ids():
				if other != fid and not world.is_at_war(fid, other) and not world.has_truce(fid, other):
					var rel: int = world.get_relationship(fid, other)
					if rel < lowest_rel:
						lowest_rel = rel
						worst_target = other
			if String(worst_target).is_empty():
				return {}
			var dip_cid := _resolve_acting_character(fid, &"diplomat", world, rng)
			return {
				"type": &"DECLARE_RIVALRY",
				"actor_faction": fid,
				"acting_character": dip_cid,
				"target_faction": worst_target,
				"target_planet": &"",
				"trigger_context": "Machtpolitische Reibereien an den Grenzsektoren"
			}

		&"TRADE":
			var trade_target: StringName = &""
			for other in world.faction_ids():
				if other != fid and world.get_relationship(fid, other) >= -10:
					trade_target = other
					break
			if String(trade_target).is_empty():
				return {}
			var dip_cid := _resolve_acting_character(fid, &"diplomat", world, rng)
			return {
				"type": &"TRADE_TREATY",
				"actor_faction": fid,
				"acting_character": dip_cid,
				"target_faction": trade_target,
				"target_planet": &"",
				"trigger_context": "Wirtschaftlicher Austausch zur Rohstoffsicherung"
			}

		&"RESEARCH":
			var sci_cid := _resolve_acting_character(fid, &"scientist", world, rng)
			return {
				"type": &"RESEARCH",
				"actor_faction": fid,
				"acting_character": sci_cid,
				"target_planet": &"",
				"target_faction": &"",
				"trigger_context": "Wissenschaftliche Forschungsinitiative"
			}

		&"BUILD", _:
			var gov_cid := _resolve_acting_character(fid, &"governor", world, rng)
			var owned := world.owned_planets(fid)
			var p: StringName = owned[rng.randi() % owned.size()] if not owned.is_empty() else &""
			return {
				"type": &"BUILD_INFRASTRUCTURE",
				"actor_faction": fid,
				"acting_character": gov_cid,
				"target_planet": p,
				"target_faction": &"",
				"trigger_context": "Infrastruktureller Flotten- und Planetenausbau"
			}


func _resolve_acting_character(
	fid: StringName,
	role: StringName,
	world: WorldState,
	rng: RandomNumberGenerator
) -> StringName:
	var pool := world.alive_characters_by_role(fid, role)
	if pool.is_empty():
		pool = world.alive_characters(fid)
	if pool.is_empty():
		var birth: int = world.year - 25
		return world.create_character("Unbekannter Gesandter", fid, birth, role, "Offizier")
	return pool[rng.randi() % pool.size()]
