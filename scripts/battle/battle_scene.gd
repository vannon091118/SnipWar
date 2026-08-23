@tool
class_name BattleScene
extends CanvasLayer

signal battle_completed(replay: CombatReplay)

const DEFAULT_SHIP_PART_CATALOG: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")
const PAPER_OUTLINE_SHADER: Shader = preload("res://assets/shaders/paper_outline.gdshader")
const DEFAULT_PAPER_STYLE: PaperStyleConfig = preload("res://resources/config/paper_style_default.tres")

var playback_speed: float = 1.0
var _events: Array[BattleEvent] = []
var _current_result: CombatReplay
## Deterministic cosmetics RNG, seeded from the replay's battle_seed so replay
## visuals match the simulation instead of using global randf_range().
var _fx_rng := RandomNumberGenerator.new()
var _ships: Dictionary = {} # id -> CompositeShipView
var _ship_initial_data: Dictionary = {}
var _elapsed: float = 0.0
var _event_index: int = 0
var _is_playing: bool = false
var _total_duration: float = 0.0

var _viewport_container: Control
var _arena: Node2D
var _status_label: Label
var _player_controls: IngamePlayerControls
var _phase_label: Label
var _route_nodes: Array[Line2D] = []
var _route_offset := Vector2.ZERO
var _engagement_time: float = 0.0
var _pending_context: BattleContext

func _ready() -> void:
	layer = 80
	_build_ui()
	call_deferred("_boot_pending_battle")

func _build_ui() -> void:
	if _viewport_container != null:
		return
	_viewport_container = Control.new()
	_viewport_container.name = "RootControl"
	_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_viewport_container)

	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.02, 0.04, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport_container.add_child(bg)

	_arena = Node2D.new()
	_arena.name = "Arena"
	_arena.position = Vector2(480.0, 240.0)
	_viewport_container.add_child(_arena)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = "⚡ FLOTTEN-GEFECHT SIMULATION"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.position = Vector2(240.0, 16.0)
	_status_label.size = Vector2(480.0, 28.0)
	_status_label.add_theme_font_size_override("font_size", 16)
	_viewport_container.add_child(_status_label)

	_phase_label = Label.new()
	_phase_label.name = "PhaseLabel"
	_phase_label.text = "APPROACH"
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.position = Vector2(340.0, 44.0)
	_phase_label.size = Vector2(280.0, 22.0)
	_phase_label.add_theme_font_size_override("font_size", 11)
	_viewport_container.add_child(_phase_label)

	_player_controls = IngamePlayerControls.new()
	_player_controls.name = "PlayerControls"
	_player_controls.position = Vector2(200.0, 480.0)
	_player_controls.play_toggled.connect(_on_play_toggled)
	_player_controls.seek_requested.connect(_on_seek_requested)
	_player_controls.speed_changed.connect(_on_speed_changed)
	_player_controls.skip_pressed.connect(_on_skip_pressed)
	_viewport_container.add_child(_player_controls)

func _boot_pending_battle() -> void:
	var state: Node = get_node_or_null("/root/GameState")
	if state == null or not state.has_method("pending_battle_context"):
		return
	var context: BattleContext = state.pending_battle_context()
	if context == null or context.replay == null:
		return
	_pending_context = context
	if not battle_completed.is_connected(_on_pending_battle_completed):
		battle_completed.connect(_on_pending_battle_completed)
	play_battle(context.replay)

func _on_pending_battle_completed(_replay: CombatReplay) -> void:
	if _pending_context == null:
		return
	var cycle: Node = get_node_or_null("/root/GameCycleManager")
	if cycle != null and cycle.has_method("apply_battle_result"):
		cycle.call("apply_battle_result", _pending_context)

