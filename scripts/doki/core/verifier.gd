class_name DOKI_Verifier
extends RefCounted
## Verifikation der Commit-Message — 11 Checks:
## Checks 1-6 (weich): Token, Impuls, Storytelling, Narrator, Composite, Cross-Narrator
## Checks 7-11 (HART): Kausalität, DocSync, ChainAudit, Datei-Limit (Atomicity), Mood-Einmaligkeit
##
## Portiert aus VerifyEngine.cs, aber mit sauberer soft/hard-Trennung
## (das alte System blockte bei JEDEM Fehler — auch bei weichen).

var _catalog: DOKI_NarratorCatalog
var _repo_root: String
var _changelog_path: String
var _config: Dictionary

const CAUSAL_CONNECTORS: String = "\\b(weil|deshalb|daher|dadurch|folglich|somit|Ursache|Wirkung)\\b"
const COMPOSITE_TOKEN_REGEX: String = "\\[COMPOSITE:(c\\d+j\\d+n\\d+a\\d+p\\d+)\\]"
## Atomicity-Gate (Check 10): max. Dateien pro Commit (ohne Auto-Managed
## narrative Dateien, die finalize selbst staged). Ein Commit = EINE logische
## Einheit — Mega-Commits (74+ Dateien) fressen Story-Platz und Info.
const MAX_FILES_PER_COMMIT: int = 200
## Von finish/finalize selbst gestagte narrative Dateien — zählen beim
## Datei-Limit nicht mit (identisch zu GateFlow.AUTO_MANAGED).
const AUTO_MANAGED: Array = ["narrative_chain.json", "change_index.json", "CHANGELOG.md", ".commit_msg.txt", "arcs.json"]
## Config-Pfad für RNG-Limits und Verifier-Regeln
const DOKI_CONFIG_PATH: String = "res://scripts/doki/data/doki_config.json"


func _init(catalog: DOKI_NarratorCatalog, repo_root: String) -> void:
	_catalog = catalog
	_repo_root = repo_root
	_changelog_path = repo_root.path_join("CHANGELOG.md")
	_config = _load_config()

func _load_config() -> Dictionary:
	var path: String = ProjectSettings.globalize_path(DOKI_CONFIG_PATH)
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		var content: String = file.get_as_text()
		file.close()
		return JSON.parse_string(content) if content != "" else {}
	return {}


## Prüft die Message gegen Session + Chain + Git-Zustand.
## Return: { success, hard_errors: [...], soft_errors: [...], checks: [...] }
func validate(message: String, session: Dictionary, chain: Dictionary, staged_file_names: Array, unstaged_doc_diffs: Array) -> Dictionary:
	var checks: Array = []
	var hard_errors: Array = []
	var soft_errors: Array = []

	_append(check_1_tokens(message, session), checks, hard_errors, soft_errors)
	_append(check_2_impulse(message, session), checks, hard_errors, soft_errors)
	_append(check_3_storytelling(message), checks, hard_errors, soft_errors)
	_append(check_4_narrator(message, session), checks, hard_errors, soft_errors)
	_append(check_5_composite(message, session, chain), checks, hard_errors, soft_errors)
	_append(check_6_cross_narrator(message, session), checks, hard_errors, soft_errors)
	_append(check_7_causality(message, session), checks, hard_errors, soft_errors)
	_append(check_8_docsync(message, session, staged_file_names, unstaged_doc_diffs), checks, hard_errors, soft_errors)
	_append(check_9_chain_audit(message, session, chain), checks, hard_errors, soft_errors)
	_append(check_10_file_limit(staged_file_names), checks, hard_errors, soft_errors)
	_append(check_11_mood_uniqueness(session), checks, hard_errors, soft_errors)

	return {
		"success": hard_errors.is_empty(),
		"hard_errors": hard_errors,
		"soft_errors": soft_errors,
		"checks": checks,
	}


