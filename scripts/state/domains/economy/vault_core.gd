class_name EconomyVaultCore
extends RefCounted

## R-007 (E1): Verhaltens-Einheit für Faction-Vaults, Credits, Local-Vaults,
## Worker-Reservierungen und die planet_resources-Map von EconomyDomain.
##
## Sämtliche State-Dictionarys und die 18 Domain-Signale bleiben auf der
## EconomyDomain-Fassade. Diese Einheit erhält die Fassade als `_owner` und
## mutiert den Zustand ausschließlich über sie — Dictionary-Referenzsemantik
## (z. B. direkte Pokes aus Preflight-Constraints) und Signal-Identität
## (GameState-Verbindungen) bleiben unverändert.

var _owner: Variant


func _init(owner: Variant) -> void:
	_owner = owner


func reset_vaults() -> void:
	_owner.faction_vaults = {
		GameState.FACTION_PLAYER: {
			GameState.RES_ENERGY: 50,
			GameState.RES_BIOMASS: 50,
			GameState.RES_RARE: 30,
			GameState.RES_MATERIAL: 30,
			GameState.RES_VOLATILE: 30
		},
		GameState.FACTION_CPU: {
			GameState.RES_ENERGY: 50,
			GameState.RES_BIOMASS: 50,
			GameState.RES_RARE: 30,
			GameState.RES_MATERIAL: 30,
			GameState.RES_VOLATILE: 30
		}
	}
	var config: EconomyConfig = _owner.economy_config if _owner.economy_config != null else _owner.DEFAULT_ECONOMY_CONFIG
	_owner.faction_credits = {
		GameState.FACTION_PLAYER: config.starting_credits,
		GameState.FACTION_CPU: config.starting_credits,
	}


func reset() -> void:
	_owner.planet_resources.clear()
	_owner.planet_upgrades.clear()
	_owner.worker_reservations.clear()
	_owner.upgrade_build_jobs.clear()
	_owner.worker_factories.clear()
	_owner.gathering_workers.clear()
	_owner.gathering_sources.clear()
	_owner.local_vaults.clear()
	_owner.trade_routes.clear()
	_owner.planet_buildings.clear()
	_owner.building_jobs.clear()
	_owner.market_prices.clear()
	_owner.trade_volumes.clear()
	_owner._next_trade_route_index = 0
	_owner._trade_tick_index = 0
	_owner.worker_transport_records.clear()
	_owner._next_worker_transport_index = 0
	_owner._local_seeded_planets.clear()
	reset_vaults()


func credit_transport_resources(faction: StringName, resource_id: StringName, amount: int) -> bool:
	if amount <= 0 or not is_valid_resource_id(resource_id):
		return false
	add_faction_resource(faction, resource_id, amount)
	return true


func get_faction_credits(faction: StringName) -> int:
	return int(_owner.faction_credits.get(faction, 0))


func add_faction_credits(faction: StringName, amount: int) -> int:
	if amount <= 0 or String(faction).is_empty():
		return get_faction_credits(faction)
	var new_amount: int = get_faction_credits(faction) + amount
	_owner.faction_credits[faction] = new_amount
	_owner.credits_changed.emit(faction, new_amount)
	return new_amount


func can_spend_faction_credits(faction: StringName, amount: int) -> bool:
	return amount <= 0 or get_faction_credits(faction) >= amount


func spend_faction_credits(faction: StringName, amount: int) -> bool:
	if amount < 0 or not can_spend_faction_credits(faction, amount):
		return false
	if amount == 0:
		return true
	_owner.faction_credits[faction] = get_faction_credits(faction) - amount
	_owner.credits_changed.emit(faction, _owner.faction_credits[faction])
	return true


func can_spend_cost(faction: StringName, resource_id: StringName, resource_amount: int, credit_amount: int) -> bool:
	return can_spend_faction_resource(faction, resource_id, resource_amount) and can_spend_faction_credits(faction, credit_amount)


func spend_cost(faction: StringName, resource_id: StringName, resource_amount: int, credit_amount: int) -> bool:
	if not can_spend_cost(faction, resource_id, resource_amount, credit_amount):
		return false
	if not spend_faction_resource(faction, resource_id, resource_amount):
		return false
	return spend_faction_credits(faction, credit_amount)


func get_faction_resource(faction: StringName, resource_id: StringName) -> int:
	if not _owner.faction_vaults.has(faction):
		return 0
	return int(_owner.faction_vaults[faction].get(resource_id, 0))


func get_faction_vault_snapshot(faction: StringName) -> Dictionary:
	if not _owner.faction_vaults.has(faction):
		return {}
	return (_owner.faction_vaults[faction] as Dictionary).duplicate()


func add_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> int:
	if amount <= 0 or String(faction).is_empty() or not is_valid_resource_id(resource_id):
		return get_faction_resource(faction, resource_id)
	if not _owner.faction_vaults.has(faction):
		_owner.faction_vaults[faction] = {}
	var current: int = get_faction_resource(faction, resource_id)
	var new_val := current + amount
	_owner.faction_vaults[faction][resource_id] = new_val
	_owner.faction_resources_changed.emit(faction, resource_id, new_val)
	return new_val


func can_spend_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> bool:
	if amount <= 0:
		return true
	return get_faction_resource(faction, resource_id) >= amount


