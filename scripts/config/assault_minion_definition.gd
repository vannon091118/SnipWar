class_name AssaultMinionDefinition
extends RefCounted

## Adapter mapping a ship loadout to a tower-defense minion. Hull contributes
## HP, weapons contribute DPS; speed comes from the conquest config (ships do
## not carry a drive speed stat in the current snapshot model).

var hp: float = 10.0
var dps: float = 2.0
var speed: float = 60.0
var source_ship_id: StringName = &""

static func from_ship(assembly: ShipAssembly, catalog: ShipPartCatalog, base_hp: float = 10.0, base_dps: float = 2.0, base_speed: float = 60.0) -> AssaultMinionDefinition:
	var minion := AssaultMinionDefinition.new()
	if assembly == null:
		minion.hp = base_hp
		minion.dps = base_dps
		minion.speed = base_speed
		return minion
	minion.source_ship_id = assembly.ship_id if assembly.ship_id != null else &""
	var stats := FleetSnapshot.calculate_ship_stats(assembly, catalog)
	minion.hp = maxf(1.0, float(stats.get("hp", base_hp)))
	minion.dps = maxf(0.0, float(stats.get("dps", base_dps)))
	minion.speed = maxf(1.0, float(stats.get("speed", base_speed)))
	return minion
