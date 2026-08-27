class_name DOKI_MessageBuilder
extends RefCounted
## Zuständigkeit: Commit-Message zusammensetzen (Subject, Tokens, Arc-Block,
## maschinengenerierte Begründungszeilen) + Summary-Bildung für die Chain.
## Kein Dateizugriff, kein Git.

var _voice: DOKI_VoiceComposer


func _init(voice: DOKI_VoiceComposer) -> void:
	_voice = voice


## Baut die finale Commit-Message (Header + Body + Tokens + Arc-Block).
func assemble(session: Dictionary, body: String, analyze: Dictionary) -> Dictionary:
	var narrator_name: String = str(session.get("narrator", ""))
	# Nur Datei-Entitäten zählen (Components sind keine "Files" im Subject).
	var file_count: int = 0
	for e in analyze.get("entities", []):
		if e.get("type") == "file":
			file_count += 1
	var subject: String = _voice.build_subject(narrator_name, str(session.get("impulse", "")), file_count, str(session.get("prev_narrator", "")))
	var composite: String = str(session.get("composite", ""))

	var lines: Array = []
	lines.append(subject)
	lines.append("")
	lines.append("[NARRATOR:%s]" % narrator_name)
	lines.append("")
	lines.append(body.strip_edges())
	lines.append("")
	lines.append("[MODEL:%s]" % str(session.get("model_id", "unknown")))
	lines.append("[IMPULSE:%s]" % str(session.get("impulse", "")))
	lines.append("[COMPOSITE:%s]" % composite)
	var prev_narrator: String = str(session.get("prev_narrator", ""))
	if not prev_narrator.is_empty():
		lines.append("[PREV_NARRATOR:%s]" % prev_narrator)
	lines.append("")
	lines.append("Arc: %s (%s) — Gewicht: %.1f" % [str(session.get("arc_name", "?")), str(session.get("arc_id", "?")), float(session.get("arc_weight", 0.0))])

	# Begründungszeilen (maschinengeneriert — ersetzt den manuellen awk-Check)
	var reason_lines: Array = build_reason_lines(analyze, str(session.get("impulse_class", "CODE")))
	if not reason_lines.is_empty():
		lines.append("")
		lines.append_array(reason_lines)

	return {"subject": subject, "full_message": "\n".join(lines), "reason_lines": reason_lines}


## Begründungszeilen je geänderte Datei (ersetzen den awk-Begründungscheck).
static func build_reason_lines(analyze: Dictionary, impulse_class: String) -> Array:
	var action: String = _action_for(impulse_class)
	var seen: Dictionary = {}
	var lines: Array = []
	for e in analyze.get("entities", []):
		var path: String = str(e.get("path", ""))
		if seen.has(path):
			continue
		seen[path] = true
		var name: String = str(e.get("name", ""))
		var id: String = str(e.get("id", ""))
		if name == path.get_file():
			lines.append("- %s: %s (%s)." % [path, action, id])
		else:
			lines.append("- %s: %s — %s (%s)." % [path, name, action, id])
	return lines


## Kurzfassung für die Chain (erste Body-Zeile, <=200).
static func summary_from_body(body: String) -> String:
	var stripped: String = body.strip_edges()
	if stripped.is_empty():
		return ""
	var first_line: String = stripped.split("\n")[0]
	if first_line.length() > 200:
		return first_line.substr(0, 197) + "..."
	return first_line


static func _action_for(impulse_class: String) -> String:
	match impulse_class:
		"DOKU":
			return "Dokumentation aktualisiert"
		"FIX":
			return "Fehler behoben"
		"REFACTOR":
			return "Umstrukturiert"
		"BUILD":
			return "Tooling erweitert"
		"TEST-ASSET":
			return "Test-Assets ergänzt"
		"TRIVIAL":
			return "Kleine Anpassung"
		_:
			return "Implementiert und integriert"