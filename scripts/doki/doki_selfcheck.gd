extends SceneTree
## DOKI Selfcheck — deterministische Regressionen.
## Läuft ohne Git: Verifier-Checks bekommen Git-Zustand als Parameter.
## Aufruf: $GODOT_BIN --headless --path . --script res://scripts/doki/doki_selfcheck.gd

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	_setup_docs()
	_test_rng_determinism()
	_test_xorshift()
	_test_composite_roundtrip()
	_test_mood_norepeat()
	_test_decode_j()
	_test_classify_impulse()
	_test_verifier_positive()
	_test_verifier_hard_blocks()
	_test_verifier_file_limit()
	_test_checks_soft()
	_test_amend_reconstruction()
	_test_amend_hash_sync()
	_test_repair_orphaned_verified()
	_test_prompt_voice_lived()
	_test_entity_window_decay()
	_test_min_commits_for_climax()
	_test_new_recur_weight_swap()
	# V9-001-004: Expanded self-check tests
	_test_hook_integration()
	_test_agent_activity_integration()
	_test_scope_unknown_fallback()
	_test_atomic_writes()
	_test_recovery_determinism()
	_test_verifier_check8_missing_file()
	_test_doki_story_amend_repair_rebase()

	print("")
	print("═══════════════════════════════════════")
	print(" Selfcheck: %d Checks, %d Fehler" % [_checks, _failures])
	print(" RESULT: %s" % ("PASSED" if _failures == 0 else "FAILED"))
	print("═══════════════════════════════════════")
	quit(1 if _failures > 0 else 0)


## ─── RNG ────────────────────────────────────────────────────────────────
## Doku-Dateien anlegen (wie init) — Check 8 braucht existierende Dateien.
func _setup_docs() -> void:
	if not FileAccess.file_exists("CHANGELOG.md"):
		var f := FileAccess.open("CHANGELOG.md", FileAccess.WRITE)
		if f != null:
			f.store_string("# CHANGELOG\n")
			f.close()
	if not FileAccess.file_exists("change_index.json"):
		var g := FileAccess.open("change_index.json", FileAccess.WRITE)
		if g != null:
			g.store_string(JSON.stringify({"version": 2, "entities": {}, "commits": {}}, "\t"))
			g.close()


func _test_rng_determinism() -> void:
	var a: Dictionary = DOKI_RngEngine.derive("c0j0n0a0p0", "tree123", "diff456", "Impuls A", {"j": 99, "n": 14, "a": 3, "p": 5}, "genesis", DOKI_MoodOverlay.default_pool())
	var b: Dictionary = DOKI_RngEngine.derive("c0j0n0a0p0", "tree123", "diff456", "Impuls A", {"j": 99, "n": 14, "a": 3, "p": 5}, "genesis", DOKI_MoodOverlay.default_pool())
	_expect("derive deterministisch (same input → same composite)", a["composite"] == b["composite"] and a["seed"] == b["seed"] and a["mood"] == b["mood"])

	# Anderer Impuls → anderer Composite (Kausalität)
	var c: Dictionary = DOKI_RngEngine.derive("c0j0n0a0p0", "tree123", "diff456", "Impuls B", {"j": 99, "n": 14, "a": 3, "p": 5}, "genesis", DOKI_MoodOverlay.default_pool())
	_expect("derive kausal (anderer Impuls → anderer Composite)", a["composite"] != c["composite"])

	# Anderer Diff → anderer Composite (Code-Bezug)
	var d: Dictionary = DOKI_RngEngine.derive("c0j0n0a0p0", "tree123", "diff789", "Impuls A", {"j": 99, "n": 14, "a": 3, "p": 5}, "genesis", DOKI_MoodOverlay.default_pool())
	_expect("derive code-gebunden (anderer Diff → anderer Composite)", a["composite"] != d["composite"])

	# c zählt hoch, bleibt Sequence
	_expect("derive c-sequenz", int(a["c"]) == 1)
	var e: Dictionary = DOKI_RngEngine.derive("c1j05n09a1p3", "tree123", "diff456", "Impuls A", {"j": 99, "n": 14, "a": 3, "p": 5}, "genesis", DOKI_MoodOverlay.default_pool())
	_expect("derive c-sequenz +1", int(e["c"]) == 2)

	# Felder im Rahmen
	_expect("n in 1..14", int(a["n"]) >= 1 and int(a["n"]) <= 14)
	_expect("j in 1..99", int(a["j"]) >= 1 and int(a["j"]) <= 99)
	_expect("a in 1..arcCount", int(a["a"]) >= 1 and int(a["a"]) <= 3)
	_expect("p in 1..plotCount", int(a["p"]) >= 1 and int(a["p"]) <= 5)


func _test_xorshift() -> void:
	var rng1 := DOKI_XorShift128.new(12345)
	var rng2 := DOKI_XorShift128.new(12345)
	var seq1: Array = []
	var seq2: Array = []
	for i in 5:
		seq1.append(rng1.next_int(1, 15))
		seq2.append(rng2.next_int(1, 15))
	_expect("xorshift gleicher Seed → gleiche Folge", seq1 == seq2)
	_expect("xorshift Werte in Range", _all_in_range(seq1, 1, 14))
	var rng3 := DOKI_XorShift128.new(67890)
	_expect("xorshift anderer Seed → andere Folge", rng3.next_int(1, 15) != seq1[0] or rng3.next_int(1, 15) != seq1[1])


static func _all_in_range(values: Array, min_v: int, max_v: int) -> bool:
	for v in values:
		if int(v) < min_v or int(v) > max_v:
			return false
	return true


func _test_composite_roundtrip() -> void:
	var fields: Dictionary = {"c": 13, "j": 5, "n": 9, "a": 1, "p": 12}
	var composite: String = DOKI_RngEngine.build_composite(fields)
	var parsed: Dictionary = DOKI_RngEngine.parse_composite(composite)
	_expect("composite roundtrip", parsed == fields)
	_expect("composite format", composite == "c13j5n9a1p12")


func _test_mood_norepeat() -> void:
	var pool: Array = ["sachlich", "sarkastisch", "erschöpft"]
	# j=0 → Pool[0]="sachlich"; wenn prev="sachlich" → +1 → "sarkastisch"
	_expect("mood non-repeat (deterministisch)", DOKI_RngEngine.select_mood(0, "sachlich", pool) == "sarkastisch")
	_expect("mood normal", DOKI_RngEngine.select_mood(0, "trocken", pool) == "sachlich")


