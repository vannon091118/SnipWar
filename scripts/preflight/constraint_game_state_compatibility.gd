class_name PreflightConstraintGameStateCompatibility
extends RefCounted

## Guards the public GameState facade against domain-split drift.
##
## This constraint intentionally runs before scene_boot. It validates the
## reflected facade method names/signatures and statically audits the common
## GameState receiver aliases used by runtime/preflight scripts for stale
## argument counts. The facade remains the compatibility boundary; domains are
## not allowed to silently become the public API.

const REQUIRED_FACADE_METHODS: Array[StringName] = [
	&"is_valid_resource",
	&"reset_from_catalog",
	&"reset_for_infinite_world",
	&"begin_new_game",
	&"reconnect_world",
	&"has_active_run",
	&"world_session_context",
	&"set_pending_battle_context",
	&"pending_battle_context",
	&"clear_pending_battle_context",
	&"register_transit",
	&"update_transit",
	&"remove_transit",
	&"get_transit",
	&"get_transit_records",
	&"next_transit_id",
	&"set_jobs_auto_advance",
	&"advance_research",
	&"advance_builds",
	&"advance_upgrade_builds",
	&"upgrade_build_in_progress",
	&"upgrade_build_remaining",
	&"abort_upgrade_build",
	&"advance_building_jobs",
	&"building_job_in_progress",
	&"abort_building_job",
	&"set_faction",
	&"register_planet",
	&"register_homeworld",
	&"seed_starting_workers",
	&"faction_of",
	&"is_owned_by",
	&"homeworld_for",
	&"get_ownership_count",
	&"all_owned_planets",
	&"starting_workers_of",
	&"add_starting_workers",
	&"discover_planet",
	&"scan_planet",
	&"is_known",
	&"has_scanned_planet",
	&"scan_info_for",
	&"known_planets_of",
	&"mark_milestone",
	&"has_milestone",
	&"get_milestones",
	&"get_faction_credits",
	&"get_market_price",
	&"market_snapshot",
	&"add_faction_credits",
	&"spend_faction_credits",
	&"can_spend_faction_credits",
	&"can_spend_faction_cost",
	&"spend_faction_cost",
	&"credit_transport_resources",
	&"begin_worker_transport",
	&"update_worker_transport",
	&"set_worker_transport_escorted",
	&"get_worker_transport_records",
	&"complete_worker_transport",
	&"get_research_ship_records",
	&"register_persistent_fleet",
	&"get_persistent_ship_records",
	&"mark_persistent_ship_arrived",
	&"mark_persistent_ship_lost",
	&"get_research_missions",
	&"queue_research_mission",
	&"cancel_research_mission",
	&"get_persistent_ship",
	&"advance_research_ship_tasks",
	&"get_faction_resource",
	&"get_faction_vault_snapshot",
	&"add_faction_resource",
	&"spend_faction_resource",
	&"can_spend_faction_resource",
	&"set_planet_resource",
	&"resource_of",
	&"deal_resources",
	&"deal_resources_for_planets",
	&"resource_snapshot",
	&"validate_resources",
	&"generate_resources_for_planet",
	&"convert_refinery_resources",
	&"has_planet_upgrade",
	&"get_planet_upgrades",
	&"can_purchase_upgrade",
	&"purchase_upgrade",
	&"add_planet_upgrade",
	&"has_worker_factory",
	&"can_build_worker_factory",
	&"build_worker_factory",
	&"register_gathering_workers",
	&"get_gathering_workers",
	&"get_gathering_source",
	&"withdraw_gathering_workers",
	&"gathering_workers_on",
	&"gather_income_tick",
	&"has_technology",
	&"get_researched_technologies",
	&"can_research_technology",
	&"research_technology",
	&"research_in_progress",
	&"research_remaining",
	&"has_planet_technology",
	&"get_planet_technologies",
	&"can_research_planet_technology",
	&"research_planet_technology",
	&"get_ship_part_inventory",
	&"get_ship_part_count",
	&"add_ship_part",
	&"spend_ship_part",
	&"can_buy_ship_part",
	&"buy_ship_part",
	&"get_ship_assemblies",
	&"has_ship_assembly",
	&"get_ship_assembly",
	&"can_assemble_ship",
	&"assemble_ship",
	&"disassemble_ship",
	&"launch_ship",
	&"get_ship_build_jobs",
	&"ship_build_in_progress",
	&"ship_build_remaining",
	&"create_fleet_from_planet",
	&"preview_fleet_from_planet",
	&"disband_fleet_to_planet",
	&"reconcile_defender_fleet",
	&"can_place_planet_building",
	&"place_planet_building",
	&"remove_planet_building",
	&"planet_building_at",
	&"get_local_resource",
	&"get_local_resources",
	&"add_local_resource",
	&"spend_local_resource",
	&"can_spend_local_resource",
	&"transfer_local_resources",
	&"deal_local_resources",
	&"can_register_trade_route",
	&"register_trade_route",
	&"tick_trade_routes",
	&"trade_routes_snapshot",
	&"capture_planet",
	&"steal_resources",
	&"validate",
	&"validate_starting_setup",
	# Scene-flow & save/load façade (scene director / save game service bridge)
	&"request_new_run",
	&"session",
	&"snapshot_run",
	&"restore_run",
	&"pending_chunk_data",
	&"consume_pending_chunk_data",
	&"pending_timers",
	&"consume_pending_timers",
]

