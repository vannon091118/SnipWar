class_name DOKI_StatusFlow
extends RefCounted
## Zuständigkeit: Status-Report (Chain + Session) — reine Lese-Sicht.

var _chain_store: DOKI_ChainStore
var _session_store: DOKI_SessionStore


func _init(chain_store: DOKI_ChainStore, session_store: DOKI_SessionStore) -> void:
	_chain_store = chain_store
	_session_store = session_store


func run() -> Dictionary:
	var chain: Dictionary = _chain_store.read()
	var session: Dictionary = _session_store.read()
	var entries: Array = chain.get("entries", [])
	return {
		"ok": true,
		"state": session.get("state", "idle"),
		"initialized": not chain.get("anchor", {}).is_empty(),
		"anchor": chain.get("anchor", {}),
		"entries": entries.size(),
		"last_entry": entries[entries.size() - 1] if not entries.is_empty() else {},
		"composite": session.get("composite", ""),
		"narrator": session.get("narrator", ""),
		"mood": session.get("mood", ""),
		"p_id": session.get("p_id", 0),
		"impulse": session.get("impulse", ""),
		"latest_c": int(entries[entries.size() - 1].get("c", 0)) if not entries.is_empty() else 0,
	}