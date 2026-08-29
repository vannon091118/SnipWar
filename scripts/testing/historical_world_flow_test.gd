extends SceneTree

## R-050 Historical-World-Flow-Test (Entry-Point-Falsifizierung).
## Prüft den echten Spielerfluss auf positiven Pfaden:
##   1. RunPreparation.prepare_new_run() → Run aktiv + WorldChronicle gefüllt
##      (vorher: run_started feuerte erst in der world.tscn → leere Chronik)
##   2. historical_world.tscn bootet mit gefüllter Chronik: Playback geladen,
##      Overlay-UI gebaut, kein Dead-End
##   3. Fallback: leere Chronik (direkter Szenen-Boot) → Bootstrap erzeugt
##      selbst Snapshots statt die Szene totzulegen
##   4. Reconnect-Vertrag: request_world_reconnect() setzt/konsumiert den Flag
##      (world.tscn reconnected statt begin_new_game → keine Doppel-Simulation)
## Preflight-kompatibles PASS/FAIL-Format; exit 1 bei Abweichung.

var _failures: int = 0
var _checks: int = 0
var _ran: bool = false
var _frame: int = 0


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_frame += 1
	if _frame < 3:
		return false
	_ran = true
	_run_test()
	return false


func _check(name: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("[PASS] " + name)
	else:
		_failures += 1
		print("[FAIL] " + name)


func _wait_frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _run_test() -> void:
	print("=== HISTORICAL WORLD FLOW TEST ===")
	print("")

	# --- 1. Run-Vorbereitung (deterministischer Seed) ---
	var prep: Dictionary = RunPreparation.prepare_new_run(424242)
	_check("RunPreparation ok", prep.get("ok", false))
	var state: Node = root.get_node_or_null("GameState")
	_check("Run aktiv nach prepare", state != null and state.has_active_run())
	var chronicle: Node = root.get_node_or_null("WorldChronicle")
	_check("Chronicle ready nach prepare", chronicle != null and chronicle.is_ready())
	var save: ChronicleSaveData = chronicle.get_save() as ChronicleSaveData
	_check("Chronicle hat Snapshots", save != null and not save.historical_snapshots.is_empty())

	# --- 2. HistoricalWorld bootet mit gefüllter Chronik ---
	var scene: PackedScene = load("res://scenes/historical_world/historical_world.tscn") as PackedScene
	var instance: Node = null
	if scene != null:
		instance = scene.instantiate()
		root.add_child(instance)
		await _wait_frames(3)
	var playback: Node = instance.get_node_or_null("PlaybackController") if instance != null else null
	_check("Szenen-Boot: Playback vorhanden", playback != null)
	_check("Playback-Snapshots geladen", playback != null and playback.get("snapshots") != null and playback.get("snapshots").size() > 0)
	if save != null and playback != null:
		_check("Playback-Snapshots == Chronik-Snapshots", playback.get("snapshots").size() == save.historical_snapshots.size())
	var overlay: Node = instance.get_node_or_null("SimulationOverlay") if instance != null else null
	_check("Overlay-UI gebaut (TopBar)", overlay != null and overlay.get_node_or_null("TopBar") != null)
	if instance != null:
		instance.queue_free()
	await _wait_frames(1)

	# --- 3. Fallback: leere Chronik → Bootstrap erzeugt selbst Snapshots ---
	chronicle.restore(ChronicleSaveData.new())
	var instance2: Node = null
	if scene != null:
		instance2 = scene.instantiate()
		root.add_child(instance2)
		await _wait_frames(3)
	var playback2: Node = instance2.get_node_or_null("PlaybackController") if instance2 != null else null
	_check("Fallback: kein Dead-End (Playback geladen)", playback2 != null and playback2.get("snapshots") != null and playback2.get("snapshots").size() > 0)
	if instance2 != null:
		instance2.queue_free()
	await _wait_frames(1)

	# --- 4. Reconnect-Vertrag ---
	_check("Reconnect-API vorhanden", state != null and state.has_method("request_world_reconnect"))
	if state != null and state.has_method("request_world_reconnect"):
		var run_active: bool = state.has_active_run()
		state.request_world_reconnect()
		var consumed: bool = state.consume_world_reconnect_request()
		_check("Reconnect-Flag setzbar/konsumierbar", run_active and consumed)

	_print_result()


func _print_result() -> void:
	print("")
	print("Checks: %d, Failures: %d" % [_checks, _failures])
	if _failures == 0:
		print("RESULT: PASSED")
		quit(0)
	else:
		print("RESULT: FAILED")
	quit(1)