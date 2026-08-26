class_name PreflightConstraintCameraAndInput
extends RefCounted

## Map camera initialization/bounds clamp and touch selection handoff.

func constraint_name() -> String:
	return "camera_and_input"

func requires_scene() -> bool:
	return true


func run(ctx: PreflightContext) -> bool:
	var background: Node = ctx.background
	var field: Node = ctx.field
	var world_config: WorldConfig = ctx.world_config
	var camera: Camera2D = background.get_node_or_null("MapCamera") as Camera2D
	if not ctx.check(camera != null, "map camera is missing from the background scene"):
		return false

	# ── WASD+Edge-scroll input actions ─────────────────────────────
	if not ctx.check(InputMap.has_action(&"camera_pan_up") and InputMap.has_action(&"camera_pan_down") and InputMap.has_action(&"camera_pan_left") and InputMap.has_action(&"camera_pan_right"), "WASD camera pan actions are missing from InputMap"):
		return false
	if not ctx.check(InputMap.has_action(&"camera_home"), "camera_home action is missing from InputMap"):
		return false

	# ── Camera export parameters ────────────────────────────────────
	var edge_margin: float = float(camera.get("edge_scroll_margin"))
	var edge_speed: float = float(camera.get("edge_scroll_speed"))
	var kb_speed: float = float(camera.get("keyboard_pan_speed"))
	if not ctx.check(edge_margin > 0.0 and edge_speed > 0.0 and kb_speed > 0.0, "camera edge-scroll and WASD exports are not configured"):
		return false
	if not ctx.check(camera.has_method("_center_on_homeworld"), "map camera is missing its homeworld centering handler"):
		return false

	# ── Basic camera init + bounds ──────────────────────────────────
	if not ctx.check(ctx.get_root().get_viewport().get_camera_2d() == camera, "map camera is not the active 2D camera"):
		return false
	if not ctx.check(camera.zoom == Vector2.ONE and camera.position.distance_to(world_config.design_size * 0.5) <= 0.01, "map camera did not initialize to the map center"):
		return false
	# Finite maps clamp to their authored rectangle. Infinite maps deliberately
	# allow exploration beyond the currently active cache and expand by FoV.
	camera.position = Vector2.ZERO
	camera.call("_clamp_position")
	if world_config.is_infinite_world():
		if not ctx.check(camera.position == Vector2.ZERO, "infinite-world camera should allow exploration outside the current cache"):
			return false
	else:
		if not ctx.check(camera.position.distance_to(world_config.design_size * 0.5) <= 0.01, "map camera bounds clamp did not constrain the position"):
			return false
	camera.position = world_config.design_size * 0.5
	camera.call("_sync_infinite_world")
	var transformer: TransformerConfig = preload("res://resources/config/transformer_default.tres")
	if not ctx.check(transformer.selection_ring_margin > 0.0 and transformer.selection_ring_width > 0.0 and transformer.selection_ring_color.a > 0.0, "selection ring config is not tuned"):
		return false
	var source: Planet = ctx.find_planet_with_size(field, &"xl") as Planet
	if not ctx.check(source != null, "no planet available for touch selection test"):
		return false
	var touch_event := InputEventScreenTouch.new()
	touch_event.index = 0
	touch_event.position = source.global_position
	touch_event.pressed = true
	source.call("_on_click_area_input_event", null, touch_event, 0)
	touch_event.pressed = false
	source.call("_on_click_area_input_event", null, touch_event, 0)
	await ctx.await_frame()
	if not ctx.check(source.is_selected(), "touch tap did not select the planet"):
		return false
	var second_planet: Planet = null
	for child in field.get_children():
		if child is Planet and child != source:
			second_planet = child as Planet
			break
	if not ctx.check(second_planet != null, "no second planet available for selection handoff"):
		return false
	var second_touch := InputEventScreenTouch.new()
	second_touch.index = 0
	second_touch.position = second_planet.global_position
	second_touch.pressed = true
	second_planet.call("_on_click_area_input_event", null, second_touch, 0)
	second_touch.pressed = false
	second_planet.call("_on_click_area_input_event", null, second_touch, 0)
	await ctx.await_frame()
	if not ctx.check(not source.is_selected() and second_planet.is_selected(), "selecting another planet did not move the selection ring"):
		return false
	return true
