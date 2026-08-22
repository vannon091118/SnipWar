class_name PreflightConstraintSaveGameSlots
extends RefCounted

## Slot-level SaveGameService contract: write/read/overwrite/list, corruption
## guard and delete. Pure — no scene boot required.

func constraint_name() -> String:
	return "save_game_slots"


func run(ctx: PreflightContext) -> bool:
	# Autoloads are only attached to the tree after the first processed frame.
	await ctx.await_frame()
	var service: Node = ctx.root().get_node_or_null("SaveGameService")
	if not ctx.check(service != null, "SaveGameService autoload is missing"):
		return false
	service.delete_save(1)
	service.delete_save(2)
	if not ctx.check(not service.has_save(1), "slot 1 should start empty"):
		return false

	# Write + read a synthetic snapshot.
	var data := RunSaveData.new()
	data.save_version = RunSaveData.SAVE_VERSION
	data.ownership = {"p0": &"a", "p1": &"b"}
	data.faction_vaults = {"a": {"energy": 123}}
	if not ctx.check(service.write_data(1, data), "write_data failed"):
		return false
	if not ctx.check(service.has_save(1), "has_save is false after write_data"):
		return false
	var loaded: RunSaveData = service.read_data(1)
	if not ctx.check(loaded != null, "read_data returned null"):
		return false
	if not ctx.check(loaded.ownership.get(&"p0") == &"a" and int(loaded.faction_vaults.get(&"a", {}).get(&"energy", 0)) == 123, "slot payload did not roundtrip"):
		return false

	# Overwrite the same slot.
	data.ownership["p0"] = &"neutral"
	if not ctx.check(service.write_data(1, data), "overwrite write_data failed"):
		return false
	loaded = service.read_data(1)
	if not ctx.check(loaded != null and loaded.ownership.get(&"p0") == &"neutral", "slot overwrite did not stick"):
		return false

	# Listing exposes the written slot.
	if not ctx.check(service.list_saves().size() >= 1, "list_saves is missing the written slot"):
		return false

	# Corruption guard: a garbage file must not load.
	var corrupted_path := "%s/run_2.tres" % service.SAVE_DIR
	var file := FileAccess.open(corrupted_path, FileAccess.WRITE)
	if not ctx.check(file != null, "could not open a corrupted-slot fixture file"):
		return false
	file.store_line("this is not a valid godot resource payload")
	file.close()
	if not ctx.check(service.has_save(2), "corrupted slot should still be reported as present"):
		return false
	if not ctx.check(service.read_data(2) == null, "corrupted slot must not load"):
		return false

	# Deletion clears the slots.
	if not ctx.check(service.delete_save(1) and service.delete_save(2), "delete_save failed"):
		return false
	if not ctx.check(not service.has_save(1) and not service.has_save(2), "slots were not cleared"):
		return false
	return true
