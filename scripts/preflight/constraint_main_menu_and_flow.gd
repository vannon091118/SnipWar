class_name PreflightConstraintMainMenuAndFlow
extends RefCounted

## Main menu scene, SceneDirector registry and save-slot gating of the
## Continue button. Real scene switching is covered by context_handover.

func constraint_name() -> String:
	return "main_menu_and_flow"


func run(ctx: PreflightContext) -> bool:
	# 1. SceneDirector registry exposes all four scenes.
	var director: Node = ctx.root().get_node_or_null("SceneDirectorService")
	if not ctx.check(director != null, "SceneDirectorService autoload is missing"):
		return false
	var ids: Array = director.registered_scene_ids()
	for expected in [&"menu", &"world", &"battle", &"conquest"]:
		if not ctx.check(ids.has(expected), "SceneDirector registry is missing %s" % expected):
			return false
	for scene_id in ids:
		if not ctx.check(director.scene_for_id(scene_id) != null, "SceneDirector resolves a null scene for %s" % scene_id):
			return false
	# 2. The main menu scene boots and exposes its flow controls.
	var menu_scene: PackedScene = preload("res://scenes/main_menu/main_menu.tscn")
	var menu: Node = menu_scene.instantiate()
	ctx.root().add_child(menu)
	await ctx.await_frame()
	var new_game_button: Button = menu.get_node_or_null("Content/NewGameButton") as Button
	var continue_button: Button = menu.get_node_or_null("Content/ContinueButton") as Button
	var quit_button: Button = menu.get_node_or_null("Content/QuitButton") as Button
	if not ctx.check(new_game_button != null and continue_button != null and quit_button != null, "main menu is missing its flow buttons"):
		menu.queue_free()
		return false
	# 3. Continue is gated on an existing save slot. The gate reads the game's
	# real slot (0), so the test backs up any existing player save first and
	# restores it on every exit path — the suite must never destroy real data.
	var service: Node = ctx.root().get_node_or_null("SaveGameService")
	if not ctx.check(service != null, "SaveGameService autoload is missing"):
		menu.queue_free()
		return false
	var backup: RunSaveData = service.read_data(0) as RunSaveData if service.has_method("read_data") else null
	service.delete_save(0)
	menu.call("_refresh_continue")
	if not ctx.check(continue_button.disabled, "Continue should be disabled without a save"):
		_restore_slot(service, backup)
		menu.queue_free()
		return false
	var synthetic := RunSaveData.new()
	if not ctx.check(service.write_data(0, synthetic), "could not stage a save for the continue gate"):
		_restore_slot(service, backup)
		menu.queue_free()
		return false
	menu.call("_refresh_continue")
	if not ctx.check(not continue_button.disabled, "Continue should be enabled with a save present"):
		_restore_slot(service, backup)
		menu.queue_free()
		return false
	service.delete_save(0)
	_restore_slot(service, backup)
	menu.queue_free()
	await ctx.await_frame()
	# 4. New-game flow resets the run so the next world boot starts fresh.
	var state: Node = ctx.game_state
	if not ctx.check(state != null, "GameState missing for new-game flow"):
		return false
	state.call("request_new_run")
	if not ctx.check(not state.has_active_run(), "request_new_run did not clear the active run"):
		return false
	return true

## Re-writes a previously existing player save that the gate test temporarily
## deleted (or is a no-op when the slot was empty before the test).
func _restore_slot(service: Node, backup: RunSaveData) -> void:
	if service == null or backup == null:
		return
	service.write_data(0, backup)
