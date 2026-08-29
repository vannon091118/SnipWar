extends SceneTree

## Chronicle Core Test — Prüft WorldChronicle als isolierte Komponente.
## Keine GameState-Abhängigkeit. Nur: reset → simulation → save → hash → restore → hash.
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
	print("=== CHRONICLE CORE TEST ===")
	print("")

	# --- WorldChronicle muss als Autoload existieren ---
	var chronicle := root.get_node_or_null("WorldChronicle")
	_check("WorldChronicle autoload", chronicle != null)
	if chronicle == null:
		_print_result()
		quit(1)
		return

	# --- HistorySimulator muss deterministisch laufen ---
	var factions := _make_factions()
	var planets := _make_planets()
	var catalog := FigureCatalog.new("res://scripts/history/data")

	# RUN 1
	var sim1 := HistorySimulator.new()
	var res1 := sim1.simulate(factions.duplicate(true), planets.duplicate(true), 424242, 300, catalog)
	var events1: Array[HistoryEvent] = res1.get("events", [])
	var bios1: Dictionary = res1.get("biographies", {})
	var rels1: Dictionary = res1.get("final_relationships", {})
	_check("Simulation produced events", events1.size() > 100)
	_check("Simulation produced biographies", bios1.size() > 10)
	_check("Simulation produced relationships", rels1.size() > 0)

	# RUN 2 (same seed)
	var sim2 := HistorySimulator.new()
	var res2 := sim2.simulate(factions.duplicate(true), planets.duplicate(true), 424242, 300, catalog)
	var events2: Array[HistoryEvent] = res2.get("events", [])
	var bios2: Dictionary = res2.get("biographies", {})
	_check("Same seed = same event count", events1.size() == events2.size())
	_check("Same seed = same bio count", bios1.size() == bios2.size())

	# VOLLSTÄNDIGER DETERMINISMUS-HASH
	var hash1 := _compute_full_hash(events1, bios1, rels1)
	var hash2 := _compute_full_hash(events2, bios2, res2.get("final_relationships", {}))
	_check("Same seed = identical full hash", hash1 == hash2)

	# RUN 3 (different seed)
	var sim3 := HistorySimulator.new()
	var res3 := sim3.simulate(factions.duplicate(true), planets.duplicate(true), 999999, 300, catalog)
	var events3: Array[HistoryEvent] = res3.get("events", [])
	var hash3 := _compute_full_hash(events3, res3.get("biographies", {}), res3.get("final_relationships", {}))
	_check("Different seed = different hash", hash1 != hash3)

	# --- WorldChronicle.reset() mit echten Headless-Daten ---
	chronicle.reset(424242, factions.duplicate(true), planets.duplicate(true))
	_check("WorldChronicle ready after reset", chronicle.is_ready())
	var save: ChronicleSaveData = chronicle.get_save()
	_check("ChronicleSaveData not null", save != null)

	var backstory_events: Array[HistoryEvent] = save.backstory_events
	_check("Backstory events populated", backstory_events.size() > 100)
	_check("Biographies populated", save.biographies.size() > 10)
	_check("Chains populated", save.chains.size() > 0)
	_check("Eras populated", save.eras.size() > 0)
	_check("Relationships populated", save.relationships.size() > 0)

	# --- Snapshot / Restore Roundtrip ---
	var snapshot: ChronicleSaveData = chronicle.snapshot()
	_check("Snapshot not null", snapshot != null)
	var snap_hash := _compute_full_hash(snapshot.backstory_events, _bio_dict(snapshot.biographies), snapshot.relationships)
	_check("Snapshot hash matches backstory", snap_hash == _compute_full_hash(backstory_events, _bio_dict(save.biographies), save.relationships))

	# Restore via from_snapshot_dict (simuliert was GameState.save/load macht)
	var snap_dict := snapshot.snapshot_dict()
	var restored: ChronicleSaveData = ChronicleSaveData.from_snapshot_dict(snap_dict)
	var restore_hash := _compute_full_hash(restored.backstory_events, _bio_dict(restored.biographies), restored.relationships)
	_check("Restore roundtrip hash == snapshot hash", restore_hash == snap_hash)
	_check("Restore event count matches", restored.backstory_events.size() == snapshot.backstory_events.size())
	_check("Restore bio count matches", restored.biographies.size() == snapshot.biographies.size())
	_check("Restore chain count matches", restored.chains.size() == snapshot.chains.size())

	# --- Live Event injecten ---
	var before_live_count: int = save.all_events().size()
	var live_event := HistoryEvent.new()
	live_event.event_id = &"live_test_001"
	live_event.year = 1
	live_event.event_type = &"conquest"
	live_event.importance = 0.6
	live_event.trigger = "Test conquest"
	chronicle._record_live_event(live_event)
	var after_live: ChronicleSaveData = chronicle.get_save()
	var after_live_count: int = after_live.all_events().size()
	_check("Live event recorded", after_live_count == before_live_count + 1)

	# --- History Hash ausgeben ---
	print("")
	print("--- DETERMINISM HASH ---")
	print("Seed 424242: %s" % str(hash1))
	print("Seed 424242 (dup): %s" % str(hash2))
	print("Seed 999999: %s" % str(hash3))

	_print_result()
	quit(0 if _failures == 0 else 1)