## validate_amend(message) — für `doki amend` (Amend eines DOKI-Commits nach
## finalize, Session ist idle). Chain-verankert: die Erwartungswerte kommen aus
## dem letzten Chain-Eintrag (gleicher Commit, gleicher Composite) + den
## Message-Tokens. Check 9 (RNG-Replay) braucht die Session-Limits und ist in
## diesem Modus nicht möglich → dokumentiert übersprungen (Checks 1-8).
func validate_amend(message: String, chain: Dictionary, unstaged_doc_diffs: Array) -> Dictionary:
	var entries: Array = chain.get("entries", [])
	var last: Dictionary = entries[entries.size() - 1] if not entries.is_empty() else {}
	var composite: String = str(last.get("composite", ""))
	var fields: Dictionary = DOKI_RngEngine.parse_composite(composite)

	# Session-artige Erwartungswerte aus Chain + Message-Tokens rekonstruieren
	var session: Dictionary = {
		"narrator": str(last.get("narrator", "")),
		"prev_narrator": str(last.get("prev_narrator", "")),
		"impulse": _extract_token(message, "IMPULSE"),
		"composite": composite,
		"c": int(fields["c"]),
		"p": int(fields["p"]),
		"a": int(fields["a"]),
		"narrator_index": 0,
	}
	var checks: Array = []
	var hard_errors: Array = []
	var soft_errors: Array = []

	_append(check_1_tokens(message, session), checks, hard_errors, soft_errors)
	_append(check_2_impulse(message, session), checks, hard_errors, soft_errors)
	_append(check_3_storytelling(message), checks, hard_errors, soft_errors)
	_append(check_4_narrator(message, session), checks, hard_errors, soft_errors)
	_append(check_5_composite(message, session, chain), checks, hard_errors, soft_errors)
	_append(check_6_cross_narrator(message, session), checks, hard_errors, soft_errors)
	_append(check_7_causality(message, session), checks, hard_errors, soft_errors)
	_append(check_8_docsync(message, session, [], unstaged_doc_diffs), checks, hard_errors, soft_errors)

	return {
		"success": hard_errors.is_empty(),
		"hard_errors": hard_errors,
		"soft_errors": soft_errors,
		"checks": checks,
	}


static func _append(result: Dictionary, checks: Array, hard_errors: Array, soft_errors: Array) -> void:
	checks.append(result)
	if result["ok"]:
		return
	if result["hard"]:
		hard_errors.append("%s: %s" % [result["id"], result["message"]])
	else:
		soft_errors.append("%s: %s" % [result["id"], result["message"]])


## ─── Check 1: Pflicht-Tokens + Wortzahl (weich) ─────────────────────────
func check_1_tokens(message: String, session: Dictionary) -> Dictionary:
	var missing: Array = []
	for token in ["[NARRATOR:", "[MODEL:", "[IMPULSE:", "[COMPOSITE:"]:
		if not message.contains(token):
			missing.append(token)
	var ok: bool = missing.is_empty()

	# Wortzahl NUR des Narrator-Bodys (ohne Token-/Arc-/Begründungszeilen) —
	# sonst blähen maschinengenerierte Reason-Lines die Zählung auf (vgl. großen Commit).
	var word_count: int = _word_count(_body_only(message))
	var narrator: Dictionary = _catalog.by_name(str(session.get("narrator", "")))
	if not narrator.is_empty():
		var rules: Dictionary = narrator.get("verifier_rules", {})
		var min_words: int = int(rules.get("min_words", 30))
		var max_words: int = int(rules.get("max_words", 1500))
		if word_count < min_words:
			ok = false
			missing.append("Wortzahl %d < min %d" % [word_count, min_words])
		elif word_count > max_words:
			ok = false
			missing.append("Wortzahl %d > max %d" % [word_count, max_words])

	return _result("CHECK 1", false, ok, "Pflicht-Tokens (%s) fehlen." % ", ".join(missing) if not ok else "")


