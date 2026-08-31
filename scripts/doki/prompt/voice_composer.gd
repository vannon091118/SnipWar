class_name DOKI_VoiceComposer
extends RefCounted
## Prompt-Engine, Port aus VoiceComposer.cs (v3) — der ausgereifteste Teil des
## alten Systems. Baut EINEN System-Prompt + User-Prompt deterministisch aus
## Charakter, Mood, Arc, SidePlot, Beziehungskontext und Diff.

var _catalog: DOKI_NarratorCatalog
var _moods: DOKI_MoodOverlay


func _init(catalog: DOKI_NarratorCatalog, moods: DOKI_MoodOverlay) -> void:
	_catalog = catalog
	_moods = moods


## ctx: siehe CommitOrchestrator.build_narrative_context().
func build_prompts(ctx: Dictionary) -> Dictionary:
	return {
		"system": _build_system_prompt(ctx),
		"user": _build_user_prompt(ctx),
	}


func _build_system_prompt(ctx: Dictionary) -> String:
	var narrator: Dictionary = ctx.get("narrator", {})
	var name: String = str(narrator.get("name", ""))
	var role: String = str(narrator.get("role", ""))
	var voice: String = str(narrator.get("voice_traits", ""))
	var tone_brief: String = str(narrator.get("tone_brief", ""))
	var attitudes: Dictionary = ctx.get("attitudes", {})
	var prev_narrator: String = str(ctx.get("prev_narrator", ""))
	var relationship: Dictionary = ctx.get("relationship", {})
	var sideplot: Dictionary = ctx.get("sideplot", {})
	var search_context: Dictionary = ctx.get("search_context", {})
	var mood: String = str(ctx.get("mood", ""))

	var prompt: String = "DU BIST: %s (%s).\n" % [name, role]
	prompt += "DEINE STIMME: %s\n" % voice
	prompt += "DEIN MOOD: %s\n" % mood
	var mood_expr: String = _moods.mood_expression(mood)
	if not mood_expr.is_empty():
		prompt += "MOOD-AUSDRUCK: %s\n" % mood_expr
	var impulse_class: String = str(ctx.get("impulse_class", "CODE"))
	var calib: String = _moods.category_calibration(impulse_class)
	if not calib.is_empty():
		prompt += "KALIBRIERUNG (%s): %s\n" % [impulse_class, calib]
	if not tone_brief.is_empty():
		prompt += "DISPOSITION: %s\n" % tone_brief

	prompt += "\nHALTUNG: Code %s / Aufräumen %s / Doku %s / Kritik %s / Lob %s / Optimismus %s / Ausführlichkeit %s\n" % [
		_attitude_text(int(attitudes.get("code_love", 5)), "liebt", "egal"),
		_attitude_text(int(attitudes.get("cleanup_resentment", 5)), "hasst", "okay"),
		_attitude_text(int(attitudes.get("doku_irritation", 5)), "nervt", "okay"),
		_attitude_text(int(attitudes.get("criticism_tendency", 5)), "gnadenlos", "nachgiebig"),
		_attitude_text(int(attitudes.get("praise_tendency", 5)), "lobt", "selten"),
		_attitude_text(int(attitudes.get("optimism", 5)), "optimistisch", "pessimistisch"),
		_attitude_text(int(attitudes.get("verbosity_bias", 5)), "ausführlich", "wortkarg"),
	]

	if not prev_narrator.is_empty():
		prompt += "\nVOR DIR WAR: %s.\n" % prev_narrator

	if not relationship.is_empty():
		var target: String = str(relationship.get("target_narrator", ""))
		if not target.is_empty():
			prompt += "\nWAS DU ÜBER %s WEISST:\n" % target.to_upper()
			prompt += "- %s\n" % str(relationship.get("knowledge", ""))
			prompt += "- Dein Sentiment: %.1f/10 (%s).\n" % [float(relationship.get("sentiment", 5.0)), str(relationship.get("label", "neutral"))]
			var directive: String = str(relationship.get("tone_directive", ""))
			if not directive.is_empty():
				prompt += "- %s\n" % directive

	prompt += "\nSTIL: Fließtext, keine Bullets. Stimme gelebt, Mood in Wortwahl, nie genannt. Kausalität eingewoben, nicht protokolliert. Dateien als Spuren."
	if not prev_narrator.is_empty():
		prompt += " %s als Teil der Geschichte." % prev_narrator
	prompt += "\n"
	if bool(search_context.get("complete", false)):
		prompt += "\nSUCHKONTEXT (vollständig):\n%s\n" % JSON.stringify(search_context)

	# Side-Plot (Merge)
	if not sideplot.is_empty():
		prompt += "\n!!! SIDE-PLOT — PARALLELE ENTWICKLUNG VEREINT !!!\n"
		prompt += "Während auf %s gearbeitet wurde, entstand auf einem Seitenpfad (%s)\n" % [str(sideplot.get("target_branch", "?")), str(sideplot.get("source_branch", "?"))]
		prompt += "eine parallele Arbeit (%d Commits).\n" % int(sideplot.get("commit_count", 0))
		prompt += "Divergenzpunkt: Commit %s. %d Commits später vereinen sich die Pfade.\n" % [str(sideplot.get("divergence_hash", "?")), int(sideplot.get("commit_count", 0))]
		prompt += "\nSIDE-PLOT REGELN:\n"
		prompt += "- Erwähne die parallele Arbeit auf '%s' NATÜRLICH im Setup — als hättest du davon gehört.\n" % str(sideplot.get("source_branch", "?"))
		prompt += "- Die %d Commits des Seitenpfads sind KEINE Fußnote — sie sind der Grund für DIESEN Merge.\n" % int(sideplot.get("commit_count", 0))
		var side_narrators: Array = sideplot.get("narrators", [])
		if not side_narrators.is_empty():
			prompt += "- Die Narratoren des Seitenpfads (%s) waren dort aktiv. Würdige ihre Arbeit.\n" % ", ".join(side_narrators)
		prompt += "- Der Merge IST die Auflösung: zwei Stränge werden eins. Erzähl es wie ein Wiedersehen.\n"
		prompt += "- KEIN 'Merged branch X into Y'. Das ist ein Protokoll, keine Geschichte.\n"

	return prompt