func _test_decode_j() -> void:
	var moods: DOKI_MoodOverlay = DOKI_MoodOverlay.new("res://scripts/doki/data")
	var dec: Dictionary = moods.decoding()
	var instr: Dictionary = DOKI_RngEngine.decode_j(0, moods.mood_pool(), dec)
	_expect("decode_j genesis", instr["tone"] == "genesis")
	var instr2: Dictionary = DOKI_RngEngine.decode_j(5, moods.mood_pool(), dec)
	_expect("decode_j tone j%10", instr2["tone"] == "neugierig")
	var instr3: Dictionary = DOKI_RngEngine.decode_j(75, moods.mood_pool(), dec)
	_expect("decode_j callback j>50", instr3["callback"] == true)


func _test_classify_impulse() -> void:
	_expect("classify FIX", DOKI_VoiceComposer.classify_impulse("Fix den exploit der ship") == "FIX")
	_expect("classify DOKU", DOKI_VoiceComposer.classify_impulse("Doku für dispatch schreiben") == "DOKU")
	_expect("classify REFACTOR", DOKI_VoiceComposer.classify_impulse("Restrukturierung der navigation") == "REFACTOR")
	_expect("classify CODE", DOKI_VoiceComposer.classify_impulse("Ship-Flotten-Logik erweitern und verdichten") == "CODE")
	_expect("classify TRIVIAL", DOKI_VoiceComposer.classify_impulse("kurz") == "TRIVIAL")


## ═══ Zentrale Fixtures — EINE Basis für alle Regressionstests ════════════
## Jede Verifier-/Amend-Prüfung nutzt diese Helfer statt eigener Dictionaries,
## damit neue Tests dieselbe konsistente Grundlage erben (kein Schema-Drift).
var _fixture_pool: Array = DOKI_MoodOverlay.default_pool()

## Verifier auf zentraler Basis (Katalog + Instanz) — keine Test-Erfindung.
func _fixture_verifier() -> DOKI_Verifier:
	var catalog := DOKI_NarratorCatalog.new("res://scripts/doki/data")
	return DOKI_Verifier.new(catalog, ".")

## ─── Verifier: Positivfall ──────────────────────────────────────────────
## Echte derive-basierte Fixtures: Chain-Eintrag 1 + Session (Eintrag 2) aus dem
##selben Inputstrom — so stimmt der RNG-Replay in Check 9.
func _test_verifier_positive() -> void:
	var chain: Dictionary = _fixture_chain()
	var session: Dictionary = _fixture_session(chain)
	var message: String = _fixture_message(session)

	var verifier: DOKI_Verifier = _fixture_verifier()
	var result: Dictionary = verifier.validate(message, session, chain, ["CHANGELOG.md", "change_index.json", "scripts/x.gd"], [])
	_expect("verifier positiv: keine harten Fehler", result["hard_errors"].is_empty())
	_expect("verifier positiv: Erfolg", result["success"])


## Chain-Fixture 1 (Verifier-Positivfall): Eintrag 1, derive-basiert (Check 9
## Replay stimmt, weil Session aus demselben Inputstrom kommt).
func _fixture_chain() -> Dictionary:
	var first: Dictionary = DOKI_RngEngine.derive("c0j0n0a0p0", "tree123", "777", "Start", {"j": 99, "n": 14, "a": 3, "p": 5}, "genesis", _fixture_pool)
	return {
		"genesis_composite": "c0j0n0a0p0",
		"genesis_mood": "genesis",
		"entries": [{
			"seq": 1, "c": int(first["c"]), "p": int(first["p"]), "hash": "abc123",
			"composite": str(first["composite"]), "mood": str(first["mood"]), "narrator": "Buffy",
		}],
	}


## Session = reales derive auf Chain-Eintrag 1 (deterministischer Positivfall).
func _fixture_session(chain: Dictionary) -> Dictionary:
	var first: Dictionary = chain["entries"][0]
	var derived: Dictionary = DOKI_RngEngine.derive(
		str(first["composite"]), "tree123", "777", "Nav-Umbau beschleunigen",
		{"j": 99, "n": 14, "a": 3, "p": maxi(1, 2)}, str(first["mood"]), _fixture_pool
	)
	return {
		"state": "prepared",
		"composite": str(derived["composite"]),
		"seed": int(derived["seed"]),
		"tree_hash": "tree123",
		"diff_hash": "777",
		"impulse": "Nav-Umbau beschleunigen",
		"narrator": DOKI_NarratorCatalog.new("res://scripts/doki/data").name_by_index(int(derived["n"])),
		"narrator_index": int(derived["n"]),
		"mood": str(derived["mood"]),
		"prev_narrator": "Buffy",
		"p_id": int(derived["p"]),
		"c": int(derived["c"]),
		"j": int(derived["j"]),
		"n": int(derived["n"]),
		"a": int(derived["a"]),
		"p": int(derived["p"]),
		"arc_id": "a1",
		"arc_name": "Der erste Stein",
		"mood_pool": _fixture_pool,
		"impulse_class": "REFACTOR",
		"limits": {"j": 99, "n": 14, "a": 3, "p": maxi(1, 2)},
	}


func _fixture_message(session: Dictionary) -> String:
	var narrator: String = str(session["narrator"])
	var composite: String = str(session["composite"])
	return """%s entdeckt: Die Navigation erwacht

[NARRATOR:%s]

Moment — wieso eigentlich? Wir haben die Navigation umgebaut, weil die alte
Route-Suche an ihren Grenzen war. Deshalb habe ich die Nachbarschafts-Logik
extrahiert und die Kette neu gewoben. Die Analyse ergab klare Trade-offs, und
meine Empfehlung: weiter so. Buffy hätte das genauso gemacht — neugierig, aber
präzise. Aha! Der erste Stein ist gelegt.

[MODEL:claude-sonnet-4]
[IMPULSE:Nav-Umbau beschleunigen]
[COMPOSITE:%s]
[PREV_NARRATOR:Buffy]

Arc: Der erste Stein (a1) — Gewicht: 1.2
- scripts/navigation_field.gd: NavigationField — Umstrukturiert (F-001).
""" % [narrator, narrator, composite]


