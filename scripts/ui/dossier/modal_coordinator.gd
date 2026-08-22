class_name ModalCoordinator
extends Node

## Owns the full-screen PaperDossier and coordinates world interaction:
## opening a view dims/freezes the world (camera input blocked) and closing
## restores it. Kept as a scene-owned node (not an autoload) so it lives and
## dies with the PlanetNetwork that wires it.

signal dossier_opened()
signal dossier_closed()

var _dossier: PaperDossier
var _map_camera: MapCamera

func setup(map_camera: MapCamera, theme_config: UIThemeConfig = null) -> void:
	_map_camera = map_camera
	_dossier = PaperDossier.new()
	_dossier.name = "PaperDossier"
	add_child(_dossier)
	_dossier.setup(theme_config)
	_dossier.closed.connect(_on_dossier_closed)

func is_open() -> bool:
	return _dossier != null and is_instance_valid(_dossier) and _dossier.is_open()

func open_view(content: Control, title: String) -> void:
	if _dossier == null or not is_instance_valid(_dossier):
		return
	_dossier.open_view(content, title)
	_set_camera_blocked(true)
	dossier_opened.emit()

func close() -> void:
	if _dossier != null and is_instance_valid(_dossier):
		_dossier.close()

func _on_dossier_closed() -> void:
	_set_camera_blocked(false)
	dossier_closed.emit()

func _set_camera_blocked(blocked: bool) -> void:
	if _map_camera != null and is_instance_valid(_map_camera) and _map_camera.has_method("set_input_blocked"):
		_map_camera.set_input_blocked(blocked)
