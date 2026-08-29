extends SceneTree

func _init() -> void:
	var store := preload("res://scripts/doki/chain/session_store.gd").new(ProjectSettings.globalize_path("res://"))
	store.reset()
	print("DOKI stale session reset to idle")
	quit(0)