## ─── Check 2: Impuls-Integration (weich) ────────────────────────────────
func check_2_impulse(message: String, session: Dictionary) -> Dictionary:
	var impulse: String = str(session.get("impulse", ""))
	if impulse.length() < 5:
		return _result("CHECK 2", false, true, "")
	var body: String = message
	var impulse_words: PackedStringArray = impulse.split(" ")
	var found: bool = false
	for w in impulse_words:
		if w.length() > 3 and body.to_lower().contains(w.substr(0, w.length() if w.length() < 17 else 17).to_lower()):
			found = true
			break
	if not found:
		found = body.contains(impulse)  # Fallback: ganzer Impuls (ohne Token)
	return _result("CHECK 2", false, found, "IMPULSE nicht im Commit-Body integriert.")


## ─── Check 3: Storytelling (weich) ──────────────────────────────────────
func check_3_storytelling(message: String) -> Dictionary:
	# Nur den Narrator-Body prüfen — die maschinengenerierten Begründungszeilen
	# („- pfad: Grund.“) sind bewusst Bullets und dürfen die Ratio nicht kippen.
	var body: String = _body_only(message)
	var lines: Array = []
	for l in body.split("\n"):
		var lt: String = l.strip_edges()
		if not lt.is_empty():
			lines.append(lt)
	var bullet_lines: int = 0
	for l in lines:
		if str(l).begins_with("- ") or str(l).begins_with("* "):
			bullet_lines += 1
	var ok: bool = true
	var problems: Array = []
	if not lines.is_empty() and float(bullet_lines) > float(lines.size()) * 0.5:
		ok = false
		problems.append("Zu viele Bullet-Points (>50%). Fließtext erzwungen.")
	var re := RegEx.new()
	re.compile(CAUSAL_CONNECTORS)
	# Konnektoren IM BODY suchen (nicht in Tokens/Reason-Lines) — sonst
	# schlägt jeder Claim fehl, obwohl der Narrator „deshalb“ gesagt hat.
	if re.search(body) == null:
		ok = false
		problems.append("Keine kausalen Konnektoren im Body (weil/deshalb/daher/usw.).")
	return _result("CHECK 3", false, ok, " ".join(problems))


## ─── Check 4: Narrator-Validierung (weich) ──────────────────────────────
func check_4_narrator(message: String, session: Dictionary) -> Dictionary:
	var re := RegEx.new()
	re.compile("\\[NARRATOR:(\\w+)\\]")
	var m: RegExMatch = re.search(message)
	if m == null:
		return _result("CHECK 4", false, false, "[NARRATOR:X] fehlt.")
	var narrator_name: String = m.get_string(1)
	var expected: String = str(session.get("narrator", ""))
	if not _catalog.validate_name(narrator_name):
		return _result("CHECK 4", false, false, "Narrator '%s' nicht in narrators.json." % narrator_name)
	if not expected.is_empty() and narrator_name != expected:
		return _result("CHECK 4", false, false, "Narrator '%s' != Session-Narrator '%s' (Composite n-Feld verletzt)." % [narrator_name, expected])
	return _result("CHECK 4", false, true, "")


## ─── Check 5: Composite-Format + Felder (weich) ─────────────────────────
func check_5_composite(message: String, session: Dictionary, chain: Dictionary) -> Dictionary:
	var re := RegEx.new()
	re.compile(COMPOSITE_TOKEN_REGEX)
	var m: RegExMatch = re.search(message)
	if m == null:
		return _result("CHECK 5", false, false, "COMPOSITE-Token fehlt oder hat ungültiges Format.")
	var composite: String = m.get_string(1)
	var fields: Dictionary = DOKI_RngEngine.parse_composite(composite)
	var ok: bool = true
	var problems: Array = []
	var expected_c: int = int(session.get("c", 0))
	var expected_p: int = int(session.get("p", 0))
	if int(fields["c"]) != expected_c:
		ok = false
		problems.append("c-Feld %d != Session %d (Ketten-Sprung!)." % [int(fields["c"]), expected_c])
	if int(fields["p"]) != expected_p:
		ok = false
		problems.append("p-Feld %d != Session %d." % [int(fields["p"]), expected_p])
	var n: int = int(fields["n"])
	if n < 1 or n > 14:
		ok = false
		problems.append("n-Feld %d außerhalb 1-14." % n)
	if int(fields["a"]) != int(session.get("a", 0)):
		ok = false
		problems.append("a-Feld %d != Session %d." % [int(fields["a"]), int(session.get("a", 0))])
	return _result("CHECK 5", false, ok, " ".join(problems))