func _compute_full_hash(events: Array[HistoryEvent], bios: Dictionary, rels: Dictionary) -> int:
	# Events: alle Felder
	var ev_str := ""
	for ev in events:
		ev_str += "%s|%d|%s|%s|%s|%s|%s|%d|%s|%.3f|%s|%s|%s;" % [
			String(ev.event_id),
			ev.year,
			String(ev.event_type),
			_actors_str(ev.actors),
			String(ev.target),
			String(ev.winner),
			String(ev.loser),
			ev.casualties,
			String(ev.territory_change),
			ev.importance,
			String(ev.cause_event_id),
			String(ev.cause_type),
			String(ev.chain_id),
		]

	# Biografien
	var bio_str := ""
	var sorted_cids: Array = bios.keys()
	sorted_cids.sort()
	for cid in sorted_cids:
		var b: CharacterBiography = bios[cid]
		bio_str += "%s|%s|%s|%d|%d|%s|" % [
			String(b.char_id),
			b.name,
			String(b.faction),
			b.birth_year,
			b.death_year,
			b.current_rank,
		]
		for r in b.rank_history:
			bio_str += "%d:%s," % [int(r.get("year", 0)), str(r.get("rank", ""))]
		bio_str += "|"
		for ach in b.achievements:
			bio_str += "%s," % ach
		bio_str += "|"
		for fail in b.failures:
			bio_str += "%s," % fail

	# Relationships
	var rel_str := ""
	var sorted_rel_keys: Array = rels.keys()
	sorted_rel_keys.sort()
	for k in sorted_rel_keys:
		rel_str += "%s:%d;" % [k, int(rels[k])]

	return (ev_str + bio_str + rel_str).hash()


func _actors_str(actors: Array[StringName]) -> String:
	var parts: PackedStringArray = []
	for a in actors:
		parts.append(String(a))
	return ",".join(parts)


func _bio_dict(bios: Array[CharacterBiography]) -> Dictionary:
	var d: Dictionary = {}
	for b in bios:
		d[b.char_id] = b
	return d


func _check(description: String, passed: bool) -> void:
	_checks += 1
	if passed:
		print("[PASS] %s" % description)
	else:
		_failures += 1
		print("[FAIL] %s" % description)


func _print_result() -> void:
	print("")
	print("=== CORE TEST RESULT ===")
	print("Checks: %d, Failures: %d" % [_checks, _failures])
	if _failures == 0:
		print("RESULT: PASSED")
	else:
		print("RESULT: FAILED")
		print("FAILURES: %d" % _failures)
	print("")


func _make_factions() -> Dictionary:
	return {
		&"a": {"territory":1,"military":35,"economy":40,"science":30,"mood":&"balanced","alive":true},
		&"b": {"territory":1,"military":50,"economy":25,"science":20,"mood":&"aggressive","alive":true},
	}


func _make_planets() -> Dictionary:
	return {
		&"planet_alpha": {"owner":&"a","population":100,"strategic_value":1.0},
		&"planet_beta": {"owner":&"b","population":80,"strategic_value":1.2},
		&"planet_gamma": {"owner":&"","population":0,"strategic_value":0.8},
		&"planet_delta": {"owner":&"","population":0,"strategic_value":0.9},
		&"planet_epsilon": {"owner":&"","population":0,"strategic_value":1.5},
	}