func _build_user_prompt(ctx: Dictionary) -> String:
	var narrator: Dictionary = ctx.get("narrator", {})
	var name: String = str(narrator.get("name", ""))
	var prompt: String = ""

	# ARC_CLIMAX
	if bool(ctx.get("is_arc_climax", false)):
		var eligible: bool = bool(ctx.get("arc_climax_eligible", true))
		if eligible:
			prompt += "\n!!! ARC_CLIMAX — STAFFELFINALE !!!\n"
			prompt += "Der aktuelle Arc '%s' erreicht heute seinen Höhepunkt.\n" % str(ctx.get("arc_name", "?"))
			prompt += "Schreibe diesen Commit ALS STAFFELFINALE:\n"
			prompt += "- Rückblick: Was wurde in diesem Arc erreicht? Welche Fragen wurden beantwortet?\n"
			prompt += "- Abschluss: Der letzte Commit dieses Handlungsbogens. Mach ihn bedeutsam.\n"
			prompt += "- AUSBLICK: Schlage am Ende des Epilogs EINEN Namen und EIN Thema für den NÄCHSTEN Arc vor (Format: 'NÄCHSTER ARC: <Name> — <Thema>').\n"
			prompt += "Der neue Arc MUSS auf der realen Arbeit basieren, die in den letzten Commits passiert ist.\n\n"
		else:
			prompt += "\n!!! WARTUNGSABSCHNITT — Arc '%s' bleibt unverändert; dieser Commit ist WARTUNG.\n" % str(ctx.get("arc_name", "?"))
			prompt += "Der Arc geht weiter — dieser Fix/Doku/Trivial-Commit ist kein Höhepunkt.\n"
			prompt += "Erzähle ihn als nötige Arbeit, die den Weg freimacht für das nächste große Thema.\n\n"

	prompt += "IMPULS: %s\n" % str(ctx.get("impulse", ""))

	prompt += "KATEGORIE: %s" % str(ctx.get("impulse_class", "CODE"))
	if bool(ctx.get("is_direction_change", false)):
		prompt += " (RICHTUNGSWECHSEL — vorher: %s von %s)" % [str(ctx.get("prev_class", "")), str(ctx.get("prev_narrator", "Vorgänger"))]
	prompt += "\n"

	var structure_info: Dictionary = ctx.get("structure_info", {})
	prompt += "STRUKTUR-VORGABE: %s — %s\n" % [str(structure_info.get("structure", "chronologisch")), str(structure_info.get("pattern", ""))]

	var body_text: String = str(ctx.get("body_text", ""))
	if not body_text.is_empty():
		prompt += "\nTECHNISCHER TEXT (was gemacht wurde):\n%s\n" % body_text
	else:
		prompt += "\nTECHNISCHER TEXT: [Kein technischer Text — der Impuls allein beschreibt, was passiert ist.]\n"

	# Side-Plot: Branch-Commits auflisten
	var sideplot: Dictionary = ctx.get("sideplot", {})
	var search_context: Dictionary = ctx.get("search_context", {})
	if bool(search_context.get("complete", false)):
		prompt += "\nSEARCH-VERTRAG: %s\n" % str(ctx.get("search_contract", "Lies den vollständigen Suchkontext."))
	if not sideplot.is_empty():
		var summary: String = str(sideplot.get("commit_summary", ""))
		if not summary.is_empty():
			prompt += "\nCOMMITS AUF '%s' (seit %s):\n%s\n" % [str(sideplot.get("source_branch", "?")), str(sideplot.get("divergence_hash", "?")), summary]

	# Dateien
	var files: Array = ctx.get("files", [])
	if not files.is_empty():
		var shown: Array = []
		for f in files:
			shown.append(f.get_file())
			if shown.size() >= 8:
				break
		var file_list: String = ", ".join(shown)
		if files.size() > 8:
			file_list += " und %d weitere" % (files.size() - 8)
		prompt += "\nDATEIEN: %s\n" % file_list

	var sidejoke: String = str(ctx.get("sidejoke", ""))
	if not sidejoke.is_empty():
		prompt += "\nSIDEJOKE (in den Epilog einweben): %s\n" % sidejoke

	prompt += "\nSCHREIBE IN DEINER STIMME:\n"
	prompt += "- %s-Stil: %s\n" % [name, _structure_hint(name, files.size())]
	prompt += "- Beginne mit WARUM dieser Commit unvermeidlich war.\n"
	prompt += "- Reagiere auf den technischen Text — analysiere, kritisiere, lobe.\n"
	prompt += "- Schließe mit einem Epilog: Dateien, Ausblick, Sidejoke.\n"
	prompt += "- Deine Absätze folgen DEINER Stimme, nicht einer Schablone.\n"

	# Trivial-Erzwingung (kontextualisierte Übertreibung, deterministisch via Djb2)
	var impulse_class: String = str(ctx.get("impulse_class", "CODE"))
	var is_trivial: bool = impulse_class == "TRIVIAL" or (impulse_class == "FIX" and files.size() <= 2)
	if is_trivial:
		prompt += "\nTRIVIAL: Dieser kleine Commit verdient trotzdem deine volle Stimme — bewerte die Bedeutung im Verhältnis.\n"

	return prompt


