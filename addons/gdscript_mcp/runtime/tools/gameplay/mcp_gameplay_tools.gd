extends RefCounted
class_name McpGameplayTools

## McpGameplayTools — Gameplay domain bridge for MCP agents.
## Wraps GameState's public API so an external agent can query and steer
## the running game without guessing autoload paths or method signatures.

# ─── Tool Definitions ───────────────────────────────────────────

static func get_tool_defs() -> Array:
	return [
		_make("game_state_snapshot", "Capture a full GameState snapshot (RunSaveData) for later restore"),
		_make("game_state_restore", "Restore a previously captured GameState snapshot", {"snapshot": {"type": "object"}}, ["snapshot"]),
		_make("game_faction_query", "Query which faction owns a planet and basic planet info", {"planet_id": {"type": "string"}}, ["planet_id"]),
		_make("game_vault_snapshot", "Read all resource vaults and credits for a faction", {"faction": {"type": "string", "default": "a"}}, ["faction"]),
		_make("game_resources_all", "List all resource IDs and the faction's current amounts", {"faction": {"type": "string", "default": "a"}}),
		_make("game_planet_info", "Detailed planet info: faction, workers, upgrades, size profile", {"planet_id": {"type": "string"}}, ["planet_id"]),
		_make("game_ship_list", "List all active and queued ship assemblies", {"faction": {"type": "string", "default": "a"}}),
		_make("game_research_status", "List active and completed research jobs", {"faction": {"type": "string", "default": "a"}}),
		_make("game_upgrade_list", "List built upgrades on a planet", {"planet_id": {"type": "string"}}, ["planet_id"]),
		_make("game_dispatch_info", "Read pending dispatch queue and active transits", {"faction": {"type": "string", "default": "a"}}),
	]


# ─── Dispatch ───────────────────────────────────────────────────

