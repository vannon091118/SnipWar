@tool
class_name Planet
extends Node2D

const DEFAULT_SIZE_PROFILE: PlanetSizeProfile = preload("res://resources/config/planet_sizes/variable.tres")
const DEFAULT_DETAIL_PROFILE: PlanetDetailProfile = preload("res://resources/config/planet_details/default.tres")

signal planet_selected(planet: Node2D)
signal workers_spawn_requested(planet: Node2D, amount: int)
signal worker_count_changed(planet: Node2D, count: int)

enum WorkerState { IDLE, SPAWNING }

const ARRIVAL_FRIENDLY := &"friendly"
const ARRIVAL_REPELLED := &"repelled"
const ARRIVAL_CAPTURED := &"captured"
const ARRIVAL_REJECTED := &"rejected"
const ARRIVAL_SETTLED := &"settled"

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
var _spawn_timer: Timer
var _detail_seed := 0
var _planet_ready := false
var _initial_workers_applied := false

const DEFAULT_UPGRADE_CATALOG: PlanetUpgradeCatalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")
const DEFAULT_TRANSFORMER_CONFIG: TransformerConfig = preload("res://resources/config/transformer_default.tres")

func _ready() -> void:
	$ClickArea.input_event.connect(_on_click_area_input_event)
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
	_sync_groups()
	_apply_visuals()
	_planet_ready = true
	_apply_detail_seed()
	if not Engine.is_editor_hint():
		_start_spawn_timer.call_deferred()

func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		planet_selected.emit(self)

func _start_spawn_timer() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = _spawn_interval()
	_spawn_timer.timeout.connect(_on_spawn_timer)
	add_child(_spawn_timer)
	_spawn_timer.start()

func _on_spawn_timer() -> void:
	worker_state = WorkerState.SPAWNING
	workers_spawn_requested.emit(self, _spawn_count())
	var state: Node = _game_state()
	if state != null and is_inside_tree() and not Engine.is_editor_hint():
		state.generate_resources_for_planet(planet_id, DEFAULT_UPGRADE_CATALOG, _active_size_profile().resource_base)
	worker_state = WorkerState.IDLE

func _on_catalog_reset(_catalog: PlanetCatalog) -> void:
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
		_spawn_timer.start()

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
	return count

func set_initial_workers(amount: int) -> void:
	if _initial_workers_applied:
		return
	worker_count = maxi(amount, 0)
	_initial_workers_applied = true
	if _planet_ready:
		worker_count_changed.emit(self, worker_count)

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

func resolve_mission(source_faction: StringName, amount: int, mission_type: StringName = &"military") -> StringName:
	if mission_type == GameState.MISSION_COLONY:
		return _resolve_colony(source_faction, amount)
	if mission_type == GameState.MISSION_CARGO:
		return _resolve_cargo(source_faction, amount)
	return resolve_arrival(source_faction, amount)

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

func unregister_workers(amount: int) -> void:
	worker_count = maxi(0, worker_count - maxi(amount, 0))
	worker_count_changed.emit(self, worker_count)

func _sync_groups() -> void:
	add_to_group(StringName("planet_" + String(planet_id)))
	add_to_group(_faction_group(get_faction()))
	add_to_group(_role_group(planet_role))

func _on_faction_changed(changed_planet_id: StringName, _old_faction: StringName, new_faction: StringName) -> void:
	if changed_planet_id == planet_id:
		remove_from_group(_faction_group(faction))
		faction = new_faction
		add_to_group(_faction_group(faction))

func _apply_visuals() -> void:
	if not is_instance_valid(_sprite):
		return
	_sprite.texture = planet_texture
	_sprite.scale = Vector2.ONE * visual_scale

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

func _game_state() -> Node:
	if Engine.is_editor_hint() or not is_inside_tree():
		return null
	var root_node: Node = get_tree().root
	if root_node == null:
		return null
	return root_node.get_node_or_null("GameState")

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
