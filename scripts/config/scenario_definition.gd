@tool
class_name ScenarioDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var map_definition: MapDefinition
@export var transit_config: TransitConfig
@export var ui_theme_config: UIThemeConfig
@export var background_config: BackgroundConfig
@export var meteor_config: MeteorConfig
@export var randomize_layout_seed := true

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("scenario definition id is empty")
	if display_name.is_empty():
		errors.append("scenario definition display_name is empty")
	if map_definition == null:
		errors.append("scenario definition map_definition is missing")
	else:
		for map_error in map_definition.validate():
			errors.append("scenario map: " + map_error)
	if transit_config == null:
		errors.append("scenario definition transit_config is missing")
	else:
		for transit_error in transit_config.validate():
			errors.append("scenario transit: " + transit_error)
	if ui_theme_config == null:
		errors.append("scenario definition ui_theme_config is missing")
	else:
		for ui_error in ui_theme_config.validate():
			errors.append("scenario UI: " + ui_error)
	if background_config == null:
		errors.append("scenario definition background_config is missing")
	else:
		for background_error in background_config.validate():
			errors.append("scenario background: " + background_error)
	if meteor_config == null:
		errors.append("scenario definition meteor_config is missing")
	else:
		for meteor_error in meteor_config.validate():
			errors.append("scenario meteor: " + meteor_error)
	return errors
