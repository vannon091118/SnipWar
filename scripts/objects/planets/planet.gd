@tool
class_name Planet
extends Node2D

const DEFAULT_SIZE_PROFILE: PlanetSizeProfile = preload("res://resources/config/planet_sizes/variable.tres")
const DEFAULT_DETAIL_PROFILE: PlanetDetailProfile = preload("res://resources/config/planet_details/default.tres")
const DEFAULT_SHIP_CONFIG: ShipConfig = preload("res://resources/config/ship_default.tres")
const DEFAULT_BUILDING_CATALOG: BuildingCatalog = preload("res://resources/config/building_catalog_default.tres")

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
## Emitted after a deterministic fleet/planet simulation produces a replayable
## result. ConflictManager consumes this handoff; Planet remains the authority
## that commits ownership and worker state.
signal conflict_simulated(simulation_type: StringName, replay: CombatReplay)
signal building_destroyed(planet_id: StringName, q: int, r: int)
signal planet_neutralized(planet_id: StringName)
signal planet_neutralization_expired(planet_id: StringName)

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
## Composition fields (set by configure_from_cache for procedural planets).
@export var composition_base_texture: Texture2D
@export var composition_tint: Color = Color.WHITE
@export var composition_decal_textures: Array[Texture2D] = []
var _composition_decals: Node2D
var _spawn_timer: Timer
var _detail_seed := 0
var _planet_ready := false
var _initial_workers_applied := false
var _strength_label: Label
var _selected: bool = false
var _fog_material_instance: ShaderMaterial
var _fog_state: FogState = FogState.VISIBLE
var _grid: PlanetGrid
var _neutralization_timer: Timer
var _is_neutralized := false

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
			if not state.resource_generated.is_connected(_on_resource_generated):
				state.resource_generated.connect(_on_resource_generated)
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
			if _composition_decals != null:
				_composition_decals.visible = true
			if _strength_label != null:
				_strength_label.visible = true
			_set_click_pickable(true)
		FogState.FRONTIER:
			visible = true
			modulate = Color(0.2, 0.2, 0.3)
			_apply_fog_shader(false)
			if _details != null:
				_details.visible = false
			if _composition_decals != null:
				_composition_decals.visible = true
			if _strength_label != null:
				_strength_label.visible = false
			_set_click_pickable(true)
		FogState.FOG:
			visible = true
			modulate = Color.WHITE
			_apply_fog_shader(true)
			if _details != null:
				_details.visible = false
			if _composition_decals != null:
				_composition_decals.visible = false
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
	workers_spawn_requested.emit(self, PlanetTraitAggregator.get_spawn_count(self))
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
	composition_base_texture = definition.composition_base_texture
	composition_tint = definition.composition_tint
	composition_decal_textures = definition.composition_decal_textures.duplicate()
	planet_texture = definition.planet_texture
	_apply_visuals()

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

func get_build_slot_count() -> int:
	return PlanetTraitAggregator.get_build_slot_count(self)

func get_perimeter_slots() -> int:
	return PlanetTraitAggregator.get_perimeter_slots(self)

func get_defense_range() -> float:
	return PlanetTraitAggregator.get_defense_range(self)

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
	return PlanetArrivalResolver.resolve_arrival(self, source_faction, amount)

## Spawns the "+N" landing label above this planet for an arrival that landed
## workers or ships. No-op for non-positive amounts and outside the tree.
func show_arrival_feedback(amount: int, arriving_faction: StringName) -> void:
	if amount <= 0 or not is_inside_tree():
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	var tint: Color = DEFAULT_TRANSFORMER_CONFIG.resolve_tint(&"faction", arriving_faction)
	FloatingText.spawn(parent, "+%d" % amount, position, tint)

func resolve_ship_arrival(arriving_fleet: FleetSnapshot, defender_fleet: FleetSnapshot = null, battle_seed: int = 1337, conquest_seed: int = 42, ship_role: StringName = &"") -> Dictionary:
	return PlanetArrivalResolver.resolve_ship_arrival(self, arriving_fleet, defender_fleet, battle_seed, conquest_seed, ship_role)