## ─── Check 6: Cross-Narrator (weich) ────────────────────────────────────
func check_6_cross_narrator(message: String, session: Dictionary) -> Dictionary:
	var prev: String = str(session.get("prev_narrator", ""))
	if prev.is_empty():
		return _result("CHECK 6", false, true, "")  # Genesis — kein Vorgänger
	# NUR der Narrator-Body zählt — die Subject-Erwähnung („… — nach X“) erfüllt
	# den Erzähl-Check nicht, sonst wäre die Body-Erwähnung nicht mehr erzwungen.
	var body: String = _body_only(message)
	var ok: bool = body.to_lower().contains(prev.to_lower())
	# Wenn [PREV_NARRATOR:...] Token existiert, muss der Name im Body stehen (ohne Token)
	var re := RegEx.new()
	re.compile("\\[PREV_NARRATOR:(\\w+)\\]")
	var m: RegExMatch = re.search(message)
	if m != null:
		var token_name: String = m.get_string(1)
		var body_clean: String = body.replace(m.get_string(0), "")
		if not body_clean.to_lower().contains(token_name.to_lower()):
			ok = false
	return _result("CHECK 6", false, ok, "Vorgänger-Narrator '%s' nicht im Commit-Body erwähnt." % prev)


## ─── Check 7: Kausalität (HARTER BLOCK) ─────────────────────────────────
func check_7_causality(message: String, session: Dictionary) -> Dictionary:
	# Kausalkette: Der Commit MUSS an die Session-Kausalkette anschließen.
	# (a) [IMPULSE:] ist der dokumentierte Auslöser — muss da sein und ≥5 Zeichen
	var re_impulse := RegEx.new()
	re_impulse.compile("\\[IMPULSE:(.+?)\\]")
	var m_impulse: RegExMatch = re_impulse.search(message)
	var ok: bool = true
	var problems: Array = []
	if m_impulse == null:
		ok = false
		problems.append("[IMPULSE:] fehlt — kein Kausalitäts-Anker.")
	elif m_impulse.get_string(1).strip_edges().length() < 5:
		ok = false
		problems.append("IMPULSE zu kurz (min. 5 Zeichen).")
	# (b) Ketten-Sprung: Message-Composite muss zur Session passen (keine alte/wiederverwendete Message)
	var re_comp := RegEx.new()
	re_comp.compile("\\[COMPOSITE:(c\\d+j\\d+n\\d+a\\d+p\\d+)\\]")
	var m_comp: RegExMatch = re_comp.search(message)
	if m_comp == null:
		ok = false
		problems.append("[COMPOSITE:] fehlt — keine Ketten-Referenz.")
	else:
		var fields: Dictionary = DOKI_RngEngine.parse_composite(m_comp.get_string(1))
		if int(fields["c"]) != int(session.get("c", 0)):
			ok = false
			problems.append("COMPOSITE c-Feld ist nicht der erwartete Kausalketten-Nachfolger (Stale Message?).")
		if int(fields["p"]) != int(session.get("p", 0)):
			ok = false
			problems.append("COMPOSITE p-Feld passt nicht zur Session (fremde Plot-ID?).")
	return _result("CHECK 7", true, ok, " ".join(problems) if not ok else "")


