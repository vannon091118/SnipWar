@tool
class_name Planet
extends Node2D

const DEFAULT_SIZE_PROFILE: PlanetSizeProfile = preload("res://resources/config/planet_sizes/variable.tres")
const DEFAULT_DETAIL_PROFILE: PlanetDetailProfile = preload("res://resources/config/planet_details/default.tres")
const DEFAULT_SHIP_CONFIG: ShipConfig = preload("res://resources/config/ship_default.tres")

signal planet_selected(planet: Node2D)
## Emitted next to planet_selected with the input modifier flags captured at
## the click time (shift/ctrl/meta/long_press). SelectionService listens to
## this to drive multi-select; the legacy planet_selected signal is preserved
## for PlanetNetwork's existing single-primary flow and for tests that drive
## clicks synthetically.
signal planet_selection_requested(planet: Node2D, modifiers: Dictionary)
signal planet_context_requested(planet: Node2D, screen_position: Vector2)
signal workers_spawn_requested(planet: Node2D, amount: int)
signal worker_count_changed(planet: Node2D, count: int)
signal worker_production_changed(planet: Node2D, enabled: bool)
signal planet_hovered(planet: Node2D)
signal planet_unhovered(planet: Node2D)

enum WorkerState { IDLE, SPAWNING }

## Fog-of-war visual state: FOG = softly fogged via shader, FRONTIER = dimmed
## unknown neighbor, VISIBLE = fully rendered known/owned planet.
enum FogState { FOG, FRONTIER, VISIBLE }

const ARRIVAL_FRIENDLY := &"friendly"
const ARRIVAL_REPELLED := &"repelled"
const ARRIVAL_CAPTURED := &"captured"
const ARRIVAL_REJECTED := &"rejected"
const ARRIVAL_SETTLED := &"settled"
const ARRIVAL_COLLECTED := &"collected"

@export var planet_id: StringName = &"planet"
@export var display_name: String = ""
@export var size_profile: PlanetSizeProfile = DEFAULT_SIZE_PROFILE
var layout_size: String = "variable":
	set(value):
		layout_size = value
		_restart_spawn_timer()
@export var faction: StringName = &"neutral":
	set(value):
		faction = value
		if is_inside_tree() and not Engine.is_editor_hint():
			var state: Node = _game_state()
			if state != null:
				state.set_faction(planet_id, value)

@export var planet_role: StringName = &"planet":
	set(value):
		if is_inside_tree() and planet_role != value:
			remove_from_group(_role_group(planet_role))
		planet_role = value
		if is_inside_tree():
			add_to_group(_role_group(planet_role))
@export var detail_profile: PlanetDetailProfile = DEFAULT_DETAIL_PROFILE
@export var planet_texture: Texture2D:
	set(value):
		planet_texture = value
		_apply_visuals()

@export_range(0.25, 2.5, 0.05) var visual_scale: float = 1.0:
	set(value):
		visual_scale = value
		_apply_visuals()

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _details: PlanetDetails = $PlanetDetails

var worker_state: WorkerState = WorkerState.IDLE
var worker_count := 0
var _worker_spawn_enabled: bool = false
var _spawn_timer: Timer
var _detail_seed := 0
var _planet_ready := false
var _initial_workers_applied := false
var _strength_label: Label
var _selected: bool = false
var _fog_material_instance: ShaderMaterial
var _fog_state: FogState = FogState.VISIBLE

const DEFAULT_UPGRADE_CATALOG: PlanetUpgradeCatalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")
const DEFAULT_TRANSFORMER_CONFIG: TransformerConfig = preload("res://resources/config/transformer_default.tres")
const FOG_SHADER: Shader = preload("res://assets/shaders/planet_fog.gdshader")

