class_name EconomyRefineryTradeUnit
extends RefCounted

## E3: Verhaltens-Einheit für Refinery, Trade-Routen, Gathering und
## Resource-Generierung aus EconomyDomain.
##
## Verantwortlich: steal_resources, register_gathering_workers, withdraw,
## gather_income_tick, generate_resources_for_planet, convert_refinery_resources,
## can/register_trade_route, market_price, tick_trade_routes, market_snapshot.
##
## State-Dictionarys und Signale bleiben auf der EconomyDomain-Fassade.
## Diese Einheit erhält die Fassade als `_owner` und nutzt dessen
## Methoden für Vault-/Local-/Signal-Operationen.

var _owner: EconomyDomain


func _init(owner: EconomyDomain) -> void:
	_owner = owner


## Encapsulates resource looting so GameState.steal_resources() becomes a
## one-liner delegation. Transfers a fraction of the planet's local stock to
## the attacker's faction vault.
func steal_resources(planet_id: StringName, attacker_faction: StringName, percentage: float = 0.5) -> Dictionary:
	var stolen: Dictionary = {}
	var vault := _owner.local_vault(planet_id).duplicate()
	for resource_id in vault:
		var amount: int = int(vault[resource_id])
		if amount <= 0:
			continue
		var take: int = maxi(1, int(round(float(amount) * clampf(percentage, 0.0, 1.0))))
		if take <= 0:
			continue
		_owner.spend_local_resource(planet_id, resource_id as StringName, take)
		_owner.add_faction_resource(attacker_faction, resource_id as StringName, take)
		stolen[resource_id] = take
	return stolen


func register_gathering_workers(faction: StringName, planet_id: StringName, source_planet_id: StringName, count: int) -> void:
	if String(faction).is_empty() or String(planet_id).is_empty() or count <= 0:
		return
	if not _owner.gathering_workers.has(faction):
		_owner.gathering_workers[faction] = {}
	if not _owner.gathering_sources.has(faction):
		_owner.gathering_sources[faction] = {}
	var current: int = _owner.gathering_workers[faction].get(planet_id, 0)
	_owner.gathering_workers[faction][planet_id] = current + count
	_owner.gathering_sources[faction][planet_id] = source_planet_id
	_owner.gathering_started.emit(faction, planet_id, count)


## Domain-ref overload: guards (faction validity, planet ownership, scan) run
## inside EconomyDomain so GameState.register_gathering_workers() becomes a
## pure delegation call. Returns the new worker count on the target planet.
func register_gathering_workers_with_domains(
	faction: StringName,
	planet_id: StringName,
	worker_amount: int,
	faction_domain: FactionDomain,
	source_planet_id: StringName = &""
) -> int:
	if faction == GameState.FACTION_NEUTRAL or faction.is_empty():
		return 0
	if faction_domain.faction_of(planet_id) != GameState.FACTION_NEUTRAL:
		return 0
	if not faction_domain.has_scanned_planet(faction, planet_id):
		return 0
	register_gathering_workers(faction, planet_id, source_planet_id, worker_amount)
	return gathering_workers_on(faction, planet_id)


func get_gathering_source(faction: StringName, planet_id: StringName) -> StringName:
	if not _owner.gathering_sources.has(faction):
		return &""
	return _owner.gathering_sources[faction].get(planet_id, &"") as StringName


func withdraw_gathering_workers(faction: StringName, planet_id: StringName, amount: int = -1) -> Dictionary:
	if not _owner.gathering_workers.has(faction) or not _owner.gathering_workers[faction].has(planet_id):
		return {"count": 0, "source_planet_id": &""}
	var current: int = _owner.gathering_workers[faction].get(planet_id, 0)
	var count: int = current if amount < 0 else mini(current, maxi(amount, 0))
	var source_planet_id: StringName = get_gathering_source(faction, planet_id)
	if count <= 0:
		return {"count": 0, "source_planet_id": source_planet_id}
	var remaining := current - count
	if remaining <= 0:
		_owner.gathering_workers[faction].erase(planet_id)
		if _owner.gathering_sources.has(faction):
			_owner.gathering_sources[faction].erase(planet_id)
	else:
		_owner.gathering_workers[faction][planet_id] = remaining
	if count > 0:
		_owner.gathering_withdrawn.emit(faction, planet_id, count)
	return {"count": count, "source_planet_id": source_planet_id}


func gathering_workers_on(faction: StringName, planet_id: StringName) -> int:
	if not _owner.gathering_workers.has(faction):
		return 0
	return int(_owner.gathering_workers[faction].get(planet_id, 0))


