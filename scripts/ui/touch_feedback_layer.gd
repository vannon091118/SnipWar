extends CanvasLayer

var _drawer: Control
var _ripples: Array[Dictionary] = []

func _ready() -> void:
	layer = 100
	_drawer = Control.new()
	_drawer.name = "FeedbackDrawer"
	_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drawer.draw.connect(_on_drawer_draw)
	add_child(_drawer)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_spawn_ripple(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_spawn_ripple(event.position)

func _spawn_ripple(pos: Vector2) -> void:
	_ripples.append({
		"pos": pos,
		"time": 0.0,
		"duration": 0.5
	})
	_drawer.queue_redraw()
	set_process(true)

func _process(delta: float) -> void:
	var needs_redraw := false
	for i in range(_ripples.size() - 1, -1, -1):
		_ripples[i].time += delta
		if _ripples[i].time >= _ripples[i].duration:
			_ripples.remove_at(i)
		else:
			needs_redraw = true

	if needs_redraw:
		_drawer.queue_redraw()
	else:
		set_process(false)

func _on_drawer_draw() -> void:
	for r in _ripples:
		var progress: float = clampf(r.time / r.duration, 0.0, 1.0)
		var ease_out := 1.0 - pow(1.0 - progress, 3.0)
		var radius := 10.0 + ease_out * 40.0
		var alpha := 1.0 - ease_out
		var color := Color(1.0, 1.0, 1.0, alpha * 0.7)
		_drawer.draw_arc(r.pos, radius, 0.0, TAU, 32, color, 2.0, true)

		# Inner filled dot
		var dot_alpha := (1.0 - progress) * 0.5
		_drawer.draw_circle(r.pos, 4.0, Color(1.0, 1.0, 1.0, dot_alpha))
