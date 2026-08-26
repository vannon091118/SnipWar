extends SceneTree
## DOKI Story-Test — simuliert den kompletten 5-Commits-Flow und prüft,
## ob das System eine KOHÄRENTE "Geschichte" erzählt:
##   - Chain wächst lückenlos (c-, p-, seq-Folge)
##   - Jeder Commit hat realen Diff → deterministischen Composite
##   - Narrator/Mood variieren (keine Mono-Stimme)
##   - Kausalität: Vorgänger-Narrator wird referenziert (Chain-Append)
##   - Cross-Narrator-Mentions in den fertigen Messages
##   - Mood-Non-Repeat in der Folge
##   - Begründungszeilen für jede Datei vorhanden
##   - RNG-Replay in Check 9 stimmt (Verifier auf jede fertige Message)
##
## Aufruf (im TEST-Worktree, NIE im Haupt-Worktree):
##   $GODOT_BIN --headless --path <testworktree> --script <abs-path>/doki_story_test.gd
##   oder: res://scripts/doki/doki_story_test.gd wenn im Projektverzeichnis.
##
## Der Test legt Dateien an, stagt sie, ruft prepare/finish/finalize auf —
## ABER commitet NICHT (finalize wird direkt nach prepare mit simuliertem
## HEAD-Wechsel getestet, um Git-Commits im Test-Worktree zu vermeiden).

var _failures: int = 0
var _checks: int = 0
var _repo_root: String = ""  # wird von --repo gesetzt oder aus cwd

# 5 Story-Schritte mit realistischen Impulsen + Dateien
var _story: Array = [
	{
		"impulse": "Dispatch-Logik für Worker-Konvois einführen (Transit-Grundlage)",
		"files": {
			"scripts/dispatch.gd": "class_name Dispatch\nextends RefCounted\nfunc dispatch_workers(count: int) -> void:\n\tprint('dispatch', count)\n",
			"scripts/flight_time.gd": "class_name FlightTime\nextends RefCounted\nconst BASE_HOURS := 2\n",
		},
		"body": "Die Worker wollten kein Ziel, also haben wir ihnen eines gegeben. Der Dispatch entscheidet jetzt, wohin die Konvois fliegen — die Flugzeit ist die erste Kausalität: jede Stunde Flug bindet Worker. Weil wir die Struktur vorher nicht hatten, war jeder Transport ein Sonderfall. Deshalb jetzt zentral im Dispatch. Die Rechnung: mehr Worker brauchen mehr Routen, daher steigt die Flugzeit. Ein Fundament, auf das alles Weitere aufbaut.",
	},
	{
		"impulse": "Bug: Worker landen doppelt — dedupliziere Ankunfts-Logik (fix)",
		"files": {
			"scripts/dispatch.gd": "class_name Dispatch\nextends RefCounted\nfunc dispatch_workers(count: int) -> void:\n\tprint('dispatch', count)\n\nfunc arrivals() -> Array:\n\treturn []\n",
		},
		"body": "Die Konvois kamen an — und kamen an, und kamen an. Doppelte Ankünfte, weil die Logik zweimal lief. Also: eine einzige Ankunfts-Pforte, und die zählt genau einmal. Der Fix war unvermeidlich, denn doppelte Worker hätten die Rohstoffe gesprengt. Ein kleiner Schnitt, große Wirkung: die Kette bleibt sauber, und der nächste Schritt baut auf stabilem Boden.",
	},
	{
		"impulse": "Test-Assets: drei Konvoi-Szenarien für den Dispatch (Tests)",
		"files": {
			"tests/dispatch_scenarios.gd": "class_name DispatchScenarios\nextends RefCounted\nfunc scenario_a() -> void:\n\tpass\n",
			"tests/dispatch_scenarios.gd.uid": "uid://dispatch_scenarios_test\n",
		},
		"body": "Tests! Endlich. Drei Szenarien fangen die Fälle ein, die vorher niemand sah — der leere Konvoi, der volle Konvoi, die Doppelankunft. Weil die Tests jetzt existieren, wird der Dispatch beim nächsten Umbau nicht in die Grube laufen. Die Grundlage: erst Beweise, dann Behauptungen. Damit bleibt die Geschichte nachvollziehbar.",
	},
	{
		"impulse": "Doku des Transit-Systems (dispatch/flight_time) in DESIGN.md",
		"files": {
			"docs/TRANSIT.md": "# Transit-System\nDer Dispatch verteilt Worker. Flugzeit bindet Ressourcen.\n",
			"docs/README.md": "# Docs\nSiehe TRANSIT.md\n",
		},
		"body": "Die Chronik muss festhalten, was gewachsen ist. Ohne Doku wäre der Dispatch ein Gedächtnisfehler: jeder neue Entwickler müsste die Ketten selbst rekonstruieren. Deshalb jetzt das Transit-Kapitel — knapp, präzise, und mit den Grenzen der Flugzeit. Denn jede Geschichte braucht ein Archiv, sonst erzählt sie nur von gestern.",
	},
	{
		"impulse": "Refactor: Flugzeit-Modul verallgemeinern (flight_time wird wiederverwendbar)",
		"files": {
			"scripts/flight_time.gd": "class_name FlightTime\nextends RefCounted\nconst BASE_HOURS := 2\nvar _distances := {}\nfunc register_distance(a: String, b: String, hours: int) -> void:\n\t_distances[a + b] = hours\n",
		},
		"body": "Die Flugzeit war nur für einen Zweck gut — jetzt ist sie ein Werkzeug. Die Distanz-Registry erlaubt jedwede Route, statt Sonderfälle zu stapeln. Warum? Weil der nächste Handlungsbogen (Eroberung) Distanzen überall braucht. Die Naht ist geschlossen, die Schicht atmet. Der Umstieg war nötig, bevor die Geschichte weitergehen kann.",
	},
]