## ─── Check 8: DocSync (HARTER BLOCK) ────────────────────────────────────
## Doku-Dateien müssen existieren, nicht leer sein und KEINE ungestagten
## Diffs haben („verwaiste" Zwischenzustände sind blockiert).
## Die Staging-Anforderung ist bewusst KEIN Teil des Checks: die Artefakte
## werden erst NACH bestandener Verifikation geschrieben+gestaged
## (apply_commit_artifacts) — zum Check-Zeitpunkt kann die aktuelle
## Commit-Doku also noch gar nicht gestaged sein.
func check_8_docsync(message: String, session: Dictionary, staged_file_names: Array, unstaged_doc_diffs: Array) -> Dictionary:
	var ok: bool = true
	var problems: Array = []

	# 8a: Dateien existieren und sind nicht leer
	if not FileAccess.file_exists(_changelog_path):
		ok = false
		problems.append("CHANGELOG.md existiert nicht.")
	elif FileAccess.get_file_as_string(_changelog_path).strip_edges().is_empty():
		ok = false
		problems.append("CHANGELOG.md ist leer.")
	if not FileAccess.file_exists(_repo_root.path_join("change_index.json")):
		ok = false
		problems.append("change_index.json existiert nicht.")

	# 8b: keine ungestagten Diffs auf den Doku-Dateien (finalize staged seine
	# Updates selbst → nach finalize ist alles staged oder clean).
	for d in unstaged_doc_diffs:
		var dn: String = str(d).get_file()
		if dn == "CHANGELOG.md" or dn == "change_index.json" or dn == "narrative_chain.json":
			ok = false
			problems.append("Ungestagter Diff auf Doku-Datei: %s (Läufe `doki repair`.)" % str(d))

	return _result("CHECK 8", true, ok, " ".join(problems) if not ok else "")


## ─── Check 9: ChainAudit (HARTER BLOCK) ─────────────────────────────────
## Neu: chain-verankert statt `git log --all`. Bestands-Commits vor dem
## Genesis-Anker sind irrelevant — nur die DOKI-Chain muss lückenlos sein.
func check_9_chain_audit(message: String, session: Dictionary, chain: Dictionary) -> Dictionary:
	var ok: bool = true
	var problems: Array = []
	var entries: Array = chain.get("entries", [])

	# 9a: c-Folge lückenlos (jedes Entry c == vorheriges + 1, Start = 1)
	var seq: int = 0
	for e in entries:
		seq += 1
		if int(e.get("c", 0)) != seq:
			ok = false
			problems.append("Chain-Lücke bei seq %d (c=%d)." % [seq, int(e.get("c", 0))])
			break

	# 9b: letzter Chain-Eintrag passt zur Session (kein Doppel-Append, kein Verlust)
	var expected_c: int = int(session.get("c", 0))
	if not entries.is_empty():
		var last: Dictionary = entries[entries.size() - 1]
		if int(last.get("c", 0)) != expected_c - 1:
			ok = false
			problems.append("Chain letzter c=%d != Session c-1=%d (finalize fehlt oder Doppel-Append)." % [int(last.get("c", 0)), expected_c - 1])

	# 9c: reproduzierbar — RNG-Replay aus Session-Seed-Inputs
	var composite: String = str(session.get("composite", ""))
	var tree_hash: String = str(session.get("tree_hash", ""))
	var diff_hash: String = str(session.get("diff_hash", ""))
	var impulse: String = str(session.get("impulse", ""))
	var prev_composite: String = DOKI_RngEngine.GENESIS_COMPOSITE
	if not entries.is_empty():
		prev_composite = str(entries[entries.size() - 1].get("composite", DOKI_RngEngine.GENESIS_COMPOSITE))
	var mood_pool: Array = session.get("mood_pool", [])
	if mood_pool.is_empty():
		mood_pool = DOKI_MoodOverlay.default_pool()
	# Limits: Session > Config > Hardcoded Fallback (für RNG-Replay-Konsistenz)
	var cfg_limits: Dictionary = _config.get("rng_limits", {"j": 99, "n": 14, "a": 52, "p": 52})
	var limits: Dictionary = session.get("limits", cfg_limits)
	var prev_mood: String = str(session.get("prev_mood", DOKI_RngEngine.GENESIS_MOOD))
	var replayed: Dictionary = DOKI_RngEngine.derive(prev_composite, tree_hash, diff_hash, impulse, limits, prev_mood, mood_pool)
	if replayed["composite"] != composite:
		ok = false
		problems.append("RNG-Replay erzeugt '%s' statt Session-Composite '%s' (Manipulation?)." % [str(replayed["composite"]), composite])

	return _result("CHECK 9", true, ok, " ".join(problems) if not ok else "")