## These are the signatures most likely to drift when a domain method is moved
## behind GameState. Argument names are checked as well as arity so a legacy
## `(faction, planet_id, ...)` wrapper cannot silently replace `(planet_id, ...)`.
const SIGNATURE_CONTRACTS: Dictionary = {
	&"begin_new_game": {"args": [&"catalog", &"scenario_id", &"layout_seed", &"infinite_world"], "required": 3},
	&"reconnect_world": {"args": [&"scenario_id", &"layout_seed", &"infinite_world"], "required": 2},
	&"set_pending_battle_context": {"args": [&"context"], "required": 1},
	&"register_transit": {"args": [&"record"], "required": 1},
	&"get_transit": {"args": [&"transit_id"], "required": 1},
	&"remove_transit": {"args": [&"transit_id"], "required": 1},
	&"is_valid_resource": {"args": [&"resource_id"], "required": 1},
	&"scan_planet": {"args": [&"faction", &"planet_id", &"resource_id", &"size_id", &"build_slots"], "required": 2},
	&"has_scanned_planet": {"args": [&"faction", &"planet_id"], "required": 1},
	&"deal_resources": {"args": [&"catalog", &"pool", &"seed_value"], "required": 1},
	&"deal_resources_for_planets": {"args": [&"planet_data", &"pool", &"seed_value"], "required": 1},
	&"validate_resources": {"args": [&"pool"], "required": 0},
	&"generate_resources_for_planet": {"args": [&"planet_id", &"catalog", &"base_amount"], "required": 1},
	&"gather_income_tick": {"args": [&"base_amounts", &"catalog"], "required": 1},
	&"can_purchase_upgrade": {"args": [&"planet_id", &"upgrade_id", &"catalog", &"available_workers"], "required": 2},
	&"purchase_upgrade": {"args": [&"planet_id", &"upgrade_id", &"catalog", &"available_workers"], "required": 2},
	&"can_build_worker_factory": {"args": [&"planet_id", &"cost_resource", &"cost_amount", &"credit_cost"], "required": 3},
	&"build_worker_factory": {"args": [&"planet_id", &"cost_resource", &"cost_amount", &"credit_cost"], "required": 3},
	&"register_gathering_workers": {"args": [&"faction", &"planet_id", &"worker_amount", &"source_planet_id"], "required": 3},
	&"withdraw_gathering_workers": {"args": [&"faction", &"planet_id", &"amount"], "required": 3},
	&"can_research_technology": {"args": [&"faction", &"technology_id", &"catalog"], "required": 2},
	&"research_technology": {"args": [&"faction", &"technology_id", &"catalog"], "required": 2},
	&"can_research_planet_technology": {"args": [&"faction", &"planet_id", &"technology_id", &"catalog"], "required": 3},
	&"research_planet_technology": {"args": [&"faction", &"planet_id", &"technology_id", &"catalog"], "required": 3},
	&"can_buy_ship_part": {"args": [&"planet_id", &"part_id", &"catalog"], "required": 2},
	&"buy_ship_part": {"args": [&"planet_id", &"part_id", &"catalog"], "required": 2},
	&"can_assemble_ship": {"args": [&"planet_id", &"hull_id", &"scanner_id", &"module_ids", &"catalog", &"weapon_id", &"drive_id", &"shield_id"], "required": 4},
	&"assemble_ship": {"args": [&"planet_id", &"hull_id", &"scanner_id", &"module_ids", &"catalog", &"weapon_id", &"drive_id", &"shield_id", &"blueprint_id", &"custom_seed", &"ship_role"], "required": 4},
	&"ship_build_in_progress": {"args": [&"planet_id", &"ship_id"], "required": 1},
	&"create_fleet_from_planet": {"args": [&"planet_id", &"ship_ids", &"catalog"], "required": 2},
	&"preview_fleet_from_planet": {"args": [&"planet_id", &"ship_ids", &"catalog"], "required": 2},
	&"restore_run": {"args": [&"data"], "required": 1},
}