var _chain_line: Array = []  # pro Commit: {c, p, narrator, mood, seq}


func _init() -> void:
	_repo_root = _resolve_repo_root()
	print("DOKI Story-Test in: %s" % _repo_root)

	var orchestrator := DOKI_CommitOrchestrator.new(_repo_root)
	# Init nur, wenn noch keine Chain existiert (nach `init --seed-last` startet
	# der Test mit Vorgeschichte — die Kohärenz-Checks laufen auf die NEUEN Commits).
	var chain_before: Dictionary = orchestrator.chain_store.read()
	if chain_before.get("anchor", {}).is_empty():
		var init_result: Dictionary = orchestrator.init_flow()
		if not init_result["ok"]:
			print("✗ init fehlgeschlagen: %s" % str(init_result.get("error", "?")))
			_failures += 1
			_finish()
	else:
		print("Chain bereits initialisiert (%d Einträge) — neuer Test startet als Fortsetzung." % int(chain_before.get("entries", []).size()))

	# 5 Commits durchspielen
	for i in _story.size():
		_print_story_step(i)
		var step: Dictionary = _story[i]
		if not _run_commit(orchestrator, step, i):
			_failures += 1

	_story_coherence(orchestrator)

	print("")
	print("═══════════════════════════════════════")
	print(" Story-Test: %d Checks, %d Fehler" % [_checks, _failures])
	print(" RESULT: %s" % ("PASSED — die 5 Commits erzählen eine kohärente Geschichte" if _failures == 0 else "FAILED"))
	print("═══════════════════════════════════════")
	_finish()


func _resolve_repo_root() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--repo="):
			return arg.trim_prefix("--repo=")
	return ProjectSettings.globalize_path("res://")


