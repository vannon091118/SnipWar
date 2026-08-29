class_name PreflightConstraintHistoricalWorld
extends RefCounted

## R-051: Preflight-Gate für den HistoricalWorld-Flow (R-050-Fix absichern).
## Der Spielerfluss „NEUES SPIEL → historical_world" endete in einer toten Szene
## (leere Chronik — `run_started` feuerte erst in world.tscn). Dieses Gate bootet
## die Szene mit gefüllter Chronik auf dem positiven Pfad und verifiziert den
## Reconnect-Vertrag, damit eine Regression sofort im Preflight auffällt.
##
## Läuft als PURE Constraint (kein Fixture): die historical_world wird temporär
## instanziiert und wieder entfernt; der Run wird via RunPreparation (deterministi-
## scher Seed 424242) vorbereitet. Am Ende wird der gefüllte Zustand wieder-
## hergestellt, damit nachfolgende Constraints idempotent starten.

const DETERMINISTIC_SEED := 424242
const SCENE_PATH := "res://scenes/historical_world/historical_world.tscn"


func constraint_name() -> String:
	return "historical_world"


func constraint_description() -> String:
	return "HistoricalWorld flow: run prepared before scene boot, playback loaded, fallback instead of dead-end, reconnect contract"


func requires_scene() -> bool:
	return false


func run(ctx: PreflightContext) -> bool:
	var ok := true

	# Autoloads sind erst nach dem ersten Idle-Frame im Baum (selbe Kante wie
	# constraint_game_state_compatibility) — vor prepare_new_run warten.
	await ctx.await_frame()

	# --- 1. Run-Vorbereitung (deterministischer Seed) ---
	var prep: Dictionary = RunPreparation.prepare_new_run(DETERMINISTIC_SEED)
	ok = ctx.check(prep.get("ok", false), "RunPreparation.prepare_new_run failed: %s" % str(prep.get("error", "?"))) and ok
	var state: Node = ctx.get_root().get_node_or_null("GameState")
	ok = ctx.check(state != null and state.has_active_run(), "Run is not active after prepare") and ok
	var chronicle: Node = ctx.get_root().get_node_or_null("WorldChronicle")
	ok = ctx.check(chronicle != null and chronicle.is_ready(), "WorldChronicle is not ready after prepare") and ok
	var save = chronicle.get_save() as ChronicleSaveData
	ok = ctx.check(save != null and not save.historical_snapshots.is_empty(), "Chronicle has no historical snapshots after prepare") and ok

	# --- 2. HistoricalWorld bootet mit gefüllter Chronik ---
	var scene: PackedScene = load(SCENE_PATH) as PackedScene
	ok = ctx.check(scene != null, "historical_world.tscn cannot be loaded") and ok
	var instance: Node = null
	if scene != null:
		instance = scene.instantiate()
		ctx.get_root().add_child(instance)
		await _wait_frames(ctx, 3)
	var playback: Node = instance.get_node_or_null("PlaybackController") if instance != null else null
	ok = ctx.check(playback != null, "Scene boot: PlaybackController missing") and ok
	var snapshots = playback.get("snapshots") if playback != null else null
	ok = ctx.check(snapshots != null and snapshots.size() > 0, "Scene boot: playback has no snapshots") and ok
	if save != null and playback != null:
		ok = ctx.check(snapshots.size() == save.historical_snapshots.size(), "Playback snapshots do not match chronicle snapshots") and ok
	var overlay: Node = instance.get_node_or_null("SimulationOverlay") if instance != null else null
	ok = ctx.check(overlay != null and overlay.get_node_or_null("TopBar") != null, "Overlay UI (TopBar) not built") and ok
	if instance != null:
		instance.queue_free()
	await _wait_frames(ctx, 1)

	# --- 3. Fallback: leere Chronik → Bootstrap erzeugt selbst Snapshots ---
	if chronicle != null:
		chronicle.restore(ChronicleSaveData.new())
	var instance2: Node = null
	if scene != null:
		instance2 = scene.instantiate()
		ctx.get_root().add_child(instance2)
		await _wait_frames(ctx, 3)
	var playback2: Node = instance2.get_node_or_null("PlaybackController") if instance2 != null else null
	ok = ctx.check(playback2 != null and playback2.get("snapshots") != null and playback2.get("snapshots").size() > 0, "Fallback: scene dead-ends on empty chronicle (playback missing/empty)") and ok
	if instance2 != null:
		instance2.queue_free()
	await _wait_frames(ctx, 1)

	# --- 4. Reconnect-Vertrag ---
	if state != null and state.has_method("request_world_reconnect"):
		var active: bool = state.has_active_run()
		state.request_world_reconnect()
		ok = ctx.check(active and state.consume_world_reconnect_request(), "Reconnect flag not settable/consumable") and ok
	else:
		ok = ctx.check(false, "Reconnect API missing on GameState") and ok

	# --- Zustand wiederherstellen (gefüllte Chronik für nachfolgende Nutzer) ---
	if ok and chronicle != null:
		RunPreparation.prepare_new_run(DETERMINISTIC_SEED)

	return ok


func _wait_frames(ctx: PreflightContext, count: int) -> void:
	for i in range(count):
		await ctx.await_frame()