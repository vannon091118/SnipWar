extends SceneTree
## DOKI Narrative Quality Analyzer
## Liest die Chain, Commit-Messages und CHANGELOG — prüft die narrative
## Konsistenz (Mood-Regel, Composite-Monotonie, Kausalität, Arc-Verlauf,
## Beziehungs-Matrix) und zeigt Stärken/Schwächen für Nachbesserungen auf.
##
## Aufruf:
##   $GODOT_BIN --headless --path . --script res://scripts/doki/doki_analyze.gd [--repo <pfad>]

var _repo_root: String = "."
var _findings: Array = []


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--repo":
		_repo_root = args[1]
	else:
		_repo_root = "res://"

	var exit_code: int = _run()
	quit(exit_code)


func _run() -> int:
	print("\n═══════════════════════════════════════════════════════")
	print(" DOKI Narrative Quality Analyzer — %s" % _repo_root)
	print("═══════════════════════════════════════════════════════\n")

	# 1. Chain laden (DOKI-Migration: liegt unter .doki/, Fallback auf Root)
	var chain_path: String = _repo_root.path_join(".doki").path_join("narrative_chain.json")
	if not FileAccess.file_exists(chain_path):
		chain_path = _repo_root.path_join("narrative_chain.json")
	var chain: Dictionary = _load_json(chain_path)
	if chain.is_empty():
		print("✗ Keine narrative_chain.json gefunden in: %s" % _repo_root)
		return 1

	var entries: Array = chain.get("entries", [])
	if entries.is_empty():
		print("✗ Chain enthält keine Einträge.")
		return 1

	var seeded: int = 0
	var real: int = 0
	for e in entries:
		if e.get("seeded", false):
			seeded += 1
		else:
			real += 1

	var anchor: Dictionary = chain.get("anchor", {})
	var genesis_hash: String = str(anchor.get("hash", "?"))
	var genesis_subject: String = str(anchor.get("subject", "?"))
	if genesis_hash.length() > 8:
		genesis_hash = genesis_hash.substr(0, 8)
	print("─── CHAIN ÜBERSICHT ───────────────────────────────")
	print("  Genesis: %s (%s)" % [genesis_hash, genesis_subject])
	print("  Einträge: %d total (%d SEED-Vorgeschichte, %d echte DOKI-Commits)" % [entries.size(), seeded, real])
	print("")

	_analyze_narrator_flow(entries)
	_analyze_mood_flow(entries)
	_analyze_composites(entries)
	_analyze_causality(entries)
	_analyze_arcs(entries)
	_analyze_relationships(entries)
	_analyze_subjects(entries)
	_analyze_changelog(entries)

	# Zusammenfassung
	print("\n═══════════════════════════════════════════════════════")
	print(" ZUSAMMENFASSUNG — Wo kann nachgebessert werden?")
	print("═══════════════════════════════════════════════════════")
	var issues: int = 0
	var warnings: int = 0
	for f in _findings:
		if f["level"] == "ERROR":
			issues += 1
		elif f["level"] == "WARN":
			warnings += 1

	print("  Befunde: %d Fehler, %d Warnungen" % [issues, warnings])
	if issues == 0 and warnings == 0:
		print("  ✓ Narrative Konsistenz: SAUBER")
	else:
		for f in _findings:
			var icon: String = "✗" if f["level"] == "ERROR" else "⚠"
			print("  %s [%s] %s" % [icon, f["category"], f["message"]])
	print("")
	print("RESULT: ANALYSE KOMPLETT (%d Befunde)" % _findings.size())
	return 0


## ═══ Analyse-Module ═══════════════════════════════════════════════════