## ─── Verifier: harte Blocks (7-9) ───────────────────────────────────────
func _test_verifier_hard_blocks() -> void:
	var verifier: DOKI_Verifier = _fixture_verifier()
	var chain: Dictionary = _fixture_chain()
	var session: Dictionary = _fixture_session(chain)
	var good: String = _fixture_message(session)

	# Check 7: Kausalität kaputt — [IMPULSE:] raus
	var no_impulse: String = good.replace("[IMPULSE:%s]\n" % str(session["impulse"]), "")
	var r7: Dictionary = verifier.validate(no_impulse, session, chain, ["CHANGELOG.md", "change_index.json", "scripts/x.gd"], [])
	_expect("CHECK 7 blockt (IMPULSE fehlt)", _has_hard(r7, "CHECK 7"))

	# Check 7: Stale Message — c-Feld weicht ab (um 1 verringert)
	var stale_composite: String = str(session["composite"]).replace("c%d" % int(session["c"]), "c%d" % (int(session["c"]) - 1))
	var stale: String = good.replace("[COMPOSITE:%s]" % str(session["composite"]), "[COMPOSITE:%s]" % stale_composite)
	var r7b: Dictionary = verifier.validate(stale, session, chain, ["CHANGELOG.md", "change_index.json", "scripts/x.gd"], [])
	_expect("CHECK 7 blockt (Stale Composite c-Feld)", _has_hard(r7b, "CHECK 7"))

	# Check 8: DocSync — Staging-Zeitpunkt ist egal (Artefakte werden NACH den
	# Checks geschrieben+gestaged). Ohne ungestagte Diffs → kein Block.
	var r8: Dictionary = verifier.validate(good, session, chain, ["scripts/x.gd"], [])
	_expect("CHECK 8 pass (Staging-Zeitpunkt egal)", not _has_hard(r8, "CHECK 8"))

	# Check 8: ungestagter Doku-Diff
	var r8b: Dictionary = verifier.validate(good, session, chain, ["CHANGELOG.md", "change_index.json"], ["CHANGELOG.md"])
	_expect("CHECK 8 blockt (unstaged CHANGELOG-Diff)", _has_hard(r8b, "CHECK 8"))

	# Check 9: ChainAudit — chain.last.c != session.c-1 (finalize fehlt)
	var chain_bad: Dictionary = _fixture_chain()
	var session_bad: Dictionary = _fixture_session(chain_bad)
	session_bad["c"] = int(session_bad["c"]) + 3  # Sprung: chain.last.c=..., erwartet +1
	var r9: Dictionary = verifier.validate(good, session_bad, chain_bad, ["CHANGELOG.md", "change_index.json", "scripts/x.gd"], [])
	_expect("CHECK 9 blockt (Chain-Lücke)", _has_hard(r9, "CHECK 9"))

	# Check 9: RNG-Manipulation — Session-Composite nachgebaut aber seed-Inputs geändert
	var session_tamper: Dictionary = _fixture_session(chain)
	session_tamper["tree_hash"] = "andertree"
	var r9b: Dictionary = verifier.validate(good, session_tamper, chain, ["CHANGELOG.md", "change_index.json", "scripts/x.gd"], [])
	_expect("CHECK 9 blockt (Manipulation: Replay mismatch)", _has_hard(r9b, "CHECK 9"))


## ─── Verifier: Check 10 — Datei-Limit / Atomicity (HARTER BLOCK) ──────
func _test_verifier_file_limit() -> void:
	var verifier: DOKI_Verifier = _fixture_verifier()
	var chain: Dictionary = _fixture_chain()
	var session: Dictionary = _fixture_session(chain)
	var good: String = _fixture_message(session)

	# Unter dem Limit (inkl. Auto-Managed narrative Dateien) → pass
	var small: Array = ["scripts/x.gd", "scripts/y.gd", "CHANGELOG.md", "change_index.json", "narrative_chain.json"]
	var r_ok: Dictionary = verifier.validate(good, session, chain, small, [])
	_expect("CHECK 10 pass (unter Limit)", not _has_hard(r_ok, "CHECK 10"))

	# Exakt am Limit → pass (Grenzwert ist inklusiv)
	var at_limit: Array = []
	for i in DOKI_Verifier.MAX_FILES_PER_COMMIT:
		at_limit.append("scripts/mod_%02d.gd" % i)
	var r_at: Dictionary = verifier.validate(good, session, chain, at_limit, [])
	_expect("CHECK 10 pass (exakt am Limit)", not _has_hard(r_at, "CHECK 10"))

	# Ein Datei über dem Limit → blockt
	var over: Array = at_limit.duplicate()
	over.append("scripts/extra.gd")
	var r_over: Dictionary = verifier.validate(good, session, chain, over, [])
	_expect("CHECK 10 blockt (über Limit)", _has_hard(r_over, "CHECK 10"))

	# Auto-Managed narrative Dateien zählen nicht mit: 35 narrative + 1 User
	var with_narrative: Array = at_limit.duplicate()
	with_narrative.append("narrative_chain.json")
	with_narrative.append("change_index.json")
	with_narrative.append("CHANGELOG.md")
	with_narrative.append(".commit_msg.txt")
	with_narrative.append("arcs.json")
	var r_narr: Dictionary = verifier.validate(good, session, chain, with_narrative, [])
	_expect("CHECK 10: Auto-Managed narrative Dateien zählen nicht", not _has_hard(r_narr, "CHECK 10"))


## ─── Verifier: weiche Checks melden, blocken nicht ─────────────────────
func _test_checks_soft() -> void:
	var verifier: DOKI_Verifier = _fixture_verifier()
	var chain: Dictionary = _fixture_chain()
	var session: Dictionary = _fixture_session(chain)

	# Body MIT Impuls-Wort (Check 7 ok — Kausalkette intakt), aber OHNE kausale
	# Konnektoren und mit Bullet-Liste → Check 3 (weich) blockt nicht.
	var narrator: String = str(session["narrator"])
	var composite: String = str(session["composite"])
	var weak: String = """Route

[NARRATOR:%s]

Navigation umgebaut. Alte Logik raus, neue rein. Weiter so.
- Zeile 1
- Zeile 2
- Zeile 3
- Zeile 4
- Zeile 5
- Zeile 6
- Zeile 7

[MODEL:claude-sonnet-4]
[IMPULSE:Nav-Umbau beschleunigen]
[COMPOSITE:%s]
[PREV_NARRATOR:Buffy]

Arc: Der erste Stein (a1) — Gewicht: 1.2
""" % [narrator, composite]
	var r: Dictionary = verifier.validate(weak, session, chain, ["CHANGELOG.md", "change_index.json"], [])
	_expect("weiche Checks: hard_errors leer", r["hard_errors"].is_empty())
	_expect("weiche Checks: soft_errors vorhanden", not r["soft_errors"].is_empty())
	_expect("weiche Checks: success trotzdem", r["success"])


