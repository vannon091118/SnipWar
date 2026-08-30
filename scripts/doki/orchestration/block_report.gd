class_name DOKI_BlockReport
extends RefCounted
## Erzeugt bei jedem DOKI-Block (hard_error in finish/gate/verify/prepare)
## eine maschinell lesbare + menschlich verständliche Diagnose-Datei
## (.doki/block_report.md) die ALLE relevanten Infos für den blockierten
## Agent enthält — kein Extra-Kontext nötig.
##
## Vertrag (AGENTS.md Phase 6): Jeder Agent (Codebuff, Claude, Copilot)
## sieht den Fehler-Tail + den Pfad zur vollständigen Diagnose und kann
## .doki/block_report.md lesen statt im Log zu grübeln.

var _repo_root: String


func _init(repo_root: String) -> void:
	_repo_root = repo_root


## Schreibt den Block-Report und gibt den Dateipfad zurück.
## phase: "finish" | "gate" | "prepare" | "verify"
## error_result: {ok:false, error/errors, soft_errors, phase}
## session: session state dict (kann leer sein)
## chain: chain state dict (kann leer sein)
## staged: Array der gestagten Dateien
func write_block_report(
	phase: String,
	error_result: Dictionary,
	session: Dictionary,
	chain: Dictionary,
	staged: Array
) -> String:
	var report: String = _build_report(phase, error_result, session, chain, staged)
	var path: String = _repo_root.path_join(".doki/block_report.md")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()
	return path


## Baut den Report-String (markdown).
func _build_report(
	phase: String,
	error_result: Dictionary,
	session: Dictionary,
	chain: Dictionary,
	staged: Array
) -> String:
	var errors: Variant = error_result.get("errors", error_result.get("error", []))
	var errors_arr: Array = []
	if errors is Array:
		errors_arr = errors
	elif errors is String and str(errors) != "":
		errors_arr = [str(errors)]
	var soft: Array = error_result.get("soft_errors", [])

	var narrator: String = str(session.get("narrator", "?"))
	var mood: String = str(session.get("mood", "?"))
	var composite: String = str(session.get("composite", "?"))
	var arc_id: String = str(session.get("arc_id", "?"))
	var arc_name: String = str(session.get("arc_name", str(chain.get("arcs", {}).get(arc_id, {}).get("name", "?"))))
	var state: String = str(session.get("state", "unknown"))
	var impulse: String = str(session.get("impulse", "?"))
	var impulse_class: String = str(session.get("impulse_class", "?"))

	var lines: Array = []
	lines.append("# DOKI BLOCK — Phase: %s" % phase)
	lines.append("")
	lines.append("## Was ist passiert?")
	lines.append("")
	for e in errors_arr:
		lines.append("- %s" % str(e))
	if not soft.is_empty():
		lines.append("")
		lines.append("### Soft-Checks (Warnungen, nicht blockierend):")
		for s in soft:
			lines.append("- %s" % str(s))
	lines.append("")
	lines.append("## Aktueller Zustand")
	lines.append("")
	lines.append("| Feld | Wert |")
	lines.append("|------|------|")
	lines.append("| Session-State | %s |" % state)
	lines.append("| Narrator | %s (n=%s) |" % [narrator, str(session.get("n", "?"))])
	lines.append("| Mood | %s (j=%s) |" % [mood, str(session.get("j", "?"))])
	lines.append("| Composite | %s |" % composite)
	lines.append("| Arc | %s (%s) |" % [arc_name, arc_id])
	lines.append("| Impuls | %s |" % impulse)
	lines.append("| Impuls-Klasse | %s |" % impulse_class)
	lines.append("| Staged-Dateien | %d |" % staged.size())
	lines.append("")
	lines.append("## Early Artifact Lifecycle Hinweis")
	lines.append("")
	lines.append("`finish` schreibt change_index.json + CHANGELOG.md UND staged sie → der")
	lines.append("Commit ist self-contained (User-Code + Artefakte zusammen).")
	lines.append("`finalize` (post-commit) schreibt NUR narrative_chain.json + arcs.json")
	lines.append("und staged sie für den NÄCHSTEN Commit — das ist normal und beabsichtigt.")
	lines.append("Kein 'Zettel auf dem Schreibtisch' — jeder Commit enthält seine Artefakte.")
	lines.append("")
	lines.append("## Was muss ich tun?")
	lines.append("")
	lines.append(_recommend(phase, errors_arr, session))
	lines.append("")
	lines.append("## Nächster Schritt")
	lines.append("")
	lines.append("```bash")
	lines.append(_next_command(phase, session))
	lines.append("```")
	return "\n".join(lines)


## Empfehlung basierend auf Fehlertyp.
func _recommend(phase: String, errors: Array, session: Dictionary) -> String:
	var err_text: String = "\n".join(errors).to_lower()
	if err_text.contains("impulse"):
		return "Der Impuls fehlt oder ist leer. Setze einen klaren Impuls im prepare-Schritt:\n`doki prepare \"<dein impulse>\"`."
	if err_text.contains("narrator") and err_text.contains("vorher"):
		return "Der Vorgänger-Narrator wird im Body nicht erwähnt. Schreibe den Body so, dass der vorherige Narrator natürlich vorkommt."
	if err_text.contains("kausal") or err_text.contains("konnektor"):
		return "Kausale Konnektoren fehlen (weil, deshalb, daher, folglich). Wobe sie natürlich in den Fließtext ein."
	if err_text.contains("staged") or err_text.contains("git add"):
		return "Dateien sind nicht gestagt. Führe `git add <datei>` aus, dann erneut `doki prepare`."
	if err_text.contains("session"):
		return "Die Session ist im falschen Zustand. Prüfe `doki status` und ggf. `doki repair`."
	return "Lies die Fehler oben, behebe die Ursache, stage die Dateien neu und wiederhole den DOKI-Flow."


## Empfohlenes Kommando basierend auf Phase.
func _next_command(phase: String, session: Dictionary) -> String:
	if phase == "prepare":
		return '$GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- prepare "<impuls>"'
	if phase == "finish":
		return '$GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- finish --body-file .doki/narrator_body.md'
	if phase == "verify":
		return '$GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- verify-only'
	return '$GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- status'
