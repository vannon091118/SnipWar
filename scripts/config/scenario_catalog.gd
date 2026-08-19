@tool
class_name ScenarioCatalog
extends Resource

@export var default_scenario_id: StringName = &"default"
@export var scenarios: Array[ScenarioDefinition] = []

func definition_for(scenario_id: StringName) -> ScenarioDefinition:
	for scenario in scenarios:
		if scenario != null and scenario.id == scenario_id:
			return scenario
	return null

func resolve(requested_id: StringName) -> ScenarioDefinition:
	var resolved_id: StringName = requested_id
	if String(resolved_id).is_empty():
		resolved_id = default_scenario_id
	var scenario := definition_for(resolved_id)
	if scenario != null:
		return scenario
	return definition_for(default_scenario_id)

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if scenarios.is_empty():
		errors.append("scenario catalog is empty")

	var scenario_ids: Dictionary = {}
	for scenario in scenarios:
		if scenario == null:
			errors.append("scenario catalog contains a null definition")
			continue
		for scenario_error in scenario.validate():
			errors.append("scenario %s: %s" % [scenario.id, scenario_error])
		if scenario_ids.has(scenario.id):
			errors.append("scenario definition ids must be unique")
		scenario_ids[scenario.id] = true
	if not scenario_ids.has(default_scenario_id):
		errors.append("scenario catalog default id is missing")
	return errors