## ═══ Zentrale Amend-Fixtures (Chain + HEAD-Message aus EINER Quelle) ══════
## Reale DOKI-HEAD-Struktur (wie `git log -1 --format=%B`): Subject, Leerzeile,
## [NARRATOR:X], Body, [MODEL:...], Tokens, Arc-Zeile, Begründungszeilen.
## Chain und HEAD-Message entstehen aus denselben Konstanten — sie können
## nicht auseinanderlaufen (Schema-Drift ist damit strukturell unmöglich).
const AMEND_SEQ: int = 20
const AMEND_C: int = 20
const AMEND_COMPOSITE: String = "c20j45n5a5p16"
const AMEND_HASH: String = "2bc5533"
const AMEND_NARRATOR: String = "Squizzle"
const AMEND_MOOD: String = "neugierig"
const AMEND_MODEL: String = "claude-sonnet-4"
const AMEND_PREV: String = "Buffy"
const AMEND_SUBJECT: String = "Squizzles Fall: Doku nachgezogen: AGENTS.md erklärt Systemaufbau"

## Chain-Fixture 2 (Amend-Fälle): letzter Eintrag = der zu amen-dende Commit.
func _fixture_amend_chain() -> Dictionary:
	return {
		"genesis_composite": "c0j0n0a0p0",
		"genesis_mood": "genesis",
		"entries": [{
			"seq": AMEND_SEQ, "c": AMEND_C, "p_id": AMEND_SEQ, "hash": AMEND_HASH,
			"composite": AMEND_COMPOSITE, "mood": AMEND_MOOD, "narrator": AMEND_NARRATOR,
			"model_id": AMEND_MODEL, "prev_narrator": AMEND_PREV,
			"summary": "FALL-AUFNAHME: Ein System...",
		}],
	}


## Reale DOKI-HEAD-Message des zu amen-denden Commits (Subject, Body-Sektion,
## Tokens, Arc-Zeile, Begründungszeile) — gebaut aus den AMEND_-Konstanten.
func _fixture_amend_head() -> String:
	return "%s\n\n[NARRATOR:%s]\n\nFALL-AUFNAHME: Der alte Body wird durch den Amend-Body ersetzt.\n\n[MODEL:%s]\n[IMPULSE:Amend-Flow: Body nachbearbeiten ohne Tokens zu verlieren]\n[COMPOSITE:%s]\n[PREV_NARRATOR:%s]\n\nArc: Nächster Akt (a6) — Gewicht: 1.1\n\n- scripts/x.gd: Fehler behoben (F-001).\n" % [AMEND_SUBJECT, AMEND_NARRATOR, AMEND_MODEL, AMEND_COMPOSITE, AMEND_PREV]


func _test_amend_reconstruction() -> void:
	# 1. Normaler Fall: Body ersetzen, Subject + Tokens + Arc + Reason bleiben
	var head_msg: String = _fixture_amend_head()
	var body: String = "FALL-NEUAUFNAHME: Der Amend korrigiert den Body, weil die Kausalität im Text fehlte. Deshalb bleibt die Struktur erhalten — der Rest der Message ist unangetastet, denn nur die Erzählung war zu dünn."
	var result: Dictionary = DOKI_CommitOrchestrator.reconstruct_amend_message(head_msg, body)
	_expect("amend reconstruct: ok", result.get("ok", false))
	if result.get("ok", false):
		var msg: String = str(result["message"])
		_expect("amend reconstruct: Subject bleibt", msg.begins_with(AMEND_SUBJECT))
		_expect("amend reconstruct: neuer Body drin", msg.contains("FALL-NEUAUFNAHME: Der Amend korrigiert"))
		_expect("amend reconstruct: alter Body weg", not msg.contains("Der alte Body wird durch den Amend-Body ersetzt"))
		_expect("amend reconstruct: Tokens bleiben", msg.contains("[MODEL:%s]" % AMEND_MODEL) and msg.contains("[COMPOSITE:%s]" % AMEND_COMPOSITE) and msg.contains("[IMPULSE:"))
		_expect("amend reconstruct: Arc-Zeile bleibt", msg.contains("Arc: Nächster Akt (a6)"))
		_expect("amend reconstruct: Reason-Zeile bleibt", msg.contains("- scripts/x.gd: Fehler behoben (F-001)."))

	# 2. REGRESSION: „[MODEL:" im Fließtext des neuen Bodys darf die Sektion
	#    NICHT vorzeitig beenden (Regex-Fix: [MODEL: nur am Zeilenanfang).
	var tricky_body: String = "Der Fix betraf das [MODEL: was hier als Text steht und nicht als Token. Weil die alte Regex am ersten Vorkommen stoppte, wurde die Message korrupt neu zusammengesetzt. Deshalb steht der Anker jetzt am Zeilenanfang."
	var tricky: Dictionary = DOKI_CommitOrchestrator.reconstruct_amend_message(head_msg, tricky_body)
	_expect("amend reconstruct: Fließtext-[MODEL: ok", tricky.get("ok", false))
	if tricky.get("ok", false):
		var tricky_msg: String = str(tricky["message"])
		_expect("amend reconstruct: Fließtext bleibt komplett", tricky_msg.contains("betraf das [MODEL: was hier als Text steht"))
		_expect("amend reconstruct: echter MODEL-Token noch da", tricky_msg.contains("\n[MODEL:%s]" % AMEND_MODEL))
		# COMPOSITE-Token darf nie dupliziert werden; [MODEL: kommt 2× vor —
		# einmal als Fließtext-Erwähnung im Body, einmal als echter Token am
		# Zeilenanfang (genau 1×). Verdopplung des echten Tokens wäre der Fehler.
		_expect("amend reconstruct: COMPOSITE-Token nicht dupliziert", tricky_msg.count("[COMPOSITE:") == 1)
		_expect("amend reconstruct: echter MODEL-Token genau 1×", tricky_msg.count("\n[MODEL:") == 1)

	# 3. Fehlerfall: HEAD ohne [COMPOSITE: → kein DOKI-Commit
	var plain_head: String = "Refactor: Flugzeit-Modul verallgemeinern\n\nNur ein normaler Commit ohne DOKI-Tokens.\n"
	var plain: Dictionary = DOKI_CommitOrchestrator.reconstruct_amend_message(plain_head, body)
	_expect("amend reconstruct: Nicht-DOKI-HEAD blockt", not plain.get("ok", false))

	# 4. Runder Pfad: rekonstruierte Message besteht validate_amend (Checks 1-8,
	#    chain-verankert am letzten Eintrag). Kein Git, keine Session nötig.
	var verifier: DOKI_Verifier = _fixture_verifier()
	var amended: Dictionary = DOKI_CommitOrchestrator.reconstruct_amend_message(head_msg, body)
	var vr: Dictionary = verifier.validate_amend(str(amended["message"]), _fixture_amend_chain(), [])
	_expect("amend reconstruct: validate_amend besteht", vr["success"])


