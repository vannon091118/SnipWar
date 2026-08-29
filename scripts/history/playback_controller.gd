class_name PlaybackController
extends Node

## Zeitsteuerung über eine Snapshot-Reihe (Presentation-Schicht, §14).
## Kennt ausschließlich HistoricalSnapshot — keinen Simulator, keine
## Narrative-Regeln. Emittiert snapshot_changed; UI kann darauf hören.

signal snapshot_changed(index: int, snapshot: HistoricalSnapshot)

var snapshots: Array[HistoricalSnapshot] = []
var current_index: int = -1
var playing: bool = false

var _tick_seconds: float = 1.0
var _elapsed: float = 0.0


func load_snapshots(series: Array[HistoricalSnapshot]) -> void:
	snapshots = series.duplicate()
	current_index = -1
	playing = false
	_elapsed = 0.0


func set_tick_seconds(seconds: float) -> void:
	_tick_seconds = maxf(seconds, 0.001)


func seek(index: int) -> void:
	if snapshots.is_empty():
		return
	current_index = clampi(index, 0, snapshots.size() - 1)
	snapshot_changed.emit(current_index, snapshots[current_index])


func current() -> HistoricalSnapshot:
	if current_index < 0 or current_index >= snapshots.size():
		return null
	return snapshots[current_index]


func play() -> void:
	if snapshots.is_empty():
		return
	if current_index < 0:
		seek(0)
	playing = true


func pause() -> void:
	playing = false


func next() -> void:
	if snapshots.is_empty():
		return
	seek(mini(current_index + 1, snapshots.size() - 1))


func prev() -> void:
	if snapshots.is_empty():
		return
	seek(maxi(current_index - 1, 0))


func _process(delta: float) -> void:
	if not playing:
		return
	_elapsed += delta
	if _elapsed < _tick_seconds:
		return
	_elapsed = 0.0
	if current_index >= snapshots.size() - 1:
		playing = false
		return
	seek(current_index + 1)