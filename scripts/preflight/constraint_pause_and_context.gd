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
	# Choose the first stable graph edge by planet id, not by size profile or
	# layout position. The default scenario randomizes both, while adjacency
	# itself is the only relationship this context-menu test needs.
	var ordered_planets: Array[Planet] = []
	for child in field.get_children():
		var candidate_planet: Planet = child as Planet
		if candidate_planet != null:
			ordered_planets.append(candidate_planet)
	ordered_planets.sort_custom(func(a, b): return String(a.planet_id) < String(b.planet_id))
	var source: Planet = null
	var neutral_neighbor: Planet = null
	for candidate_source in ordered_planets:
		var ordered_neighbors: Array[Node2D] = network.get_neighbors(candidate_source)
		ordered_neighbors.sort_custom(func(a, b): return String((a as Planet).planet_id) < String((b as Planet).planet_id))
		for neighbor_value in ordered_neighbors:
			var candidate_neighbor: Planet = neighbor_value as Planet
			if candidate_neighbor != null and candidate_neighbor != candidate_source:
				source = candidate_source
				neutral_neighbor = candidate_neighbor
				break
		if source != null:
			break
	if not ctx.check(source != null and neutral_neighbor != null, "no graph edge available for context menu test"):
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
	# Snapshot discovery state because earlier constraints may have scanned this
	# edge already. The test owns a temporary player/neutral edge and restores
	# the shared GameState before continuing with drag-drop assertions.
	var faction_domain: FactionDomain = game_state.get("faction_domain") as FactionDomain
	var known_snapshot: Dictionary = faction_domain.known_planets.duplicate(true)
	var scanned_snapshot: Dictionary = {}
	for faction_key in faction_domain.scanned_planets:
		var typed_scans: Array[StringName] = []
		for scanned_id in faction_domain.scanned_planets[faction_key] as Array:
			typed_scans.append(scanned_id as StringName)
		scanned_snapshot[faction_key] = typed_scans
	var scan_intel_snapshot: Dictionary = faction_domain.scan_intel.duplicate(true)
	var original_source_faction: StringName = source.get_faction()
	var original_neighbor_faction: StringName = neutral_neighbor.get_faction()
	game_state.set_faction(source.planet_id, GameState.FACTION_PLAYER)
	game_state.set_faction(neutral_neighbor.planet_id, GameState.FACTION_NEUTRAL)
	var player_known: Dictionary = faction_domain.known_planets.get(GameState.FACTION_PLAYER, {}) as Dictionary
	player_known.erase(neutral_neighbor.planet_id)
	faction_domain.known_planets[GameState.FACTION_PLAYER] = player_known
	var player_scanned: Array[StringName] = []
	for scanned_id in faction_domain.scanned_planets.get(GameState.FACTION_PLAYER, []) as Array:
		player_scanned.append(scanned_id as StringName)
	player_scanned.erase(neutral_neighbor.planet_id)
	faction_domain.scanned_planets[GameState.FACTION_PLAYER] = player_scanned
	var player_scan_intel: Dictionary = faction_domain.scan_intel.get(GameState.FACTION_PLAYER, {}) as Dictionary
	player_scan_intel.erase(neutral_neighbor.planet_id)
	faction_domain.scan_intel[GameState.FACTION_PLAYER] = player_scan_intel
	await ctx.await_frame()
	# Arm the temporary neutral neighbour so COLLECT/COLONIZE are unlocked.
	var scanned: bool = game_state.scan_planet(GameState.FACTION_PLAYER, neutral_neighbor.planet_id)
	if not scanned:
		_restore_context_state(game_state, faction_domain, source, original_source_faction, neutral_neighbor, original_neighbor_faction, known_snapshot, scanned_snapshot, scan_intel_snapshot)
		return ctx.check(false, "test could not arm a scanned neutral neighbour for COLLECT gating")
	# Promote the player's source first via the left-click flow.
	var left_click := InputEventMouseButton.new()
	left_click.button_index = MOUSE_BUTTON_LEFT
	left_click.pressed = true
	source.call("_on_click_area_input_event", null, left_click, 0)
	await ctx.await_frame()
	# Now right-click the deterministic neutral neighbour (target ≠ primary).
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	neutral_neighbor.call("_on_click_area_input_event", null, right_click, 0)
	await ctx.await_frame()
	# Probe the gate state so the failure message is actionable.
	network.call("_on_context_action", network.ACTION_COLLECT)
	await ctx.await_frame()
	var collect_selected: bool = ui.selected_mission_type() == GameState.MISSION_COLLECT
	_restore_context_state(game_state, faction_domain, source, original_source_faction, neutral_neighbor, original_neighbor_faction, known_snapshot, scanned_snapshot, scan_intel_snapshot)
	await ctx.await_frame()
	if not ctx.check(collect_selected, "context menu did not preselect the collect mission"):
		return false
	ui.set_mission_type(GameState.MISSION_MILITARY)
	if not ctx.check(ui.selected_mission_type() == GameState.MISSION_MILITARY, "set_mission_type did not restore the military mission"):
		return false
	# Drag-drop: the camera resolves planets and the network presets source + destination.
	var camera: MapCamera = background.get_node_or_null("MapCamera") as MapCamera
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

func _restore_context_state(
	game_state: Node,
	faction_domain: FactionDomain,
	source: Planet,
	source_faction: StringName,
	target: Planet,
	target_faction: StringName,
	known_snapshot: Dictionary,
	scanned_snapshot: Dictionary,
	scan_intel_snapshot: Dictionary
) -> void:
	game_state.set_faction(source.planet_id, source_faction)
	game_state.set_faction(target.planet_id, target_faction)
	faction_domain.known_planets = known_snapshot
	faction_domain.scanned_planets = scanned_snapshot
	faction_domain.scan_intel = scan_intel_snapshot