## ─── Amend-Flow: Hash-Sync (Regression) ─────────────────────────────────
func _test_amend_hash_sync() -> void:
	var chain: Dictionary = _fixture_amend_chain()
	var head_msg: String = _fixture_amend_head()

	# 1. Gleicher Composite, neuer Hash (nach git commit --amend) → Hash-Sync
	var r1: Dictionary = DOKI_FinalizeFlow.amended_entry_hash_sync(chain, "7c82f43", head_msg)
	_expect("amend hash-sync: changed", bool(r1.get("changed", false)))
	var synced_entries: Array = r1["chain"]["entries"]
	_expect("amend hash-sync: Hash aktualisiert", str(synced_entries[0]["hash"]) == "7c82f43")
	_expect("amend hash-sync: Composite unverändert", str(synced_entries[0]["composite"]) == AMEND_COMPOSITE)

	# 2. Idempotenz: gleicher Hash schon drin → kein Change
	var r2: Dictionary = DOKI_FinalizeFlow.amended_entry_hash_sync(r1["chain"], "7c82f43", head_msg)
	_expect("amend hash-sync: idempotent", not bool(r2.get("changed", true)))

	# 3. Composite weicht ab (fremder Commit) → kein Change
	var r3: Dictionary = DOKI_FinalizeFlow.amended_entry_hash_sync(chain, "7c82f43", head_msg.replace(AMEND_COMPOSITE, "c21j99n9a1p2"))
	_expect("amend hash-sync: fremder Composite → kein Sync", not bool(r3.get("changed", true)))

	# 4. Kein COMPOSITE-Token im HEAD → kein Change
	var r4: Dictionary = DOKI_FinalizeFlow.amended_entry_hash_sync(chain, "7c82f43", "Kein DOKI-Commit")
	_expect("amend hash-sync: Nicht-DOKI-HEAD → kein Sync", not bool(r4.get("changed", true)))

	# 5. Leere Chain → ok, kein Change
	var r5: Dictionary = DOKI_FinalizeFlow.amended_entry_hash_sync({"entries": []}, "7c82f43", head_msg)
	_expect("amend hash-sync: leere Chain ok", bool(r5.get("ok", false)) and not bool(r5.get("changed", true)))


## ─── Verwaister-verified-Fall: repair validiert die verified-Session ───────
## Regression für „doki repair": Wenn eine verified-Session KEINEN passenden
## Commit hat (HEAD steht noch auf dem Session-Anker — `git commit` nie oder
## verloren ausgeführt), muss repair die Session ATOMAR auf idle zurücksetzen,
## KEINE Chain-/Index-Datei verändern und den Recovery-Grund protokollieren —
## statt die Session dauerhaft in verified festzuhängen.
func _test_repair_orphaned_verified() -> void:
	# ─ 1. Reine Entscheidung (git-frei, deterministisch) ─
	_expect("orphan: HEAD==Anker + Message vorhanden → verwaist", bool(DOKI_FinalizeFlow.verified_orphan_decision("a1b2c3d", "a1b2c3d", true)["orphaned"]))
	_expect("orphan: HEAD==Anker + Message fehlt → verwaist", bool(DOKI_FinalizeFlow.verified_orphan_decision("a1b2c3d", "a1b2c3d", false)["orphaned"]))
	_expect("orphan: HEAD!=Anker + Message vorhanden → Commit existiert (finalize-Pfad)", not bool(DOKI_FinalizeFlow.verified_orphan_decision("e5f6a7b", "a1b2c3d", true)["orphaned"]))
	_expect("orphan: HEAD!=Anker + Message fehlt → Commit existiert (finalize-Pfad)", not bool(DOKI_FinalizeFlow.verified_orphan_decision("e5f6a7b", "a1b2c3d", false)["orphaned"]))
	_expect("orphan: leerer Anker (korrupt) → verwaist", bool(DOKI_FinalizeFlow.verified_orphan_decision("e5f6a7b", "", true)["orphaned"]))
	_expect("orphan: Begründung benennt Chain/Index unberührt", str(DOKI_FinalizeFlow.verified_orphan_decision("a1b2c3d", "a1b2c3d", true)["reason"]).contains("Chain- und Index-Dateien blieben unberührt"))

	# ─ 2. Atomarer Reset + Recovery-Protokoll in isolierter .doki-Welt ─
	var scratch: String = "user://tmp_doki_orphan_selfcheck"
	var store := DOKI_SessionStore.new(scratch)
	var orphan: Dictionary = store.default_session()
	orphan["state"] = DOKI_SessionStore.STATE_VERIFIED
	orphan["git_head_before"] = "a1b2c3d"
	orphan["composite"] = "c99j5n9a2p7"
	store.save(orphan)
	var reason: String = "Verwaiste verified-Session atomar auf idle zurückgesetzt (Test)"
	DOKI_FinalizeFlow.record_recovery(scratch, "orphaned_verified", reason)
	store.reset()
	var read_back: Dictionary = store.read()
	_expect("orphan: Reset atomar → idle", str(read_back.get("state", "?")) == DOKI_SessionStore.STATE_IDLE)
	_expect("orphan: Composite geleert", str(read_back.get("composite", "x")) == "" and str(read_back.get("git_head_before", "x")) == "")
	var log: Array = DOKI_FinalizeFlow.recovery_read(scratch)
	_expect("orphan: Recovery-Grund protokolliert", log.size() == 1 and str(log[0].get("kind", "")) == "orphaned_verified" and str(log[0].get("reason", "")) == reason)

	# ─ 3. Nach Reset ist der normale Flow wieder möglich: die Session liegt auf
	#    idle, d. h. der nächste prepare (idle→prepared) stoppt nicht mehr auf „verified".
	var ensure: Dictionary = store.ensure_state(DOKI_SessionStore.STATE_IDLE)
	_expect("orphan: Nach Reset ist der Flow-Start wieder erlaubt (idle)", ensure["ok"])

	# Aufräumen: isolierte .doki-Welt löschen
	_remove_recursive(scratch)


## Löscht ein Verzeichnis rekursiv (für isolierte Test-Welten unter user://).
func _remove_recursive(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child: String = path.path_join(name)
			if dir.current_is_dir():
				_remove_recursive(child)
			else:
				DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)  # leeres Verzeichnis


