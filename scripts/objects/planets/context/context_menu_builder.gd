class_name ContextMenuBuilder

## Builds the right-click planet context menu (items, gating, and disable
## reasons). Kept out of planet_network.gd because the menu needs only
## GameState reads and a neighbor predicate — no PlanetNetwork behavior. The
## network node still owns the PopupMenu and action dispatch; it delegates the
## pure menu assembly here and keeps the returned disable-reason map.

## Assembles and gates the menu in place. `selection_service` and `game_state`
## are duck-typed (may be null in headless contexts); `is_neighbor_fn` is the
## network's adjacency predicate; `action_ids` maps stable names to the menu
## item ids the caller owns. Returns {"disabled_reasons": Dictionary}.
static func build_menu(
	menu: PopupMenu,
	planet: Node2D,
	selection_service,
	game_state,
	is_neighbor_fn: Callable,
	action_ids: Dictionary
) -> Dictionary:
	var reasons: Dictionary = {}
	if menu == null:
		return {"disabled_reasons": reasons}
	var open_id: int = int(action_ids.get("OPEN", 0))
	var focus_id: int = int(action_ids.get("FOCUS", 1))
	var attack_id: int = int(action_ids.get("ATTACK", 3))
	var collect_id: int = int(action_ids.get("COLLECT", 4))
	var colonize_id: int = int(action_ids.get("COLONIZE", 5))
	var clear_id: int = int(action_ids.get("CLEAR", 7))

	menu.clear()
	menu.add_item("Planet öffnen", open_id)
	menu.add_item("Auf Karte zentrieren", focus_id)
	menu.add_separator()
	menu.add_item("Angreifen", attack_id)
	menu.add_item("Sammeln", collect_id)
	menu.add_item("Kolonisieren", colonize_id)
	menu.add_separator()
	menu.add_item("Alles abwählen", clear_id)

	var selection_size: int = selection_service.get_selection_count() if selection_service != null else 1
	menu.set_item_disabled(clear_id, selection_size <= 1)
	if selection_size <= 1:
		reasons[clear_id] = "Nur ein Planet ausgewählt."

	var target_planet: Node2D = planet
	var primary_planet: Node2D = selection_service.get_primary() if selection_service != null else null
	var state: Node = game_state
	var target_faction: StringName = GameState.FACTION_NEUTRAL
	var player_owns_primary: bool = false
	if primary_planet != null and state != null:
		player_owns_primary = state.faction_of(primary_planet.planet_id) == GameState.FACTION_PLAYER
	if target_planet != null and state != null:
		target_faction = state.faction_of(target_planet.planet_id)
	var target_known_scanned: bool = state != null and target_planet != null and state.has_scanned_planet(GameState.FACTION_PLAYER, target_planet.planet_id)
	var hostile_target: bool = target_faction != GameState.FACTION_PLAYER and target_faction != GameState.FACTION_NEUTRAL and player_owns_primary and primary_planet != null and primary_planet != target_planet
	var neutral_target: bool = target_faction == GameState.FACTION_NEUTRAL and primary_planet != null and primary_planet != target_planet

	# Angreifen: hostile neighbours only, primary owns.
	if hostile_target and is_neighbor_fn.call(primary_planet, target_planet):
		menu.set_item_disabled(attack_id, false)
	else:
		menu.set_item_disabled(attack_id, true)
		reasons[attack_id] = get_attack_disable_reason(player_owns_primary, target_faction, primary_planet, target_planet, is_neighbor_fn)
	# Sammeln: scanned neutral neighbour, primary owns.
	if neutral_target and target_known_scanned and is_neighbor_fn.call(primary_planet, target_planet):
		menu.set_item_disabled(collect_id, false)
	else:
		menu.set_item_disabled(collect_id, true)
		reasons[collect_id] = get_collect_disable_reason(player_owns_primary, target_faction, target_known_scanned, primary_planet, target_planet, is_neighbor_fn)
	# Kolonisieren: scanned neutral neighbour, primary owns.
	if neutral_target and target_known_scanned and is_neighbor_fn.call(primary_planet, target_planet):
		menu.set_item_disabled(colonize_id, false)
	else:
		menu.set_item_disabled(colonize_id, true)
		reasons[colonize_id] = get_colonize_disable_reason(player_owns_primary, target_faction, target_known_scanned, primary_planet, target_planet, is_neighbor_fn)

	return {"disabled_reasons": reasons}

static func get_attack_disable_reason(player_owns_primary: bool, target_faction: StringName, primary_planet: Node2D, target_planet: Node2D, is_neighbor_fn: Callable) -> String:
	if primary_planet == null:
		return "Kein eigener Planet ausgewählt."
	if not player_owns_primary:
		return "Angreifen erfordert einen eigenen Planeten als Quelle."
	if target_faction == GameState.FACTION_PLAYER:
		return "Eigener Planet — kein Angriff nötig."
	if target_planet == null or primary_planet == target_planet:
		return "Wähle einen feindlichen Nachbarplaneten."
	if target_faction == GameState.FACTION_NEUTRAL:
		return "Neutrale Welten können erst nach Scout-Aufklärung angegriffen werden."
	if not is_neighbor_fn.call(primary_planet, target_planet):
		return "Zielplanet liegt außerhalb der Nachbarschaftskanten."
	return "Angriff aktuell nicht verfügbar."

static func get_collect_disable_reason(player_owns_primary: bool, target_faction: StringName, scanned: bool, primary_planet: Node2D, target_planet: Node2D, is_neighbor_fn: Callable) -> String:
	if primary_planet == null:
		return "Kein eigener Planet ausgewählt."
	if not player_owns_primary:
		return "Sammeln erfordert einen eigenen Planeten als Quelle."
	if target_planet == null or primary_planet == target_planet:
		return "Wähle einen neutralen Nachbarplaneten zum Sammeln."
	if target_faction != GameState.FACTION_NEUTRAL:
		return "Sammeln ist nur an neutralen, gescannten Welten möglich."
	if not scanned:
		return "Zielplanet wurde noch nicht gescannt (Scout benötigt)."
	if not is_neighbor_fn.call(primary_planet, target_planet):
		return "Zielplanet liegt außerhalb der Nachbarschaftskanten."
	return "Sammeln aktuell nicht verfügbar."

static func get_colonize_disable_reason(player_owns_primary: bool, target_faction: StringName, scanned: bool, primary_planet: Node2D, target_planet: Node2D, is_neighbor_fn: Callable) -> String:
	if primary_planet == null:
		return "Kein eigener Planet ausgewählt."
	if not player_owns_primary:
		return "Kolonisieren erfordert einen eigenen Planeten als Quelle."
	if target_planet == null or primary_planet == target_planet:
		return "Wähle einen neutralen Nachbarplaneten."
	if target_faction != GameState.FACTION_NEUTRAL:
		return "Nur neutrale Welten sind Kolonieziele."
	if not scanned:
		return "Zielplanet wurde noch nicht gescannt (Scout benötigt)."
	if not is_neighbor_fn.call(primary_planet, target_planet):
		return "Zielplanet liegt außerhalb der Nachbarschaftskanten."
	return "Kolonisieren aktuell nicht verfügbar."
