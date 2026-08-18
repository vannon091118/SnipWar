extends SceneTree

var _observed_planet: Node2D
var _observed_state := -1
var _observed_amount := -1

func _init() -> void:
	var scene: PackedScene = preload("res://scenes/backgrounds/starfield_background.tscn")
	var background: Node = scene.instantiate()
	root.add_child(background)
	await process_frame
	await process_frame

	var field: Node = background.get_node("PlanetField")
	var network: Node = field.get_node("PlanetNetwork")
	var manager: Node = field.get_node("WorkerManager")
	var ocean: Node = field.get_node("Ocean")
	var desert: Node = field.get_node("Desert")
	var ember: Node = field.get_node("Ember")
	var ocean_timer: Timer = _find_timer(ocean)
	var desert_timer: Timer = _find_timer(desert)
	var ember_timer: Timer = _find_timer(ember)

	if not _check(get_nodes_in_group("planets").size() == 10, "planet group count is wrong"):
		return
	if not _check(ocean_timer.wait_time == 5.0 and desert_timer.wait_time == 7.0 and ember_timer.wait_time == 10.0, "spawn intervals are wrong"):
		return

	_observed_planet = ocean
	ocean.workers_spawn_requested.connect(_capture_spawn)
	ocean.call("_on_spawn_timer")
	desert.call("_on_spawn_timer")
	ember.call("_on_spawn_timer")
	await process_frame
	if not _check(_observed_state == 1 and _observed_amount == 3 and int(ocean.worker_state) == 0, "planet state transition is wrong"):
		return
	if not _check(ocean.worker_count == 3 and desert.worker_count == 2 and ember.worker_count == 1, "planet worker counts are wrong"):
		return

	var worker_script: Script = preload("res://scripts/objects/workers/worker.gd")
	var workers: Array[Node] = []
	for child in manager.get_children():
		if child.get_script() == worker_script:
			workers.append(child)
	if not _check(workers.size() == 6, "worker spawn totals are wrong"):
		return
	var count_labels: Dictionary = network.get("_count_labels")
	var ocean_count_label: Label = count_labels[ocean]
	if not _check(ocean_count_label.text == "Ocean: 3", "planet tab count is not live"):
		return
	var worker_position: Vector2 = workers[0].global_position
	await create_timer(0.2).timeout
	if not _check(workers[0].global_position == worker_position, "worker moves autonomously"):
		return
	workers[0].queue_free()
	await process_frame
	if not _check(ocean.worker_count == 2 and ocean_count_label.text == "Ocean: 2", "worker removal did not update planet count"):
		return

	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	ocean.call("_on_click_area_input_event", null, event, 0)
	await process_frame
	var panel: PanelContainer = network.get("_panel")
	var destination_option: OptionButton = network.get("_destination_option")
	var neighbors: Array[Node2D] = network.get_neighbors(ocean)
	if not _check(panel.visible and destination_option.item_count == 9 and count_labels.size() == 10 and not neighbors.is_empty(), "planet tab or neighbors are missing"):
		return
	network.call("_toggle_panel")
	if not _check(not panel.visible, "planet tab did not close"):
		return
	network.call("_toggle_panel")
	if not _check(panel.visible, "planet tab did not reopen"):
		return
	var line_phase: float = network.get("_line_phase")
	await create_timer(0.2).timeout
	if not _check(float(network.get("_line_phase")) != line_phase, "neighbor line animation is inactive"):
		return
	var destination: Node2D = neighbors[0]
	var destination_index := -1
	for index in destination_option.item_count:
		if destination_option.get_item_text(index) == destination.name:
			destination_index = index
			break
	if not _check(destination_index >= 0, "destination is missing from planet tab"):
		return
	network.call("_on_destination_selected", destination_index)
	if not _check(network.get_destination(ocean) == destination and panel.visible, "destination route was not stored"):
		return
	manager.call("_spawn_workers", ocean, 1)
	await process_frame
	var newest_worker: Node
	for child in manager.get_children():
		if child.get_script() == worker_script:
			newest_worker = child
	if not _check(newest_worker.destination_planet == destination, "worker destination was not assigned"):
		return

	var meteor_field: Node = background.get_node("MeteorField")
	var meteor_positions: Array[Vector2] = []
	for meteor in meteor_field.get_children():
		meteor_positions.append(meteor.position)
		var pixels: float = meteor.texture.get_width() * meteor.scale.x
		if not _check(pixels >= 4.0 and pixels <= 10.0, "%s pixel size is invalid" % meteor.name):
			return
	await create_timer(0.2).timeout
	if not _check(meteor_field.get_child(0).position != meteor_positions[0], "meteor movement is inactive"):
		return
	var respawn_meteor: Sprite2D = meteor_field.get_child(0)
	respawn_meteor.position = Vector2(-100.0, 270.0)
	await create_timer(0.05).timeout
	if not _check(respawn_meteor.position != Vector2(-100.0, 270.0), "meteor respawn is inactive"):
		return

	var orbit: Node = field.get_node("ToxicOrbitAsteroid")
	var orbit_position: Vector2 = orbit.global_position
	await create_timer(0.2).timeout
	if not _check(orbit.global_position != orbit_position, "Toxic orbit is inactive"):
		return

	print("PASS: SnipWar preflight")
	quit()

func _capture_spawn(planet: Node2D, amount: int) -> void:
	if planet == _observed_planet:
		_observed_state = int(planet.worker_state)
		_observed_amount = amount

func _find_timer(planet: Node) -> Timer:
	for child in planet.get_children():
		if child is Timer:
			return child
	return null

func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("FAIL: " + message)
	quit(1)
	return false