func dispatch_tool(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"game_state_snapshot": return _state_snapshot()
		"game_state_restore": return _state_restore(args.get("snapshot"))
		"game_faction_query": return _faction_query(str(args.get("planet_id", "")))
		"game_vault_snapshot": return _vault_snapshot(str(args.get("faction", "a")))
		"game_resources_all": return _resources_all(str(args.get("faction", "a")))
		"game_planet_info": return _planet_info(str(args.get("planet_id", "")))
		"game_ship_list": return _ship_list(str(args.get("faction", "a")))
		"game_research_status": return _research_status(str(args.get("faction", "a")))
		"game_upgrade_list": return _upgrade_list(str(args.get("planet_id", "")))
		"game_dispatch_info": return _dispatch_info(str(args.get("faction", "a")))
		_: return {"error": "Unknown gameplay tool: " + tool_name}


# ─── Implementations ────────────────────────────────────────────

func _get_gs() -> Node:
	var ml: Object = Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("/root/GameState")
	return null


func _state_snapshot() -> Dictionary:
	var gs := _get_gs()
	if gs == null:
		return {"error": "GameState not available"}
	if gs.has_method("snapshot_run"):
		var snapshot: Variant = gs.call("snapshot_run")
		if snapshot != null:
			return {"ok": true, "snapshot": _serialize_resource(snapshot)}
	return {"error": "snapshot_run not available"}


func _state_restore(snapshot: Variant) -> Dictionary:
	if snapshot == null:
		return {"error": "snapshot is null"}
	var gs := _get_gs()
	if gs == null:
		return {"error": "GameState not available"}
	if gs.has_method("restore_run"):
		var restored: bool = gs.call("restore_run", _deserialize_resource(snapshot))
		return {"ok": restored, "restored": restored}
	return {"error": "restore_run not available"}


func _faction_query(planet_id: String) -> Dictionary:
	var gs := _get_gs()
	if gs == null:
		return {"error": "GameState not available"}
	var ml: Object = Engine.get_main_loop()
	if ml is SceneTree:
		var pf: Node = (ml as SceneTree).root.get_node_or_null("/root/World/PlanetField")
		if pf != null:
			var all_planets: Array = []
			_find_planets_recursive(pf, all_planets)
			var planets: Array = []
			for p in all_planets:
				var id: String = String(p.call("get_id"))
				if planet_id == "" or id == planet_id:
					planets.append({
						"id": id,
						"faction": String(p.call("get_faction")),
						"type": str(p.get("planet_type")) if p.get("planet_type") != null else "",
					})
			return {"planets": planets, "count": planets.size()}
	return {"error": "PlanetField not found"}


func _vault_snapshot(faction: String) -> Dictionary:
	var gs := _get_gs()
	if gs == null:
		return {"error": "GameState not available"}
	var fid := StringName(faction)
	if gs.has_method("get_faction_vault_snapshot"):
		var vault: Variant = gs.call("get_faction_vault_snapshot", fid)
		return {"faction": faction, "vault": vault}
	return {"error": "get_faction_vault_snapshot not available"}


func _resources_all(faction: String) -> Dictionary:
	var gs := _get_gs()
	if gs == null:
		return {"error": "GameState not available"}
	var fid := StringName(faction)
	var resource_ids := ["energy", "biomass", "rare", "volatile", "material"]
	var result: Dictionary = {}
	for rid in resource_ids:
		if gs.has_method("get_faction_resource"):
			result[rid] = gs.call("get_faction_resource", fid, StringName(rid))
	if gs.has_method("get_faction_credits"):
		result["credits"] = gs.call("get_faction_credits", fid)
	return {"faction": faction, "resources": result}


func _planet_info(planet_id: String) -> Dictionary:
	var ml: Object = Engine.get_main_loop()
	if not (ml is SceneTree):
		return {"error": "No scene tree"}
	var pf: Node = (ml as SceneTree).root.get_node_or_null("/root/World/PlanetField")
	if pf == null:
		return {"error": "PlanetField not found"}
	var all_planets: Array = []
	_find_planets_recursive(pf, all_planets)
	for p in all_planets:
		if String(p.call("get_id")) == planet_id:
			var info: Dictionary = {
				"id": planet_id,
				"faction": String(p.call("get_faction")) if p.has_method("get_faction") else "",
				"type": str(p.get("planet_type")) if p.get("planet_type") != null else "",
			}
			if p.has_method("get_worker_count"):
				info["workers"] = p.call("get_worker_count")
			if p.has_method("get_build_slot_count"):
				info["build_slots"] = p.call("get_build_slot_count")
			return info
	return {"error": "Planet not found: " + planet_id}


func _ship_list(faction: String) -> Dictionary:
	var gs := _get_gs()
	if gs == null:
		return {"error": "GameState not available"}
	var assemblies: Array = gs.get("assemblies") if gs.get("assemblies") != null else []
	var result: Array = []
	for asm in assemblies:
		if asm is Dictionary:
			var asm_faction: String = str(asm.get("faction", ""))
			if faction == "" or asm_faction == faction:
				result.append(asm)
	return {"faction": faction, "ships": result, "count": result.size()}


func _research_status(faction: String) -> Dictionary:
	var gs := _get_gs()
	if gs == null:
		return {"error": "GameState not available"}
	# The real research state lives in TechDomain (research_jobs[fac][tech] =
	# remaining; researched_techs[fac] = list). The old lookup read two
	# fields that never existed on GameState, so active/completed were always
	# empty even while a timed research was running (UX-Bug G3).
	var tech_domain: Object = gs.get("tech_domain") if gs.get("tech_domain") != null else null
	if tech_domain == null:
		return {"faction": faction, "research": {"active": [], "completed": []}}
	var faction_key := StringName(faction)
	var jobs: Dictionary = tech_domain.get("research_jobs") if tech_domain.get("research_jobs") != null else {}
	var researched: Dictionary = tech_domain.get("researched_techs") if tech_domain.get("researched_techs") != null else {}
	var active: Array = []
	var faction_jobs: Dictionary = jobs.get(faction_key, {}) as Dictionary
	for tech_value in faction_jobs.keys():
		active.append({
			"technology_id": String(tech_value),
			"remaining": float(faction_jobs[tech_value]),
		})
	var completed: Array = []
	var faction_done: Array = researched.get(faction_key, []) as Array
	for tech_value in faction_done:
		completed.append(String(tech_value))
	return {"faction": faction, "research": {"active": active, "completed": completed}}


func _upgrade_list(planet_id: String) -> Dictionary:
	var ml: Object = Engine.get_main_loop()
	if not (ml is SceneTree):
		return {"error": "No scene tree"}
	var pf: Node = (ml as SceneTree).root.get_node_or_null("/root/World/PlanetField")
	if pf == null:
		return {"error": "PlanetField not found"}
	var all_planets: Array = []
	_find_planets_recursive(pf, all_planets)
	for p in all_planets:
		if String(p.call("get_id")) == planet_id:
			var upgrades: Array = p.get("built_upgrades") if p.get("built_upgrades") != null else []
			return {"planet_id": planet_id, "upgrades": upgrades, "count": upgrades.size()}
	return {"error": "Planet not found: " + planet_id}


func _dispatch_info(faction: String) -> Dictionary:
	var ml: Object = Engine.get_main_loop()
	if not (ml is SceneTree):
		return {"error": "No scene tree"}
	var wm: Node = (ml as SceneTree).root.get_node_or_null("/root/World/PlanetField/WorkerManager")
	if wm == null:
		return {"error": "WorkerManager not found"}
	var pending: Array = wm.get("pending_dispatches") if wm.get("pending_dispatches") != null else []
	var active: Array = wm.get("active_transits") if wm.get("active_transits") != null else []
	var result: Dictionary = {"pending": [], "active": []}
	for d in pending:
		if d is Dictionary and str(d.get("faction", "")) == faction:
			result["pending"].append(d)
	for t in active:
		if t is Dictionary and str(t.get("source_faction", "")) == faction:
			result["active"].append(t)
	return {"faction": faction, "dispatch": result}


# ─── Helpers ────────────────────────────────────────────────────

## Rekursive Suche nach Planet-Objekten im Szenenbaum.
## Planeten sind Node2D-Container, die eigentlichen Planet-Objekte
## liegen eine Ebene tiefer als PlanetField-Kinder.
func _find_planets_recursive(node: Node, results: Array) -> void:
	if node.has_method("get_id") and node.has_method("get_faction"):
		results.append(node)
	for child in node.get_children():
		_find_planets_recursive(child, results)


static func _make(name: String, description: String, properties: Dictionary = {}, required: Array = []) -> Dictionary:
	var schema := {"type": "object", "properties": properties}
	if not required.is_empty():
		schema["required"] = required
	return {"name": name, "description": description, "inputSchema": schema}


func _serialize_resource(res: Resource) -> Dictionary:
	if res == null:
		return {}
	var data: Dictionary = {"_class": res.get_class(), "_path": str(res.resource_path)}
	for prop in res.get_property_list():
		var prop_name: String = str(prop.get("name", ""))
		if prop_name == "script" or not (int(prop.get("usage", 0)) & PROPERTY_USAGE_STORAGE):
			continue
		var val: Variant = res.get(prop_name)
		if val is Resource:
			data[prop_name] = _serialize_resource(val)
		elif val is StringName:
			data[prop_name] = String(val)
		elif val is Vector2:
			data[prop_name] = {"x": val.x, "y": val.y}
		elif val is Color:
			data[prop_name] = {"r": val.r, "g": val.g, "b": val.b, "a": val.a}
		else:
			data[prop_name] = val
	return data


func _deserialize_resource(data: Variant) -> Variant:
	if data is Dictionary:
		var dict: Dictionary = data
		if dict.has("_class") and dict.has("_path"):
			var path: String = str(dict.get("_path", ""))
			if path != "" and ResourceLoader.exists(path):
				var res: Resource = ResourceLoader.load(path)
				if res != null:
					return res
	return data
