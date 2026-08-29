extends SceneTree

func _init():
	var catalog := FigureCatalog.new("res://scripts/history/data")
	var factions := {
		&"solari": {"territory":1,"military":35,"economy":40,"science":30,"mood":&"balanced","alive":true},
		&"vanguard": {"territory":1,"military":50,"economy":25,"science":20,"mood":&"aggressive","alive":true},
		&"krypton_miners": {"territory":1,"military":25,"economy":55,"science":25,"mood":&"expansionist","alive":true},
	}
	var planets := {
		&"planet_alpha": {"owner":&"solari","population":100,"strategic_value":1.0},
		&"planet_beta": {"owner":&"vanguard","population":80,"strategic_value":1.2},
		&"planet_gamma": {"owner":&"krypton_miners","population":120,"strategic_value":1.1},
		&"planet_delta": {"owner":&"","population":0,"strategic_value":0.8},
		&"planet_epsilon": {"owner":&"","population":0,"strategic_value":0.9},
		&"planet_zeta": {"owner":&"","population":0,"strategic_value":1.5},
	}
	var seed_val: int = 424242

	# --- RUN 1 ---
	var sim1 := HistorySimulator.new()
	var res1: Dictionary = sim1.simulate(factions.duplicate(true), planets.duplicate(true), seed_val, 300, catalog)
	var events1: Array[HistoryEvent] = res1.get("events", [])
	var bios1: Dictionary = res1.get("biographies", {})
	var rels1: Dictionary = res1.get("final_relationships", {})

	# --- RUN 2 (same seed) ---
	var sim2 := HistorySimulator.new()
	var res2: Dictionary = sim2.simulate(factions.duplicate(true), planets.duplicate(true), seed_val, 300, catalog)
	var events2: Array[HistoryEvent] = res2.get("events", [])
	var bios2: Dictionary = res2.get("biographies", {})
	var rels2: Dictionary = res2.get("final_relationships", {})

	# --- RUN 3 (different seed) ---
	var sim3 := HistorySimulator.new()
	var res3: Dictionary = sim3.simulate(factions.duplicate(true), planets.duplicate(true), 999999, 300, catalog)
	var events3: Array[HistoryEvent] = res3.get("events", [])

	# --- Compare same-seed ---
	print("=== SAME SEED COMPARISON ===")
	print("Run1 events: %d, Run2 events: %d" % [events1.size(), events2.size()])

	var same_count: int = 0
	var diff_count: int = 0
	var min_size: int = mini(events1.size(), events2.size())
	for i in range(min_size):
		var e1: HistoryEvent = events1[i]
		var e2: HistoryEvent = events2[i]
		if e1.event_id == e2.event_id and e1.year == e2.year and e1.event_type == e2.event_type and e1.importance == e2.importance:
			same_count += 1
		else:
			diff_count += 1
			if diff_count <= 5:
				print("  DIFF [%d]: id=%s/%s year=%d/%d type=%s/%s imp=%.2f/%.2f" % [
					i, String(e1.event_id), String(e2.event_id),
					e1.year, e2.year,
					String(e1.event_type), String(e2.event_type),
					e1.importance, e2.importance])

	print("Same: %d, Diff: %d (of %d)" % [same_count, diff_count, min_size])
	print("Event count match: %s" % (events1.size() == events2.size()))

	# Compare biographies
	print("\nBio count: Run1=%d, Run2=%d" % [bios1.size(), bios2.size()])
	var bio_same: int = 0
	for cid in bios1:
		if bios2.has(cid):
			var b1: CharacterBiography = bios1[cid]
			var b2: CharacterBiography = bios2[cid]
			if b1.name == b2.name and b1.faction == b2.faction and b1.birth_year == b2.birth_year:
				bio_same += 1
	print("Bio names match: %d/%d" % [bio_same, bios1.size()])

	# Compare relationships
	print("\nRelationship keys: Run1=%d, Run2=%d" % [rels1.size(), rels2.size()])
	var rel_diff: int = 0
	for k in rels1:
		if rels2.has(k) and rels1[k] != rels2[k]:
			rel_diff += 1
	print("Relationship diffs: %d" % rel_diff)

	# --- Compare different-seed ---
	print("\n=== DIFFERENT SEED COMPARISON ===")
	print("Run1 (424242): %d events, Run3 (999999): %d events" % [events1.size(), events3.size()])

	var cross_same: int = 0
	var cross_min: int = mini(events1.size(), events3.size())
	for i in range(cross_min):
		var e1: HistoryEvent = events1[i]
		var e3: HistoryEvent = events3[i]
		if e1.year == e3.year and e1.event_type == e3.event_type:
			cross_same += 1
	print("Events with same year+type: %d/%d (%.1f%%)" % [cross_same, cross_min, 100.0 * float(cross_same) / maxf(1.0, float(cross_min))])

	# --- SIMULATION TRACE (first 10 events) ---
	print("\n=== SIMULATION TRACE (seed=%d, first 15 events) ===" % seed_val)
	for i in range(mini(15, events1.size())):
		var e: HistoryEvent = events1[i]
		print("Year %4d | %-12s | actors=%s | target=%s | imp=%.2f | cause=%s" % [
			e.year, String(e.event_type), str(e.actors), String(e.target),
			e.importance, String(e.cause_event_id)])

	# --- EVENT TYPE COUNTS ---
	print("\n=== EVENT TYPE COUNTS ===")
	var counts: Dictionary = {}
	for ev in events1:
		var t: String = String(ev.event_type)
		counts[t] = int(counts.get(t, 0)) + 1
	for k in counts:
		print("  %s : %d" % [k, counts[k]])

	# --- CHAIN DETECTION ---
	var detector := ChainDetector.new()
	var chains: Array[EventChain] = detector.detect_chains(events1)
	print("\n=== CHAIN DETECTION ===")
	print("Total chains: %d" % chains.size())
	for c in chains:
		print("  %s: %d events (%d–%d) resolution=%s" % [
			String(c.chain_id), c.event_count(), c.start_year, c.end_year, String(c.resolution)])

	# --- IMPORTANCE DISTRIBUTION ---
	print("\n=== IMPORTANCE DISTRIBUTION ===")
	var imp_buckets: Dictionary = {"invisible": 0, "minor": 0, "normal": 0, "major": 0, "turning_point": 0}
	var eval := ImportanceEvaluator.new()
	for ev in events1:
		var cat: String = String(eval.categorize(ev.importance))
		imp_buckets[cat] = int(imp_buckets.get(cat, 0)) + 1
	for k in imp_buckets:
		print("  %s: %d" % [k, imp_buckets[k]])

	print("\n=== DETERMINISM TEST COMPLETE ===")
	quit(0)
