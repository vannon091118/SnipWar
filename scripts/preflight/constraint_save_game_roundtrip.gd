class_name PreflightConstraintSaveGameRoundtrip
extends RefCounted

## Mutates a booted run, snapshots it, saves it, wipes GameState, restores the
## save and asserts the canonical snapshot is identical (lossless roundtrip).
## Ends by clearing the run so the next fixture boot starts fresh.

func constraint_name() -> String:
	return "save_game_roundtrip"

func requires_scene() -> bool:
	return true


func run(ctx: PreflightContext) -> bool:
	var state: Node = ctx.game_state
	var service: Node = ctx.root().get_node_or_null("SaveGameService")
	if not ctx.check(state != null, "save roundtrip needs a booted world fixture"):
		return false
	if not ctx.check(service != null, "SaveGameService autoload is missing"):
		return false
	# Anchor the fixture world as current_scene so chunk data and pacing timers
	# are captured from the live coordinator/economy manager. The test uses the
	# dedicated test slot 7 (MAX_SLOTS-1): the game only ever touches slot 0,
	# so the suite must never delete or overwrite a real player save.
	ctx.root().get_tree().current_scene = ctx.background
	service.delete_save(7)

	# Give the run real content so the roundtrip is meaningful.
	for resource_id in GameState.ALL_RESOURCES:
		state.add_faction_resource(GameState.FACTION_PLAYER, resource_id, 200)
	var player_home: StringName = state.homeworld_for(GameState.FACTION_PLAYER)
	if not ctx.check(state.research_technology(GameState.FACTION_PLAYER, &"shipyard_construction"), "could not start research for the roundtrip"):
		return false
	state.advance_research(999.0)
	if not ctx.check(state.has_technology(GameState.FACTION_PLAYER, &"shipyard_construction"), "research did not complete"):
		return false
	state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY, 37)
	state.add_ship_part(player_home, &"hull_t1", 3)
	var captured: bool = false
	for child in ctx.field.get_children():
		var planet: Planet = child as Planet
		if planet != null and planet.get_faction() == GameState.FACTION_NEUTRAL:
			state.set_faction(planet.planet_id, GameState.FACTION_PLAYER)
			captured = true
			break
	if not ctx.check(captured, "no neutral planet available for a capture mutation"):
		return false

	var before: RunSaveData = state.snapshot_run() as RunSaveData
	if not ctx.check(before != null, "snapshot_run returned null"):
		return false
	if not ctx.check(before.chunk_data != null, "snapshot did not capture the chunk-world payload"):
		return false
	# Chronicle-Persistence-Vertrag: Die Weltchronik ist Teil des kanonischen
	# RunSaveData und muss den Roundtrip verlustfrei überleben.
	if not ctx.check(before.chronicle != null, "snapshot did not capture the chronicle payload"):
		return false
	if not ctx.check(before.chronicle.backstory_events.size() > 0, "chronicle backstory is empty in the snapshot"):
		return false
	# save_run stamps the slot onto the session; mirror that so the comparison
	# covers domain state rather than the storage binding.
	if before.session != null:
		before.session.save_slot = 7
	if not ctx.check(service.save_run(7), "save_run failed"):
		return false
	if not ctx.check(service.has_save(7), "save file missing after save_run"):
		return false

	# Wipe the run completely.
	state.begin_new_game(ctx.planet_catalog, &"default", ctx.original_seed, ctx.world_config.is_infinite_world())
	if not ctx.check(not state.has_technology(GameState.FACTION_PLAYER, &"shipyard_construction"), "run wipe did not clear research"):
		return false

	# Restore and compare.
	if not ctx.check(service.load_run(7), "load_run failed"):
		return false
	var after: RunSaveData = state.snapshot_run() as RunSaveData
	if not ctx.check(after != null, "snapshot_run returned null after restore"):
		return false
	if not ctx.check(after.chunk_data != null, "restored snapshot lost the chunk-world payload"):
		return false
	if not ctx.check(after.chronicle != null, "restored snapshot lost the chronicle payload"):
		return false
	if not ctx.check(after.chronicle.backstory_events.size() == before.chronicle.backstory_events.size(), "chronicle backstory event count changed across the roundtrip"):
		return false
	var before_cmp: Dictionary = RunSaveData.comparable(before)
	var after_cmp: Dictionary = RunSaveData.comparable(after)
	if before_cmp != after_cmp:
		for key in before_cmp:
			if before_cmp[key] != after_cmp.get(key, "<MISSING>"):
				print("  ROUNDTRIP_DIFF[", key, "] BEFORE=", str(before_cmp[key]).left(300), " AFTER=", str(after_cmp.get(key, "<MISSING>")).left(300))
	if not ctx.check(before_cmp == after_cmp, "save/load roundtrip is not lossless"):
		return false
	if not ctx.check(state.has_technology(GameState.FACTION_PLAYER, &"shipyard_construction"), "restored run lost the researched tech"):
		return false
	if not ctx.check(state.get_ship_part_count(player_home, &"hull_t1") >= 3, "restored run lost ship parts"):
		return false

	service.delete_save(7)
	# Clear the run so the next fixture boot always starts a fresh game.
	state.call("request_new_run")
	ctx.root().get_tree().current_scene = null
	await ctx.await_frame()

	# --- Migration Test: v1 → v2 ---
	# Create a legacy v1 save manually, then load it and verify migration.
	service.delete_save(6)
	var legacy_data: RunSaveData = state.snapshot_run() as RunSaveData
	if legacy_data != null:
		legacy_data.save_version = 1
		if legacy_data.session != null:
			legacy_data.session.save_slot = 6
		if ctx.check(service.write_data(6, legacy_data), "legacy v1 write_data failed"):
			if ctx.check(service.has_save(6), "legacy v1 save file missing"):
				state.begin_new_game(ctx.planet_catalog, &"default", ctx.original_seed, ctx.world_config.is_infinite_world())
				if ctx.check(service.load_run(6), "legacy v1 load_run failed"):
					var migrated_after: RunSaveData = state.snapshot_run() as RunSaveData
					if ctx.check(migrated_after != null, "migrated snapshot_run returned null"):
						if ctx.check(migrated_after.save_version == 2, "migration did not update save_version to 2: got %d" % migrated_after.save_version):
							# Verify migrated data integrity (save_version is expected to differ)
							var mig_before_cmp: Dictionary = RunSaveData.comparable(legacy_data)
							var mig_after_cmp: Dictionary = RunSaveData.comparable(migrated_after)
							mig_before_cmp.erase("save_version")
							mig_after_cmp.erase("save_version")
							if ctx.check(mig_before_cmp == mig_after_cmp, "migration roundtrip is not lossless"):
								pass
		service.delete_save(6)

	return true
