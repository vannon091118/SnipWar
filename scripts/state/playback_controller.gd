@tool
## Verwaister Stump — die echte PlaybackController-Klasse liegt in
## scripts/history/playback_controller.gd. Diese Datei hatte eine
## class_name-Kollision verursacht (gleicher Name wie die echte Klasse).
## class_name entfernt; der Node wird über seinen Namen gefunden
## (historical_world_bootstrap: get_node_or_null("PlaybackController")).
extends Node

@export var snapshots: Array = []

func load_snapshots(snapshots: Array) -> void:
	self.snapshots = snapshots