func resolve_mission(source_faction: StringName, amount: int, mission_type: StringName = &"military", source_planet_id: StringName = &"") -> StringName:
	return PlanetArrivalResolver.resolve_mission(self, source_faction, amount, mission_type, source_planet_id)

func resolve_military_arrival(source_faction: StringName, amount: int, _source_planet_id: StringName = &"", conquest_seed: int = 42) -> StringName:
	return PlanetArrivalResolver.resolve_military_arrival(self, source_faction, amount, _source_planet_id, conquest_seed)

func recall_gathering_workers(target_faction: StringName, amount: int) -> int:
	return PlanetArrivalResolver.recall_gathering_workers(self, target_faction, amount)

func get_transfer_speed_multiplier() -> float:
	return PlanetTraitAggregator.get_transfer_speed_multiplier(self)

func get_cluster_tier_bonus() -> int:
	return PlanetTraitAggregator.get_cluster_tier_bonus(self)

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

func _on_resource_generated(changed_planet_id: StringName, resource_id: StringName, amount: int) -> void:
	if changed_planet_id != planet_id or amount <= 0 or get_faction() != GameState.FACTION_PLAYER:
		return
	var parent: Node = get_parent()
	if parent == null or not is_inside_tree():
		return
	var resource_definition: GameResource = GameState.DEFAULT_RESOURCE_POOL.resource_for(resource_id)
	var resource_name: String = resource_definition.display_name if resource_definition != null and not resource_definition.display_name.is_empty() else String(resource_id)
	var tint: Color = DEFAULT_TRANSFORMER_CONFIG.resolve_tint(&"resource", resource_id)
	FloatingText.spawn(parent, "+%d %s" % [amount, resource_name], position, tint, 1.2)

func _on_faction_changed(changed_planet_id: StringName, old_faction: StringName, new_faction: StringName) -> void:
	if changed_planet_id == planet_id:
		# The setter already flipped `faction` before this signal fired, so the
		# old group must come from `old_faction`, not the already-updated field.
		remove_from_group(_faction_group(old_faction))
		faction = new_faction
		add_to_group(_faction_group(new_faction))
		queue_redraw()
		_update_strength_indicator()

func _apply_visuals() -> void:
	if not is_instance_valid(_sprite):
		return
	if composition_base_texture != null:
		_sprite.texture = composition_base_texture
		_sprite.modulate = composition_tint
		_sprite.scale = Vector2.ONE * visual_scale
	else:
		_sprite.texture = planet_texture
		_sprite.scale = Vector2.ONE * visual_scale
	_rebuild_composition_decals()
	queue_redraw()

func _rebuild_composition_decals() -> void:
	if not is_instance_valid(_sprite):
		return
	if _composition_decals == null or not is_instance_valid(_composition_decals):
		_composition_decals = Node2D.new()
		_composition_decals.name = "CompositionDecals"
		_composition_decals.z_index = 1
		add_child(_composition_decals)
	else:
		for child in _composition_decals.get_children():
			_composition_decals.remove_child(child)
			child.queue_free()
	for texture in composition_decal_textures:
		if texture == null:
			continue
		var decal := Sprite2D.new()
		decal.texture = texture
		decal.modulate = composition_tint
		decal.scale = Vector2.ONE * visual_scale
		_composition_decals.add_child(decal)

## Configures a procedural planet from cached chunk data (not from a
## PlanetDefinition). This is the counterpart to apply_definition() for
## planets generated by ChunkCoordinator.
##
## Must be called BEFORE add_child() so _ready() registers the real planet_id
## and faction and applies the correct detail/size profiles. The caller
## (ChunkCoordinator) resolves the size profile, since the parent lookup does
## not exist yet before the node enters the tree.
func configure_from_cache(data, size_profile: PlanetSizeProfile = null) -> void:
	PlanetProcedural.configure_from_cache(self, data, size_profile)

