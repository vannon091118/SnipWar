class_name ScoutShip
extends Node2D

signal arrived(scout: Node2D)

var destination: Planet
var source_faction: StringName = &""

var _route_path: Array[Vector2] = []
var _duration := 0.0
var _arrived := false
var _hull: Sprite2D
var _scanner: Sprite2D

func configure(destination_planet: Planet, source_faction_name: StringName, route_path: Array[Vector2], duration: float, hull_texture: Texture2D, scanner_texture: Texture2D) -> void:
	destination = destination_planet
	source_faction = source_faction_name
	_route_path = route_path.duplicate() if route_path.size() >= 2 else []
	_duration = maxf(duration, 0.001)
	_ensure_sprites()
	if _hull != null:
		_hull.texture = hull_texture
	if _scanner != null:
		_scanner.texture = scanner_texture

func start_flight() -> void:
	if _route_path.is_empty():
		_arrive()
		return
	global_position = _route_path[0]
	var total_length := _path_distance(_route_path)
	var tween := create_tween()
	for index in range(1, _route_path.size()):
		var segment_length: float = _route_path[index - 1].distance_to(_route_path[index])
		var segment_duration: float = _duration * segment_length / total_length if total_length > 0.0 else 0.0
		tween.tween_property(self, "global_position", _route_path[index], segment_duration).set_trans(Tween.TRANS_LINEAR)
	tween.finished.connect(Callable(self, "_arrive"))

func has_arrived() -> bool:
	return _arrived

func _arrive() -> void:
	if _arrived:
		return
	_arrived = true
	var state: Node = _game_state()
	if state != null and destination != null and is_instance_valid(destination) and not String(source_faction).is_empty():
		state.discover_planet(source_faction, destination.planet_id)
	arrived.emit(self)

func _ensure_sprites() -> void:
	if _hull == null or not is_instance_valid(_hull):
		_hull = get_node_or_null("Hull") as Sprite2D
		if _hull == null:
			_hull = Sprite2D.new()
			_hull.name = "Hull"
			add_child(_hull)
	if _scanner == null or not is_instance_valid(_scanner):
		_scanner = get_node_or_null("Scanner") as Sprite2D
		if _scanner == null:
			_scanner = Sprite2D.new()
			_scanner.name = "Scanner"
			add_child(_scanner)
			_scanner.position = Vector2(7.0, -5.0)
			_scanner.scale = Vector2.ONE * 0.5

func _game_state() -> Node:
	return GameStateAccess.autoload(self)

func _path_distance(path: Array[Vector2]) -> float:
	return PathUtils.distance(path)
