class_name AssaultMinionDefinition
extends RefCounted

const DEFAULT_SHIP_PART_CATALOG: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")

## Adapter mapping a ship loadout to a tower-defense minion. Ships carry their
## full module state (per-module HP from the ModuleInfluence model) so towers
## can destroy individual modules — a destroyed drive immobilizes the minion,
## a destroyed weapon silences it. Repair drone modules regenerate module HP
## up to their tier cap (never fully). Worker minions stay flat HP pools.

var id: StringName = &""
var hp: float = 10.0
var max_hp: float = 10.0
var dps: float = 2.0
var speed: float = 60.0
var source_ship_id: StringName = &""
## Module payloads as produced by FleetSnapshot.calculate_ship_stats() plus a
## mutable "hp" / "alive" field per module. Empty for worker minions.
var modules: Array[Dictionary] = []
var repair_rate: float = 0.0
var repair_cap: float = 0.0
var pos: Vector2 = Vector2(-220.0, 0.0)

static func from_ship(assembly: ShipAssembly, catalog: ShipPartCatalog, base_hp: float = 10.0, base_dps: float = 2.0, base_speed: float = 60.0, cfg: ConquestConfig = null) -> AssaultMinionDefinition:
	# The conquest simulator historically passes a null catalog; resolve the
	# default here so repair-drone detection and stat reads always work.
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	var minion := AssaultMinionDefinition.new()
	if assembly == null:
		minion.hp = base_hp
		minion.max_hp = base_hp
		minion.dps = base_dps
		minion.speed = base_speed
		return minion
	minion.source_ship_id = assembly.ship_id if assembly.ship_id != null else &""
	var stats := FleetSnapshot.calculate_ship_stats(assembly, cat)
	minion.hp = maxf(1.0, float(stats.get("hp", base_hp)))
	minion.max_hp = minion.hp
	minion.dps = maxf(0.0, float(stats.get("dps", base_dps)))
	minion.speed = maxf(1.0, float(stats.get("speed", base_speed)))
	for entry in stats.get("modules", []):
		var mod: Dictionary = (entry as Dictionary).duplicate(true)
		mod["hp"] = float(mod.get("max_hp", 0.0))
		mod["alive"] = true
		minion.modules.append(mod)
	var repair_result := ModuleInfluence.repair_profile(_mounted_parts(assembly, cat), cfg)
	minion.repair_rate = float(repair_result.get("rate", 0.0))
	minion.repair_cap = float(repair_result.get("cap", 0.0))
	return minion


## Current HP = sum of alive module HP (flat pool for worker minions).
func current_hp() -> float:
	if modules.is_empty():
		return hp
	var total := 0.0
	for mod in modules:
		if mod.get("alive", false):
			total += float(mod.get("hp", 0.0))
	return total


## Recomputes dps/speed from alive modules; a ship without drives is immobile.
func recompute_stats() -> void:
	if modules.is_empty():
		return
	var dps_total := FleetSnapshot.BASE_DPS
	var speed_mult := 1.0
	var drives_alive := 0
	var hull_alive := false
	for mod in modules:
		if not mod.get("alive", false):
			continue
		var stat: Dictionary = mod.get("stat", {}) as Dictionary
		dps_total += float(stat.get("dps", 0.0))
		speed_mult *= float(stat.get("speed_mult", 1.0))
		var slot_type: StringName = mod.get("slot_type", &"") as StringName
		if slot_type == ShipPartDefinition.SLOT_DRIVE:
			drives_alive += 1
		if slot_type == ShipPartDefinition.SLOT_HULL:
			hull_alive = true
	dps = dps_total
	speed = FleetSnapshot.BASE_SPEED * speed_mult if drives_alive > 0 else 0.0
	hp = current_hp()
	# A minion is dead once its hull module is destroyed (or all modules gone).
	if not hull_alive or hp <= 0.0:
		dps = 0.0
		speed = 0.0