## Narrator-spezifischer Subject (Port von BuildSubject).
## prev_narrator: Wenn vorhanden, wird die Kausalkette im Git-Log sichtbar
## („… — nach <Vorgänger>") — genau das prüft der Analyzer (Kausalität).
func build_subject(narrator_name: String, impulse: String, file_count: int, prev_narrator: String = "") -> String:
	var short_impulse: String = impulse
	while short_impulse.length() > 0 and ".,:;!? ".find(short_impulse[short_impulse.length() - 1]) != -1:
		short_impulse = short_impulse.substr(0, short_impulse.length() - 1)
	if short_impulse.length() > 55:
		var cut: String = short_impulse.substr(0, 50)
		var last_space: int = cut.rfind(" ")
		short_impulse = (cut.substr(0, last_space) if last_space > 30 else cut) + "…"
	var words: PackedStringArray = short_impulse.split(" ")

	var subject: String = ""
	match narrator_name:
		"Buffy":
			subject = "[%s] %s" % [narrator_name, short_impulse]
		"Basher":
			subject = "%s (%d files): %s" % [narrator_name, file_count, short_impulse]
		"Vannon":
			var taken: PackedStringArray = words.slice(0, 4)
			subject = " ".join(taken) + (". …" if words.size() > 4 else "")
		"Thinker":
			subject = "%s [Analyse: %s]" % [short_impulse, narrator_name]
		"Devin":
			subject = "%s sagt: %s" % [narrator_name, short_impulse]
		"Ghost":
			subject = "%s verzeichnet: %s" % [narrator_name, short_impulse]
		"Glitch":
			subject = "%s ermittelt: %s" % [narrator_name, short_impulse]
		"Squizzle":
			subject = "%ss Fall: %s" % [narrator_name, short_impulse]
		"Echo":
			subject = "%s erinnert: %s" % [narrator_name, short_impulse]
		"Spark":
			subject = "%s entdeckt: %s" % [narrator_name, short_impulse]
		"Argos":
			subject = "%s: %d Dateien — %s" % [narrator_name, file_count, short_impulse.substr(0, 30) + ("…" if short_impulse.length() > 30 else "")]
		"Null":
			subject = "%s: %s" % [narrator_name, short_impulse.substr(0, 40) + ("…" if short_impulse.length() > 40 else "")]
		"Flux":
			subject = "%s — also — %s" % [narrator_name, " ".join(words.slice(0, 5)) + ("…" if words.size() > 5 else "")]
		"Sage":
			subject = "%s lehrt: %s" % [narrator_name, short_impulse]
		_:
			subject = "%s: %s" % [narrator_name, short_impulse]

	if not prev_narrator.is_empty():
		subject += " — nach %s" % prev_narrator
	return subject


