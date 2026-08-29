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
	var director: Node = get_node_or_null("/root/SceneDirectorService")
	if director != null and director.has_method("goto_scene"):
		director.call("goto_scene", &"world")
