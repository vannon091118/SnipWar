class_name EconomyWorkerFactoryUnit
extends RefCounted

## R-007 (E4b): Verhaltens-Einheit für Worker-Fabriken aus EconomyDomain.
##
## Verantwortlich: has_worker_factory, can_build_worker_factory,
## build_worker_factory, can_build_worker_factory_with_domains,
## build_worker_factory_with_domains.
##
## Kostengating läuft über die Vault-Schicht (_owner.can_spend_cost /
## _owner.spend_cost) — die Fabrik selbst besitzt keinen eigenen Ressourcen-
## State. Der Faktory-Zustand (worker_factories-Dictionary) bleibt auf der
## Fassade; die Einheit mutiert ihn über _owner und feuert
## worker_factory_built über die Fassade (Signal-Identität bleibt).

var _owner: Variant


func _init(owner: Variant) -> void:
	_owner = owner


func has_worker_factory(planet_id: StringName) -> bool:
	return _owner.worker_factories.get(planet_id, false) as bool


func can_build_worker_factory(
	faction: StringName,
	planet_id: StringName,
	has_shipyard: bool,
	first_scan_done: bool,
	has_automation_tech: bool,
	available_slots: int = -1,
	cost_resource: StringName = GameState.RES_MATERIAL,
	cost_amount: int = 5,
	credit_cost: int = 5
) -> bool:
	if faction == GameState.FACTION_NEUTRAL or not _owner.faction_vaults.has(faction) or has_worker_factory(planet_id):
		return false
	if not has_shipyard or not first_scan_done or not has_automation_tech:
		return false
	if available_slots >= 0 and available_slots <= 0:
		return false
	return _owner.can_spend_cost(faction, cost_resource, cost_amount, credit_cost)


func build_worker_factory(
	faction: StringName,
	planet_id: StringName,
	has_shipyard: bool,
	first_scan_done: bool,
	has_automation_tech: bool,
	available_slots: int = -1,
	cost_resource: StringName = GameState.RES_MATERIAL,
	cost_amount: int = 5,
	credit_cost: int = 5
) -> bool:
	if not can_build_worker_factory(faction, planet_id, has_shipyard, first_scan_done, has_automation_tech, available_slots, cost_resource, cost_amount, credit_cost):
		return false
	if not _owner.spend_cost(faction, cost_resource, cost_amount, credit_cost):
		return false
	_owner.worker_factories[planet_id] = true
	_owner.worker_factory_built.emit(planet_id)
	return true


## Domain-ref overload: queries faction + tech requirements via the domain
## objects so GameState.can_build_worker_factory() becomes a one-liner.
func can_build_worker_factory_with_domains(
	planet_id: StringName,
	faction_domain: FactionDomain,
	tech_domain: TechDomain,
	cost_resource: StringName = GameState.RES_MATERIAL,
	cost_amount: int = 5,
	credit_cost: int = 5
) -> bool:
	var faction: StringName = faction_domain.faction_of(planet_id)
	return can_build_worker_factory(
		faction,
		planet_id,
		_owner.has_planet_upgrade(planet_id, &"shipyard"),
		faction_domain.has_scanned_planet(faction),
		tech_domain.has_technology(faction, GameState.TECH_WORKER_AUTOMATION),
		-1,
		cost_resource,
		cost_amount,
		credit_cost
	)


## Domain-ref overload: same as can_build_worker_factory_with_domains but also
## executes the build so GameState.build_worker_factory() becomes a one-liner.
func build_worker_factory_with_domains(
	planet_id: StringName,
	faction_domain: FactionDomain,
	tech_domain: TechDomain,
	cost_resource: StringName = GameState.RES_MATERIAL,
	cost_amount: int = 5,
	credit_cost: int = 5
) -> bool:
	var faction: StringName = faction_domain.faction_of(planet_id)
	return build_worker_factory(
		faction,
		planet_id,
		_owner.has_planet_upgrade(planet_id, &"shipyard"),
		faction_domain.has_scanned_planet(faction),
		tech_domain.has_technology(faction, GameState.TECH_WORKER_AUTOMATION),
		-1,
		cost_resource,
		cost_amount,
		credit_cost
	)