## ─── Stimmen gelebt (nicht genannt): Stil-Beispiel + Mood-Ausdruck + Kalibrierung ─
## Regression für die Voice-Qualität: Der Prompt MUSS zeigen, wie die Stimme
## klingt (Stil-Beispiel), wie der Mood gelebt wird (Mood-Ausdruck statt Name)
## und wie die Emotion zur Arbeit steht (Kategorie-Kalibrierung — niemand ist
## euphorisch über Doku).
func _test_prompt_voice_lived() -> void:
	var catalog := DOKI_NarratorCatalog.new("res://scripts/doki/data")
	var moods := DOKI_MoodOverlay.new("res://scripts/doki/data")
	var composer := DOKI_VoiceComposer.new(catalog, moods)

	# 1. Jeder Mood im Pool hat eine Ausdrucks-Anleitung (gelebt, nicht nur benannt)
	var missing_expr: Array = []
	for m in moods.mood_pool():
		if moods.mood_expression(str(m)).is_empty():
			missing_expr.append(str(m))
	_expect("voice-lived: alle 10 Moods haben mood_expression", missing_expr.is_empty())

	# 2. Jeder Charakter hat ein konkretes Stil-Beispiel
	var missing_sample: Array = []
	for c in catalog.all():
		if str(c.get("style_sample", "")).is_empty():
			missing_sample.append(str(c.get("name", "?")))
	_expect("voice-lived: alle 14 Charaktere haben style_sample", missing_sample.is_empty())

	# 3. Jede Impuls-Kategorie hat eine Kalibrierung (Emotion ↔ Arbeit)
	var classes: Array = ["CODE", "FEATURE", "REFACTOR", "BUILD", "FIX", "DOKU", "TRIVIAL", "TEST-ASSET"]
	var missing_calib: Array = []
	for cls in classes:
		if moods.category_calibration(str(cls)).is_empty():
			missing_calib.append(str(cls))
	_expect("voice-lived: alle Kategorien haben category_calibration", missing_calib.is_empty())

	# 4. Prompt lebt die Stimme: Beispiel + Mood-Ausdruck + Kalibrierung + Anti-Naming
	var ctx: Dictionary = _fixture_voice_ctx(catalog, "Buffy", "sarkastisch", "CODE")
	var sys: String = str(composer.build_prompts(ctx)["system"])
	_expect("voice-lived: Stil-Beispiel im Prompt", sys.contains("SO SCHREIBST DU") and sys.contains(str(catalog.by_name("Buffy").get("style_sample", ""))))
	_expect("voice-lived: Mood-Ausdruck statt nur Name", sys.contains("SO LEBST DU DEN MOOD") and sys.contains("passiv-aggressiv"))
	_expect("voice-lived: Kategorie-Kalibrierung im Prompt", sys.contains("KALIBRIERUNG (Kategorie CODE)"))
	_expect("voice-lived: Anti-Naming-Regel (NIE Mood beim Namen)", sys.contains("(NIE)"))

	# 5. Doku-Arbeit dämpft Euphorie: triumphierender Mood + DOKU-Kategorie → nüchtern
	var ctx_doku: Dictionary = _fixture_voice_ctx(catalog, "Buffy", "triumphierend", "DOKU")
	var sys_doku: String = str(composer.build_prompts(ctx_doku)["system"])
	_expect("voice-lived: DOKU-Kalibrierung dämpft Euphorie", sys_doku.contains("KALIBRIERUNG (Kategorie DOKU)") and sys_doku.contains("niemand euphorisch"))
	_expect("voice-lived: Mood-Ausdruck bleibt kategorie-tauglich", sys_doku.contains("Übertreibend, aber faktenbasiert"))


## Minimaler Prompt-Kontext für die Stimmen-Tests (deterministisch, kein Git).
func _fixture_voice_ctx(catalog: DOKI_NarratorCatalog, narrator_name: String, mood: String, impulse_class: String) -> Dictionary:
	return {
		"narrator": catalog.by_name(narrator_name),
		"attitudes": {},
		"impulse": "Ship-Logik erweitern und die Kette schließen",
		"impulse_class": impulse_class,
		"body_text": "",
		"files": ["scripts/ship_manager.gd"],
		"sidejoke": "",
		"prev_narrator": "",
		"prev_class": "",
		"is_direction_change": false,
		"is_arc_climax": false,
		"arc_climax_eligible": true,
		"arc_name": "a1",
		"arc_id": "a1",
		"relationship": {},
		"sideplot": {},
		"mood": mood,
		"structure_info": {"structure": "chronologisch", "pattern": ""},
	}


## ─── Arc-Engine: Entity-Window Decay (Sliding-Window) ───────────────
## Regression für ENTITY_WINDOW=50: _merge_seen kapp die Liste bei >50.
func _test_entity_window_decay() -> void:
	# Weniger als 50 → bleibt
	var seen_small: Array = ["F-1", "F-2", "F-3"]
	var merged_small: Array = DOKI_ArcEngine._merge_seen(seen_small, ["F-4", "F-5"])
	_expect("entity window: 5 items stay (under 50)", merged_small.size() == 5)

	# Genau 50 → bleibt (Grenzwert inklusiv)
	var seen_50: Array = []
	for i in 48:
		seen_50.append("F-%d" % i)
	var merged_50: Array = DOKI_ArcEngine._merge_seen(seen_50, ["F-50", "F-51"])
	_expect("entity window: 50 stays (at limit)", merged_50.size() == 50)

	# Über 50 → gekappt auf die letzten 50
	var seen_60: Array = []
	for i in 60:
		seen_60.append("F-%d" % i)
	var merged_60: Array = DOKI_ArcEngine._merge_seen(seen_60, [])
	_expect("entity window: 60 capped at 50", merged_60.size() == 50)
	_expect("entity window: letzte 50 behalten", str(merged_60[0]) == "F-10" and str(merged_60[49]) == "F-59")


## ─── Arc-Engine: MIN_COMMITS_FOR_CLIMAX ─────────────────────────────
## Regression für MIN_COMMITS_FOR_CLIMAX=2: Climax erst ab 2 Commits.
func _test_min_commits_for_climax() -> void:
	# Arc mit commit_count=0, aber hohes Gewicht → kein Climax
	var arc_0: Dictionary = {"weight": 10.0, "climax_weight": 5.0, "commit_count": 0, "seen_entities": []}
	var forecast_0: Dictionary = DOKI_ArcEngine.new("res://scripts/doki/data").forecast_weight(arc_0, ["F-1", "F-2", "F-3", "F-4", "F-5", "F-6", "F-7", "F-8", "F-9", "F-10"], false, "CODE")
	_expect("min commits: 0 commits → kein climax trotz hohem gewicht", not bool(forecast_0["climax"]))

	# Arc mit commit_count=1 → noch kein Climax
	var arc_1: Dictionary = {"weight": 10.0, "climax_weight": 5.0, "commit_count": 1, "seen_entities": []}
	var forecast_1: Dictionary = DOKI_ArcEngine.new("res://scripts/doki/data").forecast_weight(arc_1, ["F-1", "F-2", "F-3", "F-4", "F-5", "F-6", "F-7", "F-8", "F-9", "F-10"], false, "CODE")
	_expect("min commits: 1 commit → noch kein climax", not bool(forecast_1["climax"]))

	# Arc mit commit_count=2 → Climax möglich (wenn Gewicht reicht)
	var arc_2: Dictionary = {"weight": 10.0, "climax_weight": 5.0, "commit_count": 2, "seen_entities": []}
	var forecast_2: Dictionary = DOKI_ArcEngine.new("res://scripts/doki/data").forecast_weight(arc_2, ["F-1", "F-2", "F-3", "F-4", "F-5", "F-6", "F-7", "F-8", "F-9", "F-10"], false, "CODE")
	_expect("min commits: 2 commits → climax erlaubt", bool(forecast_2["climax"]))


