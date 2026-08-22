@tool
class_name SectorFlavorCatalog
extends Resource

@export var flavors: Array[SectorFlavor] = []

func resolve(id: StringName) -> SectorFlavor:
	for flavor in flavors:
		if flavor != null and flavor.id == id:
			return flavor
	return null

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids: Dictionary = {}
	for flavor in flavors:
		if flavor == null:
			errors.append("sector flavor catalog contains a null flavor")
			continue
		for flavor_error in flavor.validate():
			errors.append("sector flavor %s: %s" % [flavor.id, flavor_error])
		if ids.has(flavor.id):
			errors.append("sector flavor ids must be unique")
		ids[flavor.id] = true
	return errors