## Deterministische Impuls-Klassifikation (Port von ClassifyImpulse).
static func classify_impulse(text: String) -> String:
	var lower: String = text.to_lower()
	var re := RegEx.new()
	re.compile("\\b(doku|archiv|changelog|readme|plan|comment|docs)\\b")
	if re.search(lower) != null:
		return "DOKU"
	re.compile("\\b(fix|bug|hotfix|patch|repair|fehler|korr)\\b")
	if re.search(lower) != null:
		return "FIX"
	re.compile("\\b(restruktur|refactor|cleanup|aufr|umstruktur|moved|verschoben|modular|extract|dedupli)")
	if re.search(lower) != null:
		return "REFACTOR"
	re.compile("\\b(build|commitlayer|commit_layer|author.system|hook|verifier|pipeline|doki)\\b")
	if re.search(lower) != null:
		return "BUILD"
	re.compile("\\b(test|test\\w*)\\b")
	if re.search(lower) != null:
		return "TEST-ASSET"
	if text.length() < 12 or text.split(" ").size() <= 2:
		return "TRIVIAL"
	return "CODE"


## Graduierte Attitude-Textuierung (Port von AttitudeText).
static func _attitude_text(value: int, high: String, low: String) -> String:
	if value >= 9:
		return high
	if value >= 7:
		return high + ", fast immer"
	if value >= 5:
		return "ausgeglichen"
	if value >= 3:
		return low + ", manchmal"
	return low


## Narrator-spezifische Strukturhinweise (Port von GetStructureHint).
static func _structure_hint(narrator_name: String, file_count: int) -> String:
	match narrator_name:
		"Basher":
			return "Kurz, maschinell. Fakten. CLI-Output-Ästhetik. Keine Absätze — Statuszeilen."
		"Buffy":
			return "Zynisch-präzise. Problem → Analyse → Fix → Auswirkung. Strukturiert aber bissig."
		"Thinker":
			return "Methodisch. Kontext → Analyse → Fazit → Empfehlung. Logisch aufbauend."
		"Vannon":
			return "Knapp. Direktiv. Imperative. Keine Rechtfertigungen — Entscheidungen."
		"Squizzle":
			return "Detektiv-Logbuch. Spuren → Indizien → Rekonstruktion → Fall geschlossen."
		"Devin":
			return "Architektonisch. Pattern erkennen → Bruchstelle lokalisieren → Neu vernähen."
		"Argos":
			return "Werkstatt-Stil. Direkt, bissig. 'Hab ich doch gesagt' — dann der Fix."
		"Ghost":
			return "Chronik-Eintrag. Datum → Ereignis → Bedeutung für die Historia."
		"Spark":
			return "Neugierig-entdeckend. Frage → Aha-Moment → Begeisterung. Laut denkend."
		"Glitch":
			return "Konspirativ. Verbindung A → Verbindung B → Theorie → 'Zufall? Ich denke nicht.'"
		"Null":
			return "Resigniert-philosophisch. 'Es wird eh wieder...' → technische Fakten → existenzielle Einsicht."
		"Echo":
			return "Flashback-schwer. 'Das erinnert mich an...' → historischer Vergleich → Echo in die Zukunft."
		"Flux":
			return "Stream-of-Consciousness. Abschweifend, Einschübe, — Moment — Gedankenstriche. Egal."
		"Sage":
			return "Pädagogisch. 'Stell dir vor...' → Kontext → Prinzip → Moral. Eine Lektion."
		_:
			return "Erzählend. %d Dateien. Finde deine eigene Stimme." % file_count