func _ready() -> void:
	$ClickArea.input_event.connect(_on_click_area_input_event)
	$ClickArea.mouse_entered.connect(_on_click_area_mouse_entered)
	$ClickArea.mouse_exited.connect(_on_click_area_mouse_exited)
	add_to_group("planets")
	if not Engine.is_editor_hint():
		var state: Node = _game_state()
		if state != null:
			state.register_planet(planet_id, faction)
			if not state.faction_changed.is_connected(_on_faction_changed):
				state.faction_changed.connect(_on_faction_changed)
			if not state.catalog_reset.is_connected(_on_catalog_reset):
				state.catalog_reset.connect(_on_catalog_reset)
			if not state.planet_upgraded.is_connected(_on_planet_upgraded):
				state.planet_upgraded.connect(_on_planet_upgraded)
			if not state.technology_researched.is_connected(_on_technology_researched):
				state.technology_researched.connect(_on_technology_researched)
			if not state.worker_factory_built.is_connected(_on_worker_factory_built):
				state.worker_factory_built.connect(_on_worker_factory_built)
	_sync_groups()
	_apply_visuals()
	_planet_ready = true
	_apply_detail_seed()
	if not Engine.is_editor_hint():
		_ensure_strength_label()
		_ensure_spawn_timer.call_deferred()
	queue_redraw()

## Applies the fog-of-war visual state computed by PlanetNetwork.
## FOG planets stay rendered but are softly blended into the nebula via a
## shader and are non-interactive; the underlying network is fixed per seed.
func apply_fog(state: FogState) -> void:
	_fog_state = state
	match state:
		FogState.VISIBLE:
			visible = true
			modulate = Color.WHITE
			_apply_fog_shader(false)
			if _details != null:
				_details.visible = true
			if _strength_label != null:
				_strength_label.visible = true
			_set_click_pickable(true)
		FogState.FRONTIER:
			visible = true
			modulate = Color(0.2, 0.2, 0.3)
			_apply_fog_shader(false)
			if _details != null:
				_details.visible = false
			if _strength_label != null:
				_strength_label.visible = false
			_set_click_pickable(true)
		FogState.FOG:
			visible = true
			modulate = Color.WHITE
			_apply_fog_shader(true)
			if _details != null:
				_details.visible = false
			if _strength_label != null:
				_strength_label.visible = false
			_set_click_pickable(false)
	queue_redraw()

func get_fog_state() -> FogState:
	return _fog_state

func _apply_fog_shader(enabled: bool) -> void:
	if not is_instance_valid(_sprite):
		return
	_sprite.material = _fog_shader_material() if enabled else null

func _fog_shader_material() -> ShaderMaterial:
	if _fog_material_instance == null:
		_fog_material_instance = ShaderMaterial.new()
		_fog_material_instance.shader = FOG_SHADER
	return _fog_material_instance

func _set_click_pickable(pickable: bool) -> void:
	var click_area: Area2D = get_node_or_null("ClickArea") as Area2D
	if click_area != null:
		click_area.input_pickable = pickable

const LONG_PRESS_THRESHOLD_SEC := 0.4

var _long_press_timer: Timer = null
var _long_press_target_active: bool = false
var _long_press_consumed: bool = false
var _touch_selection_emitted: bool = false
var _touch_press_modifiers: Dictionary = {}

func _ensure_long_press_timer() -> void:
	if _long_press_timer != null and is_instance_valid(_long_press_timer):
		return
	_long_press_timer = Timer.new()
	_long_press_timer.name = "SelectionLongPressTimer"
	_long_press_timer.one_shot = true
	_long_press_timer.wait_time = LONG_PRESS_THRESHOLD_SEC
	_long_press_timer.timeout.connect(_on_long_press_timer_elapsed)
	add_child(_long_press_timer)

func _on_long_press_timer_elapsed() -> void:
	if not _long_press_target_active:
		return
	_long_press_consumed = true
	_long_press_target_active = false
	# Touch long-press counts as a toggle modifier — same semantics as shift.
	planet_selection_requested.emit(self, {"long_press": true, "shift_pressed": true, "ctrl_pressed": false, "meta_pressed": false})

func _cancel_long_press() -> void:
	_long_press_target_active = false
	if _long_press_timer != null and is_instance_valid(_long_press_timer):
		_long_press_timer.stop()