func play_battle(replay: CombatReplay) -> void:
	_ensure_ui()
	if replay == null or not replay.is_battle():
		return
	_current_result = replay
	_fx_rng.seed = replay.battle_seed
	_events = replay.events
	_total_duration = replay.duration
	_engagement_time = replay.engagement_time_a if replay.engagement_time_a > 0.0 else _total_duration * 0.35
	_route_offset = Vector2.ZERO
	if not replay.route_a.is_empty() and not replay.route_b.is_empty():
		_route_offset = Vector2(480.0, 270.0) - replay.engagement_point
	_event_index = 0
	_elapsed = 0.0
	_is_playing = true
	visible = true

	_player_controls.setup(_total_duration)
	_clear_arena()
	_cache_spawn_data()
	_draw_routes(replay)

func _ensure_ui() -> void:
	if _viewport_container == null:
		_build_ui()

func _clear_arena() -> void:
	for child in _arena.get_children():
		child.queue_free()
	_route_nodes.clear()
	_ships.clear()

func _draw_routes(replay: CombatReplay) -> void:
	if replay == null:
		return
	for route_data in [replay.route_a, replay.route_b]:
		if route_data.size() < 2:
			continue
		var line := Line2D.new()
		line.width = 1.5
		line.default_color = Color(0.2, 0.55, 0.85, 0.4) if _route_nodes.is_empty() else Color(0.9, 0.3, 0.3, 0.4)
		var points := PackedVector2Array()
		for point in route_data:
			points.append(point + _route_offset)
		line.points = points
		_arena.add_child(line)
		_route_nodes.append(line)
	if replay.engagement_point != Vector2.ZERO:
		var marker := Sprite2D.new()
		marker.name = "EngagementPoint"
		marker.position = replay.engagement_point + _route_offset
		marker.scale = Vector2.ONE * 0.3
		marker.modulate = Color(1.0, 0.75, 0.2, 0.85)
		marker.texture = preload("res://assets/objects/workers/worker_unit.svg")
		_arena.add_child(marker)

func _cache_spawn_data() -> void:
	_ship_initial_data.clear()
	for ev in _events:
		if ev.event_type == BattleEvent.TYPE_SPAWN:
			_ship_initial_data[ev.source_id] = {
				"pos": ev.source_pos,
				"hp": ev.value,
				"ship_data": ev.ship_data.copy() if ev.ship_data != null else null
			}

func _process(delta: float) -> void:
	if not _is_playing:
		return

	_elapsed += delta * playback_speed
	_player_controls.set_progress(_elapsed)
	if _phase_label != null:
		if _elapsed < maxf(_engagement_time - 1.0, 0.0):
			_phase_label.text = "APPROACH"
		elif _elapsed < _engagement_time + 1.0:
			_phase_label.text = "ENGAGEMENT"
		elif _elapsed < _total_duration - 0.8:
			_phase_label.text = "CLIMAX"
		else:
			_phase_label.text = "RESOLUTION"

	while _event_index < _events.size():
		var event: BattleEvent = _events[_event_index]
		if event.timestamp <= _elapsed:
			_process_event(event)
			_event_index += 1
		else:
			break

	if _event_index >= _events.size() and _elapsed >= _total_duration + 0.8:
		_finish_battle()

func _process_event(event: BattleEvent) -> void:
	match event.event_type:
		BattleEvent.TYPE_SPAWN:
			_spawn_ship_visual(event.source_id, event.source_pos + _route_offset, event.ship_data)
		BattleEvent.TYPE_FIRE:
			_animate_fire(event.source_id, event.source_pos + _route_offset, event.target_pos + _route_offset)
		BattleEvent.TYPE_HIT:
			_animate_hit(event.target_id, event.target_pos + _route_offset, event.value)
		BattleEvent.TYPE_DESTROYED:
			_animate_destruction(event.source_id, event.source_pos + _route_offset)