func gather_income_tick(base_amounts: Dictionary, catalog: PlanetUpgradeCatalog = null) -> int:
	var effective_catalog: PlanetUpgradeCatalog = catalog if catalog != null else GameState.DEFAULT_UPGRADE_CATALOG
	var total_earned := 0
	for faction in _owner.gathering_workers:
		var faction_name := faction as StringName
		var planets: Dictionary = _owner.gathering_workers[faction]
		for p_id in planets:
			var planet_id := p_id as StringName
			var count: int = planets[p_id]
			if count <= 0:
				continue
			var res_id: StringName = _owner.resource_of(planet_id)
			if not _owner._is_valid_resource_id(res_id):
				continue
			var base_amt: int = maxi(int(base_amounts.get(planet_id, 1)), 1)
			var gather_multiplier := 1.0
			if effective_catalog != null:
				for upgrade_id in _owner.get_planet_upgrades(planet_id):
					var upgrade: PlanetUpgradeDefinition = effective_catalog.resolve(upgrade_id)
					if upgrade != null and upgrade.trait_definition != null:
						gather_multiplier *= upgrade.trait_definition.gather_income_multiplier
			var earned: int = maxi(1, int(round(float(count * base_amt) * gather_multiplier)))
			_owner.add_faction_resource(faction_name, res_id, earned)
			total_earned += earned
			_owner.resources_collected.emit(faction_name, planet_id, res_id, earned)
	return total_earned


# Generates consumed-amount of the planet's resource for its owning faction,
# applying per-upgrade production boosts and per-planet tech multipliers.
# Maintenance costs are subtracted best-effort (refinery upgrade may leave the
# faction broke — production is still added).
func generate_resources_for_planet(
	planet_id: StringName,
	faction_domain: FactionDomain,
	tech: TechDomain,
	catalog: PlanetUpgradeCatalog,
	base_amount: int = 1
) -> int:
	var faction: StringName = faction_domain.faction_of(planet_id)
	if faction == GameState.FACTION_NEUTRAL or not _owner.faction_vaults.has(faction):
		return 0
	var resource_id: StringName = _owner.resource_of(planet_id)
	if String(resource_id).is_empty() or not _owner._is_valid_resource_id(resource_id):
		return 0
	var multiplier := 1.0
	for up_id in _owner.get_planet_upgrades(planet_id):
		var def: PlanetUpgradeDefinition = catalog.resolve(up_id) if catalog != null else null
		if def != null and def.trait_definition != null:
			multiplier += def.trait_definition.production_boost
			var maintenance_resource: StringName = def.trait_definition.maintenance_cost_resource
			if not String(maintenance_resource).is_empty() and def.trait_definition.maintenance_cost_amount > 0:
				_owner.spend_faction_resource(faction, maintenance_resource, def.trait_definition.maintenance_cost_amount)
			if def.trait_definition.maintenance_credit_cost > 0:
				_owner.spend_faction_credits(faction, def.trait_definition.maintenance_credit_cost)
	for planet_technology_id in tech.get_planet_technologies(planet_id):
		var planet_technology: TechnologyDefinition = GameState.DEFAULT_TECHNOLOGY_CATALOG.resolve(planet_technology_id)
		if planet_technology != null:
			multiplier *= planet_technology.production_multiplier
	var final_amount: int = maxi(1, int(round(float(maxi(base_amount, 1)) * multiplier)))
	_owner.add_faction_resource(faction, resource_id, final_amount)
	_owner.resource_generated.emit(planet_id, resource_id, final_amount)
	return final_amount


# Material→Rare conversion (refinery upgrade only). Refunds the spent material
# if energy runs short mid-transaction; emits refinery_converted on success.
func convert_refinery_resources(planet_id: StringName, faction_domain: FactionDomain) -> Dictionary:
	var faction: StringName = faction_domain.faction_of(planet_id)
	if faction == GameState.FACTION_NEUTRAL or not _owner.faction_vaults.has(faction) or not _owner.has_planet_upgrade(planet_id, &"refinery"):
		return {"converted": false}
	var material: int = _owner.get_faction_resource(faction, GameState.RES_MATERIAL)
	var energy: int = _owner.get_faction_resource(faction, GameState.RES_ENERGY)
	if material < 2 or energy < 1:
		return {"converted": false}
	if not _owner.spend_faction_resource(faction, GameState.RES_MATERIAL, 2):
		return {"converted": false}
	if not _owner.spend_faction_resource(faction, GameState.RES_ENERGY, 1):
		_owner.add_faction_resource(faction, GameState.RES_MATERIAL, 2)
		return {"converted": false}
	var produced_resource: StringName = GameState.RES_RARE
	_owner.add_faction_resource(faction, produced_resource, 1)
	var consumed := {GameState.RES_MATERIAL: 2, GameState.RES_ENERGY: 1}
	var produced := {produced_resource: 1}
	_owner.refinery_converted.emit(planet_id, faction, consumed, produced)
	return {"converted": true, "consumed": consumed, "produced": produced}


