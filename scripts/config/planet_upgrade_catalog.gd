@tool
class_name PlanetUpgradeCatalog
extends Resource

@export var upgrades: Array[PlanetUpgradeDefinition] = []

func resolve(upgrade_id: StringName) -> PlanetUpgradeDefinition:
	for upgrade in upgrades:
		if upgrade != null and upgrade.id == upgrade_id:
			return upgrade
	return null

func get_upgrades_for_branch(branch: StringName) -> Array[PlanetUpgradeDefinition]:
	var result: Array[PlanetUpgradeDefinition] = []
	for upgrade in upgrades:
		if upgrade != null and upgrade.branch == branch:
			result.append(upgrade)
	return result

func can_unlock(current_upgrades: Array, upgrade_id: StringName) -> bool:
	if current_upgrades.has(upgrade_id):
		return false
	var upgrade := resolve(upgrade_id)
	if upgrade == null:
		return false
	if not String(upgrade.parent_upgrade_id).is_empty() and not current_upgrades.has(upgrade.parent_upgrade_id):
		return false
	if not String(upgrade.exclusive_with).is_empty() and current_upgrades.has(upgrade.exclusive_with):
		return false
	return true

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if upgrades.is_empty():
		errors.append("upgrade catalog is empty")
		return errors
	var ids: Dictionary = {}
	for upgrade in upgrades:
		if upgrade == null:
			errors.append("catalog contains a null upgrade entry")
			continue
		errors.append_array(upgrade.validate())
		if ids.has(upgrade.id):
			errors.append("duplicate upgrade id: %s" % upgrade.id)
		ids[upgrade.id] = true
	for upgrade in upgrades:
		if upgrade == null:
			continue
		if not String(upgrade.parent_upgrade_id).is_empty() and not ids.has(upgrade.parent_upgrade_id):
			errors.append("upgrade %s references unknown parent %s" % [upgrade.id, upgrade.parent_upgrade_id])
		if not String(upgrade.exclusive_with).is_empty() and not ids.has(upgrade.exclusive_with):
			errors.append("upgrade %s references unknown exclusive upgrade %s" % [upgrade.id, upgrade.exclusive_with])
	return errors
