@tool
class_name ConquestScene
extends CanvasLayer

signal conquest_completed(result: Dictionary)

var playback_speed: float = 1.0
var _result: Dictionary = {}
var _elapsed: float = 0.0
var _duration: float = 8.0
var _is_playing: bool = false

var _viewport_container: Control
var _arena: Node2D
var _status_label: Label
var _planet_sprite: Sprite2D
var _garrison_bar: ProgressBar
var _player_controls: IngamePlayerControls

var _attackers: Array[Node2D] = []
var _towers: Array[Node2D] = []

func _ready() -> void:
	layer = 85
	_build_ui()

func _build_ui() -> void:
	if _viewport_container != null:
		return
	_viewport_container = Control.new()
	_viewport_container.name = "RootControl"
	_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_viewport_container)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.015, 0.02, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport_container.add_child(bg)

	_arena = Node2D.new()
	_arena.name = "Arena"
	_arena.position = Vector2(480.0, 240.0)
	_viewport_container.add_child(_arena)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = "⚔️ PLANETARE INVASION / CONQUEST"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.position = Vector2(240.0, 16.0)
	_status_label.size = Vector2(480.0, 28.0)
	_status_label.add_theme_font_size_override("font_size", 16)
	_viewport_container.add_child(_status_label)

	_garrison_bar = ProgressBar.new()
	_garrison_bar.name = "GarrisonBar"
	_garrison_bar.position = Vector2(340.0, 50.0)
	_garrison_bar.size = Vector2(280.0, 16.0)
	_garrison_bar.value = 100.0
	_viewport_container.add_child(_garrison_bar)

	_player_controls = IngamePlayerControls.new()
	_player_controls.name = "PlayerControls"
	_player_controls.position = Vector2(200.0, 480.0)
	_player_controls.play_toggled.connect(_on_play_toggled)
	_player_controls.speed_changed.connect(_on_speed_changed)
	_player_controls.skip_pressed.connect(_on_finish_pressed)
	_viewport_container.add_child(_player_controls)

func play_conquest(result: Dictionary) -> void:
	_ensure_ui()
	_result = result
	_duration = float(result.get("duration", 8.0))
	_elapsed = 0.0
	_is_playing = true
	visible = true

	_player_controls.setup(_duration)
	_setup_battlefield()

func _ensure_ui() -> void:
	if _viewport_container == null:
		_build_ui()

func _setup_battlefield() -> void:
	for child in _arena.get_children():
		child.queue_free()
	_attackers.clear()
	_towers.clear()

	# Center Planet
	_planet_sprite = Sprite2D.new()
	_planet_sprite.name = "PlanetCore"
	_planet_sprite.texture = preload("res://assets/objects/planets/planet_09_paper.svg")
	_planet_sprite.scale = Vector2.ONE * 0.5
	_arena.add_child(_planet_sprite)

	# Orbiting Defense Towers
	for i in range(3):
		var tower := Sprite2D.new()
		tower.name = "Tower_%d" % i
		tower.texture = preload("res://assets/objects/satellites/planet_satellite.svg")
		var ang := float(i) * TAU / 3.0
		tower.position = Vector2(cos(ang), sin(ang)) * 80.0
		tower.scale = Vector2.ONE * 0.35
		_arena.add_child(tower)
		_towers.append(tower)

	# Assault Minions on perimeter
	for i in range(5):
		var minion := Sprite2D.new()
		minion.name = "Minion_%d" % i
		minion.texture = preload("res://assets/objects/workers/cluster_k.svg")
		minion.position = Vector2(-220.0, float(i * 35 - 70))
		minion.scale = Vector2.ONE * 0.3
		minion.modulate = Color(0.3, 0.7, 1.0)
		_arena.add_child(minion)
		_attackers.append(minion)

		# Advance tween
		var tw := minion.create_tween()
		tw.tween_property(minion, "position:x", -90.0, _duration * 0.8)

func _process(delta: float) -> void:
	if not _is_playing:
		return

	_elapsed += delta * playback_speed
	_player_controls.set_progress(_elapsed)

	# Update garrison progress
	var frac: float = clampf(1.0 - (_elapsed / _duration), 0.0, 1.0)
	if _garrison_bar != null:
		_garrison_bar.value = frac * 100.0

	# Periodical Tower & Minion Fire
	if Engine.get_process_frames() % 25 == 0 and _attackers.size() > 0 and _towers.size() > 0:
		var shooter: Node2D = _towers[randi() % _towers.size()]
		var target: Node2D = _attackers[randi() % _attackers.size()]
		_fire_laser(shooter.position, target.position, Color(1.0, 0.4, 0.2))

	if _elapsed >= _duration:
		_finish_conquest()

func _fire_laser(src: Vector2, tgt: Vector2, col: Color) -> void:
	var line := Line2D.new()
	line.default_color = col
	line.width = 2.0
	line.add_point(src)
	line.add_point(tgt)
	_arena.add_child(line)

	var tw := create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.15)
	tw.finished.connect(line.queue_free)
	FloatingText.spawn(_arena, "-8", tgt, Color(1.0, 0.8, 0.2), 0.8)

func _on_play_toggled(playing: bool) -> void:
	_is_playing = playing

func _on_speed_changed(speed: float) -> void:
	playback_speed = speed

func _on_finish_pressed() -> void:
	_finish_conquest()

func _finish_conquest() -> void:
	_is_playing = false
	visible = false
	conquest_completed.emit(_result)