# --- TRADE ROUTES ---


func can_register_trade_route(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> bool:
	if String(from_planet).is_empty() or String(to_planet).is_empty() or from_planet == to_planet or not _owner._is_valid_resource_id(resource_id):
		return false
	var owner: StringName = _route_owner(from_planet)
	if owner == GameState.FACTION_NEUTRAL:
		return true
	# A route becomes a market connection only when at least one endpoint is
	# backed by a trade post/network upgrade. Neutral synthetic test planets
	# remain valid for deterministic local-vault tests.
	return _owner.has_planet_upgrade(from_planet, &"trade_post") or _owner.has_planet_upgrade(from_planet, &"trade_network") or _owner.has_planet_upgrade(to_planet, &"trade_post") or _owner.has_planet_upgrade(to_planet, &"trade_network")


func register_trade_route(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> StringName:
	if not can_register_trade_route(from_planet, to_planet, resource_id):
		return &""
	_owner._next_trade_route_index += 1
	var route_id := StringName("route_%d" % _owner._next_trade_route_index)
	_owner.trade_routes[route_id] = {
		"from": from_planet,
		"to": to_planet,
		"resource_id": resource_id,
		"flow_rate": 1,
		"active": true,
		"volume": 0,
		"last_price": market_price(from_planet, to_planet, resource_id),
		"toll_credits": 0,
	}
	return route_id


func market_price(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> float:
	if not _owner._is_valid_resource_id(resource_id):
		return 0.0
	var source_stock: int = _owner.get_local_resource(from_planet, resource_id)
	var destination_stock: int = _owner.get_local_resource(to_planet, resource_id)
	# Scarcity at the destination raises the price, while source abundance
	# lowers it. Clamp it to keep the credit economy stable and deterministic.
	var scarcity: float = clampf(float(destination_stock - source_stock) / 20.0, -0.5, 1.5)
	var price: float = clampf(1.0 + scarcity, 0.5, 2.5)
	_owner.market_prices[StringName("%s:%s:%s" % [String(from_planet), String(to_planet), String(resource_id)])] = price
	return price


func get_market_price(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> float:
	var key := StringName("%s:%s:%s" % [String(from_planet), String(to_planet), String(resource_id)])
	return float(_owner.market_prices.get(key, market_price(from_planet, to_planet, resource_id)))


func trade_routes_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for route_id in _owner.trade_routes:
		snapshot[route_id] = (_owner.trade_routes[route_id] as Dictionary).duplicate()
	return snapshot


func tick_trade_routes() -> int:
	_owner._trade_tick_index += 1
	var moved := 0
	var config: EconomyConfig = _owner.economy_config if _owner.economy_config != null else _owner.DEFAULT_ECONOMY_CONFIG
	for route_id in _owner.trade_routes:
		var route: Dictionary = _owner.trade_routes[route_id]
		if not bool(route.get("active", false)):
			continue
		var resource_id: StringName = route["resource_id"] as StringName
		var amount: int = maxi(int(route.get("flow_rate", 1)), 1)
		var from_planet: StringName = route["from"] as StringName
		var to_planet: StringName = route["to"] as StringName
		var price: float = market_price(from_planet, to_planet, resource_id)
		if _owner.transfer_resources(from_planet, to_planet, resource_id, amount):
			moved += amount
			var volume: int = int(route.get("volume", 0)) + amount
			var toll: int = maxi(1, int(round(float(amount) * price * config.market_toll_rate)))
			route["volume"] = volume
			route["last_price"] = price
			route["toll_credits"] = int(route.get("toll_credits", 0)) + toll
			_owner.trade_volumes[resource_id] = int(_owner.trade_volumes.get(resource_id, 0)) + amount
			# Test fixtures use synthetic planets without ownership. In a live run,
			# the route owner receives the tariff; neutral routes simply move cargo.
			var owner: StringName = _route_owner(from_planet)
			if owner != GameState.FACTION_NEUTRAL:
				_owner.add_faction_credits(owner, toll)
		_owner.trade_routes[route_id] = route
	return moved


func _route_owner(planet_id: StringName) -> StringName:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var state: Node = tree.root.get_node_or_null("GameState") if tree != null and tree.root != null else null
	if state != null and state.has_method("faction_of"):
		return state.faction_of(planet_id)
	return GameState.FACTION_NEUTRAL


func market_snapshot() -> Dictionary:
	return {"prices": _owner.market_prices.duplicate(), "volumes": _owner.trade_volumes.duplicate(), "routes": trade_routes_snapshot()}
