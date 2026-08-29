extends SceneTree

## Chronicle Lifecycle Test — Prüft den echten Signalfluss:
##   GameState.begin_new_game() → EventBus.run_started → WorldChronicle.reset()
## Kein call_deferred, kein Mock. Echter GameState-Lifecycle.
## Event-Boundary: WorldChronicle darf NICHT direkt an GameState hängen.
##
## Preflight-kompatibles PASS/FAIL-Format.

var _failures: int = 0
var _checks: int = 0
var _ran: bool = false
var _frame: int = 0


func _init():
	pass  # autoloads register after _init, run in _process


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_frame += 1
	if _frame < 3:
		return false
	_ran = true
	_run_test()
	return false


func _run_test() -> void:
	print("=== CHRONICLE LIFECYCLE TEST ===")
	print("")

	# --- Pre-Checks ---
	var state := root.get_node_or_null("GameState")
	_check("GameState autoload", state != null)

	var chronicle := root.get_node_or_null("WorldChronicle")
	_check("WorldChronicle autoload", chronicle != null)

	var bus := root.get_node_or_null("EventBus")
	_check("EventBus autoload", bus != null)

	if state == null or chronicle == null:
		_print_result()
		quit(1)
		return

	# --- Verify signal connection (Event-Boundary) ---
	# WorldChronicle darf nicht mehr direkt an GameState.run_started hängen;
	# der einzige Start-Pfad ist der EventBus.
	_check("WorldChronicle NOT connected to GameState.run_started directly",
		not state.run_started.is_connected(chronicle._on_run_started))
	_check("WorldChronicle connected to EventBus",
		bus.game_event.is_connected(chronicle._on_game_event))

	# --- Create minimal PlanetCatalog ---
	var catalog := PlanetCatalog.new()
	var p1 := PlanetDefinition.new()
	p1.planet_id = &"test_planet_a"
	p1.display_name = "Test Alpha"
	p1.faction = &"a"
	p1.planet_role = &"homeworld"
	catalog.planets.append(p1)

	var p2 := PlanetDefinition.new()
	p2.planet_id = &"test_planet_b"
	p2.display_name = "Test Beta"
	p2.faction = &"b"
	p2.planet_role = &"homeworld"
	catalog.planets.append(p2)

	var p3 := PlanetDefinition.new()
	p3.planet_id = &"test_planet_neutral"
	p3.display_name = "Test Gamma"
	p3.faction = &"neutral"
	p3.planet_role = &"planet"
	catalog.planets.append(p3)

	# --- Pre-state: Chronicle should NOT be ready before game start ---
	_check("Chronicle not ready before game start", not chronicle.is_ready())

	# --- Start new game (this triggers run_started via EventBus internally) ---
	state.begin_new_game(catalog, &"test_scenario", 424242, false)

	# --- Wait for signal chain to complete ---
	# _on_game_event(run_started) calls reset() which is synchronous
	# (simulation runs immediately). But _connect_signals was deferred,
	# so we need a few frames.
	await process_frame
	await process_frame
	await process_frame

	# --- Post-state: Chronicle should be ready ---
	_check("Chronicle ready after begin_new_game", chronicle.is_ready())

	# --- Check data ---
	var save: ChronicleSaveData = chronicle.get_save()
	_check("ChronicleSaveData populated", save != null)

	if save != null:
		var backstory: Array[HistoryEvent] = save.backstory_events
		_check("Backstory events > 50", backstory.size() > 50)
		_check("Biographies > 5", save.biographies.size() > 5)
		_check("Chains > 0", save.chains.size() > 0)
		_check("Eras > 0", save.eras.size() > 0)
		_check("Relationships > 0", save.relationships.size() > 0)

		# --- Verify real faction IDs were used (not old solari/vanguard/krypton_miners) ---
		var used_factions: Dictionary = {}
		for ev in backstory:
			for actor in ev.actors:
				var fid := String(actor)
				if not fid.begins_with("char_"):
					used_factions[fid] = true
		_check("Uses real faction IDs (a, b)", used_factions.has("a") or used_factions.has("b"))
		_check("No old test faction IDs", not (used_factions.has("solari") or used_factions.has("vanguard")))

		# --- Snapshot roundtrip via GameState ---
		var snapshot_run: RunSaveData = state.snapshot_run() as RunSaveData
		_check("snapshot_run() succeeded", snapshot_run != null)
		if snapshot_run != null:
			_check("snapshot_run has chronicle", snapshot_run.chronicle != null)
			if snapshot_run.chronicle != null:
				var snap_events: Array = snapshot_run.chronicle.backstory_events
				_check("Snapshot event count matches", snap_events.size() == backstory.size())

				# Restore into chronicle
				chronicle.restore(snapshot_run.chronicle)
				var restored_save: ChronicleSaveData = chronicle.get_save() as ChronicleSaveData
				_check("Restore event count matches", restored_save.backstory_events.size() == backstory.size())
				_check("Restore bio count matches", restored_save.biographies.size() == save.biographies.size())

	# --- Test live event via EventBus ---
	var live_before: int = save.all_events().size() if save != null else 0
	bus.emit_event(&"faction_changed", {
		"planet_id": &"test_planet_neutral",
		"old_faction": &"neutral",
		"new_faction": &"a",
	})
	await process_frame
	var live_after: int = chronicle.get_save().all_events().size()
	_check("Live event via EventBus recorded", live_after > live_before)

	_print_result()
	quit(0 if _failures == 0 else 1)


func _check(description: String, passed: bool) -> void:
	_checks += 1
	if passed:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		print("[FAIL] %s" % description)


func _print_result() -> void:
	print("")
	print("=== LIFECYCLE TEST RESULT ===")
	print("Checks: %d, Failures: %d" % [_checks, _failures])
	if _failures == 0:
		print("RESULT: PASSED")
	else:
		print("RESULT: FAILED")
		print("FAILURES: %d" % _failures)
	print("")
