@tool
class_name PlanetDetailProfile
extends Resource

@export var id: StringName
@export_range(0, 20, 1) var max_details: int = 3
@export var optional_count_range: Vector2i
@export var definitions: Array[PlanetDetailDefinition] = []
@export var guaranteed_detail_ids: Array[StringName] = []
@export var optional_detail_ids: Array[StringName] = []

func definition_for(detail_id: StringName) -> PlanetDetailDefinition:
	for definition in definitions:
		if definition != null and definition.id == detail_id:
			return definition
	return null

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("planet detail profile id is empty")
	if max_details < 0:
		errors.append("planet detail profile max_details cannot be negative")
	if optional_count_range.x < 0 or optional_count_range.y < optional_count_range.x:
		errors.append("planet detail optional_count_range is invalid")

	var definition_ids: Dictionary = {}
	for definition in definitions:
		if definition == null:
			errors.append("planet detail profile contains a null definition")
			continue
		for definition_error in definition.validate():
			errors.append("detail %s: %s" % [definition.id, definition_error])
		if definition_ids.has(definition.id):
			errors.append("planet detail definition ids must be unique")
		definition_ids[definition.id] = true

	var guaranteed_ids: Dictionary = {}
	for detail_id in guaranteed_detail_ids:
		if not definition_ids.has(detail_id):
			errors.append("guaranteed detail %s is not defined" % detail_id)
		if guaranteed_ids.has(detail_id):
			errors.append("guaranteed detail ids must be unique")
		guaranteed_ids[detail_id] = true
	if guaranteed_detail_ids.size() > max_details:
		errors.append("guaranteed details exceed max_details")

	var optional_ids: Dictionary = {}
	for detail_id in optional_detail_ids:
		if not definition_ids.has(detail_id):
			errors.append("optional detail %s is not defined" % detail_id)
		if guaranteed_ids.has(detail_id):
			errors.append("detail %s cannot be both guaranteed and optional" % detail_id)
		if optional_ids.has(detail_id):
			errors.append("optional detail ids must be unique")
		optional_ids[detail_id] = true
	if optional_count_range.y > optional_detail_ids.size():
		errors.append("optional_count_range exceeds optional detail count")
	return errors
