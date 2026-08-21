@tool
class_name PlanetDefinition
extends Resource

@export var planet_id: StringName
@export var display_name: String
@export var planet_role: StringName = &"planet"
@export var faction: StringName = &"neutral"
@export var planet_texture: Texture2D
@export var detail_profile: PlanetDetailProfile
@export var signature_resource: StringName = &""
@export_range(0.0, 1.0, 0.05) var signature_probability: float = 0.75
## When non-null, the planet is rendered from building blocks (base texture +
## tint + decal overlays) instead of the legacy planet_texture path. Procedural
## planets from chunk generation set this; catalog planets keep planet_texture.
@export var composition_base_texture: Texture2D
@export var composition_tint: Color = Color.WHITE
## Name assigned by the planet name generator during chunk generation. Stored
## in the chunk cache and reused on re-instantiation (never recomputed).
@export var generated_name: String = ""

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(planet_id).is_empty():
		errors.append("planet definition id is empty")
	if display_name.is_empty():
		errors.append("planet definition display_name is empty")
	if planet_texture == null and composition_base_texture == null:
		errors.append("planet definition needs either planet_texture or composition_base_texture")
	if detail_profile == null:
		errors.append("planet definition detail profile is missing")
	if signature_probability < 0.0 or signature_probability > 1.0:
		errors.append("signature_probability must be between 0.0 and 1.0")
	return errors