const LEGACY_SIGNATURE_PATTERNS: Array[Dictionary] = [
	{
		"method": &"can_purchase_upgrade",
		"pattern": "^[(][[:space:]]*(?:faction|source_faction|GameState[.]FACTION_[A-Z_]+)[[:space:]]*,",
		"message": "legacy faction-first can_purchase_upgrade call",
	},
	{
		"method": &"purchase_upgrade",
		"pattern": "^[(][[:space:]]*(?:faction|source_faction|GameState[.]FACTION_[A-Z_]+)[[:space:]]*,",
		"message": "legacy faction-first purchase_upgrade call",
	},
	{
		"method": &"can_buy_ship_part",
		"pattern": "^[(][[:space:]]*(?:faction|source_faction|GameState[.]FACTION_[A-Z_]+)[[:space:]]*,",
		"message": "legacy faction-first can_buy_ship_part call",
	},
	{
		"method": &"buy_ship_part",
		"pattern": "^[(][[:space:]]*(?:faction|source_faction|GameState[.]FACTION_[A-Z_]+)[[:space:]]*,",
		"message": "legacy faction-first buy_ship_part call",
	},
	{
		"method": &"register_gathering_workers",
		"pattern": "^[(][[:space:]]*[^,]+,[[:space:]]*[^,]+,[[:space:]]*(?:source_planet_id|source_id)[[:space:]]*,",
		"message": "legacy source-before-count register_gathering_workers call",
	},
	{
		"method": &"can_assemble_ship",
		"pattern": "^[(][[:space:]]*[^,]+,[[:space:]]*[^,]+,[[:space:]]*[^,]+,[[:space:]]*[^,]+,[[:space:]]*(?:weapon_id|weapon_part_id|weapon_part[.]id)[[:space:]]*,",
		"message": "legacy weapon-before-catalog can_assemble_ship call",
	},
	{
		"method": &"assemble_ship",
		"pattern": "^[(][[:space:]]*[^,]+,[[:space:]]*[^,]+,[[:space:]]*[^,]+,[[:space:]]*[^,]+,[[:space:]]*(?:weapon_id|weapon_part_id|weapon_part[.]id)[[:space:]]*,",
		"message": "legacy weapon-before-catalog assemble_ship call",
	},
]

const CALLSITE_RECEIVER_PATTERN := "(?:\\bGameState\\b|\\bgame_state\\b|\\bstate\\b|\\bctx\\.game_state\\b)"

func constraint_name() -> String:
	return "game_state_compatibility"

func requires_scene() -> bool:
	return true

func run(ctx: PreflightContext) -> bool:
	var state: Node = ctx.root().get_node_or_null("GameState") as Node
	if state == null:
		# Autoloads are available after the first idle frame even though this
		# constraint intentionally runs before the main scene is instantiated.
		await ctx.await_frame()
		state = ctx.root().get_node_or_null("GameState") as Node
	if not ctx.check(state != null, "GameState autoload is missing before scene boot"):
		return false

	var reflected_methods: Dictionary = _reflected_methods(state)
	for method_name in REQUIRED_FACADE_METHODS:
		if not ctx.check(reflected_methods.has(method_name), "GameState façade method is missing: %s" % method_name):
			return false

	for method_name in SIGNATURE_CONTRACTS:
		var contract: Dictionary = SIGNATURE_CONTRACTS[method_name]
		var method_info: Dictionary = reflected_methods.get(method_name, {}) as Dictionary
		if method_info.is_empty():
			if not ctx.check(false, "GameState signature cannot be checked because %s is missing" % method_name):
				return false
			continue
		if not _check_signature(ctx, method_name, method_info, contract):
			return false

	var callsite_errors: PackedStringArray = _scan_callsites(ctx.code_index.gd_sources)
	if not ctx.check(callsite_errors.is_empty(), "stale GameState call signature detected before scene boot", {"errors": callsite_errors}):
		return false
	return true

func _reflected_methods(state: Node) -> Dictionary:
	var result: Dictionary = {}
	for method_value in state.get_method_list():
		var method_info: Dictionary = method_value as Dictionary
		var method_name: StringName = method_info.get("name", &"") as StringName
		if not String(method_name).is_empty():
			result[method_name] = method_info
	return result

func _check_signature(ctx: PreflightContext, method_name: StringName, method_info: Dictionary, contract: Dictionary) -> bool:
	var expected_args: Array = contract.get("args", []) as Array
	var actual_args: Array = method_info.get("args", []) as Array
	if not ctx.check(actual_args.size() == expected_args.size(), "GameState façade argument count drifted for %s (expected %d, got %d)" % [method_name, expected_args.size(), actual_args.size()]):
		return false
	for index in expected_args.size():
		var actual_arg: Dictionary = actual_args[index] as Dictionary
		var actual_name: String = String(actual_arg.get("name", ""))
		var expected_name: String = String(expected_args[index])
		if not ctx.check(actual_name == expected_name, "GameState façade parameter %d drifted for %s (expected %s, got %s)" % [index + 1, method_name, expected_name, actual_name]):
			return false
	var expected_required: int = int(contract.get("required", expected_args.size()))
	var actual_defaults: Array = method_info.get("default_args", []) as Array
	var actual_required: int = actual_args.size() - actual_defaults.size()
	return ctx.check(actual_required == expected_required, "GameState façade optional-argument contract drifted for %s (expected %d required, got %d)" % [method_name, expected_required, actual_required])

