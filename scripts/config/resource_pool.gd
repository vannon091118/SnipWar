@tool
class_name ResourcePool
extends Resource

@export var resources: Array[GameResource] = []

func resource_for(resource_id: StringName) -> GameResource:
	for resource in resources:
		if resource != null and resource.id == resource_id:
			return resource
	return null

## Empty vault dictionary keyed by every resource id in this pool (used for
## per-planet local vaults).
func empty_vault() -> Dictionary:
	var vault: Dictionary = {}
	for resource in resources:
		if resource != null and not String(resource.id).is_empty():
			vault[resource.id] = 0
	return vault

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if resources.is_empty():
		errors.append("resource pool is empty")
	var ids: Dictionary = {}
	for resource in resources:
		if resource == null:
			errors.append("resource pool contains a null resource")
			continue
		for resource_error in resource.validate():
			errors.append("resource %s: %s" % [resource.id, resource_error])
		if ids.has(resource.id):
			errors.append("resource ids must be unique")
		ids[resource.id] = true
	if resources.size() < 2:
		errors.append("resource pool needs at least two resources for distinct homeworlds")
	return errors