## Returns the FoV radius (in chunk cells) this planet provides for the owning
## faction. Base radius + fov_radius_bonus from upgrades.
func get_fov_radius() -> int:
	var field: Node = get_parent()
	var config: WorldConfig = field.get("world_config") if field != null else null
	return PlanetProcedural.fov_radius(self, config, _game_state())

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

# --- SECTOR META (density-field classification) ---

func get_sector_role() -> StringName:
	return get_meta("sector_role", &"void") as StringName

func get_sector_id() -> StringName:
	return get_meta("sector_id", &"") as StringName

func get_sector_depth() -> float:
	return float(get_meta("sector_depth", 0.0))

# --- HEX/RECT GRID & BUILDINGS ---

func get_grid() -> PlanetGrid:
	if _grid != null and is_instance_valid(_grid):
		return _grid
	_grid = PlanetGrid.new()
	_grid.name = "PlanetGrid"
	var profile := get_size_profile()
	var config: PlanetGridConfig = profile.grid_config if profile != null and profile.grid_config != null else PlanetGridConfig.new()
	_grid.configure(config, DEFAULT_BUILDING_CATALOG)
	if is_inside_tree() and not Engine.is_editor_hint():
		add_child(_grid)
	return _grid

# --- LOCAL RESOURCES ---

func get_local_resources() -> Dictionary:
	var state: Node = _game_state()
	if state != null and state.has_method("get_local_resources"):
		return state.get_local_resources(planet_id)
	return {}

func can_afford_local(costs: Dictionary) -> bool:
	var state: Node = _game_state()
	if state == null or not state.has_method("can_spend_local_resource"):
		return costs.is_empty()
	for resource_id in costs:
		var amount: int = int(costs[resource_id])
		if amount > 0 and not state.can_spend_local_resource(planet_id, resource_id as StringName, amount):
			return false
	return true

# --- DEFENSE SNAPSHOT / BASE HP ---

func get_defense_snapshot() -> Dictionary:
	var snapshot := {
		"planet_id": planet_id,
		"base_hp": get_base_hp(),
		"garrison": worker_count,
		"buildings": [],
	}
	var grid := get_grid()
	if grid != null:
		for cell in grid.building_cells():
			snapshot["buildings"].append({
				"q": cell.axial_q,
				"r": cell.axial_r,
				"building_id": cell.building.id,
				"hp": cell.current_hp,
			})
	return snapshot

func get_base_hp() -> int:
	var grid := get_grid()
	return grid.base_hp() if grid != null else 0

func damage_base(amount: int) -> void:
	if amount <= 0:
		return
	var grid := get_grid()
	if grid == null:
		return
	var remaining := amount
	for cell in grid.building_cells():
		if remaining <= 0:
			break
		var dealt := mini(cell.current_hp, remaining)
		cell.current_hp -= dealt
		remaining -= dealt
		if cell.current_hp <= 0:
			var q := cell.axial_q
			var r := cell.axial_r
			grid.remove_building(q, r)
			var state: Node = _game_state()
			if state != null and state.has_method("remove_planet_building"):
				state.remove_planet_building(planet_id, q, r)
			building_destroyed.emit(planet_id, q, r)
	grid.queue_redraw()

# --- NEUTRALIZATION ---

func neutralize(duration: float = 600.0) -> void:
	_is_neutralized = true
	if _neutralization_timer == null or not is_instance_valid(_neutralization_timer):
		_neutralization_timer = Timer.new()
		_neutralization_timer.name = "NeutralizationTimer"
		_neutralization_timer.one_shot = true
		_neutralization_timer.timeout.connect(_on_neutralization_expired)
		if is_inside_tree():
			add_child(_neutralization_timer)
	_neutralization_timer.start(maxf(duration, 0.1))
	planet_neutralized.emit(planet_id)

func is_neutralized() -> bool:
	return _is_neutralized

func _on_neutralization_expired() -> void:
	_is_neutralized = false
	planet_neutralization_expired.emit(planet_id)