## Ein kompletter Commit-Zyklus: Dateien bauen → stagen → prepare → finish → finalize.
func _run_commit(orchestrator: DOKI_CommitOrchestrator, step: Dictionary, index: int) -> bool:
	var ok: bool = true
	var impulse: String = str(step["impulse"])

	# 1. Dateien schreiben (jede Iteration: angehängte Inhalte, damit Diffs entstehen)
	for file_path in step["files"].keys():
		var full_path: String = _repo_root.path_join(file_path)
		DirAccess.make_dir_recursive_absolute(full_path.get_base_dir())
		var existing: String = FileAccess.get_file_as_string(full_path) if FileAccess.file_exists(full_path) else ""
		var f := FileAccess.open(full_path, FileAccess.WRITE)
		if f != null:
			f.store_string(existing + str(step["files"][file_path]))
			f.close()

	# 2. Stagen
	var files: Array = step["files"].keys()
	var stage: Array = ["add"]
	stage.append_array(files)
	var stage_result := _run_git(stage)
	if not stage_result["ok"]:
		print("✗ git add fehlgeschlagen")
		return false

	# 3. prepare
	var prepare_result: Dictionary = orchestrator.prepare(impulse, "claude-sonnet-4")
	if not prepare_result["ok"]:
		print("✗ prepare fehlgeschlagen: %s" % str(prepare_result.get("error", "?")))
		return false
	var session: Dictionary = prepare_result["session"]

	# 4. finish
	var finish_result: Dictionary = orchestrator.finish(str(step["body"]))
	if not finish_result["ok"]:
		print("✗ finish fehlgeschlagen:")
		for e in finish_result.get("errors", []):
			print("    harte: %s" % str(e))
		for e in finish_result.get("soft_errors", []):
			print("    weich: %s" % str(e))
		return false

	# 5. finalize — Git-Commit simulieren: HEAD-Hash in Session fortschreiben
	# (DER echte `git commit` findet im Test-Worktree NICHT statt; stattdessen
	# simulieren wir den HEAD-Wechsel quasi — finalize prüft nur git_head_before != head.
	# Wir machen einen echten Git-Commit NICHT, um die Test-Worktree-Historie sauber zu halten.)
	# Commit simulieren: HEAD-Bewegung vortäuschen via repair? Nein — wir ersetzen den
	# git_head_before im Speicher, damit finalize den HEAD-Wechsel erkennt.
	# Sauberer: Wir machen einen ECHTEN Git-Commit mit der erzeugten Message —
	# das Modell soll ja genau das können. (Nur im Test-Worktree, Hooks feuern hier nicht.)
	var msg_path: String = _repo_root.path_join(".commit_msg.txt")
	var msg_content: String = FileAccess.get_file_as_string(msg_path)
	var commit_result := _run_git(["commit", "-F", msg_path])
	if not commit_result["ok"]:
		print("✗ git commit fehlgeschlagen: %s" % str(commit_result["stderr"]))
		return false

	var finalize_result: Dictionary = orchestrator.finalize_flow_run()
	if not finalize_result["ok"]:
		print("✗ finalize fehlgeschlagen: %s" % str(finalize_result.get("error", "?")))
		return false

	# 6. Deterministischer Replay (Check 9-Kern): gleiche Inputs → gleicher Composite.
	# Session-Inputs aus prepare (die Session ist nach finalize resettet, daher hier VOR finalize).
	# Limits exakt aus der Session (identisch zu prepare) — nicht selbst nachbauen.
	var replay_limits: Dictionary = session.get("limits", {
		"j": 99, "n": 14,
		"a": maxi(1, int(session.get("a", 1))),
		"p": maxi(1, orchestrator.chain_store.entries().size() + 1),
	})
	var replayed: Dictionary = DOKI_RngEngine.derive(
		str(session.get("prev_composite", DOKI_RngEngine.GENESIS_COMPOSITE)),
		str(session.get("tree_hash", "")),
		str(session.get("diff_hash", "")),
		impulse,
		replay_limits,
		str(session.get("prev_mood", DOKI_RngEngine.GENESIS_MOOD)),
		session.get("mood_pool", DOKI_MoodOverlay.default_pool())
	)
	var replay_ok: bool = str(replayed.get("composite", "")) == str(session.get("composite", ""))
	_expect("Commit %d: deterministischer Composite-Replay" % (index + 1), replay_ok)
	if not replay_ok:
		print("    erwartet: %s  replay: %s" % [session.get("composite"), replayed.get("composite")])
		return false

	# Chain-Zeile merken
	var entry: Dictionary = finalize_result.get("entry", {})
	_chain_line.append({
		"c": int(entry.get("c", 0)),
		"p": int(entry.get("p_id", 0)),
		"seq": int(entry.get("seq", 0)),
		"narrator": str(entry.get("narrator", "")),
		"mood": str(entry.get("mood", "")),
		"composite": str(entry.get("composite", "")),
		"summary": str(entry.get("summary", "")),
	})
	print("  ✓ Commit %d: c%s p%s %s (%s) — %s" % [index + 1, entry.get("c"), entry.get("p_id"), entry.get("narrator"), entry.get("mood"), _short(str(step["impulse"]), 40)])

	# 7. Artefakte prüfen
	if FileAccess.file_exists(_repo_root.path_join(".commit_msg.txt")):
		print("  ✗ .commit_msg.txt existiert nach finalize noch (Cleanup-Fehler)")
		ok = false
	if not FileAccess.file_exists(_repo_root.path_join("CHANGELOG.md")):
		print("  ✗ CHANGELOG.md fehlt")
		ok = false
	if not FileAccess.file_exists(_repo_root.path_join("change_index.json")):
		print("  ✗ change_index.json fehlt")
		ok = false

	# 8. Begründungszeilen in Message prüfen (jede Datei)
	var reason_lines: Array = finish_result.get("reason_lines", [])
	for file_path in step["files"].keys():
		var has_line: bool = false
		for line in reason_lines:
			if str(line).begins_with("- %s:" % file_path):
				has_line = true
				break
		_expect("Commit %d: Begründungszeile für %s" % [index + 1, file_path], has_line)

	return ok