func spend_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> bool:
	if amount < 0:
		return false
	if amount == 0:
		return true
	if not can_spend_faction_resource(faction, resource_id, amount):
		return false
	var current: int = get_faction_resource(faction, resource_id)
	var new_val := current - amount
	_owner.faction_vaults[faction][resource_id] = new_val
	_owner.faction_resources_changed.emit(faction, resource_id, new_val)
	return true


func set_planet_resource(planet_id: StringName, resource_id: StringName) -> void:
	if String(planet_id).is_empty() or not is_valid_resource_id(resource_id):
		return
	_owner.planet_resources[planet_id] = resource_id


func resource_of(planet_id: StringName) -> StringName:
	return _owner.planet_resources.get(planet_id, &"") as StringName


func resource_snapshot() -> Dictionary:
	return _owner.planet_resources.duplicate()


func available_workers(planet_id: StringName, total_workers: int) -> int:
	var reserved := 0
	if _owner.worker_reservations.has(planet_id):
		for amount in (_owner.worker_reservations[planet_id] as Dictionary).values():
			reserved += int(amount)
	return maxi(0, total_workers - reserved)


func reserve_workers(planet_id: StringName, job_id: StringName, amount: int, total_workers: int) -> bool:
	if amount <= 0:
		return true
	if available_workers(planet_id, total_workers) < amount:
		return false
	if not _owner.worker_reservations.has(planet_id):
		_owner.worker_reservations[planet_id] = {}
	var jobs: Dictionary = _owner.worker_reservations[planet_id]
	jobs[job_id] = int(jobs.get(job_id, 0)) + amount
	_owner.workers_reserved.emit(planet_id, job_id, amount)
	return true


func release_workers(planet_id: StringName, job_id: StringName) -> int:
	if not _owner.worker_reservations.has(planet_id):
		return 0
	var jobs: Dictionary = _owner.worker_reservations[planet_id]
	var amount: int = int(jobs.get(job_id, 0))
	jobs.erase(job_id)
	if jobs.is_empty():
		_owner.worker_reservations.erase(planet_id)
	if amount > 0:
		_owner.workers_released.emit(planet_id, job_id, amount)
	return amount


# --- LOCAL VAULTS (per-planet) ---

func local_vault(planet_id: StringName) -> Dictionary:
	if not _owner.local_vaults.has(planet_id):
		_owner.local_vaults[planet_id] = GameState.DEFAULT_RESOURCE_POOL.empty_vault()
	return _owner.local_vaults[planet_id]


func get_local_resource(planet_id: StringName, resource_id: StringName) -> int:
	return int(local_vault(planet_id).get(resource_id, 0))


func add_local_resource(planet_id: StringName, resource_id: StringName, amount: int) -> int:
	if amount <= 0 or String(planet_id).is_empty() or not is_valid_resource_id(resource_id):
		return get_local_resource(planet_id, resource_id)
	var vault := local_vault(planet_id)
	var new_val := get_local_resource(planet_id, resource_id) + amount
	vault[resource_id] = new_val
	_owner.local_vaults[planet_id] = vault
	_owner.local_resources_changed.emit(planet_id, resource_id, new_val)
	return new_val


func spend_local_resource(planet_id: StringName, resource_id: StringName, amount: int) -> bool:
	if amount < 0:
		return false
	if amount == 0:
		return true
	if get_local_resource(planet_id, resource_id) < amount:
		return false
	var vault := local_vault(planet_id)
	var new_val := get_local_resource(planet_id, resource_id) - amount
	vault[resource_id] = new_val
	_owner.local_vaults[planet_id] = vault
	_owner.local_resources_changed.emit(planet_id, resource_id, new_val)
	return true


func transfer_resources(from_planet: StringName, to_planet: StringName, resource_id: StringName, amount: int) -> bool:
	if amount <= 0 or from_planet == to_planet:
		return false
	if not spend_local_resource(from_planet, resource_id, amount):
		return false
	add_local_resource(to_planet, resource_id, amount)
	_owner.resource_transferred.emit(from_planet, to_planet, resource_id, amount)
	return true


## Seeds a small deterministic starting stock of each planet's own resource.
func seed_local_resources(planet_ids: Array, pool: ResourcePool = null, seed_value: int = 0) -> void:
	var effective_pool: ResourcePool = pool if pool != null else GameState.DEFAULT_RESOURCE_POOL
	if effective_pool == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for planet_id_value in planet_ids:
		var planet_id: StringName = planet_id_value as StringName
		if _owner._local_seeded_planets.has(planet_id):
			continue
		var res_id: StringName = resource_of(planet_id)
		if String(res_id).is_empty():
			continue
		var vault := local_vault(planet_id)
		var starting := maxi(1, rng.randi_range(2, 8))
		vault[res_id] = int(vault.get(res_id, 0)) + starting
		_owner.local_vaults[planet_id] = vault
		_owner._local_seeded_planets[planet_id] = true


# Local copy of GameState.is_valid_resource — calling the static via the autoload
# instance triggers a STATIC_CALLED_ON_INSTANCE warning under Godot's parser.
func is_valid_resource_id(resource_id: StringName) -> bool:
	return resource_id == GameState.RES_ENERGY or resource_id == GameState.RES_BIOMASS or resource_id == GameState.RES_RARE or resource_id == GameState.RES_MATERIAL or resource_id == GameState.RES_VOLATILE
