class_name WorldState
extends RefCounted

## TEMPORÄRER Simulationszustand für die historische Vorgeschichte (-300→0).
## Verwaltet:
##   - Bilanzen & Unterhalt (Income, Stock, Upkeep, Losses)
##   - World Pressures (0.0..1.0 je Fraktion)
##   - Figuren mit echten Eigenschaften (Mut, Vorsicht, Ehrgeiz, Loyalität)
##   - Aktive Kriege (State Machine: erklärt -> Kampagnen -> Schlachten -> Friedensschluss)
##   - Waffenstillstände (Truces) & gerichtete Beziehungen

var factions: Dictionary = {}
var relationships: Dictionary = {}
var planets: Dictionary = {}
var characters: Dictionary = {}
var technologies: Dictionary = {}

## Aktive Kriege: { "faction_a<->faction_b": Dictionary }
var active_wars: Dictionary = {}

## Waffenstillstände: { "faction_a<->faction_b": end_year }
var truces: Dictionary = {}

## Aktuelles Jahr
var year: int = 0

## ID-Zähler
var _next_event_id: int = 0
var _next_char_id: int = 0
var _next_chain_id: int = 0


func reset(initial_factions: Dictionary, initial_planets: Dictionary, start_year: int = -300) -> void:
	factions.clear()
	for fid in initial_factions:
		var raw: Dictionary = initial_factions[fid]
		factions[fid] = {
			"territory": int(raw.get("territory", 1)),
			"economy_stock": float(raw.get("economy", 50.0)),
			"economy_income": float(raw.get("economy", 30.0)),
			"military_strength": float(raw.get("military", 30.0)),
			"military_upkeep": float(raw.get("military", 30.0)) * 0.4,
			"science_stock": float(raw.get("science", 20.0)),
			"mood": StringName(str(raw.get("mood", "balanced"))),
			"alive": bool(raw.get("alive", true)),
			"pressures": {
				"resource": 0.3,
				"border": 0.2,
				"military": 0.2,
				"economic": 0.2,
				"diplomatic": 0.1,
			}
		}

	planets = initial_planets.duplicate(true)
	relationships.clear()
	characters.clear()
	technologies.clear()
	active_wars.clear()
	truces.clear()
	year = start_year
	_next_event_id = 0
	_next_char_id = 0
	_next_chain_id = 0


func next_event_id() -> StringName:
	_next_event_id += 1
	return StringName("evt_%06d" % _next_event_id)


func next_char_id() -> StringName:
	_next_char_id += 1
	return StringName("char_%04d" % _next_char_id)


func next_chain_id() -> StringName:
	_next_chain_id += 1
	return StringName("chain_%04d" % _next_chain_id)


# --- Faction Queries & Balance ---

func faction_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for fid in factions:
		var f: Dictionary = factions[fid]
		if f.get("alive", true):
			result.append(fid as StringName)
	return result


func is_faction_alive(fid: StringName) -> bool:
	return bool(factions.get(fid, {}).get("alive", false))


func faction_territory(fid: StringName) -> int:
	return int(factions.get(fid, {}).get("territory", 0))


func faction_military(fid: StringName) -> int:
	return int(round(float(factions.get(fid, {}).get("military_strength", 0.0))))


func faction_economy(fid: StringName) -> int:
	return int(round(float(factions.get(fid, {}).get("economy_stock", 0.0))))


func faction_science(fid: StringName) -> int:
	return int(round(float(factions.get(fid, {}).get("science_stock", 0.0))))


func faction_mood(fid: StringName) -> StringName:
	return str(factions.get(fid, {}).get("mood", "balanced")) as StringName


func get_pressures(fid: StringName) -> Dictionary:
	return factions.get(fid, {}).get("pressures", {})


func get_pressure(fid: StringName, pressure_type: String) -> float:
	return float(get_pressures(fid).get(pressure_type, 0.0))


func set_pressure(fid: StringName, pressure_type: String, val: float) -> void:
	if factions.has(fid) and factions[fid].has("pressures"):
		(factions[fid]["pressures"] as Dictionary)[pressure_type] = clampf(val, 0.0, 1.0)


func set_faction_attribute(fid: StringName, attr: String, value: Variant) -> void:
	if not factions.has(fid):
		return
	if attr == "economy":
		(factions[fid] as Dictionary)["economy_stock"] = float(value)
	elif attr == "military":
		(factions[fid] as Dictionary)["military_strength"] = float(value)
	elif attr == "science":
		(factions[fid] as Dictionary)["science_stock"] = float(value)
	else:
		(factions[fid] as Dictionary)[attr] = value


func add_faction_territory(fid: StringName, delta: int) -> void:
	if not factions.has(fid):
		return
	var f: Dictionary = factions[fid]
	f["territory"] = maxi(0, int(f.get("territory", 0)) + delta)


# --- Active Wars & Truces Lifecycle ---

