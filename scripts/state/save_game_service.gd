extends Node

## Autoload (SaveGameService) that persists and restores RunSaveData snapshots.
##
## Storage: user://saves/run_<slot>.tres (Godot Resource format). Writes are
## atomic (tmp file + rename) so a crash cannot leave a half-written save.
## save_run() snapshots the active GameState run; load_run() restores it and
## marks the world for reconnect. write_data()/read_data() are the low-level
## slot API used by tests and the main menu.

const SAVE_DIR: String = "user://saves"
const SAVE_PREFIX: String = "run_"
const SAVE_EXT: String = ".tres"
const MAX_SLOTS: int = 8

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_auto_save_on_quit()

## Snapshots the active run from GameState and writes it to the slot.
func save_run(slot: int) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		return false
	var state: Node = get_node_or_null("/root/GameState")
	if state == null or not state.has_method("snapshot_run") or not state.has_method("has_active_run") or not state.has_active_run():
		return false
	var data: RunSaveData = state.call("snapshot_run") as RunSaveData
	if data == null:
		return false
	if data.session != null:
		data.session.save_slot = slot
	return write_data(slot, data)

## Reads the slot and restores it into GameState (world reconnects on next boot).
func load_run(slot: int) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		return false
	var data: RunSaveData = read_data(slot)
	if data == null:
		return false
	var state: Node = get_node_or_null("/root/GameState")
	if state == null or not state.has_method("restore_run"):
		return false
	return bool(state.call("restore_run", data))

## Low-level slot write (no GameState dependency).
func write_data(slot: int, data: RunSaveData) -> bool:
	if slot < 0 or slot >= MAX_SLOTS or data == null:
		return false
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := _save_path(slot)
	# ResourceSaver validates the file extension, so the temp file must keep a
	# recognized resource extension (.tres) before it is renamed into place.
	var tmp_path := path.replace(SAVE_EXT, "_tmp" + SAVE_EXT)
	var err := ResourceSaver.save(data, tmp_path)
	if err != OK:
		return false
	# Atomic replace: remove a stale target, then rename the tmp file over it.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var rename_err := DirAccess.rename_absolute(tmp_path, path)
	return rename_err == OK

## Low-level slot read. Returns null for missing or corrupted saves.
func read_data(slot: int) -> RunSaveData:
	if slot < 0 or slot >= MAX_SLOTS:
		return null
	var path := _save_path(slot)
	if not FileAccess.file_exists(path):
		return null
	# CACHE_MODE_REPLACE so an overwritten slot is always re-read from disk
	# instead of returning Godot's stale cached instance of the old payload.
	var data: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if data == null or not data is RunSaveData:
		return null
	return data as RunSaveData

func has_save(slot: int) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		return false
	return FileAccess.file_exists(_save_path(slot))

func list_saves() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in MAX_SLOTS:
		if has_save(slot):
			result.append({"slot": slot, "path": _save_path(slot)})
	return result

func delete_save(slot: int) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		return false
	var path := _save_path(slot)
	if not FileAccess.file_exists(path):
		return false
	DirAccess.remove_absolute(path)
	return true

func _save_path(slot: int) -> String:
	return "%s/%s%d%s" % [SAVE_DIR, SAVE_PREFIX, slot, SAVE_EXT]

func _auto_save_on_quit() -> void:
	# Headless runs (preflight suite, smoke tests) must never write user saves:
	# they end with an active test run and would clobber the real slot 0.
	if OS.has_feature("headless"):
		return
	var state: Node = get_node_or_null("/root/GameState")
	if state != null and state.has_method("has_active_run") and state.has_active_run():
		save_run(0)
