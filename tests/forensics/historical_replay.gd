# 🔬 FORENSICS (AUDIT 3) — historical_replay.gd
# Replays the 10 SEEDED composites via the REAL DOKI_RngEngine to document that
# none are reproducible by current code (see docs/AUDIT_3_REPRODUCIBILITY.md §3.1).
# READ-ONLY: reads narrative_chain.json; never writes.
# Run: $GODOT_BIN --headless --path . --script res://tests/forensics/historical_replay.gd

extends SceneTree

func _init() -> void:
	var chain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("narrative_chain.json"))
	var entries: Array = chain["entries"]
	var stored_by_seq := {}
	for e in entries:
		stored_by_seq[int(e["seq"])] = e

	# seeded commits (hash, tree, full subject) — copied from git
	var commits := [
		["2a4319479209fddf27a67de473e447564f8b3aa9", "bea0da92f709ba40c7effb35eb48125ca5e60895", "feat: Layer-Separation — Kampf-/Eroberungs-Szenen ohne Autoload-Abhängigkeit"],
		["ced4704fe26f41caed00a755e3faf3ae35909c0d", "34f2f1e7583e94973e065ca6aba0ef425fbba416", "feat: MCP-In-Process-Runtime im Editor — Dock verbindet direkt, keine separaten Prozesse"],
		["f26e7f3267f8ded0e6769e800e179892b8323717", "34f2f1e7583e94973e065ca6aba0ef425fbba416", "merge: MCP-In-Process-Runtime (#3) in main übernehmen"],
		["257d6832ab3a99316f969f8e562e473590d41f16", "bfb0feffde6367b9c204ccbabd3a4a0dca432cb8", "feat: decouple MCP bridge from project-specific assumptions"],
		["54e367169698ace193fbacd85d85fb3e4d129e32", "dfac5deda099e1c3b996ec42f14982ebfa144e74", "fix: complete project-agnostic MCP wiring"],
		["fa6f9fc9f89e21203ab50ebe862fb7989c300b2b", "c7a83682b85cdc3018f74243ef8a8dd23ed11bca", "fix: Runtime-MCP-Auto-Boot überlebt langsame Skriptserver-Kompilierung"],
		["e883fb41b8dc8eac3cb7cd2ea527c89ea57cfe91", "8ebbf6a5cefbcaba0885191ada6cbd9282578599", "fix: make preflight phase metadata authoritative"],
		["6933ae940ecbdec3c75fce9ac7de7112edc18e4a", "8d370b9908d4fe7426611a6084b0d734417a1d7b", "fix: preflight SOT and repository boundaries"],
		["a5f7a966ceb9712f01b97bdc8424bb0b6f01654c", "a60beaa0c16bac8d174e4bc3033818475befc744", "chore: keep agent session data out of repository"],
		["bbf8763ef955b92465ac981d415baba7afaa6e7d", "a60beaa0c16bac8d174e4bc3033818475befc744", "Merge remote-tracking branch 'origin/main'"],
	]

	var mood_pool: Array = ["sachlich", "sarkastisch", "erschöpft", "triumphierend", "selbstironisch", "neugierig", "müde-zufrieden", "alarmiert", "trocken", "warm"]
	var prev_comp: String = DOKI_RngEngine.GENESIS_COMPOSITE
	var prev_mood: String = DOKI_RngEngine.GENESIS_MOOD
	var arc_count: int = 1
	var any_ok := false
	print("REPLAY-USING-REAL-DOKI-RNGEINGINE")
	for i in range(1, commits.size() + 1):
		var h: String = commits[i - 1][0]
		var tree: String = commits[i - 1][1]
		var subj: String = commits[i - 1][2]
		var limits: Dictionary = {"j": 99, "n": 14, "a": maxi(1, arc_count), "p": i}
		var diff_hash: String = str(DOKI_RngEngine.djb2(subj + h))
		var d: Dictionary = DOKI_RngEngine.derive(prev_comp, tree, diff_hash, subj, limits, prev_mood, mood_pool)
		var entry: Dictionary = stored_by_seq[i]
		var ok: bool = str(d["composite"]) == str(entry["composite"])
		any_ok = any_ok or ok
		print("seq=%d stored=%s replay=%s %s" % [i, str(entry["composite"]), str(d["composite"]), "OK" if ok else "MISMATCH"])
		prev_comp = str(d["composite"])
		prev_mood = str(d["mood"])
	# AUDIT-3 fixed verdict: NOT REPRODUCIBLE (determinism given, inputs were transient).
	print("VERDICT=%s" % ("PARTIALLY REPRODUCED" if any_ok else "NOT REPRODUCIBLE (expected per AUDIT 3)"))
	quit(0)