func _spawn_ship_visual(ship_id: StringName, pos: Vector2, ship_data: ShipAssembly = null) -> void:
	if _ships.has(ship_id):
		return

	var view := CompositeShipView.new()
	view.name = String(ship_id)
	view.position = pos
	view.scale = Vector2.ONE * 0.4

	# Hand-authored events may omit a typed assembly. Resolve that compatibility
	# case through the catalog too, so every replay uses the same visual path.
	var visual_data: ShipAssembly = ship_data.copy() if ship_data != null else ShipAssembly.new()
	var catalog: ShipPartCatalog = DEFAULT_SHIP_PART_CATALOG
	if String(visual_data.hull_id).is_empty() or catalog.resolve(visual_data.hull_id) == null:
		visual_data.hull_id = &"hull_t1"

	var hull: ShipPartDefinition = catalog.resolve(visual_data.hull_id)
	var scanner: ShipPartDefinition = catalog.resolve(visual_data.scanner_id)
	var drive: ShipPartDefinition = catalog.resolve(visual_data.drive_id)
	var weapon: ShipPartDefinition = catalog.resolve(visual_data.weapon_id)
	var shield: ShipPartDefinition = catalog.resolve(visual_data.shield_id)
	var modules: Array[ShipPartDefinition] = []
	for module_id in visual_data.module_ids:
		var module_part: ShipPartDefinition = catalog.resolve(module_id)
		if module_part != null:
			modules.append(module_part)

	var is_cpu: bool = String(ship_id).begins_with("b")
	var faction: StringName = &"b" if is_cpu else &"a"
	view.setup_from_parts(
		hull,
		scanner,
		drive,
		weapon,
		shield,
		modules,
		faction,
		null,
		_resolve_view_variants(catalog, visual_data)
	)
	_arena.add_child(view)
	_apply_comic_fx(view)
	_ships[ship_id] = view
	var tw := view.create_tween().set_loops()
	tw.tween_property(view, "position:y", pos.y + 4.0, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(view, "position:y", pos.y - 4.0, 1.2).set_trans(Tween.TRANS_SINE)

## Paper-comic outline on every sprite of a ship view (Layer 2 visual polish).
func _apply_comic_fx(node: Node) -> void:
	if node == null or DEFAULT_PAPER_STYLE == null:
		return
	for child in node.get_children():
		var sprite := child as Sprite2D
		if sprite == null:
			continue
		var material := ShaderMaterial.new()
		material.shader = PAPER_OUTLINE_SHADER
		material.set_shader_parameter("outline_color", DEFAULT_PAPER_STYLE.outline_color)
		material.set_shader_parameter("outline_width", DEFAULT_PAPER_STYLE.outline_width)
		sprite.material = material

func _resolve_view_variants(catalog: ShipPartCatalog, assembly: ShipAssembly) -> Dictionary:
	var result: Dictionary = {}
	var slot_types: Array[StringName] = [ShipPartDefinition.SLOT_HULL, ShipPartDefinition.SLOT_DRIVE, ShipPartDefinition.SLOT_WEAPON, ShipPartDefinition.SLOT_SHIELD, ShipPartDefinition.SLOT_SCANNER]
	for slot_type in slot_types:
		var part_id: StringName = assembly.hull_id
		match slot_type:
			ShipPartDefinition.SLOT_DRIVE:
				part_id = assembly.drive_id
			ShipPartDefinition.SLOT_WEAPON:
				part_id = assembly.weapon_id
			ShipPartDefinition.SLOT_SHIELD:
				part_id = assembly.shield_id
			ShipPartDefinition.SLOT_SCANNER:
				part_id = assembly.scanner_id
		var part: ShipPartDefinition = catalog.resolve(part_id)
		var variant: ShipComponentVariant = catalog.resolve_variant(part, assembly.variant_id_for(slot_type))
		if variant != null:
			result[slot_type] = variant

	var module_variants: Array[ShipComponentVariant] = []
	for index in range(assembly.module_ids.size()):
		var module_part: ShipPartDefinition = catalog.resolve(assembly.module_ids[index])
		module_variants.append(catalog.resolve_variant(module_part, assembly.variant_id_for(ShipPartDefinition.SLOT_UTILITY, index)))
	result[ShipPartDefinition.SLOT_UTILITY] = module_variants
	return result

func _animate_fire(src_id: StringName, src_pos: Vector2, tgt_pos: Vector2) -> void:
	if _ships.has(src_id):
		var ship: Node2D = _ships[src_id] as Node2D
		var recoil_dir := (src_pos - tgt_pos).normalized() * 5.0
		var r_tw := create_tween()
		r_tw.tween_property(ship, "position", ship.position + recoil_dir, 0.08)
		r_tw.tween_property(ship, "position", ship.position, 0.15)

	var is_cpu := String(src_id).begins_with("b")
	var line := Line2D.new()
	line.default_color = Color(1.0, 0.3, 0.3, 0.9) if is_cpu else Color(0.3, 0.8, 1.0, 0.9)
	line.width = 2.5
	line.add_point(src_pos)
	line.add_point(tgt_pos)
	_arena.add_child(line)

	var tw := create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.18)
	tw.finished.connect(line.queue_free)

