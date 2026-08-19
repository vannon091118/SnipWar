@tool
class_name BattleScene
extends CanvasLayer

signal battle_completed(result: Dictionary)

var playback_speed: float = 1.0
var _events: Array[BattleEvent] = []
var _current_result: Dictionary = {}
var _ships: Dictionary = {} # id -> Sprite2D
var _ship_initial_data: Dictionary = {}
var _elapsed: float = 0.0
var _event_index: int = 0
var _is_playing: bool = false
var _total_duration: float = 0.0

var _viewport_container: Control
var _arena: Node2D
var _status_label: Label
var _player_controls: IngamePlayerControls

func _ready() -> void:
	layer = 80
	_build_ui()

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

	_player_controls = IngamePlayerControls.new()
	_player_controls.name = "PlayerControls"
	_player_controls.position = Vector2(200.0, 480.0)
	_player_controls.play_toggled.connect(_on_play_toggled)
	_player_controls.seek_requested.connect(_on_seek_requested)
	_player_controls.speed_changed.connect(_on_speed_changed)
	_player_controls.skip_pressed.connect(_on_skip_pressed)
	_viewport_container.add_child(_player_controls)

func play_battle(result: Dictionary) -> void:
	_ensure_ui()
	_current_result = result
	_events = result.get("events", [])
	_total_duration = float(result.get("duration", 5.0))
	_event_index = 0
	_elapsed = 0.0
	_is_playing = true
	visible = true

	_player_controls.setup(_total_duration)
	_clear_arena()
	_cache_spawn_data()

func _ensure_ui() -> void:
	if _viewport_container == null:
		_build_ui()

func _clear_arena() -> void:
	for child in _arena.get_children():
		child.queue_free()
	_ships.clear()

func _cache_spawn_data() -> void:
	_ship_initial_data.clear()
	for ev in _events:
		if ev.event_type == BattleEvent.TYPE_SPAWN:
			_ship_initial_data[ev.source_id] = {
				"pos": ev.source_pos,
				"hp": ev.value
			}

func _process(delta: float) -> void:
	if not _is_playing:
		return

	_elapsed += delta * playback_speed
	_player_controls.set_progress(_elapsed)

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
			_spawn_ship_visual(event.source_id, event.source_pos)
		BattleEvent.TYPE_FIRE:
			_animate_fire(event.source_id, event.source_pos, event.target_pos)
		BattleEvent.TYPE_HIT:
			_animate_hit(event.target_id, event.target_pos, event.value)
		BattleEvent.TYPE_DESTROYED:
			_animate_destruction(event.source_id, event.source_pos)

func _spawn_ship_visual(ship_id: StringName, pos: Vector2) -> void:
	if _ships.has(ship_id):
		return
	var sprite := Sprite2D.new()
	sprite.name = String(ship_id)
	sprite.texture = preload("res://assets/objects/workers/cluster_k.svg")
	sprite.position = pos
	sprite.scale = Vector2.ONE * 0.4
	var is_cpu := String(ship_id).begins_with("b")
	sprite.modulate = Color(1.0, 0.4, 0.4) if is_cpu else Color(0.3, 0.7, 1.0)
	_arena.add_child(sprite)
	_ships[ship_id] = sprite

	# Idle Floating Tween
	var tw := sprite.create_tween().set_loops()
	tw.tween_property(sprite, "position:y", pos.y + 4.0, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sprite, "position:y", pos.y - 4.0, 1.2).set_trans(Tween.TRANS_SINE)

func _animate_fire(src_id: StringName, src_pos: Vector2, tgt_pos: Vector2) -> void:
	# Recoil animation on shooter
	if _ships.has(src_id):
		var ship: Sprite2D = _ships[src_id]
		var recoil_dir := (src_pos - tgt_pos).normalized() * 5.0
		var r_tw := create_tween()
		r_tw.tween_property(ship, "position", ship.position + recoil_dir, 0.08)
		r_tw.tween_property(ship, "position", ship.position, 0.15)

	# Laser beam
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
	# Hit flash on target
	if _ships.has(target_id):
		var ship: Sprite2D = _ships[target_id]
		var orig_color := ship.modulate
		ship.modulate = Color(2.0, 2.0, 2.0)
		var f_tw := create_tween()
		f_tw.tween_property(ship, "modulate", orig_color, 0.12)

	# Floating damage number
	FloatingText.spawn(_arena, "-%.0f" % damage, tgt_pos + Vector2(0, -10), Color(1.0, 0.85, 0.3))

func _animate_destruction(ship_id: StringName, pos: Vector2) -> void:
	if _ships.has(ship_id):
		var target_node: Node2D = _ships[ship_id]
		_ships.erase(ship_id)

		# Destruction expansion & explosion ring
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

		# Debris sparks
		for d in range(6):
			var spark := Sprite2D.new()
			spark.texture = preload("res://assets/objects/workers/worker_unit.svg")
			spark.position = pos
			spark.scale = Vector2.ONE * 0.15
			_arena.add_child(spark)
			var dir := Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(20.0, 50.0)
			var s_tw := create_tween()
			s_tw.set_parallel(true)
			s_tw.tween_property(spark, "position", pos + dir, 0.4)
			s_tw.tween_property(spark, "rotation", randf_range(-TAU, TAU), 0.4)
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
	# Re-execute events up to scrubbed time
	for i in range(_events.size()):
		var ev := _events[i]
		if ev.timestamp <= time:
			if ev.event_type == BattleEvent.TYPE_SPAWN:
				_spawn_ship_visual(ev.source_id, ev.source_pos)
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
	visible = false
	battle_completed.emit(_current_result)
