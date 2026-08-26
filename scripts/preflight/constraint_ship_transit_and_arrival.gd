class_name PreflightConstraintShipTransitAndArrival
extends RefCounted

## ShipBase dispatch, fleet preview and live military arrival into the conquest
## replay (deterministic replay reproduction + ConquestScene handoff).

func constraint_name() -> String:
	return "ship_transit_and_arrival"


func run(ctx: PreflightContext) -> bool:
	var field: Node = ctx.field
	var game_state: Node = ctx.game_state

	if not ctx.check(ctx.fixture.prepare_ship_builder(), "ship-builder fixture could not prepare the shipyard prerequisite"):
		return false
	await ctx.await_frame()
	var source: Planet = ctx.find_planet_by_id(field, game_state.homeworld_for(GameState.FACTION_PLAYER) as StringName)
	if not ctx.check(source != null and game_state.has_planet_upgrade(source.planet_id, ShipManager.SHIPYARD_UPGRADE_ID), "player homeworld should carry a shipyard before the ship transit test"):
		return false
	var ship_manager: ShipManager = field.get_node_or_null("ShipManager") as ShipManager
	if not ctx.check(ship_manager != null, "ShipManager runtime module is missing"):
		return false
	var catalog: ShipPartCatalog = ship_manager.get_part_catalog()
	var hull_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_HULL)[0]
	var drive_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_DRIVE)[0]
	var weapon_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_WEAPON)[0]
	var shield_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_SHIELD)[0]
	var scanner_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_SCANNER)[0]

	# Arm the flight ship: research the weapon gate and stock a full loadout.
	var tech_catalog: TechnologyCatalog = ship_manager.get_technology_catalog()
	if not game_state.has_technology(GameState.FACTION_PLAYER, &"weapon_systems"):
		if not ctx.check(game_state.research_technology(GameState.FACTION_PLAYER, &"weapon_systems", tech_catalog), "weapon_systems research should start for the flight ship"):
			return false
		game_state.call("advance_research", 999.0)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_MATERIAL, 100)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY, 100)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_VOLATILE, 100)
	if not ctx.check(ship_manager.buy_part(source, hull_part.id), "flight hull part purchase should succeed"):
		return false
	if not ctx.check(ship_manager.buy_part(source, scanner_part.id), "flight scanner part purchase should succeed"):
		return false
	if not ctx.check(ship_manager.buy_part(source, weapon_part.id), "flight weapon part purchase should succeed"):
		return false
	if not ctx.check(ship_manager.buy_part(source, drive_part.id), "flight drive part purchase should succeed"):
		return false
	if not ctx.check(ship_manager.buy_part(source, shield_part.id), "flight shield part purchase should succeed"):
		return false

	# --- FLYING SHIPBASE: dispatch consumes the assembly and spawns a flyable instance ---
	var conflict_manager: Node = field.get_node_or_null("ConflictManager")
	if not ctx.check(conflict_manager != null and conflict_manager.has_method("preview_duration"), "ConflictManager runtime module is missing"):
		return false
	if not ctx.check(conflict_manager.has_signal("replay_started"), "ConflictManager replay handoff is missing from the ShipBase path"):
		return false
	var ship_replay_kinds: Array[StringName] = []
	var ship_replays: Array[CombatReplay] = []
	var ship_replay_capture: Callable = func(simulation_type, replay):
		ship_replay_kinds.append(simulation_type as StringName)
		var typed_replay: CombatReplay = replay as CombatReplay
		if typed_replay != null:
			ship_replays.append(typed_replay)
	conflict_manager.connect("replay_started", ship_replay_capture)
	var flight_ship_id: StringName = ship_manager.assemble_ship(source, hull_part.id, scanner_part.id, [], weapon_part.id, drive_part.id, shield_part.id)
	if not ctx.check(not String(flight_ship_id).is_empty(), "flight ship assembly did not start"):
		return false
	game_state.call("advance_builds", 999.0)
	if not ctx.check(game_state.has_ship_assembly(source.planet_id, flight_ship_id), "flight ship did not finish its build job"):
		return false
	var neutral_home: StringName = game_state.homeworld_for(GameState.FACTION_NEUTRAL) as StringName
	var flight_destination: Planet = null
	for child in field.get_children():
		if child is Planet and (child as Planet).get_faction() == GameState.FACTION_NEUTRAL and (child as Planet).planet_id != neutral_home and child != source:
			flight_destination = child as Planet
			break
	if not ctx.check(flight_destination != null, "no disposable neutral planet available for ship flight test"):
		return false
	var preview_duration: float = float(conflict_manager.call("preview_duration", source, flight_destination, flight_ship_id))
	var source_assembly_before_preview: ShipAssembly = game_state.get_ship_assembly(source.planet_id, flight_ship_id)
	var preview_fleet: FleetSnapshot = game_state.preview_fleet_from_planet(source.planet_id, [flight_ship_id], catalog)
	if not ctx.check(preview_fleet != null and preview_fleet.ships.size() == 1 and game_state.has_ship_assembly(source.planet_id, flight_ship_id) and source_assembly_before_preview != null and not source_assembly_before_preview.is_empty(), "fleet preview must not consume the source assembly"):
		return false
	var ship_base: ShipBase = ship_manager.dispatch_ship(source, flight_destination, flight_ship_id)
	if not ctx.check(ship_base != null, "dispatch_ship did not spawn a flyable ShipBase"):
		return false
	if not ctx.check(not game_state.has_ship_assembly(source.planet_id, flight_ship_id), "dispatch did not consume the assembly from inventory"):
		return false
	if not ctx.check(ship_base.fleet != null and ship_base.fleet.faction == GameState.FACTION_PLAYER and ship_base.fleet.ships.size() == 1, "flyable ShipBase lost its fleet payload"):
		return false
	if not ctx.check(ship_base.destination == flight_destination, "flyable ShipBase lost its destination"):
		return false
	if not ctx.check(absf(preview_duration - ship_base.flight_duration()) <= 0.01, "drive trait flight preview and actual ShipBase duration diverged"):
		return false
	var ship_visual: CompositeShipView = ship_base.get_node_or_null("ShipVisual") as CompositeShipView
	if not ctx.check(ship_visual != null and ship_visual.get_node_or_null("WeaponOverlay").visible and ship_visual.get_node_or_null("EngineOverlay").visible and ship_visual.get_node_or_null("ShieldOverlay").visible, "flyable ShipBase did not composite its drive/weapon/shield overlays"):
		return false
	if not ctx.check(not ship_base.has_arrived(), "ShipBase reported arrival before its flight finished"):
		return false
	var launched_fleet: FleetSnapshot = ship_base.fleet
	var defender_workers_before_arrival: int = flight_destination.worker_count
	var defender_rating_before_arrival: int = PlanetTraitAggregator.aggregate_defense_rating(flight_destination)
	var perimeter_slots_before_arrival: int = flight_destination.get_perimeter_slots()
	var defense_range_before_arrival: float = flight_destination.get_defense_range()
	var battle_counter_before_arrival: int = int(conflict_manager.call("battle_counter"))
	ship_base.call("_arrive")
	if not ctx.check(ship_replay_kinds.has(&"conquest"), "live ShipBase military arrival did not start the conquest replay"):
		return false
	if not ctx.check(ship_replays.size() > 0, "live ShipBase military arrival did not provide a typed replay payload"):
		return false
	var conquest_replay: CombatReplay = ship_replays[ship_replays.size() - 1]
	if not ctx.check(conquest_replay.is_conquest() and conquest_replay.conquest_seed != 42, "live conquest replay must use a derived seed instead of the legacy constant"):
		return false
	if not ctx.check(int(conflict_manager.call("battle_counter")) == battle_counter_before_arrival + 1, "combat counter did not advance exactly once for the live encounter"):
		return false
	var replayed_conquest: CombatReplay = ConquestSimulator.simulate_conquest(
		launched_fleet,
		0,
		defender_workers_before_arrival,
		defender_rating_before_arrival,
		perimeter_slots_before_arrival,
		defense_range_before_arrival,
		conquest_replay.conquest_seed
	)
	if not ctx.check(
		replayed_conquest.captured == conquest_replay.captured
		and replayed_conquest.surviving_attackers == conquest_replay.surviving_attackers
		and is_equal_approx(replayed_conquest.duration, conquest_replay.duration),
		"captured conquest seed must reproduce the live replay result"):
		return false
	if not ctx.check(ship_replay_kinds.has(&"conquest"), "live ShipBase military arrival did not emit replay_started for conquest"):
		return false
	await ctx.await_frame()
	if not ctx.check(not is_instance_valid(ship_base), "arrived ShipBase was not freed after resolving arrival"):
		return false

	return true
