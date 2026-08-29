extends SceneTree

## E2-E4-Gate (R-007): Verifiziert das Verhalten der extrahierten Einheiten:
## EconomyDealUnit (Ressourcenverteilung, Shuffle), EconomyUpgradeUnit
## (Kosten, Build Advance, Abort, Worker-Reservierung/-Release),
## EconomyRefineryTradeUnit (Conversion, Trade Route, Market Price, Owner via
## injizierten Resolver) und EconomyGatheringTransportUnit (Gathering-
## Registrierung, Income, Transport-Lifecycle, Resource-Generierung).
##
## Echte Assertions mit Failure-Path; Exit 1 bei Abweichung, kein Print-only.
## Die Upgrade-Assertions laufen ueber einen synthetischen Katalog (keine
## Abhaengigkeit von den shipped Katalogen), damit sie gegen Katalog-Drift
## stabil bleiben.

var _failures: Array[String] = []

var _instant_id := &"test_instant"
var _queued_id := &"test_queued"
var _abort_id := &"test_abort"

func _init() -> void:
	call_deferred("_run")

func _fail(what: String) -> void:
	_failures.append(what)

func _run() -> void:
	_run_e2_deal_and_upgrade()
	_run_e3_refinery_trade()
	_run_e4_gathering_transport()
	_run_e4_buildings_grid()

	if not _failures.is_empty():
		for failure in _failures:
			printerr("[E2-E4-FAIL] " + failure)
		print("E2-E4 ECONOMY UNITS: FAIL (%d failures)" % _failures.size())
		quit(1)
		return
	print("E2-E4 ECONOMY UNITS: PASS (all assertions held)")
	quit(0)


func _make_test_catalog() -> PlanetUpgradeCatalog:
	var catalog := PlanetUpgradeCatalog.new()
	var instant := PlanetUpgradeDefinition.new()
	instant.id = _instant_id
	instant.cost_amount = 10
	instant.credit_cost = 5
	instant.workers_required = 1
	instant.build_time = 0.0
	var queued := PlanetUpgradeDefinition.new()
	queued.id = _queued_id
	queued.cost_amount = 10
	queued.credit_cost = 5
	queued.workers_required = 1
	queued.build_time = 2.0
	var abort := PlanetUpgradeDefinition.new()
	abort.id = _abort_id
	abort.cost_amount = 10
	abort.credit_cost = 5
	abort.workers_required = 1
	abort.build_time = 1.0
	catalog.upgrades = [instant, queued, abort]
	return catalog


func _fund_economy() -> EconomyDomain:
	var economy := EconomyDomain.new()
	economy.reset_vaults()
	economy.add_faction_credits(GameState.FACTION_PLAYER, 5000)
	for resource in GameState.DEFAULT_RESOURCE_POOL.resources:
		economy.add_faction_resource(GameState.FACTION_PLAYER, resource.id, 500)
	return economy


# --- E2: Deal + Upgrade ---