func _analyze_narrator_flow(entries: Array) -> void:
	print("─── 1. NARRATOR-FUSSPUR (Wer erzählt wann?) ──────────")
	var prev_doki_name: String = ""
	for e in entries:
		var name: String = str(e.get("narrator", "?"))
		var mood: String = str(e.get("mood", "?"))
		var seq: int = int(e.get("seq", 0))
		var seeded_entry: bool = e.get("seeded", false)
		var marker: String = "[SEED]" if seeded_entry else "[DOKI]"
		print("  %3d %s %-10s | %-16s | %s" % [seq, marker, name, mood, str(e.get("composite", "?"))])

		if not seeded_entry and name == prev_doki_name and not prev_doki_name.is_empty():
			_findings.append({"level": "WARN", "category": "Narrator", "message": "seq %d: '%s' erzählt zweimal in Folge — Abwechslung fehlt" % [seq, name]})
		if not seeded_entry:
			prev_doki_name = name
	print("")


func _analyze_mood_flow(entries: Array) -> void:
	print("─── 2. MOOD-PROGRESSION (Regel: nie zweimal gleich) ──")
	var prev_mood: String = ""
	var prev_seq: int = 0
	var moods_used: Dictionary = {}
	for e in entries:
		if e.get("seeded", false):
			continue
		var mood: String = str(e.get("mood", "?"))
		var seq: int = int(e.get("seq", 0))
		if mood == prev_mood and not prev_mood.is_empty():
			_findings.append({"level": "ERROR", "category": "Mood", "message": "seq %d: Mood '%s' identisch mit seq %d — Regelverstoß (Mood[N] ≠ Mood[N-1])" % [seq, mood, prev_seq]})
		moods_used[mood] = moods_used.get(mood, 0) + 1
		prev_mood = mood
		prev_seq = seq

	print("  Verwendete Moods (nur DOKI-Commits):")
	for m in moods_used:
		print("    %-16s × %d" % [m, moods_used[m]])
	print("")


func _analyze_composites(entries: Array) -> void:
	print("─── 3. COMPOSITE-INTEGRITÄT (c/p lückenlos, Format) ───")
	# Lückenlos wie Verifier-Check 9a: jedes Entry c == vorheriges + 1 (Start 1).
	# Eine Lücke (c: 5 → 7) heißt: ein Commit wurde nicht in die Chain geschrieben.
	var expected_c: int = 0
	var expected_p: int = 0
	var c_ok: bool = true
	var p_ok: bool = true
	var fmt_ok: bool = true
	var re := RegEx.new()
	re.compile(DOKI_RngEngine.COMPOSITE_REGEX)

	for e in entries:
		var c: int = int(e.get("c", 0))
		var p_id: int = int(e.get("p_id", 0))
		var composite: String = str(e.get("composite", ""))
		var seq: int = int(e.get("seq", 0))

		expected_c += 1
		if c != expected_c:
			c_ok = false
			_findings.append({"level": "ERROR", "category": "Composite", "message": "seq %d: c=%d — Lücke (erwartet %d, finalize übersprungen?)" % [seq, c, expected_c]})
		expected_p += 1
		if p_id != expected_p:
			p_ok = false
			_findings.append({"level": "ERROR", "category": "Composite", "message": "seq %d: p_id=%d — Lücke (erwartet %d)" % [seq, p_id, expected_p]})

		if re.search(composite) == null:
			fmt_ok = false
			_findings.append({"level": "WARN", "category": "Composite", "message": "seq %d: '%s' hat ungültiges Format (erwartet cXjXnXaXpX)" % [seq, composite]})

	var c_first: int = int(entries[0].get("c", 0))
	var c_last: int = int(entries[entries.size() - 1].get("c", 0))
	var p_first: int = int(entries[0].get("p_id", 0))
	var p_last: int = int(entries[entries.size() - 1].get("p_id", 0))
	var c_state: String = "✓ lückenlos" if c_ok else "✗ LÜCKE"
	var p_state: String = "✓ lückenlos" if p_ok else "✗ LÜCKE"
	var fmt_state: String = "✓ alle ok" if fmt_ok else "✗ abweichend (siehe Findings)"
	print("  c-Folge:  %d → %d  %s" % [c_first, c_last, c_state])
	print("  p-Folge:  %d → %d  %s" % [p_first, p_last, p_state])
	print("  Format:   %s" % fmt_state)
	print("")


