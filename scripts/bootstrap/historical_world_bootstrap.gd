class_name HistoricalWorldBootstrap
extends Node2D

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

var _renderer: HistoricalRenderer
var _playback: PlaybackController
var _overlay: SimulationOverlay
var _chronicle: Node
var _finished: bool = false

func _ready() -> void:
	_renderer = get_node_or_null("HistoricalRenderer") as HistoricalRenderer
	_playback = get_node_or_null("PlaybackController") as PlaybackController
	_overlay = get_node_or_null("SimulationOverlay") as SimulationOverlay
	_chronicle = get_node_or_null("/root/WorldChronicle")
	if _renderer == null or _playback == null or _overlay == null or _chronicle == null:
		push_error("HistoricalWorld: required presentation components are missing")
		return
	_playback.snapshot_changed.connect(_on_snapshot_changed)
	_overlay.playback_finished.connect(_on_playback_finished)
	_overlay.year_changed.connect(_on_overlay_year_changed)
	var save: ChronicleSaveData = _chronicle.get_save() as ChronicleSaveData
	if save == null or save.historical_snapshots.is_empty():
		# R-050-Fallback: Wurde der Run nicht vorbereitet (z. B. direkter
		# Szenen-Boot), erzeugt die Chronik selbst deterministische Snapshots
		# aus dem aktiven Run-Seed — nie ein Dead-End ohne Playback.
		_chronicle.reset(_chronicle_seed())
		save = _chronicle.get_save() as ChronicleSaveData
	if save == null or save.historical_snapshots.is_empty():
		push_error("HistoricalWorld: chronicle has no historical snapshots")
		return
	var snapshots: Array[HistoricalSnapshot] = save.snapshots_as_resources()
	_playback.load_snapshots(snapshots)
	_overlay.setup(save.backstory_events, save.eras, DEFAULT_THEME)
	_playback.seek(0)
	_overlay.play()

func _on_snapshot_changed(_index: int, snapshot: HistoricalSnapshot) -> void:
	if _renderer != null:
		_renderer.show_snapshot(snapshot)

func _chronicle_seed() -> int:
	var state: Node = get_node_or_null("/root/GameState")
	if state != null and state.has_method("world_session_context"):
		return int(state.world_session_context().get("layout_seed", 0))
	return 424242


func _on_overlay_year_changed(year: int) -> void:
	if _playback == null or _playback.snapshots.is_empty():
		return
	var closest_index: int = 0
	for i in range(_playback.snapshots.size()):
		if _playback.snapshots[i].year <= year:
			closest_index = i
	_playback.seek(closest_index)

func _on_playback_finished() -> void:
	if _finished:
		return
	_finished = true
	# R-050: Reconnect-Vertrag — die world.tscn darf den aktiven Run NICHT per
	# begin_new_game() neu erzeugen (Doppel-Simulation). Der Flag veranlasst
	# WorldBootstrap, über reconnect_world() denselben Run fortzusetzen.
	# R-050: Reconnect-Vertrag — die world.tscn darf den aktiven Run NICHT per
	# begin_new_game() neu erzeugen (Doppel-Simulation). Der Flag veranlasst
	# WorldBootstrap, über reconnect_world() denselben Run fortzusetzen.
	# R-052: Ownership wird direkt aus WorldChronicle.final_year0_ownership()
	# gelesen (Snapshot-basiert), nicht über GameState-Handoff.
	var state: Node = get_node_or_null("/root/GameState")
	if state != null and state.has_active_run() and state.has_method("request_world_reconnect"):
		state.request_world_reconnect()
	var director: Node = get_node_or_null("/root/SceneDirectorService")
	if director != null and director.has_method("goto_scene"):
		director.call("goto_scene", &"world")