## ─── Check 11: Mood-Einmaligkeit (HARTER BLOCK) ──────────────────────────
## Der Mood darf sich nicht wiederholen (select_mood garantiert prev_mood != mood).
## Verifier prüft explizit: session.mood != session.prev_mood.
func check_11_mood_uniqueness(session: Dictionary) -> Dictionary:
	if not _config.get("verifier", {}).get("mood_uniqueness_check", true):
		return _result("CHECK 11", true, true, "Mood-Uniqueness-Check deaktiviert per Config.")
	var mood: String = str(session.get("mood", ""))
	var prev_mood: String = str(session.get("prev_mood", ""))
	var ok: bool = mood != prev_mood
	var msg: String = ""
	if not ok:
		msg = "Mood '%s' wiederholte sich (prev_mood war ebenfalls '%s'). select_mood() garantiert Einmaligkeit — Session korrupt?" % [mood, prev_mood]
	return _result("CHECK 11", true, ok, msg)
## Ein Commit = eine logische Einheit. Werden mehr als MAX_FILES_PER_COMMIT
## Dateien gestaged, ist der Commit zu groß — der Diff muss in atomare
## Commits aufgeteilt werden. Auto-managed narrative Dateien (finalize staged
## sie selbst) zählen nicht mit.
func check_10_file_limit(staged_file_names: Array) -> Dictionary:
	var user_files: Array = []
	for f in staged_file_names:
		if not AUTO_MANAGED.has(str(f).get_file()):
			user_files.append(str(f))
	var ok: bool = user_files.size() <= MAX_FILES_PER_COMMIT
	return _result("CHECK 10", true, ok, "Commit umfasst %d Dateien (max %d). Bitte in atomare Commits aufteilen — ein Commit = eine logische Einheit." % [user_files.size(), MAX_FILES_PER_COMMIT] if not ok else "")


## ─── Helfer ─────────────────────────────────────────────────────────────
## Extrahiert den Narrator-Body aus der Message-Struktur:
##   <subject> / [NARRATOR:X] / <body> / [MODEL:...] / [IMPULSE:...] / ... / Arc: ... / reason-lines
## Extrahiert den Wert eines Token (IMPULSE, MODEL, …) aus der Message.
static func _extract_token(message: String, token: String) -> String:
	var re := RegEx.new()
	re.compile("\\[%s:([^\\]]*)\\]" % token)
	var m: RegExMatch = re.search(message)
	if m == null:
		return ""
	return m.get_string(1).strip_edges()


static func _body_only(message: String) -> String:
	var lines: PackedStringArray = message.split("\n")
	var in_body: bool = false
	var out: Array = []
	for l in lines:
		if l.begins_with("[NARRATOR:"):
			in_body = true
			continue
		if l.begins_with("[MODEL:"):
			break
		if in_body:
			out.append(l)
	return "\n".join(out)


static func _word_count(text: String) -> int:
	if text.strip_edges().is_empty():
		return 0
	return text.split(" ", false).size()


static func _result(id: String, hard: bool, ok: bool, message: String) -> Dictionary:
	return {"id": id, "hard": hard, "ok": ok, "message": message}