func _war_key(a: StringName, b: StringName) -> String:
	var sa := String(a)
	var sb := String(b)
	return "%s<->%s" % [sa, sb] if sa < sb else "%s<->%s" % [sb, sa]


func is_at_war(a: StringName, b: StringName) -> bool:
	return active_wars.has(_war_key(a, b))


func get_active_war(a: StringName, b: StringName) -> Dictionary:
	return active_wars.get(_war_key(a, b), {})


func start_war(attacker: StringName, defender: StringName, goal_planet: StringName, declaration_event_id: StringName) -> void:
	var key := _war_key(attacker, defender)
	active_wars[key] = {
		"attacker": attacker,
		"defender": defender,
		"start_year": year,
		"goal_planet": goal_planet,
		"battles": 0,
		"attacker_losses": 0,
		"defender_losses": 0,
		"war_exhaustion": 0.0,
		"declaration_event_id": declaration_event_id,
		"last_battle_event_id": declaration_event_id
	}
	# Hebe bestehende Waffenstillstände auf
	truces.erase(key)


func record_war_battle(a: StringName, b: StringName, battle_event_id: StringName, att_losses: int, def_losses: int) -> void:
	var key := _war_key(a, b)
	if not active_wars.has(key):
		return
	var w: Dictionary = active_wars[key]
	w["battles"] = int(w.get("battles", 0)) + 1
	w["attacker_losses"] = int(w.get("attacker_losses", 0)) + att_losses
	w["defender_losses"] = int(w.get("defender_losses", 0)) + def_losses
	w["last_battle_event_id"] = battle_event_id
	# Kriegsmüdigkeit steigt
	w["war_exhaustion"] = clampf(float(w.get("war_exhaustion", 0.0)) + 0.25 + float(att_losses + def_losses) * 0.01, 0.0, 1.0)


func end_war(a: StringName, b: StringName, truce_years: int = 20) -> Dictionary:
	var key := _war_key(a, b)
	var war_data: Dictionary = active_wars.get(key, {})
	active_wars.erase(key)
	set_truce(a, b, truce_years)
	return war_data


func has_truce(a: StringName, b: StringName) -> bool:
	var key := _war_key(a, b)
	if truces.has(key):
		return year < int(truces[key])
	return false


func set_truce(a: StringName, b: StringName, duration_years: int) -> void:
	var key := _war_key(a, b)
	truces[key] = year + duration_years


# --- Jährliche Bilanz & Drücke ---

func process_economy_turn() -> void:
	for fid in faction_ids():
		var f: Dictionary = factions[fid]
		var territory: int = int(f.get("territory", 1))
		var mil_strength: float = float(f.get("military_strength", 10.0))

		var base_income: float = 15.0 + float(territory) * 12.0
		var upkeep: float = mil_strength * 0.45 + float(territory) * 3.0
		var net_income: float = base_income - upkeep
		var current_stock: float = float(f.get("economy_stock", 50.0))
		var new_stock: float = maxf(0.0, current_stock + net_income)

		f["economy_income"] = base_income
		f["military_upkeep"] = upkeep
		f["economy_stock"] = new_stock

		if net_income < -10.0 and new_stock <= 5.0:
			f["military_strength"] = maxf(5.0, mil_strength * 0.90)


func update_pressures() -> void:
	for fid in faction_ids():
		var f: Dictionary = factions[fid]
		var econ_stock: float = float(f.get("economy_stock", 50.0))
		var mil_strength: float = float(f.get("military_strength", 30.0))
		var territory: int = int(f.get("territory", 1))
		var unowned: int = unowned_planets().size()

		# 1. Resource Pressure
		var res_press: float = clampf((60.0 - econ_stock) / 60.0, 0.0, 1.0)
		if territory < 2 and unowned > 0:
			res_press = clampf(res_press + 0.25, 0.0, 1.0)

		# 2. Border Pressure
		var border_press: float = 0.2
		if unowned == 0:
			border_press += 0.4
		for other in faction_ids():
			if other != fid:
				var rel: int = get_relationship(fid, other)
				if rel < -20:
					border_press += 0.2
		border_press = clampf(border_press, 0.0, 1.0)

		# 3. Military Pressure
		var max_threat: float = 0.0
		for other in faction_ids():
			if other != fid:
				var other_mil: float = float(factions[other].get("military_strength", 30.0))
				var rel: int = get_relationship(fid, other)
				if (rel < 0 or is_at_war(fid, other)) and other_mil > mil_strength:
					var ratio: float = (other_mil - mil_strength) / maxf(1.0, mil_strength)
					max_threat = maxf(max_threat, clampf(ratio * 0.6, 0.0, 1.0))
		var mil_press: float = clampf(max_threat, 0.1, 1.0)

		# 4. Economic Pressure
		var upkeep: float = float(f.get("military_upkeep", 10.0))
		var econ_press: float = clampf((upkeep * 2.0 - econ_stock) / maxf(1.0, econ_stock + 10.0), 0.0, 1.0)

		# 5. Diplomatic Pressure
		var bad_relations: int = 0
		for other in faction_ids():
			if other != fid and (get_relationship(fid, other) < -30 or is_at_war(fid, other)):
				bad_relations += 1
		var diplo_press: float = clampf(float(bad_relations) * 0.35, 0.0, 1.0)

		var p_dict: Dictionary = f.get("pressures", {})
		p_dict["resource"] = res_press
		p_dict["border"] = border_press
		p_dict["military"] = mil_press
		p_dict["economic"] = econ_press
		p_dict["diplomatic"] = diplo_press
		f["pressures"] = p_dict


