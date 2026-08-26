class_name PreflightConstraintSelectionAndContext
extends RefCounted

## Slice 2 coverage: SelectionService modifier rules, aggregated PlanetPanel
## overview, dynamic context-menu enable/disable matrix and tooltip popover.

func constraint_name() -> String:
	return "selection_and_context"

func requires_scene() -> bool:
	return true


func run(ctx: PreflightContext) -> bool:
	var field: Node = ctx.field
	var network: Node = ctx.network

	# --- SelectionService exists and is wired to PlanetNetwork.
	var service: SelectionService = network.call("get_selection_service") if network.has_method("get_selection_service") else null
	if not ctx.check(service != null, "SelectionService is not attached to PlanetNetwork"):
		return false
	# Earlier constraints may have left primary selection; reset so this
	# module sees a deterministic baseline.
	service.clear()
	if not ctx.check(service.get_selection_count() == 0, "SelectionService starts empty"):
		return false

	# Spin up stand-in planets we can route clicks/touch through.
	var stand_ins := _build_stand_in_planets(field, 3)
	if not ctx.check(stand_ins.size() == 3, "expected 3 stand-in planets (got %d)" % stand_ins.size()):
		return false
	# SelectionService.handle_request does not require the stand-ins to be in
	# the live tree; we add them as virtual participants only via the direct
	# API. Skipping add_child avoids triggering seeded_layout re-layout.

	# --- Plain click sets primary and clears secondary.
	service.handle_request(stand_ins[0], {"shift_pressed": false, "ctrl_pressed": false, "meta_pressed": false, "long_press": false})
	await ctx.await_frame()
	if not ctx.check(service.get_primary() == stand_ins[0] and service.get_selection_count() == 1, "plain click only sets primary"):
		return false

	# --- Shift-click toggles a secondary planet; another shift-click adds a third.
	service.handle_request(stand_ins[1], {"shift_pressed": true, "ctrl_pressed": false, "meta_pressed": false, "long_press": false})
	if not ctx.check(service.get_selection_count() == 2, "shift-click should toggle second planet (got %d)" % service.get_selection_count()):
		return false
	service.handle_request(stand_ins[2], {"ctrl_pressed": true, "shift_pressed": false, "meta_pressed": false, "long_press": false})
	if not ctx.check(service.get_selection_count() == 3, "ctrl-click should add third planet"):
		return false
	if not ctx.check(service.get_primary() == stand_ins[0], "modifier clicks must not change primary"):
		return false

	# --- Removing via shift-click cycles count back down.
	service.handle_request(stand_ins[1], {"shift_pressed": true})
	if not ctx.check(service.get_selection_count() == 2 and not service.is_selected(stand_ins[1]), "shift-click on selected secondary removes it"):
		return false

	# --- A plain click on a new planet resets the secondary set.
	service.handle_request(stand_ins[2], {"shift_pressed": false, "ctrl_pressed": false, "meta_pressed": false, "long_press": false})
	if not ctx.check(service.get_selection_count() == 1 and service.get_primary() == stand_ins[2], "plain click replaces primary and clears secondary"):
		return false

	# --- clear() resets the service.
	service.clear()
	if not ctx.check(service.get_selection_count() == 0, "clear() leaves no planets in selection"):
		return false

	# --- Aggregated overview is visible only when selection > 1.
	var panel: PlanetPanel = network.get_ui().get_panel() as PlanetPanel
	if not ctx.check(panel != null, "PlanetPanel is missing"):
		return false
	var ui: PlanetNetworkUI = network.get_ui() as PlanetNetworkUI
	var dispatch_button: Button = panel.get_send_button()
	if not ctx.check(dispatch_button != null and dispatch_button.get_parent().name == "FooterContent", "dispatch action must live in the fixed footer"):
		return false
	if not ctx.check(panel.get_node_or_null("MarginContainer/PanelLayout/PanelScroll") != null, "planet panel must keep its content scrollable"):
		return false
	if not ctx.check(panel.get_node_or_null("MarginContainer/PanelLayout/PanelScroll/Content/AmountValueLabel") != null, "dispatch amount value label is missing"):
		return false
	panel.set_amount_bounds(Vector2i(1, 3))
	panel.set_selected_count(3)
	var amount_value_label: Label = panel.get_node("MarginContainer/PanelLayout/PanelScroll/Content/AmountValueLabel") as Label
	if not ctx.check(amount_value_label != null and amount_value_label.text == "1 / 3 Einheiten", "dispatch amount label must show selected over available units"):
		return false
	panel.set_dispatch_preview({"summary": "Sende: 1 / 3 Einheiten\\nTransit: 2.0 s"})
	var summary_label: Label = panel.get_node("MarginContainer/PanelLayout/ActionFooter/FooterContent/DispatchSummaryLabel") as Label
	if not ctx.check(summary_label != null and summary_label.text.contains("Sende: 1 / 3"), "dispatch consequence summary is not rendered in the footer"):
		return false
	service.handle_request(stand_ins[0], {})
	service.handle_request(stand_ins[1], {"shift_pressed": true})
	await ctx.await_frame()
	ui.refresh_selection_overview(service.get_selection())
	await ctx.await_frame()
	var focus_overlay: ColorRect = ui.get_node_or_null("PlanetTabUI/MapFocusOverlay") as ColorRect
	if not ctx.check(focus_overlay != null and focus_overlay.visible, "opening the planet panel should lower map emphasis"):
		return false
	if not ctx.check(panel.has_method("set_selection_overview"), "PlanetPanel does not expose set_selection_overview"):
		return false

	# --- Context-menu actions with no planet context: rebuild + sizing.
	network.call("_build_context_menu_for", stand_ins[0])
	if not ctx.check(network.get("_context_menu").item_count >= 7, "context menu should expose at least seven items"):
		return false

	# --- Reason map keeps a human-readable explanation for every disabled action.
	var reasons: Dictionary = network.get("_context_disabled_reasons")
	if not ctx.check(not reasons.is_empty(), "context menu should record at least one disabled-action reason"):
		return false
	for required in [network.ACTION_ATTACK, network.ACTION_COLLECT, network.ACTION_COLONIZE]:
		if not ctx.check(reasons.has(required), "context menu should explain why %s is disabled" % required):
			return false

	# --- ACTION_CLEAR_SELECTION disabled when only one planet is selected.
	service.clear()
	service.handle_request(stand_ins[0], {})
	await ctx.await_frame()
	network.call("_build_context_menu_for", stand_ins[0])
	var cm: PopupMenu = network.get("_context_menu") as PopupMenu
	if not ctx.check(cm != null, "context menu not initialised"):
		return false
	if not ctx.check(cm.is_item_disabled(network.ACTION_CLEAR_SELECTION), "Alles abwählen is disabled with a single planet"):
		return false

	# --- Clear-selection action becomes enabled when multi-select is active.
	service.handle_request(stand_ins[1], {"shift_pressed": true})
	await ctx.await_frame()
	network.call("_build_context_menu_for", stand_ins[0])
	cm = network.get("_context_menu") as PopupMenu
	if not ctx.check(not cm.is_item_disabled(network.ACTION_CLEAR_SELECTION), "Alles abwählen should be enabled with >1 planet"):
		return false
	network.call("_on_clear_selection_requested")
	await ctx.await_frame()
	if not ctx.check(service.get_selection_count() == 0, "UI clear-selection button routes into SelectionService.clear()"):
		return false

	# --- Action tooltip is a SelectionActionTooltip child of the UI.
	var tooltip: SelectionActionTooltip = ui.get_node_or_null("SelectionActionTooltip") as SelectionActionTooltip
	if not ctx.check(tooltip != null, "SelectionActionTooltip is missing under PlanetNetworkUI"):
		return false
	tooltip.show_text("Ziel nicht gescannt.", Vector2(120.0, 80.0))
	if not ctx.check(tooltip.visible, "SelectionActionTooltip should auto-show when invoked"):
		return false

	# Stand-ins never entered the tree; nothing to clean up.

	return true


## Spawns lightweight Planet instances for selection tests. They do NOT
## enter the live tree (so SeededLayout never re-runs and no signal cascade
## fires), but they DO carry the Planet script so duck-typed property reads
## (planet_id, worker_count, faction, get_faction) keep working.
func _build_stand_in_planets(_field: Node, count: int) -> Array[Node2D]:
	var planets: Array[Node2D] = []
	var planet_scene: PackedScene = preload("res://scenes/objects/planets/planet.tscn")
	for index in count:
		var planet: Planet = planet_scene.instantiate() as Planet
		planet.name = "StandIn_%d" % index
		planet.set("planet_id", StringName("standin_%d" % index))
		planet.set("worker_count", 4 + index)
		planet.faction = StringName("neutral")
		planet.global_position = Vector2(120 + index * 160, 80)
		planets.append(planet)
	return planets