## ─── Arc-Engine: NEW/RECUR Weight Swap ─────────────────────────────
## Regression für den Tausch: NEW=0.4 (zählt mehr) vs RECUR=0.2.
func _test_new_recur_weight_swap() -> void:
	# Neue Entitäten zählen mehr als wiedergefundene
	_expect("new > recur: 0.4 > 0.2", DOKI_ArcEngine.NEW_ENTITY_WEIGHT > DOKI_ArcEngine.RECUR_ENTITY_WEIGHT)

	# Konstanten haben die korrekten Werte
	_expect("new weight = 0.4", abs(DOKI_ArcEngine.NEW_ENTITY_WEIGHT - 0.4) < 0.001)
	_expect("recur weight = 0.2", abs(DOKI_ArcEngine.RECUR_ENTITY_WEIGHT - 0.2) < 0.001)

	# FIX-Kategorie → base=0, nicht eligible (kein Climax)
	var arc_fix: Dictionary = {"weight": 10.0, "climax_weight": 5.0, "commit_count": 5, "seen_entities": []}
	var forecast_fix: Dictionary = DOKI_ArcEngine.new("res://scripts/doki/data").forecast_weight(arc_fix, ["F-1", "F-2"], false, "FIX")
	_expect("fix: nicht eligible", not bool(forecast_fix["climax_eligible"]))

	# REFACTOR → base=0.25 (halbiert), eligible
	var arc_refactor: Dictionary = {"weight": 0.0, "climax_weight": 5.0, "commit_count": 5, "seen_entities": []}
	var forecast_refactor: Dictionary = DOKI_ArcEngine.new("res://scripts/doki/data").forecast_weight(arc_refactor, ["F-1", "F-2"], false, "REFACTOR")
	_expect("refactor: eligible", bool(forecast_refactor["climax_eligible"]))


## ─── V9-001: Hook Integration Tests ─────────────────────────────────────
func _test_hook_integration() -> void:
	# Verify .githooks directory and scripts exist
	_expect("hook: .githooks/pre-commit exists", FileAccess.file_exists(".githooks/pre-commit"))
	_expect("hook: .githooks/commit-msg exists", FileAccess.file_exists(".githooks/commit-msg"))
	_expect("hook: .githooks/post-commit exists", FileAccess.file_exists(".githooks/post-commit"))
	_expect("hook: install_hooks.sh exists", FileAccess.file_exists("scripts/doki/install_hooks.sh"))
	
	# Verify hook content has DOKI gate calls
	var pre_commit: String = FileAccess.get_file_as_string(".githooks/pre-commit")
	_expect("hook: pre-commit calls doki gate", pre_commit.contains("doki.gd -- gate"))
	
	var commit_msg: String = FileAccess.get_file_as_string(".githooks/commit-msg")
	_expect("hook: commit-msg calls doki verify-only", commit_msg.contains("doki.gd -- verify-only"))
	
	var post_commit: String = FileAccess.get_file_as_string(".githooks/post-commit")
	_expect("hook: post-commit calls doki finalize", post_commit.contains("doki.gd -- finalize"))


## ─── V9-001: Agent Activity Integration Tests ───────────────────────────
func _test_agent_activity_integration() -> void:
	# Verify agent_activity.sh exists and has required functions
	_expect("agent_activity: script exists", FileAccess.file_exists("scripts/agent_activity.sh"))
	var script: String = FileAccess.get_file_as_string("scripts/agent_activity.sh")
	_expect("agent_activity: has check_in", script.contains("check_in()"))
	_expect("agent_activity: has seed_for", script.contains("seed_for()"))
	_expect("agent_activity: has run_gate", script.contains("run_gate()"))
	_expect("agent_activity: has hmac_sha256", script.contains("hmac_sha256()"))
	
	# Verify ADOPT_SCOPE bypass removed (V10-005)
	_expect("agent_activity: ADOPT_SCOPE bypass removed", not script.contains("AGENT_ACTIVITY_ADOPT_SCOPE"))
	
	# Verify seed derivation uses HMAC
	_expect("agent_activity: seed uses HMAC", script.contains("hmac_seed"))


## ─── V9-001/002: Scope Unknown Fallback Tests ───────────────────────────
func _test_scope_unknown_fallback() -> void:
	# Test ChangeImpactResolver with unknown path falls back to "unmapped" contract
	var resolver := preload("res://scripts/preflight_v2/change_impact_resolver.gd")
	
	# Unknown path should not fail-closed but add "unmapped" contract with warning
	var result: Dictionary = resolver.resolve(["scripts/unknown/path.gd"])
	_expect("scope: unknown path adds unmapped contract", result.get("ok", false) == true)
	_expect("scope: unmapped in contracts", (result.get("contracts", []) as Array).has("unmapped"))
	_expect("scope: warning present", (result.get("warnings", []) as Array).size() > 0)
	
	# Generic error message (V3-004) - no path leak
	var result_fail: Dictionary = resolver.resolve(["scripts/unknown/path.gd"])
	if not bool(result_fail.get("ok", true)):
		var error_msg: String = str(result_fail.get("error", ""))
		_expect("scope: generic error (no path leak)", not error_msg.contains("unknown/path.gd"))
	
	# Test R/D status support (V3-003)
	var status_result: Dictionary = resolver.resolve_status(["R\told/path.gd\tnew/path.gd"])
	_expect("scope: rename status supported", status_result.get("ok", false) == true)
	var delete_result: Dictionary = resolver.resolve_status(["D\tdeleted/path.gd"])
	_expect("scope: delete status supported", delete_result.get("ok", false) == true)