func _run_e2_deal_and_upgrade() -> void:
	var economy := _fund_economy()

	# Deal: two planets get resources; homeworld gets DISTINCT identities.
	var catalog := PlanetCatalog.new()
	var home := PlanetDefinition.new()
	home.planet_id = &"hw"
	home.planet_role = &"homeworld"
	var other := PlanetDefinition.new()
	other.planet_id = &"other"
	other.planet_role = &"neutral"
	catalog.planets = [home, other]
	economy.deal_resources(catalog, GameState.DEFAULT_RESOURCE_POOL, 424242)
	if String(economy.resource_of(&"hw")).is_empty():
		_fail("deal_resources did not assign a resource to the homeworld")
	if economy.resource_of(&"hw") == economy.resource_of(&"other"):
		_fail("homeworld and neutral planet share the same resource after dealing")

	# Instant upgrade: cost gating, purchase, record.
	var test_catalog := _make_test_catalog()
	if not economy.can_purchase_upgrade(GameState.FACTION_PLAYER, &"hw", _instant_id, 50, test_catalog):
		_fail("can_purchase_upgrade should pass with enough workforce")
	if not economy.purchase_upgrade(GameState.FACTION_PLAYER, &"hw", _instant_id, 50, test_catalog):
		_fail("purchase_upgrade should succeed")
	if not economy.has_planet_upgrade(&"hw", _instant_id):
		_fail("purchase_upgrade did not record the upgrade")

	# Worker reserved during a build, released after advance.
	if not economy.purchase_upgrade(GameState.FACTION_PLAYER, &"hw", _queued_id, 50, test_catalog):
		_fail("purchase_upgrade (build_time) should queue")
	if not economy.upgrade_build_in_progress(&"hw", _queued_id):
		_fail("queued upgrade should be in progress")
	if economy.available_workers(&"hw", 5) != 4:
		_fail("queued build should reserve 1 worker")
	var remaining: float = economy.upgrade_build_remaining(&"hw", _queued_id)
	if remaining <= 0.0:
		_fail("queued upgrade should have positive build time")
	economy.advance_upgrade_builds(remaining + 0.1)
	if economy.upgrade_build_in_progress(&"hw", _queued_id):
		_fail("advance_upgrade_builds should complete the build")
	if not economy.has_planet_upgrade(&"hw", _queued_id):
		_fail("advanced build should record the upgrade")
	if economy.available_workers(&"hw", 5) != 5:
		_fail("completed build should release workers")

	# Abort path: queue again and abort -> refund, no upgrade, workers released.
	var credits_before: int = economy.get_faction_credits(GameState.FACTION_PLAYER)
	if not economy.purchase_upgrade(GameState.FACTION_PLAYER, &"hw", _abort_id, 50, test_catalog):
		_fail("purchase_upgrade (for abort) should queue")
	if not economy.abort_upgrade_build(&"hw", _abort_id):
		_fail("abort_upgrade_build should succeed")
	if economy.has_planet_upgrade(&"hw", _abort_id):
		_fail("aborted upgrade should not be recorded")
	if economy.upgrade_build_in_progress(&"hw", _abort_id):
		_fail("aborted upgrade should not remain in progress")
	if economy.available_workers(&"hw", 5) != 5:
		_fail("aborted build should release workers")
	if economy.get_faction_credits(GameState.FACTION_PLAYER) != credits_before:
		_fail("aborted build should refund credits")


# --- E3: Refinery / Trade / Market / Owner ---


func _run_e3_refinery_trade() -> void:
	var economy := _fund_economy()
	var faction_domain := FactionDomain.new()
	faction_domain.set_faction(&"p_a", GameState.FACTION_PLAYER)
	economy.set_planet_resource(&"p_a", GameState.RES_MATERIAL)
	economy.set_planet_resource(&"p_b", GameState.RES_ENERGY)
	economy.seed_local_resources([&"p_a", &"p_b"], null, 7)

	# Conversion refuses on NEUTRAL planet.
	var conv: Dictionary = economy.convert_refinery_resources(&"p_b", faction_domain)
	if bool(conv.get("converted", false)):
		_fail("refinery conversion on a neutral planet should fail")

	# Conversion succeeds on owned planet with refinery upgrade.
	economy.add_planet_upgrade(&"p_a", &"refinery")
	economy.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_MATERIAL, 4)
	conv = economy.convert_refinery_resources(&"p_a", faction_domain)
	if not bool(conv.get("converted", false)):
		_fail("refinery conversion on owned planet with refinery upgrade should succeed")
	if int(conv.get("consumed", {}).get(GameState.RES_MATERIAL, 0)) != 2:
		_fail("conversion consumed wrong material amount")
	if economy.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_RARE) < 1:
		_fail("conversion should produce rare")

	# Trade route with injected resolver -> owner is PLAYER for p_a.
	var resolver := func(planet_id: StringName) -> StringName:
		if planet_id == &"p_a":
			return GameState.FACTION_PLAYER
		return GameState.FACTION_NEUTRAL
	economy.set_route_owner_resolver(resolver)
	economy.add_planet_upgrade(&"p_a", &"trade_post")
	var route_id: StringName = economy.register_trade_route(&"p_a", &"p_b", GameState.RES_ENERGY)
	if String(route_id).is_empty():
		_fail("register_trade_route should create a route for owned planet with trade post")
	economy.add_local_resource(&"p_a", GameState.RES_ENERGY, 10)
	var moved: int = economy.tick_trade_routes()
	if moved <= 0:
		_fail("tick_trade_routes should move cargo")

	# Market price is deterministic and clamped.
	var price: float = economy.market_price(&"p_a", &"p_b", GameState.RES_ENERGY)
	if price < 0.5 or price > 2.5:
		_fail("market_price out of clamp range: %f" % price)