func is_alive() -> bool:
	if modules.is_empty():
		return hp > 0.0
	for mod in modules:
		if mod.get("alive", false) and float(mod.get("hp", 0.0)) > 0.0 and (mod.get("slot_type", &"") as StringName) == ShipPartDefinition.SLOT_HULL:
			return true
	return false


## Regenerates module HP up to the tier cap (never full) and returns the total
## amount healed. Destroyed modules are revived to the cap, keeping the ship
## "functional" without restoring full integrity.
func repair(delta: float, _rng: RandomNumberGenerator = null) -> float:
	if modules.is_empty() or repair_rate <= 0.0 or repair_cap <= 0.0:
		return 0.0
	var healed := 0.0
	for mod in modules:
		var max_module_hp: float = float(mod.get("max_hp", 0.0))
		var cap_hp: float = max_module_hp * repair_cap
		var current: float = float(mod.get("hp", 0.0))
		if current >= cap_hp - 0.01:
			continue
		var amount: float = minf(cap_hp - current, repair_rate * delta)
		mod["hp"] = current + amount
		if not mod.get("alive", false):
			mod["alive"] = true
		healed += amount
	if healed > 0.0:
		recompute_stats()
	return healed


## Applies tower damage to the minion's modules (weighted by influence). A
## destroyed drive immobilizes the minion; a destroyed hull kills it.
func take_damage(amount: float, rng: RandomNumberGenerator) -> float:
	if amount <= 0.0 or not is_alive():
		return 0.0
	if modules.is_empty():
		var applied := minf(amount, hp)
		hp -= applied
		return applied
	var remaining := amount
	var guard := 0
	while remaining > 0.01 and guard < 32 and is_alive():
		guard += 1
		var alive_modules: Array[Dictionary] = []
		for mod in modules:
			if mod.get("alive", false) and float(mod.get("hp", 0.0)) > 0.0:
				alive_modules.append(mod)
		if alive_modules.is_empty():
			break
		var picked: Dictionary = _pick_module(rng, alive_modules)
		var applied := minf(remaining, float(picked.get("hp", 0.0)))
		picked["hp"] = maxf(0.0, float(picked.get("hp", 0.0)) - applied)
		remaining -= applied
		if float(picked.get("hp", 0.0)) <= 0.0 and picked.get("alive", false):
			picked["alive"] = false
			picked["just_destroyed"] = true
	recompute_stats()
	return amount - remaining


## Returns and clears the modules destroyed by the last take_damage() call.
func consume_destroyed_modules() -> Array[Dictionary]:
	var destroyed: Array[Dictionary] = []
	for mod in modules:
		if mod.get("just_destroyed", false):
			mod.erase("just_destroyed")
			destroyed.append(mod)
	return destroyed


static func _pick_module(rng: RandomNumberGenerator, alive_modules: Array[Dictionary]) -> Dictionary:
	var total := 0.0
	for mod in alive_modules:
		total += float(mod.get("weight", 1.0))
	if total <= 0.0:
		return alive_modules[rng.randi_range(0, alive_modules.size() - 1)] as Dictionary
	var roll := rng.randf() * total
	for mod in alive_modules:
		roll -= float(mod.get("weight", 1.0))
		if roll <= 0.0:
			return mod
	return alive_modules.back() as Dictionary


static func _mounted_parts(assembly: ShipAssembly, catalog: ShipPartCatalog) -> Array[ShipPartDefinition]:
	var parts: Array[ShipPartDefinition] = []
	if assembly == null:
		return parts
	for part_id in [assembly.hull_id, assembly.drive_id, assembly.weapon_id, assembly.shield_id, assembly.scanner_id]:
		if not String(part_id).is_empty() and catalog != null:
			var part: ShipPartDefinition = catalog.resolve(part_id)
			if part != null:
				parts.append(part)
	for module_id in assembly.module_ids:
		if catalog != null:
			var mod_part: ShipPartDefinition = catalog.resolve(module_id)
			if mod_part != null:
				parts.append(mod_part)
	return parts