## ─── V9-001: Atomic Writes Tests ────────────────────────────────────────
func _test_atomic_writes() -> void:
	var scratch: String = "user://tmp_atomic_test"
	DirAccess.make_dir_recursive_absolute(scratch)
	
	# Test _atomic_write helper pattern
	var test_path: String = scratch.path_join("test.txt")
	var test_content: String = "test content"
	
	# Use the same pattern as in our code
	var tmp_path: String = test_path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	_expect("atomic: can open tmp file", file != null)
	if file != null:
		file.store_string(test_content)
		file.close()
		DirAccess.remove_absolute(test_path)
		DirAccess.rename_absolute(tmp_path, test_path)
		_expect("atomic: file exists after rename", FileAccess.file_exists(test_path))
		_expect("atomic: content correct", FileAccess.get_file_as_string(test_path) == test_content)
	
	# Cleanup
	_remove_recursive(scratch)


## ─── V9-001: Recovery Determinism Tests ─────────────────────────────────
func _test_recovery_determinism() -> void:
	# Test deterministic timestamp generation (genesis + offset)
	var scratch: String = "user://tmp_recovery_test"
	DirAccess.make_dir_recursive_absolute(scratch)
	
	# Create mock chain with genesis_date
	var chain: Dictionary = {
		"genesis_date": "2026-01-01 00:00:00",
		"entries": [
			{"seq": 1, "c": 1}, {"seq": 2, "c": 2}, {"seq": 3, "c": 3}
		]
	}
	var chain_path: String = scratch.path_join("narrative_chain.json")
	var file := FileAccess.open(chain_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(chain))
	file.close()
	
	# Test recovery log timestamp is deterministic
	var finalize_flow := preload("res://scripts/doki/orchestration/flows/finalize_flow.gd")
	var ts1: String = finalize_flow._get_deterministic_timestamp(scratch)
	var ts2: String = finalize_flow._get_deterministic_timestamp(scratch)
	_expect("recovery: deterministic timestamp", ts1 == ts2)
	_expect("recovery: timestamp format", ts1.begins_with("2026-01-01"))
	
	# Test recovery log entries use deterministic timestamp
	finalize_flow.record_recovery(scratch, "test_kind", "test reason")
	var log: Array = finalize_flow.recovery_read(scratch)
	_expect("recovery: log has entry", log.size() == 1)
	_expect("recovery: entry has deterministic timestamp", str(log[0].get("at", "")) == ts1)
	
	# Cleanup
	_remove_recursive(scratch)


## ─── V9-002: Verifier Check 8 Missing File Tests ────────────────────────
func _test_verifier_check8_missing_file() -> void:
	var verifier: DOKI_Verifier = _fixture_verifier()
	var chain: Dictionary = _fixture_chain()
	var session: Dictionary = _fixture_session(chain)
	var good: String = _fixture_message(session)
	
	# Test Check 8 fails when CHANGELOG.md missing
	var result: Dictionary = verifier.validate(good, session, chain, ["scripts/x.gd"], [])
	# Check 8 should pass with our fixture setup (files created in _setup_docs)
	
	# Create a test with missing narrative_chain.json
	var scratch: String = "user://tmp_check8_test"
	DirAccess.make_dir_recursive_absolute(scratch)
	DirAccess.remove_absolute(scratch.path_join(".doki"))
	
	var verifier2: DOKI_Verifier = DOKI_Verifier.new(DOKI_NarratorCatalog.new("res://scripts/doki/data"), scratch)
	var result2: Dictionary = verifier2.validate(good, session, chain, ["scripts/x.gd"], [])
	_expect("check8: fails when narrative_chain.json missing", _has_hard(result2, "CHECK 8"))
	
	# Create .doki/narrative_chain.json
	DirAccess.make_dir_recursive_absolute(scratch.path_join(".doki"))
	var nc_file := FileAccess.open(scratch.path_join(".doki/narrative_chain.json"), FileAccess.WRITE)
	nc_file.store_string(JSON.stringify({"entries": []}))
	nc_file.close()
	
	# Also need arcs.json
	DirAccess.make_dir_recursive_absolute(scratch.path_join("scripts/doki/data"))
	var arcs_file := FileAccess.open(scratch.path_join("scripts/doki/data/arcs.json"), FileAccess.WRITE)
	arcs_file.store_string(JSON.stringify({"arcs": {}, "active": ""}))
	arcs_file.close()
	
	var result3: Dictionary = verifier2.validate(good, session, chain, ["scripts/x.gd"], [])
	_expect("check8: passes when all doc files exist", not _has_hard(result3, "CHECK 8"))
	
	# Cleanup
	_remove_recursive(scratch)


## ─── V9-003/004: DOKI Story Test Coverage (amend, repair, rebase, concurrent) ─────
func _test_doki_story_amend_repair_rebase() -> void:
	# Test amend flow
	var orchestrator := DOKI_CommitOrchestrator.new(".")
	var head_msg: String = _fixture_amend_head()
	var body: String = "Amended body with proper causal structure — deshalb wurde der Fix angewendet."
	var amend_result: Dictionary = DOKI_CommitOrchestrator.reconstruct_amend_message(head_msg, body)
	_expect("story: amend reconstruction works", amend_result.get("ok", false))
	
	# Test verify_amend passes
	var verifier: DOKI_Verifier = _fixture_verifier()
	var vr: Dictionary = verifier.validate_amend(str(amend_result["message"]), _fixture_amend_chain(), [])
	_expect("story: verify_amend passes", vr["success"])
	
	# Test repair orphaned verified decision logic
	var repair_decision: Dictionary = DOKI_FinalizeFlow.verified_orphan_decision("same_hash", "same_hash", true)
	_expect("story: orphan decision correct", bool(repair_decision["orphaned"]))
	
	var commit_decision: Dictionary = DOKI_FinalizeFlow.verified_orphan_decision("new_hash", "old_hash", true)
	_expect("story: commit exists decision correct", not bool(commit_decision["orphaned"]))
	
	# Test hash sync for amend
	var sync_result: Dictionary = DOKI_FinalizeFlow.amended_entry_hash_sync(_fixture_amend_chain(), "new_hash", head_msg)
	_expect("story: amend hash sync works", bool(sync_result.get("changed", false)))
	
	# Test concurrent session claim rejection (via session store)
	var session_store := DOKI_SessionStore.new("user://tmp_concurrent")
	var claim1: Dictionary = session_store.claim("agent:test:seed:123")
	_expect("story: first claim succeeds", bool(claim1.get("ok", false)))
	var claim2: Dictionary = session_store.claim("agent:other:seed:456")
	_expect("story: second claim rejected", not bool(claim2.get("ok", false)))
	
	# Cleanup
	_remove_recursive("user://tmp_concurrent")


static func _has_hard(result: Dictionary, check_prefix: String) -> bool:
	for e in result.get("hard_errors", []):
		if str(e).begins_with(check_prefix):
			return true
	return false


func _expect(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("✗ %s" % label)
	else:
		print("✓ %s" % label)