## Scans pre-loaded GDScript sources for stale GameState call signatures.
## sources: Array[{file:String, content:String, lines:Array[String]}] from PreflightCodeIndex.
func _scan_callsites(sources: Array[Dictionary]) -> PackedStringArray:
	var errors := PackedStringArray()
	var receiver_regex := RegEx.new()
	var compile_error: int = receiver_regex.compile(CALLSITE_RECEIVER_PATTERN + "\\s*\\.\\s*([A-Za-z_]\\w*)\\s*\\(")
	if compile_error != OK:
		errors.append("could not compile GameState callsite regex")
		return errors
	for source in sources:
		var path: String = String(source.file)
		if path.ends_with("constraint_game_state_compatibility.gd"):
			continue
		# Only check scripts/ subtree (addons have separate conventions)
		if not path.begins_with("res://scripts"):
			continue
		var source_str: String = String(source.content)
		var masked_source: String = _mask_non_code(source_str)
		for match in receiver_regex.search_all(masked_source):
			var method_name: StringName = StringName(match.get_string(1))
			if not SIGNATURE_CONTRACTS.has(method_name):
				continue
			var open_index: int = match.get_end() - 1
			var argument_count: int = _count_call_arguments(masked_source, open_index)
			var contract: Dictionary = SIGNATURE_CONTRACTS[method_name]
			var expected_args: Array = contract.get("args", []) as Array
			var required: int = int(contract.get("required", expected_args.size()))
			var line_number: int = masked_source.left(match.get_start()).count("\n") + 1
			if argument_count < required or argument_count > expected_args.size():
				errors.append("%s:%d %s(...) has %d arguments; expected %d..%d" % [path.trim_prefix("res://"), line_number, method_name, argument_count, required, expected_args.size()])
			var legacy_message: String = _legacy_signature_message(method_name, masked_source.substr(open_index, 240))
			if not legacy_message.is_empty():
				errors.append("%s:%d %s" % [path.trim_prefix("res://"), line_number, legacy_message])
	return errors

func _legacy_signature_message(method_name: StringName, call_prefix: String) -> String:
	for pattern_value in LEGACY_SIGNATURE_PATTERNS:
		var pattern: Dictionary = pattern_value as Dictionary
		if pattern.get("method", &"") != method_name:
			continue
		var regex := RegEx.new()
		if regex.compile(String(pattern.get("pattern", ""))) == OK and regex.search(call_prefix) != null:
			return String(pattern.get("message", "legacy GameState call"))
	return ""

func _mask_non_code(source: String) -> String:
	var bytes: PackedByteArray = source.to_utf8_buffer()
	var in_string := false
	var in_comment := false
	var escaped := false
	var byte_count: int = bytes.size()
	for i in range(byte_count):
		var b: int = bytes[i]
		if in_comment:
			if b == 10:  # \n
				in_comment = false
			else:
				bytes[i] = 32  # space
			continue
		if in_string:
			if b == 10:  # \n
				continue
			elif escaped:
				bytes[i] = 32
				escaped = false
			elif b == 92:  # \
				bytes[i] = 32
				escaped = true
			elif b == 34:  # "
				bytes[i] = 32
				in_string = false
			else:
				bytes[i] = 32
			continue
		if b == 35:  # #
			in_comment = true
			bytes[i] = 32
		elif b == 34:  # "
			in_string = true
			bytes[i] = 32
	return bytes.get_string_from_utf8()

func _count_call_arguments(source: String, open_index: int) -> int:
	var parentheses := 0
	var nested_containers := 0
	var commas := 0
	var has_value := false
	for index in range(open_index, source.length()):
		var character: String = source[index]
		if character == "(":
			parentheses += 1
			continue
		if character == ")":
			parentheses -= 1
			if parentheses == 0:
				break
			continue
		if parentheses != 1:
			continue
		if character == "[" or character == "{":
			nested_containers += 1
		elif character == "]" or character == "}":
			nested_containers = maxi(nested_containers - 1, 0)
		elif character == "," and nested_containers == 0:
			commas += 1
		elif nested_containers == 0 and character != " " and character != "\t" and character != "\r" and character != "\n":
			has_value = true
	return commas + 1 if has_value else 0