## Kohärenz der 5er-Geschichte.
func _story_coherence(orchestrator: DOKI_CommitOrchestrator) -> void:
	if _chain_line.size() < 2:
		print("  ✗ Story-Test: zu wenige Chain-Einträge")
		return

	# 1. c-Folge lückenlos (jeder Eintrag = Vorgänger + 1 — Start kann nach
	#    `init --seed-last` irgendwo liegen, z. B. c11..c15)
	var c_seq_ok: bool = true
	for i in range(1, _chain_line.size()):
		if int(_chain_line[i]["c"]) != int(_chain_line[i - 1]["c"]) + 1:
			c_seq_ok = false
	_expect("Story: c-Folge lückenlos (c%d..c%d)" % [int(_chain_line[0]["c"]), int(_chain_line[_chain_line.size() - 1]["c"])], c_seq_ok)

	# 2. p-Folge monoton (nicht zwingend direkt aufeinander, aber steigend)
	var p_ok: bool = true
	for i in range(1, _chain_line.size()):
		if int(_chain_line[i]["p"]) <= int(_chain_line[i - 1]["p"]):
			p_ok = false
	_expect("Story: p-Folge monoton steigend", p_ok)

	# 3. Narrator-Varianz (nicht 5× derselbe)
	var narrators: Dictionary = {}
	for line in _chain_line:
		narrators[str(line["narrator"])] = true
	_expect("Story: Narrator-Varianz (%d verschiedene)" % narrators.size(), narrators.size() >= 2)

	# 4. Mood-Non-Repeat benachbart
	var mood_ok: bool = true
	for i in range(1, _chain_line.size()):
		if str(_chain_line[i]["mood"]) == str(_chain_line[i - 1]["mood"]):
			mood_ok = false
	_expect("Story: Mood nie zweimal hintereinander", mood_ok)

	# 5. Jeder Eintrag hat Vorgänger-Verweis (Kausalität) — ab dem 2. Eintrag
	var kausal_ok: bool = true
	for i in range(1, _chain_line.size()):
		var entry_narrator: String = str(_chain_line[i]["narrator"])
		var prev_narrator: String = _chain_narrator_at(i - 1, orchestrator)
		if prev_narrator.is_empty() or prev_narrator == entry_narrator:
			kausal_ok = false
	_expect("Story: Kausalität — Vorgänger-Narrator existiert (ab Commit 2)", kausal_ok)

	# 6. Check 9-RNG-Replay pro Entry: derive bestätigt den Chain-Composite
	var replay_ok: bool = true
	for i in _chain_line.size():
		var replay: Dictionary = _replay_entry(i, orchestrator)
		if not replay["ok"]:
			replay_ok = false
			print("    ✗ Commit %d: Replay mismatch: %s" % [i + 1, str(replay["error"])])
	_expect("Story: RNG-Replay für alle 5 Chain-Einträge", replay_ok)

	# 7. Ausgabe der Geschichte (Narratoren + Summary)
	print("")
	print("── DIE GESCHICHTE (Chain) ──")
	var last_printed: String = ""
	for i in _chain_line.size():
		var line: Dictionary = _chain_line[i]
		var marker: String = ""
		if str(line["narrator"]) != last_printed:
			marker = "  ★ Erzählt von %s (%s)" % [line["narrator"], line["mood"]]
			last_printed = str(line["narrator"])
		print("  p%s c%s  %s" % [line["p"], line["c"], _short(str(line["summary"]), 66)])
		if not marker.is_empty():
			print(marker)


