extends SceneTree

## Historical Playback Test — Presentation-Grundlage (Phase 8).
## Prüft:
##   1. simulate_with_snapshots() erzeugt NUR lesend Snapshots:
##      identische Event-Folge zu simulate() (Determinismus-Vertrag)
##   2. gleicher Seed ×2 → identische Snapshot-Reihe
##   3. anderer Seed → andere Event-Folge
##   4. PlaybackController: seek/next/prev/current/play → snapshot_changed
##   5. HistoricalRenderer: baut Planet-Knoten aus Snapshot (nur Snapshot-Kenntnis)
## Preflight-kompatibles PASS/FAIL-Format.

var _failures: int = 0
var _checks: int = 0
var _ran: bool = false
var _frame: int = 0


func _init() -> void:
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


func _check(name: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("[PASS] " + name)
	else:
		_failures += 1
		print("[FAIL] " + name)


func _run_test() -> void:
	print("=== HISTORICAL PLAYBACK TEST ===")
	print("")

	var factions := _make_factions()
	var planets := _make_planets()
	var catalog := FigureCatalog.new("res://scripts/history/data")

	# --- 1. simulate() vs simulate_with_snapshots(): identische Events ---
	var sim_plain := HistorySimulator.new()
	var res_plain: Dictionary = sim_plain.simulate(factions.duplicate(true), planets.duplicate(true), 424242, 300, catalog)
	var sim_snap := HistorySimulator.new()
	var res_snap: Dictionary = sim_snap.simulate_with_snapshots(factions.duplicate(true), planets.duplicate(true), 424242, 300, catalog, 25)

	var events_plain: Array = res_plain["events"]
	var events_snap: Array = res_snap["events"]
	_check("Snapshot-Modus erzeugt identische Event-Anzahl", events_plain.size() == events_snap.size())
	_check("Snapshot-Modus erzeugt identische Event-Hashes", _events_hash(events_plain) == _events_hash(events_snap))

	# --- 2. gleicher Seed ×2 → identische Snapshot-Reihe ---
	var sim_snap2 := HistorySimulator.new()
	var res_snap2: Dictionary = sim_snap2.simulate_with_snapshots(factions.duplicate(true), planets.duplicate(true), 424242, 300, catalog, 25)
	var shots1: Array = res_snap["snapshots"]
	var shots2: Array = res_snap2["snapshots"]
	_check("Snapshot-Reihe deterministisch (gleiche Anzahl)", shots1.size() == shots2.size())
	_check("Snapshot-Reihe deterministisch (identische Hashes)", _snapshots_hash(shots1) == _snapshots_hash(shots2))
	_check("Snapshot-Reihe nicht leer", not shots1.is_empty())
	if not shots1.is_empty():
		var last_shot: HistoricalSnapshot = shots1[shots1.size() - 1]
		_check("Letzter Snapshot enthält Ownership", not last_shot.ownership.is_empty())
		_check("Snapshot-Events auf Jahr begrenzt", last_shot.events.size() <= events_snap.size())

	# --- 3. anderer Seed → andere Event-Folge ---
	var sim_other := HistorySimulator.new()
	var res_other: Dictionary = sim_other.simulate_with_snapshots(factions.duplicate(true), planets.duplicate(true), 999999, 300, catalog, 25)
	var events_other: Array = res_other["events"]
	_check("Anderer Seed → andere Event-Folge", _events_hash(events_other) != _events_hash(events_snap))

	# --- 4. PlaybackController ---
	var playback := PlaybackController.new()
	root.add_child(playback)
	var seen: Array = []
	playback.snapshot_changed.connect(func(index: int, snapshot: HistoricalSnapshot) -> void:
		seen.append([index, snapshot.year])
	)
	playback.load_snapshots(shots1)
	_check("Playback: kein Snapshot vor seek", playback.current() == null)
	playback.seek(0)
	_check("Playback: seek(0) liefert ersten Snapshot", playback.current() != null and playback.current().year == (shots1[0] as HistoricalSnapshot).year)
	playback.next()
	_check("Playback: next() bewegt Index", playback.current_index == 1)
	playback.prev()
	_check("Playback: prev() bewegt zurück", playback.current_index == 0)
	playback.seek(shots1.size() - 1)
	playback.next()
	_check("Playback: next() am Ende bleibt stehen", playback.current_index == shots1.size() - 1)
	playback.seek(0)
	playback.set_tick_seconds(0.01)
	playback.play()
	_check("Playback: play() startet", playback.playing)
	_check("Playback: snapshot_changed wurde emittiert", seen.size() >= 1)
	playback.pause()
	_check("Playback: pause() stoppt", not playback.playing)

	# --- 5. HistoricalRenderer: nur Snapshot-Kenntnis ---
	var renderer := HistoricalRenderer.new()
	root.add_child(renderer)
	var mid_shot: HistoricalSnapshot = shots1[shots1.size() / 2]
	renderer.show_snapshot(mid_shot)
	_check("Renderer: Planet-Knoten == Ownership-Größe", renderer.planet_count() == mid_shot.ownership.size())
	renderer.show_snapshot(shots1[0])
	_check("Renderer: früherer Snapshot blendet Planeten aus", renderer.planet_count() == (shots1[0] as HistoricalSnapshot).ownership.size())

	_print_result()


func _events_hash(events: Array) -> String:
	var parts: Array[String] = []
	for event in events:
		var e: HistoryEvent = event
		var actor_part: Array[String] = []
		for a in e.actors:
			actor_part.append(String(a))
		parts.append("%s|%s|%s|%s" % [str(e.year), String(e.event_type), "".join(actor_part), String(e.target)])
	return "".join(parts).sha256_text()


func _snapshots_hash(shots: Array) -> String:
	var parts: Array[String] = []
	for shot in shots:
		var s: HistoricalSnapshot = shot
		var owner_part: Array[String] = []
		for pid in s.ownership:
			owner_part.append("%s=%s" % [String(pid), String(s.ownership[pid])])
		owner_part.sort()
		parts.append("%s:%d:%s" % [str(s.year), s.events.size(), "".join(owner_part)])
	return "".join(parts).sha256_text()


func _make_factions() -> Dictionary:
	return {
		&"a": {"territory": 4, "economy": 60.0, "military": 45.0, "science": 30.0, "mood": "ambitious"},
		&"b": {"territory": 3, "economy": 50.0, "military": 40.0, "science": 25.0, "mood": "cautious"},
	}


func _make_planets() -> Dictionary:
	var planets := {}
	for i in range(8):
		var pid: StringName = StringName("p%02d" % i)
		planets[pid] = {
			"owner": &"a" if i < 4 else &"b",
			"resources": 10.0 + i,
			"defense": 5.0 + i,
		}
	return planets


func _print_result() -> void:
	print("")
	print("Checks: %d, Failures: %d" % [_checks, _failures])
	if _failures == 0:
		print("RESULT: PASSED")
		quit(0)
	else:
		print("RESULT: FAILED")
		quit(1)