# --- Relationships & Planets ---

func get_relationship(from_id: StringName, to_id: StringName) -> int:
	var key: String = "%s→%s" % [String(from_id), String(to_id)]
	return int(relationships.get(key, 0))


func set_relationship(from_id: StringName, to_id: StringName, value: int) -> void:
	var key: String = "%s→%s" % [String(from_id), String(to_id)]
	relationships[key] = clampi(value, -100, 100)


func modify_relationship(from_id: StringName, to_id: StringName, delta: int) -> int:
	var current: int = get_relationship(from_id, to_id)
	var new_val: int = clampi(current + delta, -100, 100)
	set_relationship(from_id, to_id, new_val)
	return new_val


func planet_owner(planet_id: StringName) -> StringName:
	return str(planets.get(planet_id, {}).get("owner", "")) as StringName


func set_planet_owner(planet_id: StringName, new_owner: StringName) -> StringName:
	var old_owner: StringName = planet_owner(planet_id)
	if not planets.has(planet_id):
		return old_owner
	(planets[planet_id] as Dictionary)["owner"] = new_owner
	return old_owner


func owned_planets(fid: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for pid in planets:
		if planet_owner(pid as StringName) == fid:
			result.append(pid as StringName)
	return result


func unowned_planets() -> Array[StringName]:
	var result: Array[StringName] = []
	for pid in planets:
		if planet_owner(pid as StringName) == &"":
			result.append(pid as StringName)
	return result


# --- Character Model ---

func create_character(
	char_name: String,
	faction: StringName,
	birth_year: int,
	role: StringName,
	rank: String,
	traits: Dictionary = {}
) -> StringName:
	var cid: StringName = next_char_id()
	var default_traits := {
		"courage": 5,
		"caution": 5,
		"ambition": 5,
		"loyalty": 5
	}
	for t in traits:
		default_traits[t] = traits[t]

	characters[cid] = {
		"name": char_name,
		"faction": faction,
		"role": role,
		"rank": rank,
		"traits": default_traits,
		"alive": true,
		"birth_year": birth_year,
		"death_year": -99999,
		"cause_of_death": "",
		"reputation": 0.0,
		"wounds": 0,
		"rival_char_id": &""
	}
	return cid


func kill_character(cid: StringName, death_year: int, cause: String = "Altersschwäche") -> void:
	if characters.has(cid):
		var c: Dictionary = characters[cid]
		c["alive"] = false
		c["death_year"] = death_year
		c["cause_of_death"] = cause


func alive_characters(fid: StringName = &"") -> Array[StringName]:
	var result: Array[StringName] = []
	for cid in characters:
		var c: Dictionary = characters[cid]
		if c.get("alive", false) and (String(fid).is_empty() or c.get("faction", &"") == fid):
			result.append(cid as StringName)
	return result


func alive_characters_by_role(fid: StringName, role: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for cid in characters:
		var c: Dictionary = characters[cid]
		if c.get("alive", false) and c.get("faction", &"") == fid and c.get("role", &"") == role:
			result.append(cid as StringName)
	return result


func character_name(cid: StringName) -> String:
	return str(characters.get(cid, {}).get("name", "Unknown"))


func character_faction(cid: StringName) -> StringName:
	return str(characters.get(cid, {}).get("faction", "")) as StringName


func character_role(cid: StringName) -> StringName:
	return str(characters.get(cid, {}).get("role", "")) as StringName


func character_rank(cid: StringName) -> String:
	return str(characters.get(cid, {}).get("rank", ""))


func character_traits(cid: StringName) -> Dictionary:
	return characters.get(cid, {}).get("traits", {})


func promote_character(cid: StringName, new_rank: String) -> void:
	if characters.has(cid):
		(characters[cid] as Dictionary)["rank"] = new_rank


func wound_character(cid: StringName) -> void:
	if characters.has(cid):
		var c: Dictionary = characters[cid]
		c["wounds"] = int(c.get("wounds", 0)) + 1


# --- Technology ---

func has_technology(fid: StringName, tech_id: StringName) -> bool:
	var techs: Array = technologies.get(fid, [])
	return techs.has(tech_id)


func add_technology(fid: StringName, tech_id: StringName) -> void:
	if not technologies.has(fid):
		technologies[fid] = []
	var techs: Array = technologies[fid]
	if not techs.has(tech_id):
		techs.append(tech_id)


func faction_technology_count(fid: StringName) -> int:
	return int(technologies.get(fid, []).size())