# --- E4: Gathering / Transport ---


func _run_e4_gathering_transport() -> void:
	var economy := _fund_economy()
	var faction_domain := FactionDomain.new()
	faction_domain.set_faction(&"g2", GameState.FACTION_PLAYER)
	economy.set_planet_resource(&"g1", GameState.RES_BIOMASS)
	economy.set_planet_resource(&"g2", GameState.RES_ENERGY)
	economy.seed_local_resources([&"g1", &"g2"], null, 9)

	# Gathering registration + income.
	economy.register_gathering_workers(GameState.FACTION_PLAYER, &"g1", &"src", 3)
	if economy.gathering_workers_on(GameState.FACTION_PLAYER, &"g1") != 3:
		_fail("gathering registration did not record workers")
	var earned: int = economy.gather_income_tick({&"g1": 2})
	if earned <= 0:
		_fail("gather_income_tick should produce income")

	# Transport lifecycle: begin -> update phase/cargo -> complete removes record.
	var path: Array[Vector2] = [Vector2.ZERO, Vector2(10, 10)]
	var tid: StringName = economy.begin_worker_transport(GameState.FACTION_PLAYER, &"g1", &"g2", 2, 3.0, path)
	if String(tid).is_empty():
		_fail("begin_worker_transport should create a transport")
	if not economy.update_worker_transport(tid, &"returning", GameState.RES_BIOMASS, 4):
		_fail("update_worker_transport should succeed")
	var records: Array[Dictionary] = economy.get_worker_transport_records(GameState.FACTION_PLAYER)
	if records.size() != 1:
		_fail("expected 1 transport record")
	if records[0].get("phase") != &"returning":
		_fail("transport phase should be returning")
	if int(records[0].get("cargo_amount", 0)) != 4:
		_fail("transport cargo amount not updated")
	if not economy.set_worker_transport_escorted(tid, true):
		_fail("set_worker_transport_escorted should succeed")
	if not (economy.get_worker_transport_records(GameState.FACTION_PLAYER)[0].get("escorted", false) as bool):
		_fail("escorted flag not persisted")

	# Failure path: begin with NEUTRAL faction.
	if not String(economy.begin_worker_transport(GameState.FACTION_NEUTRAL, &"g1", &"g2", 2, 1.0, path)).is_empty():
		_fail("begin_worker_transport with NEUTRAL faction should fail")

	# Resource generation (owned planet).
	var generated: int = economy.generate_resources_for_planet(&"g2", faction_domain, TechDomain.new(), null, 1)
	if generated <= 0:
		_fail("generate_resources_for_planet should produce resources")

	# Complete -> record removed.
	if not economy.complete_worker_transport(tid, true):
		_fail("complete_worker_transport should succeed")
	if not economy.get_worker_transport_records(GameState.FACTION_PLAYER).is_empty():
		_fail("completed transport should be removed from active records")

	# Failure path: unknown transport.
	if economy.complete_worker_transport(StringName("no_such_transport")):
		_fail("complete_worker_transport on unknown id should fail")
	if economy.update_worker_transport(StringName("no_such_transport"), &"phase"):
		_fail("update_worker_transport on unknown id should fail")


# --- E4b: Buildings / Grid ---


