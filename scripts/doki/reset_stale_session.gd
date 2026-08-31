extends SceneTree
## reset_stale_session — Recovery: verwaiste/veraltete Sessions zurücksetzen.
## V4-001: Require ownership proof, audit log.
## Usage: $GODOT_BIN --headless --path . --script res://scripts/doki/reset_stale_session.gd --agent <name> --seed <seed>

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var agent_name: String = ""
	var owner_token: String = ""
	var reason: String = "manual_reset"
	
	for i in range(args.size()):
		if args[i] == "--agent" and i + 1 < args.size():
			agent_name = str(args[i + 1])
		elif args[i] == "--seed" and i + 1 < args.size():
			owner_token = str(args[i + 1])
		elif args[i] == "--reason" and i + 1 < args.size():
			reason = str(args[i + 1])
	
	if agent_name.is_empty() or owner_token.is_empty():
		print("Usage: doki reset_stale_session --agent <name> --seed <owner_token> [--reason <reason>]")
		quit(1)
	
	var repo_root: String = ProjectSettings.globalize_path("res://")
	var store := preload("res://scripts/doki/chain/session_store.gd").new(repo_root)
	var session: Dictionary = store.read()
	
	# Verify ownership
	var owner_check: Dictionary = store.assert_owner(owner_token)
	if not bool(owner_check.get("ok", false)):
		print("❌ Ownership verification failed: %s" % str(owner_check.get("error", "unknown")))
		quit(1)
	
	# Verify agent name matches
	var session_agent: String = str(session.get("agent_name", ""))
	if not session_agent.is_empty() and session_agent != agent_name:
		print("❌ Agent mismatch: session belongs to '%s', not '%s'" % [session_agent, agent_name])
		quit(1)
	
	# Check if session is actually stale (not ACTIVE)
	var state: String = str(session.get("state", "idle"))
	if state == DOKI_SessionStore.STATE_IDLE:
		print("✅ Session already idle — nothing to reset")
		quit(0)
	
	# Audit log before reset
	var audit_entry: String = "%s|reset_stale_session|%s|state=%s|agent=%s\n" % [
		Time.get_datetime_string_from_system(),
		reason,
		state,
		agent_name
	]
	var audit_path: String = repo_root.path_join(".doki").path_join("reset_audit.log")
	DirAccess.make_dir_recursive_absolute(audit_path.get_base_dir())
	var file := FileAccess.open(audit_path, FileAccess.WRITE_READ)
	if file != null:
		file.seek_end()
		file.store_string(audit_entry)
		file.close()
	
	store.reset()
	print("✅ DOKI stale session reset to idle (agent: %s, reason: %s)" % [agent_name, reason])
	quit(0)