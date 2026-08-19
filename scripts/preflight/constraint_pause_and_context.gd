class_name PreflightConstraintPauseAndContext
extends RefCounted

## Pause/resume tree control, planet context quick actions and drag-drop presets.

func constraint_name() -> String:
	return "pause_and_context"


func run(ctx: PreflightContext) -> bool:
	var background: Node = ctx.background
	var network: Node = ctx.network
	var field: Node = ctx.field
	var game_state: Node = ctx.game_state
	if not ctx.check(InputMap.has_action(&"ui_cancel") and InputMap.has_action(&"ui_accept") and InputMap.has_action(&"pause"), "InputMap is missing ui_cancel/ui_accept/pause actions"):
		return false
	var esc_check := InputEventKey.new()
	esc_check.keycode = KEY_ESCAPE
	esc_check.pressed = true
	if not ctx.check(esc_check.is_action_pressed(&"ui_cancel"), "ui_cancel does not resolve to Escape"):
		return false
	var space_check := InputEventKey.new()
	space_check.keycode = KEY_SPACE
	space_check.pressed = true
	if not ctx.check(space_check.is_action_pressed(&"pause"), "pause does not resolve to Space"):
		return false
	var pause_menu: Node = background.get_node_or_null("PauseMenu")
	if not ctx.check(pause_menu != null, "pause menu is missing from the background scene"):
		return false
	if not ctx.check(pause_menu.has_method("pause") and pause_menu.has_method("resume"), "pause menu is missing pause/resume controls"):
		return false
	pause_menu.call("pause")
	await ctx.await_frame()
	if not ctx.check(game_state.get_tree().paused, "pause menu did not pause the tree"):
		pause_menu.call("resume")
		return false
	pause_menu.call("resume")
	await ctx.await_frame()
	if not ctx.check(not game_state.get_tree().paused, "pause menu did not resume the tree"):
		return false
	var ui: PlanetNetworkUI = network.get_ui()
	var context_menu: PopupMenu = ui.get_node_or_null("PlanetContextMenu") as PopupMenu
	if not ctx.check(context_menu != null, "planet context menu is missing its quick actions"):
		return false
	var source: Planet = ctx.find_planet_with_size(field, &"xl") as Planet
	if not ctx.check(source != null, "no planet available for context menu test"):
		return false
	# Slice 2 builds the menu lazily on first right-click. Force a single
	# rebuild pass so the contract check covers the canonical item count.
	network.call("_build_context_menu_for", source)
	if not ctx.check(context_menu.item_count == network.ACTION_COUNT, "planet context menu is missing its quick actions (got %d, expected %d)" % [context_menu.item_count, network.ACTION_COUNT]):
		return false
	# Reset transient state from earlier constraints so this test starts from
	# a deterministic baseline (left-click → primary = source).
	var selection_service: SelectionService = network.call("get_selection_service") if network.has_method("get_selection_service") else null
	if selection_service != null:
		selection_service.clear()
	network.set("_context_active_planet", null)
	# Switch ownership so the source is the player's own XL planet — this
	# makes ATTACK/SAMMELN/KOLONISIEREN enabled against scanned neutral
	# neighbours without breaking the rest of the constraint order.
	var original_source_faction: StringName = source.get_faction()
	game_state.set_faction(source.planet_id, GameState.FACTION_PLAYER)
	await ctx.await_frame()
	var neutral_neighbor: Planet = null
	for neighbor_value in network.get_neighbors(source):
		var neighbor: Planet = neighbor_value as Planet
		if neighbor != null and neighbor.get_faction() == GameState.FACTION_NEUTRAL and not game_state.is_known(neighbor.planet_id, GameState.FACTION_PLAYER):
			neutral_neighbor = neighbor
			break
	# If the preceding discovery constraints exhausted this source's neutral
	# neighbours, fall back to any unknown neutral planet and keep the target
	# relation explicit in the assertion below.
	if neutral_neighbor == null:
		for child in field.get_children():
			var candidate: Planet = child as Planet
			if candidate != null and candidate.get_faction() == GameState.FACTION_NEUTRAL and not game_state.is_known(candidate.planet_id, GameState.FACTION_PLAYER):
				neutral_neighbor = candidate
				break
	if not ctx.check(neutral_neighbor != null, "no neutral neighbour available for context-menu COLLECT unlock"):
		return false
	# Pretend the neighbour was scanned so COLLECT/COLONIZE are unlocked.
	# `scan_planet` rejects re-scans of already-known planets, so call it
	# first; it handles the implicit discover step itself.
	var original_neighbor_faction: StringName = neutral_neighbor.get_faction()
	game_state.set_faction(neutral_neighbor.planet_id, GameState.FACTION_NEUTRAL)
	var scanned: bool = game_state.scan_planet(GameState.FACTION_PLAYER, neutral_neighbor.planet_id)
	if not ctx.check(scanned, "test could not arm a scanned neutral neighbour for COLLECT gating"):
		return false
	# Promote the player's XL to primary first via the left-click flow.
	var left_click := InputEventMouseButton.new()
	left_click.button_index = MOUSE_BUTTON_LEFT
	left_click.pressed = true
	source.call("_on_click_area_input_event", null, left_click, 0)
	await ctx.await_frame()
	# Now right-click the NEUTRAL neighbour (target ≠ primary).
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	neutral_neighbor.call("_on_click_area_input_event", null, right_click, 0)
	await ctx.await_frame()
	# Probe the gate state so the failure message is actionable.
	network.call("_on_context_action", network.ACTION_COLLECT)
	await ctx.await_frame()
	if not ctx.check(ui.selected_mission_type() == GameState.MISSION_COLLECT, "context menu did not preselect the collect mission"):
		return false
	game_state.set_faction(source.planet_id, original_source_faction)
	game_state.set_faction(neutral_neighbor.planet_id, original_neighbor_faction)
	await ctx.await_frame()
	ui.set_mission_type(GameState.MISSION_MILITARY)
	if not ctx.check(ui.selected_mission_type() == GameState.MISSION_MILITARY, "set_mission_type did not restore the military mission"):
		return false
	# Drag-drop: the camera resolves planets and the network presets source + destination.
	var camera: Node2D = ctx.first_node_in_group("map_camera") as Node2D
	if not ctx.check(camera != null and camera.has_signal("planet_drag_dropped"), "map camera is missing its planet drag signal"):
		return false
	var drag_destination: Planet = null
	for child in field.get_children():
		if child is Planet and child != source:
			drag_destination = child as Planet
			break
	if not ctx.check(drag_destination != null, "no second planet available for drag-drop test"):
		return false
	network.call("_on_planet_drag_dropped", source, drag_destination)
	await ctx.await_frame()
	if not ctx.check(network.get("_active_planet") == source and network.get_destination(source) == drag_destination, "drag-drop did not select the source and set the destination"):
		return false
	return true