func _analyze_causality(entries: Array) -> void:
	print("─── 4. KAUSALITÄT (wird der Vorgänger erwähnt?) ─────")
	var mentions: int = 0
	var misses: int = 0
	for e in entries:
		if e.get("seeded", false):
			continue
		var prev: String = str(e.get("prev_narrator", ""))
		# Echter Git-Subject (build_subject inkl. „— nach <Vorgänger>");
		# Alt-/Seeded-Einträge ohne subject-Feld fallen auf summary zurück.
		var summary: String = str(e.get("subject", str(e.get("summary", ""))))
		var seq: int = int(e.get("seq", 0))
		var name: String = str(e.get("narrator", "?"))
		if prev.is_empty():
			continue
		if summary.to_lower().contains(prev.to_lower()):
			mentions += 1
		else:
			misses += 1
			_findings.append({"level": "WARN", "category": "Kausalität", "message": "seq %d (%s): Vorgänger '%s' fehlt im Subject: '%s'" % [seq, name, prev, summary.substr(0, 55)]})

	print("  Vorgänger-Erwähnung im Subject: %d× ✓, %d× fehlt" % [mentions, misses])
	if misses > 0:
		print("  → Tipp: 'VOR DIR WAR: X' im Prompt ist Pflicht — der Subject sollte den Vorgänger spiegeln.")
	print("")


func _analyze_arcs(entries: Array) -> void:
	print("─── 5. ARC-VERLAUF ─────────────────────────────────")
	var arcs: Dictionary = {}
	for e in entries:
		var arc: String = str(e.get("arc", "?"))
		if not arcs.has(arc):
			arcs[arc] = []
		arcs[arc].append(e)

	for arc_id in arcs:
		var arc_entries: Array = arcs[arc_id]
		var narrators: Array = []
		var subjects: Array = []
		for e in arc_entries:
			if not e.get("seeded", false):
				narrators.append(str(e.get("narrator", "?")))
				var subj: String = str(e.get("summary", ""))
				if subj.length() > 40:
					subj = subj.substr(0, 40)
				subjects.append(subj)
		var marker: String = "[SEED]" if narrators.is_empty() else ""
		var narrator_str: String = "— (nur Seed)"
		if not narrators.is_empty():
			narrator_str = ", ".join(narrators)
		print("  Arc '%s'%s: %d Einträge, Erzähler: %s" % [arc_id, marker, arc_entries.size(), narrator_str])
		if not subjects.is_empty():
			print("    Themen: %s" % " | ".join(subjects))

	# arcs.json Konsistenz + erweiterte Statistiken
	var arc_data: Dictionary = _load_json(_repo_root.path_join("scripts/doki/data/arcs.json"))
	if not arc_data.is_empty():
		print("\n  arcs.json Status:")
		var active: String = str(arc_data.get("active", "?"))
		var real_arcs: int = 0
		var climax_count: int = 0
		var total_commits_in_arcs: int = 0
		for arc_id in arc_data.get("arcs", {}):
			var a: Dictionary = arc_data["arcs"][arc_id]
			var status: String = str(a.get("status", "?"))
			var active_mark: String = " ◄ AKTIV" if arc_id == active else ""
			var commit_count: int = int(a.get("commit_count", 0))
			total_commits_in_arcs += commit_count
			if status == "completed":
				real_arcs += 1
				if commit_count >= 3:
					climax_count += 1
			print("    %s '%s' — weight: %-5.1f, commits: %d, status: %s%s" % [arc_id, str(a.get("name", "?")), float(a.get("weight", 0)), commit_count, status, active_mark])
		# Erweiterte Statistiken
		var total_arcs_in_json: int = (arc_data.get("arcs", {}) as Dictionary).size()
		var avg_arc_length: float = float(total_commits_in_arcs) / float(max(1, total_arcs_in_json))
		print("\n  Ø Arc-Länge: %.1f Commits" % avg_arc_length)
		if real_arcs > 0:
			print("  Arcs ≥3 Commits (echte Handlungsbögen): %d/%d (%.0f%%)" % [climax_count, real_arcs, climax_count * 100.0 / real_arcs])
		else:
			print("  Arcs ≥3 Commits: 0 (noch keine abgeschlossenen Arcs)")
	print("")