func _animate_hit(target_id: StringName, tgt_pos: Vector2, damage: float) -> void:
	if _ships.has(target_id):
		var ship: Node2D = _ships[target_id] as Node2D
		var orig_color := ship.modulate
		ship.modulate = Color(2.0, 2.0, 2.0)
		var f_tw := create_tween()
		f_tw.tween_property(ship, "modulate", orig_color, 0.12)

	FloatingText.spawn(_arena, "-%.0f" % damage, tgt_pos + Vector2(0, -10), Color(1.0, 0.85, 0.3))

func _animate_destruction(ship_id: StringName, pos: Vector2) -> void:
	if _ships.has(ship_id):
		var target_node: Node2D = _ships[ship_id]
		_ships.erase(ship_id)

		var ring := Line2D.new()
		ring.default_color = Color(1.0, 0.6, 0.2, 1.0)
		ring.width = 3.0
		var pts: PackedVector2Array = []
		for i in range(12):
			var a := float(i) * TAU / 12.0
			pts.append(pos + Vector2(cos(a), sin(a)) * 6.0)
		pts.append(pts[0])
		ring.points = pts
		_arena.add_child(ring)

		var r_tw := create_tween()
		r_tw.set_parallel(true)
		r_tw.tween_property(ring, "scale", Vector2.ONE * 3.5, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		r_tw.tween_property(ring, "modulate:a", 0.0, 0.35)
		r_tw.chain().tween_callback(ring.queue_free)

		for d in range(6):
			var spark := Sprite2D.new()
			spark.texture = preload("res://assets/objects/workers/worker_unit.svg")
			spark.position = pos
			spark.scale = Vector2.ONE * 0.15
			_arena.add_child(spark)
			var dir := Vector2(_fx_rng.randf_range(-1, 1), _fx_rng.randf_range(-1, 1)).normalized() * _fx_rng.randf_range(20.0, 50.0)
			var s_tw := create_tween()
			s_tw.set_parallel(true)
			s_tw.tween_property(spark, "position", pos + dir, 0.4)
			s_tw.tween_property(spark, "rotation", _fx_rng.randf_range(-TAU, TAU), 0.4)
			s_tw.tween_property(spark, "modulate:a", 0.0, 0.4)
			s_tw.chain().tween_callback(spark.queue_free)

		FloatingText.spawn(_arena, "ZERSTÖRT!", pos, Color(1.0, 0.3, 0.2), 1.2)
		target_node.queue_free()

func _on_play_toggled(playing: bool) -> void:
	_is_playing = playing

func _on_speed_changed(speed: float) -> void:
	playback_speed = speed

func _on_seek_requested(time: float) -> void:
	_elapsed = time
	_clear_arena()
	_event_index = 0
	for i in range(_events.size()):
		var ev: BattleEvent = _events[i]
		if ev.timestamp <= time:
			if ev.event_type == BattleEvent.TYPE_SPAWN:
				_spawn_ship_visual(ev.source_id, ev.source_pos + _route_offset, ev.ship_data)
			elif ev.event_type == BattleEvent.TYPE_DESTROYED and _ships.has(ev.source_id):
				var node: Node2D = _ships[ev.source_id]
				_ships.erase(ev.source_id)
				node.queue_free()
			_event_index = i + 1
		else:
			break

func _on_skip_pressed() -> void:
	_finish_battle()

func _finish_battle() -> void:
	_is_playing = false
	_clear_arena()
	visible = false
	battle_completed.emit(_current_result)