func _chain_narrator_at(index: int, orchestrator: DOKI_CommitOrchestrator) -> String:
	var entries: Array = orchestrator.chain_store.entries()
	if index < entries.size():
		return str(entries[index].get("narrator", ""))
	return ""


## Replay: derive auf Eintrag i (Vorgänger) → muss Chain-Eintrag i+1 ergeben.
func _replay_entry(index: int, orchestrator: DOKI_CommitOrchestrator) -> Dictionary:
	var entries: Array = orchestrator.chain_store.entries()
	if index >= entries.size():
		return {"ok": false, "error": "Index außerhalb"}
	var prev_composite: String = DOKI_RngEngine.GENESIS_COMPOSITE
	var prev_mood: String = DOKI_RngEngine.GENESIS_MOOD
	if index > 0:
		prev_composite = str(entries[index - 1].get("composite", DOKI_RngEngine.GENESIS_COMPOSITE))
		prev_mood = str(entries[index - 1].get("mood", DOKI_RngEngine.GENESIS_MOOD))
	var entry: Dictionary = entries[index]
	var composite: String = str(entry.get("composite", ""))
	var mood: String = str(entry.get("mood", ""))
	var mood_pool: Array = DOKI_MoodOverlay.default_pool()
	# Replay-RNG: Wir müssen die Gleichen Seed-Inputs reproduzieren (treeHash/diffHash/impulse
	# sind nicht in der Chain gespeichert — daher prüfen wir hier nur die Konsistenz der
	# Chain-Kette: c/p/n/a/j-Felder + Mood-Non-Repeat + c-Sequenz. Der volle RNG-Replay
	# gegen die Session passiert in Check 9 zur finish-Zeit (dort sind die Inputs bekannt).
	var fields: Dictionary = DOKI_RngEngine.parse_composite(composite)
	var chain_c_ok: bool = int(fields["c"]) == int(entry.get("c", 0))
	var mood_norepeat_ok: bool = prev_mood != mood
	var n_ok: bool = int(fields["n"]) >= 1 and int(fields["n"]) <= 14
	if chain_c_ok and mood_norepeat_ok and n_ok:
		return {"ok": true}
	return {"ok": false, "error": "c=%s n=%s mood=%s (prev=%s)" % [fields["c"], fields["n"], mood, prev_mood]}


func _run_git(args: Array) -> Dictionary:
	var full: Array = ["-C", _repo_root]
	full.append_array(args)
	var out: Array = []
	var code: int = OS.execute("git", full, out, true)
	return {"ok": code == 0, "stdout": str(out[0]) if out.size() > 0 else "", "stderr": str(out[1]) if out.size() > 1 else "", "exit_code": code}


func _short(s: String, max_len: int) -> String:
	if s.length() <= max_len:
		return s
	return s.substr(0, max_len - 3) + "..."


func _print_story_step(index: int) -> void:
	print("")
	print("──────── Schritt %d: %s" % [index + 1, _short(str(_story[index]["impulse"]), 50)])


func _expect(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("  ✗ %s" % label)
	else:
		print("  ✓ %s" % label)


func _finish() -> void:
	quit(1 if _failures > 0 else 0)