func _analyze_relationships(entries: Array) -> void:
	print("─── 6. BEZIEHUNGS-MATRIX (Wer folgt auf wen?) ───────")
	var pairs: Dictionary = {}
	for e in entries:
		if e.get("seeded", false):
			continue
		var name: String = str(e.get("narrator", "?"))
		var prev: String = str(e.get("prev_narrator", ""))
		if prev.is_empty():
			continue
		var pair: String = "%s → %s" % [prev, name]
		pairs[pair] = pairs.get(pair, 0) + 1

	if pairs.is_empty():
		print("  (noch keine echten DOKI-Übergänge)")
	else:
		print("  Narrator-Übergänge (nur DOKI-Commits):")
		for pair in pairs:
			print("    %-30s × %d" % [pair, pairs[pair]])
	print("")


func _analyze_subjects(entries: Array) -> void:
	print("─── 7. SUBJECT-STILE PRO ERZÄHLER ──────────────────")
	var by_narrator: Dictionary = {}
	for e in entries:
		if e.get("seeded", false):
			continue
		var name: String = str(e.get("narrator", "?"))
		var summary: String = str(e.get("subject", str(e.get("summary", ""))))
		if not by_narrator.has(name):
			by_narrator[name] = []
		by_narrator[name].append(summary)

	if by_narrator.is_empty():
		print("  (noch keine echten DOKI-Commits)")
		return

	for name in by_narrator:
		print("  %s:" % name)
		for s in by_narrator[name]:
			print("    • %s" % s.substr(0, 72))
	print("")


func _analyze_changelog(entries: Array) -> void:
	print("─── 8. CHANGELOG / Doku-Sync ───────────────────────")
	var changelog: String = _read_file(_repo_root.path_join("CHANGELOG.md"))
	if changelog.is_empty():
		_findings.append({"level": "WARN", "category": "CHANGELOG", "message": "CHANGELOG.md ist leer oder nicht vorhanden"})
		print("  ✗ CHANGELOG.md fehlt oder ist leer")
		return

	var lines: PackedStringArray = changelog.split("\n")
	var entry_count: int = 0
	for line in lines:
		if line.begins_with("## ") or line.begins_with("### "):
			entry_count += 1

	var real_doki: int = 0
	for e in entries:
		if not e.get("seeded", false):
			real_doki += 1

	print("  CHANGELOG-Einträge: %d (echte DOKI-Commits: %d)" % [entry_count, real_doki])
	if entry_count < real_doki:
		_findings.append({"level": "WARN", "category": "CHANGELOG", "message": "CHANGELOG hat %d Einträge, aber %d echte DOKI-Commits — Doku hinkt hinterher" % [entry_count, real_doki]})
	elif entry_count > real_doki:
		_findings.append({"level": "WARN", "category": "CHANGELOG", "message": "CHANGELOG hat %d Einträge, aber nur %d echte DOKI-Commits — Orphan-Verdacht (Eintrag ohne Commit, z. B. gescheiterter finish). Migration/repair nötig." % [entry_count, real_doki]})
	else:
		print("  ✓ 1:1 Sync")
	print("")


## ═══ Hilfsfunktionen ═════════════════════════════════════════════════

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var content: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if parsed is Dictionary:
		return parsed
	return {}


func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content