func _run_e4_buildings_grid() -> void:
	var economy := _fund_economy()
	var faction_domain := FactionDomain.new()
	faction_domain.set_faction(&"pb", GameState.FACTION_PLAYER)
	faction_domain.starting_workers[&"pb"] = 10

	# Synthetischer Building-Katalog (instant + queued + abort).
	var instant := BuildingDefinition.new()
	instant.id = &"test_bld_instant"
	instant.cost_resources = {GameState.RES_ENERGY: 5}
	instant.credit_cost = 5
	instant.workers_required = 1
	instant.build_time = 0.0
	var queued := BuildingDefinition.new()
	queued.id = &"test_bld_queued"
	queued.cost_resources = {GameState.RES_ENERGY: 5}
	queued.credit_cost = 5
	queued.workers_required = 1
	queued.build_time = 2.0
	var abort := BuildingDefinition.new()
	abort.id = &"test_bld_abort"
	abort.cost_resources = {GameState.RES_ENERGY: 5}
	abort.credit_cost = 5
	abort.workers_required = 1
	abort.build_time = 1.0
	var catalog := BuildingCatalog.new()
	catalog.buildings = [instant, queued, abort]

	var placed_signals: Array = []
	var removed_signals: Array = []
	economy.building_placed.connect(func(planet_id: StringName, building_id: StringName, q: int, r: int) -> void:
		placed_signals.append([planet_id, building_id, q, r])
	)
	economy.building_removed.connect(func(planet_id: StringName, q: int, r: int) -> void:
		removed_signals.append([planet_id, q, r])
	)

	# can_place + instant placement.
	if not economy.can_place_building(&"pb", instant.id, faction_domain, TechDomain.new(), catalog):
		_fail("can_place_building should allow on owned planet")
	if not economy.place_building(&"pb", instant.id, 0, 0, faction_domain, TechDomain.new(), catalog):
		_fail("place_building (instant) should succeed")
	if economy.planet_building_at(&"pb", 0, 0) != instant.id:
		_fail("instant building not recorded on grid")
	if placed_signals.size() != 1:
		_fail("building_placed signal should fire once")

	# Occupied cell rejects a second placement.
	if economy.place_building(&"pb", queued.id, 0, 0, faction_domain, TechDomain.new(), catalog):
		_fail("place_building on occupied cell should fail")

	# Queued build: worker reserved, advance completes and releases.
	if not economy.place_building(&"pb", queued.id, 1, 0, faction_domain, TechDomain.new(), catalog):
		_fail("place_building (queued) should succeed")
	if not economy.building_job_in_progress(&"pb", 1, 0):
		_fail("queued building should be in progress")
	if economy.available_workers(&"pb", 10) != 9:
		_fail("queued build should reserve 1 worker")
	economy.advance_building_jobs(2.1)
	if economy.building_job_in_progress(&"pb", 1, 0):
		_fail("advance_building_jobs should complete the queued build")
	if economy.planet_building_at(&"pb", 1, 0) != queued.id:
		_fail("completed building not recorded on grid")
	if economy.available_workers(&"pb", 10) != 10:
		_fail("completed build should release workers")
	if placed_signals.size() != 2:
		_fail("building_placed signal should fire for the completed build")

	# Abort: refund + release + no record.
	var credits_before: int = economy.get_faction_credits(GameState.FACTION_PLAYER)
	if not economy.place_building(&"pb", abort.id, 2, 0, faction_domain, TechDomain.new(), catalog):
		_fail("place_building (for abort) should succeed")
	if not economy.abort_building_job(&"pb", 2, 0):
		_fail("abort_building_job should succeed")
	if economy.building_job_in_progress(&"pb", 2, 0):
		_fail("aborted job should not remain in progress")
	if economy.planet_building_at(&"pb", 2, 0) != &"":
		_fail("aborted building should not be recorded")
	if economy.available_workers(&"pb", 10) != 10:
		_fail("aborted build should release workers")
	if economy.get_faction_credits(GameState.FACTION_PLAYER) != credits_before:
		_fail("aborted build should refund credits")

	# Failure paths.
	if economy.abort_building_job(&"pb", 5, 5):
		_fail("abort_building_job on empty cell should fail")

	# Remove recorded building.
	if economy.remove_planet_building(&"pb", 0, 0) != instant.id:
		_fail("remove_planet_building should return the removed id")
	if economy.planet_building_at(&"pb", 0, 0) != &"":
		_fail("removed building should leave the grid")
	if removed_signals.size() != 1:
		_fail("building_removed signal should fire once")