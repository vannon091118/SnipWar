class_name ResearchIndicator
extends Node2D

## Pulsierender Fortschritts-Ring über der Spieler-Homeworld, solange eine
## fraktionsweite Forschung läuft. Der Ring füllt sich von 0→1 (research_time
## verstrichen) und gibt sich selbst frei, sobald der Job abgeschlossen oder
## abgebrochen wurde.

const SEGMENTS := 12
const RING_RADIUS := 30.0
const DOT_RADIUS := 3.0
const TRACK_COLOR := Color(0.55, 0.6, 0.7, 0.45)
const FILL_COLOR := Color(0.98, 0.82, 0.35)

var faction: StringName = &""
var tech_id: StringName = &""
var total_time: float = 1.0

func _ready() -> void:
	z_index = 5

func _process(_delta: float) -> void:
	var state: Node = GameStateAccess.autoload(self)
	if state == null:
		return
	if not state.has_method("research_in_progress") or not state.research_in_progress(faction, tech_id):
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var remaining: float = 0.0
	var state: Node = GameStateAccess.autoload(self)
	if state != null and state.has_method("research_remaining"):
		remaining = float(state.research_remaining(faction, tech_id))
	var progress := 1.0 - clampf(remaining / maxf(total_time, 0.001), 0.0, 1.0)
	var angle_step := TAU / float(SEGMENTS)
	for i in SEGMENTS:
		var angle := -PI * 0.5 + float(i) * angle_step
		var center := Vector2(cos(angle), sin(angle)) * RING_RADIUS
		var filled := float(i) < progress * float(SEGMENTS)
		draw_circle(center, DOT_RADIUS, FILL_COLOR if filled else TRACK_COLOR)