func _modifiers_for_event(event: InputEvent) -> Dictionary:
	var modifiers := {
		"shift_pressed": false,
		"ctrl_pressed": false,
		"meta_pressed": false,
		"long_press": false,
	}
	if event is InputEventWithModifiers:
		var with_mods: InputEventWithModifiers = event
		modifiers["shift_pressed"] = with_mods.shift_pressed
		modifiers["ctrl_pressed"] = with_mods.ctrl_pressed
		modifiers["meta_pressed"] = with_mods.meta_pressed
	return modifiers

func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Left press is left unhandled so the MapCamera can distinguish a
			# drag-from-planet (dispatch) from a pan on empty space.
			var modifiers := _modifiers_for_event(event)
			planet_selection_requested.emit(self, modifiers)
			planet_selected.emit(self)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			planet_context_requested.emit(self, event.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_cancel_long_press()
	elif event is InputEventScreenTouch and event.pressed:
		# Defer an unmodified tap until release so a held touch can become a
		# toggle. A long press emits exactly one modifier request at the timer
		# boundary; release then suppresses the deferred plain-click request.
		_long_press_consumed = false
		_touch_selection_emitted = false
		_touch_press_modifiers = _modifiers_for_event(event)
		var modifiers: Dictionary = _touch_press_modifiers
		if modifiers["shift_pressed"] or modifiers["ctrl_pressed"] or modifiers["meta_pressed"]:
			planet_selection_requested.emit(self, modifiers)
			planet_selected.emit(self)
			_touch_selection_emitted = true
		else:
			_ensure_long_press_timer()
			_long_press_target_active = true
			if _long_press_timer != null and is_instance_valid(_long_press_timer):
				_long_press_timer.start()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and not event.pressed:
		var long_press_handled: bool = _long_press_consumed or _touch_selection_emitted
		_cancel_long_press()
		if not long_press_handled:
			planet_selection_requested.emit(self, _touch_press_modifiers)
			planet_selected.emit(self)
		_long_press_consumed = false
		_touch_selection_emitted = false
		_touch_press_modifiers.clear()

func _on_click_area_mouse_entered() -> void:
	planet_hovered.emit(self)

func _on_click_area_mouse_exited() -> void:
	planet_unhovered.emit(self)

func _ensure_spawn_timer() -> void:
	if is_instance_valid(_spawn_timer):
		_spawn_timer.wait_time = _spawn_interval()
		return
	_spawn_timer = Timer.new()
	_spawn_timer.name = "WorkerSpawnTimer"
	_spawn_timer.wait_time = _spawn_interval()
	_spawn_timer.timeout.connect(_on_spawn_timer)
	add_child(_spawn_timer)
	_spawn_timer.stop()

func set_worker_spawn_enabled(enabled: bool) -> void:
	_worker_spawn_enabled = enabled
	_ensure_spawn_timer()
	_spawn_timer.wait_time = _spawn_interval()
	if enabled:
		_spawn_timer.start()
	else:
		_spawn_timer.stop()
	worker_production_changed.emit(self, enabled)
	_refresh_shipyard_hangar()

func is_worker_spawn_enabled() -> bool:
	return _worker_spawn_enabled

func _on_spawn_timer() -> void:
	if not _worker_spawn_enabled:
		return
	worker_state = WorkerState.SPAWNING
	workers_spawn_requested.emit(self, _spawn_count())
	worker_state = WorkerState.IDLE

func generate_economy_resources() -> int:
	if Engine.is_editor_hint() or not is_inside_tree():
		return 0
	var state: Node = _game_state()
	if state == null:
		return 0
	return state.generate_resources_for_planet(planet_id, DEFAULT_UPGRADE_CATALOG, _active_size_profile().resource_base)

func _on_catalog_reset(_catalog: PlanetCatalog) -> void:
	set_worker_spawn_enabled(false)
	var details: PlanetDetails = _details if is_instance_valid(_details) else get_node_or_null("PlanetDetails") as PlanetDetails
	if details != null:
		details.clear_upgrade_structures()

func _on_planet_upgraded(changed_planet_id: StringName, upgrade_id: StringName) -> void:
	if changed_planet_id != planet_id:
		return
	var catalog := DEFAULT_UPGRADE_CATALOG
	var upgrade := catalog.resolve(upgrade_id)
	if upgrade == null:
		return
	var details: PlanetDetails = _details if is_instance_valid(_details) else get_node_or_null("PlanetDetails") as PlanetDetails
	if details != null:
		var tint: Color = DEFAULT_TRANSFORMER_CONFIG.resolve_tint(upgrade.transformer_tint_mode, get_faction())
		details.add_upgrade_structure(upgrade, tint)
		_refresh_shipyard_hangar()

func apply_definition(definition: PlanetDefinition) -> void:
	if definition == null:
		return
	planet_id = definition.planet_id
	display_name = definition.display_name
	planet_role = definition.planet_role
	faction = definition.faction
	detail_profile = definition.detail_profile if definition.detail_profile != null else DEFAULT_DETAIL_PROFILE
	planet_texture = definition.planet_texture

func set_size_profile(profile: PlanetSizeProfile) -> void:
	size_profile = profile if profile != null else DEFAULT_SIZE_PROFILE
	layout_size = String(size_profile.id)
	_restart_spawn_timer()

func get_size_profile() -> PlanetSizeProfile:
	return size_profile if size_profile != null else DEFAULT_SIZE_PROFILE

func _active_size_profile() -> PlanetSizeProfile:
	return get_size_profile()

func _restart_spawn_timer() -> void:
	if is_instance_valid(_spawn_timer):
		_spawn_timer.wait_time = _spawn_interval()
		if _worker_spawn_enabled:
			_spawn_timer.start()
		else:
			_spawn_timer.stop()

func _spawn_interval() -> float:
	return _active_size_profile().spawn_interval

func _spawn_count() -> int:
	var count := _active_size_profile().spawn_count
	var state: Node = _game_state()
	if state != null:
		for up_id in state.get_planet_upgrades(planet_id):
			var def := DEFAULT_UPGRADE_CATALOG.resolve(up_id)
			if def != null and def.trait_definition != null:
				count += def.trait_definition.worker_spawn_bonus
	return mini(count, get_build_slot_count())

func get_build_slot_count() -> int:
	return maxi(_active_size_profile().build_slot_count, 1)

func get_perimeter_slots() -> int:
	var base: int = _active_size_profile().build_slot_count
	var bonus := 0
	var state: Node = _game_state()
	if state != null:
		for up_id in state.get_planet_upgrades(planet_id):
			var def := DEFAULT_UPGRADE_CATALOG.resolve(up_id)
			if def != null and def.trait_definition != null:
				bonus += def.trait_definition.perimeter_slots_bonus
	return maxi(1, base + bonus)

func get_defense_range() -> float:
	var base := 150.0
	var bonus := 0.0
	var state: Node = _game_state()
	if state != null:
		for up_id in state.get_planet_upgrades(planet_id):
			var def := DEFAULT_UPGRADE_CATALOG.resolve(up_id)
			if def != null and def.trait_definition != null:
				bonus += def.trait_definition.range_bonus
	return maxf(50.0, base + bonus)

func can_build_workers() -> bool:
	var state: Node = _game_state()
	if state == null:
		return false
	return state.can_build_worker_factory(planet_id, DEFAULT_SHIP_CONFIG.worker_build_cost_resource, DEFAULT_SHIP_CONFIG.worker_build_cost_amount)

func set_initial_workers(amount: int) -> void:
	if _initial_workers_applied:
		return
	worker_count = maxi(amount, 0)
	_initial_workers_applied = true
	if _planet_ready:
		worker_count_changed.emit(self, worker_count)
		_update_strength_indicator()

func resolve_arrival(source_faction: StringName, amount: int) -> StringName:
	var incoming: int = maxi(amount, 0)
	if incoming <= 0 or source_faction.is_empty() or source_faction == &"neutral":
		return ARRIVAL_REJECTED
	var destination_faction: StringName = get_faction()
	if destination_faction == source_faction:
		register_workers(incoming)
		return ARRIVAL_FRIENDLY
	var bonus_defense := 0
	var state: Node = _game_state()
	if state != null:
		for up_id in state.get_planet_upgrades(planet_id):
			var def := DEFAULT_UPGRADE_CATALOG.resolve(up_id)
			if def != null and def.trait_definition != null:
				bonus_defense += def.trait_definition.defense_rating
	var defenders: int = worker_count + bonus_defense
	if incoming <= defenders:
		unregister_workers(mini(incoming, worker_count))
		return ARRIVAL_REPELLED
	unregister_workers(worker_count)
	set_faction(source_faction)
	register_workers(incoming - defenders)
	return ARRIVAL_CAPTURED

## Spawns the "+N" landing label above this planet for an arrival that landed
## workers or ships. No-op for non-positive amounts and outside the tree.
func show_arrival_feedback(amount: int, faction: StringName) -> void:
	if amount <= 0 or not is_inside_tree():
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	var tint: Color = DEFAULT_TRANSFORMER_CONFIG.resolve_tint(&"faction", faction)
	FloatingText.spawn(parent, "+%d" % amount, position, tint)

# Number of surviving attackers registered as workers on a captured planet when
# the result comes from a fleet-vs-fleet FleetBattleSimulator outcome. The
# simulator returns surviving ships (not workers); we convert ships to workers
# at this fixed rate so capture always produces a measurable garrison on the
# destination. ConquestSimulator already operates on workers directly.
const _CAPTURED_WORKER_PER_SHIP := 10

## Resolves an incoming FleetSnapshot (assembled ships) through the existing
## deterministic FleetBattleSimulator (fleet-vs-fleet) and ConquestSimulator
## (fleet-vs-ground) – the worker-count MVP rule in resolve_arrival() stays for
## pure-worker transit.
##
## defender_fleet: non-null with ships → FleetBattleSimulator; null/empty →
## ConquestSimulator using this planet's defenders.
##
## Returns a Dictionary with `result` (ARRIVAL_*), `surviving_attackers` (int)
## and `duration` (float). Side effects when captured: set_faction(
## attacking_faction) and register_workers(survivor_count).
func resolve_ship_arrival(arriving_fleet: FleetSnapshot, defender_fleet: FleetSnapshot = null, battle_seed: int = 1337, conquest_seed: int = 42, ship_role: StringName = &"") -> Dictionary:
	var out: Dictionary = {"result": ARRIVAL_REJECTED, "surviving_attackers": 0, "duration": 0.0}
	if arriving_fleet == null or arriving_fleet.ships.is_empty():
		return out
	var attacking_faction: StringName = arriving_fleet.faction
	if String(attacking_faction).is_empty() or attacking_faction == GameState.FACTION_NEUTRAL:
		return out
	var resolved_role: StringName = ship_role if not String(ship_role).is_empty() else arriving_fleet.mission_role
	if resolved_role == &"colony":
		return _resolve_colony_ship_arrival(arriving_fleet, attacking_faction, out)
	var defending_faction: StringName = get_faction()
	if defending_faction == attacking_faction:
		out["result"] = ARRIVAL_FRIENDLY
		var gain: int = arriving_fleet.ships.size() * _CAPTURED_WORKER_PER_SHIP
		if gain > 0:
			register_workers(gain)
		out["surviving_attackers"] = gain
		return out
	if defender_fleet != null and not defender_fleet.ships.is_empty():
		return _resolve_ship_vs_fleet(arriving_fleet, defender_fleet, battle_seed, attacking_faction, out)
	return _resolve_ship_vs_planet(arriving_fleet, conquest_seed, attacking_faction, out)


func _resolve_ship_vs_fleet(arriving_fleet: FleetSnapshot, defender_fleet: FleetSnapshot, battle_seed: int, attacking_faction: StringName, out: Dictionary) -> Dictionary:
	var battle: Dictionary = FleetBattleSimulator.simulate_battle(arriving_fleet, defender_fleet, battle_seed)
	var winner: StringName = battle.get("winner", &"neutral") as StringName
	var survivors: Array = battle.get("survivors_a", [])
	var defender_survivors: Array = battle.get("survivors_b", [])
	var state: Node = _game_state()
	if state != null:
		state.reconcile_defender_fleet(planet_id, defender_fleet, [] if winner == attacking_faction else defender_survivors)
	if winner == attacking_faction:
		unregister_workers(worker_count)
		set_faction(attacking_faction)
		var gain: int = survivors.size() * _CAPTURED_WORKER_PER_SHIP
		if gain > 0:
			register_workers(gain)
		out["result"] = ARRIVAL_CAPTURED
		out["surviving_attackers"] = gain
	else:
		out["result"] = ARRIVAL_REPELLED
	out["duration"] = float(battle.get("duration", 0.0))
	return out


func _resolve_colony_ship_arrival(arriving_fleet: FleetSnapshot, attacking_faction: StringName, out: Dictionary) -> Dictionary:
	var state: Node = _game_state()
	if get_faction() != GameState.FACTION_NEUTRAL or state == null or not state.has_scanned_planet(attacking_faction, planet_id):
		out["result"] = ARRIVAL_REJECTED
		return out
	var settlers: int = maxi(arriving_fleet.ships.size() * 10, 1)
	set_faction(attacking_faction)
	register_workers(settlers)
	out["result"] = ARRIVAL_SETTLED
	out["surviving_attackers"] = settlers
	return out


func _resolve_ship_vs_planet(arriving_fleet: FleetSnapshot, conquest_seed: int, attacking_faction: StringName, out: Dictionary) -> Dictionary:
	var defender_workers: int = worker_count
	var defense_rating := _aggregate_defense_rating()
	var conquest: Dictionary = ConquestSimulator.simulate_conquest(
		arriving_fleet, 0, defender_workers, defense_rating,
		get_perimeter_slots(), get_defense_range(), conquest_seed)
	if bool(conquest.get("captured", false)):
		unregister_workers(worker_count)
		set_faction(attacking_faction)
		var gain: int = int(conquest.get("surviving_attackers", 0))
		if gain > 0:
			register_workers(gain)
		out["result"] = ARRIVAL_CAPTURED
		out["surviving_attackers"] = gain
	else:
		out["result"] = ARRIVAL_REPELLED
	out["duration"] = float(conquest.get("duration", 0.0))
	return out


func _aggregate_defense_rating() -> int:
	var total := 0
	var state: Node = _game_state()
	if state == null:
		return total
	for up_id in state.get_planet_upgrades(planet_id):
		var def := DEFAULT_UPGRADE_CATALOG.resolve(up_id)
		if def != null and def.trait_definition != null:
			total += def.trait_definition.defense_rating
	return total

func resolve_mission(source_faction: StringName, amount: int, mission_type: StringName = &"military", source_planet_id: StringName = &"") -> StringName:
	if mission_type == GameState.MISSION_COLONY:
		return _resolve_colony(source_faction, amount)
	if mission_type == GameState.MISSION_CARGO:
		return _resolve_cargo(source_faction, amount)
	if mission_type == GameState.MISSION_COLLECT:
		return _resolve_collect(source_faction, amount, source_planet_id)
	return resolve_military_arrival(source_faction, amount, source_planet_id)

## Resolves a military arrival by drafting the source planet's assembled ships into
## a FleetSnapshot (create_fleet_from_planet) and running the deterministic
## FleetBattleSimulator (fleet-vs-fleet) or ConquestSimulator (fleet-vs-ground)
## through resolve_ship_arrival(). When the source carries no assembled ships the
## legacy worker-count rule in resolve_arrival() handles pure-worker transit.
func resolve_military_arrival(source_faction: StringName, amount: int, source_planet_id: StringName = &"") -> StringName:
	var state: Node = _game_state()
	var attacking_fleet: FleetSnapshot = _build_fleet_from_assemblies(state, source_planet_id, true)
	if attacking_fleet != null and not attacking_fleet.ships.is_empty():
		var defender_fleet: FleetSnapshot = _build_fleet_from_assemblies(state, planet_id, false)
		var result: Dictionary = resolve_ship_arrival(attacking_fleet, defender_fleet)
		return result.get(&"result", ARRIVAL_REJECTED) as StringName
	return resolve_arrival(source_faction, amount)


func _build_fleet_from_assemblies(state: Node, target_planet_id: StringName, consume: bool) -> FleetSnapshot:
	if state == null or String(target_planet_id).is_empty():
		return null
	var assemblies: Dictionary = state.get_ship_assemblies(target_planet_id)
	if assemblies.is_empty():
		return null
	var ship_ids: Array = assemblies.keys()
	if consume:
		return state.create_fleet_from_planet(target_planet_id, ship_ids) as FleetSnapshot
	return state.preview_fleet_from_planet(target_planet_id, ship_ids) as FleetSnapshot

func _resolve_colony(source_faction: StringName, amount: int) -> StringName:
	var incoming: int = maxi(amount, 0)
	if incoming <= 0 or source_faction.is_empty() or source_faction == GameState.FACTION_NEUTRAL:
		return ARRIVAL_REJECTED
	if get_faction() != GameState.FACTION_NEUTRAL:
		return ARRIVAL_REJECTED
	set_faction(source_faction)
	register_workers(incoming)
	return ARRIVAL_SETTLED

func _resolve_cargo(source_faction: StringName, amount: int) -> StringName:
	var incoming: int = maxi(amount, 0)
	if incoming <= 0 or source_faction.is_empty() or source_faction == GameState.FACTION_NEUTRAL:
		return ARRIVAL_REJECTED
	if get_faction() != source_faction:
		return ARRIVAL_REJECTED
	register_workers(incoming)
	return ARRIVAL_FRIENDLY

func _resolve_collect(source_faction: StringName, amount: int, source_planet_id: StringName = &"") -> StringName:
	var incoming: int = maxi(amount, 0)
	if incoming <= 0 or source_faction.is_empty() or source_faction == GameState.FACTION_NEUTRAL:
		return ARRIVAL_REJECTED
	if get_faction() != GameState.FACTION_NEUTRAL:
		return ARRIVAL_REJECTED
	var state: Node = _game_state()
	if state == null:
		return ARRIVAL_REJECTED
	var registered: int = state.register_gathering_workers(source_faction, planet_id, incoming, source_planet_id)
	if registered <= 0:
		return ARRIVAL_REJECTED
	return ARRIVAL_COLLECTED

func recall_gathering_workers(target_faction: StringName, amount: int) -> int:
	var state: Node = _game_state()
	if state == null:
		return 0
	var source_id: StringName = state.get_gathering_source(target_faction, planet_id) as StringName
	var withdrawn: int = state.withdraw_gathering_workers(target_faction, planet_id, amount)
	if withdrawn <= 0:
		return 0
	if String(source_id).is_empty():
		return withdrawn
	var field: Node = get_parent()
	if field == null:
		return withdrawn
	for child in field.get_children():
		var candidate := child as Planet
		if candidate != null and candidate.planet_id == source_id:
			candidate.register_workers(withdrawn)
			break
	return withdrawn

func get_transfer_speed_multiplier() -> float:
	var state: Node = _game_state()
	if state == null:
		return 1.0
	var multiplier := 1.0
	for up_id in state.get_planet_upgrades(planet_id):
		var def := DEFAULT_UPGRADE_CATALOG.resolve(up_id)
		if def != null and def.trait_definition != null:
			multiplier *= def.trait_definition.transfer_speed_multiplier
	return multiplier

func get_cluster_tier_bonus() -> int:
	var state: Node = _game_state()
	if state == null:
		return 0
	var bonus := 0
	for up_id in state.get_planet_upgrades(planet_id):
		var def := DEFAULT_UPGRADE_CATALOG.resolve(up_id)
		if def != null and def.trait_definition != null:
			bonus += def.trait_definition.cluster_tier_bonus
	return maxi(bonus, 0)

func register_workers(amount: int) -> void:
	worker_count += maxi(amount, 0)
	worker_count_changed.emit(self, worker_count)
	_update_strength_indicator()

func unregister_workers(amount: int) -> void:
	worker_count = maxi(0, worker_count - maxi(amount, 0))
	worker_count_changed.emit(self, worker_count)
	_update_strength_indicator()

func _sync_groups() -> void:
	add_to_group(StringName("planet_" + String(planet_id)))
	add_to_group(_faction_group(get_faction()))
	add_to_group(_role_group(planet_role))

func _on_technology_researched(changed_faction: StringName, _technology_id: StringName) -> void:
	if changed_faction == get_faction():
		_refresh_shipyard_hangar()

func _on_worker_factory_built(changed_planet_id: StringName) -> void:
	if changed_planet_id != planet_id:
		return
	set_worker_spawn_enabled(true)

func _on_faction_changed(changed_planet_id: StringName, _old_faction: StringName, new_faction: StringName) -> void:
	if changed_planet_id == planet_id:
		remove_from_group(_faction_group(faction))
		faction = new_faction
		add_to_group(_faction_group(faction))
		queue_redraw()
		_update_strength_indicator()

func _apply_visuals() -> void:
	if not is_instance_valid(_sprite):
		return
	_sprite.texture = planet_texture
	_sprite.scale = Vector2.ONE * visual_scale
	queue_redraw()

func _process(_delta: float) -> void:
	if _strength_label != null and is_instance_valid(_strength_label):
		var desired_scale := 1.0 / maxf(scale.x, 0.001)
		if not is_equal_approx(_strength_label.scale.x, desired_scale):
			_strength_label.scale = Vector2.ONE * desired_scale

func set_selected(selected: bool) -> void:
	if _selected == selected:
		return
	_selected = selected
	queue_redraw()

func is_selected() -> bool:
	return _selected

func _draw() -> void:
	if Engine.is_editor_hint():
		return

	var state: Node = _game_state()
	if state != null and not state.is_known(planet_id, GameState.FACTION_PLAYER):
		return

	var ring_radius: float = _faction_ring_radius()
	PlanetView.draw_planet_rings(self, ring_radius, get_faction(), _selected, DEFAULT_TRANSFORMER_CONFIG)

func _faction_ring_radius() -> float:
	return PlanetView.calculate_faction_ring_radius(_sprite, DEFAULT_TRANSFORMER_CONFIG)

func _ensure_strength_label() -> void:
	if _strength_label != null and is_instance_valid(_strength_label):
		return
	_strength_label = Label.new()
	_strength_label.name = "StrengthLabel"
	PlanetView.setup_strength_label(_strength_label, DEFAULT_TRANSFORMER_CONFIG)
	add_child(_strength_label)
	_update_strength_indicator()

func _update_strength_indicator() -> void:
	if _strength_label == null or not is_instance_valid(_strength_label):
		return
	PlanetView.update_strength_label(_strength_label, worker_count, get_faction(), _faction_ring_radius(), scale.x, DEFAULT_TRANSFORMER_CONFIG)

func _faction_group(value: StringName) -> StringName:
	return StringName("faction_" + String(value))

func _role_group(value: StringName) -> StringName:
	return StringName("planet_role_" + String(value))

func get_faction() -> StringName:
	var state: Node = _game_state()
	if state != null:
		return state.faction_of(planet_id) as StringName
	return faction

func get_resource_id() -> StringName:
	var state: Node = _game_state()
	if state != null:
		return state.resource_of(planet_id) as StringName
	return &""

func set_faction(value: StringName) -> void:
	faction = value

func _refresh_shipyard_hangar() -> void:
	var details: PlanetDetails = _details if is_instance_valid(_details) else get_node_or_null("PlanetDetails") as PlanetDetails
	if details != null:
		details.refresh_shipyard_hangar()

func _game_state() -> Node:
	return GameStateAccess.autoload(self)

func set_planet_role(value: StringName) -> void:
	planet_role = value

func set_detail_seed(value: int) -> void:
	_detail_seed = value
	if _planet_ready:
		_apply_detail_seed()

func _apply_detail_seed() -> void:
	var details: PlanetDetails = _details if is_instance_valid(_details) else get_node_or_null("PlanetDetails") as PlanetDetails
	if details != null:
		details.set_seed(_detail_seed)

func set_group_enabled(enabled: bool) -> void:
	visible = enabled
	process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
