class_name DOKI_ArtifactWriter
extends RefCounted
## Zuständigkeit: Narrative Artefakte auf Disk schreiben NICHT nach Checks
## (change_index.json, CHANGELOG-Eintrag, .commit_msg.txt, Stagen) + Prompt-Datei.
## Erst nach bestandener Verifikation benutzen — bei Fehlschlag bleibt Disk unberührt.

var _repo_root: String
var _git: DOKI_GitHelper
var _index_store: DOKI_ChangeIndexStore


func _init(repo_root: String, git: DOKI_GitHelper, index_store: DOKI_ChangeIndexStore) -> void:
	_repo_root = repo_root
	_git = git
	_index_store = index_store


## Schreibt alle Commit-Artefakte (nach bestandenen Checks).
## - persistiert change_index.json (mit neuen Entitäten)
## - hängt CHANGELOG-Eintrag an
## - schreibt .commit_msg.txt
## - staged CHANGELOG + change_index
## - speichert die Analyze-Ergebnisse in der Session (für finalize-Link)
func apply_commit_artifacts(session: Dictionary, message: Dictionary, analyze: Dictionary, index: Dictionary, subject: String, date_str: String) -> void:
	_index_store.save(index)
	session["_entities"] = analyze

	var changelog_path: String = _repo_root.path_join("CHANGELOG.md")
	var existing: String = FileAccess.get_file_as_string(changelog_path) if FileAccess.file_exists(changelog_path) else "# CHANGELOG\n"
	_write_changelog(changelog_path, existing.rstrip("\n") + "\n" + _changelog_entry(session, subject, message, date_str))

	var msg_path: String = _repo_root.path_join(".commit_msg.txt")
	var msg_file := FileAccess.open(msg_path, FileAccess.WRITE)
	if msg_file != null:
		msg_file.store_string(str(message["full_message"]))
		msg_file.close()

	_git.stage(["CHANGELOG.md", "change_index.json"])


## CHANGELOG-Eintrag für diesen Commit (deterministischer Zeitstempel aus der Chain).
func _changelog_entry(session: Dictionary, subject: String, message: Dictionary, date_str: String) -> String:
	var entry_lines: Array = []
	entry_lines.append("")
	entry_lines.append("## %s — p%d · %s · %s · %s" % [date_str, int(session.get("p_id", 0)), str(session.get("composite", "")), str(session.get("narrator", "")), str(session.get("mood", ""))])
	entry_lines.append("")
	entry_lines.append("**%s**" % subject)
	entry_lines.append("")
	entry_lines.append(str(session.get("impulse", "")))
	var reasons: Array = message.get("reason_lines", [])
	if not reasons.is_empty():
		entry_lines.append("")
		entry_lines.append_array(reasons)
	entry_lines.append("")
	return "\n".join(entry_lines)


## Schreibt .doki/prompt.txt (System+User) für den Agenten.
func write_prompt_file(prompt: Dictionary, narrator: String, mood: String) -> String:
	var prompt_path: String = _repo_root.path_join(".doki").path_join("prompt.txt")
	DirAccess.make_dir_recursive_absolute(prompt_path.get_base_dir())
	var file := FileAccess.open(prompt_path, FileAccess.WRITE)
	if file == null:
		push_error("DOKI: prompt.txt nicht schreibbar: %s" % prompt_path)
		return ""
	file.store_string("════════ SYSTEM-PROMPT ════════\n" + str(prompt["system"])
		+ "\n\n════════ USER-PROMPT ════════\n" + str(prompt["user"])
		+ "\n\n════════ AUFGABE ════════\n"
		+ "Schreibe den Commit-Body in der Rolle von " + narrator + " (Mood: " + mood
		+ ") als Fließtext-Erzählung (keine Bullets). Schreibe NUR den Body — ohne Tokens, ohne Header.\n"
		+ "Danach: `doki finish --body-file .doki/narrator_body.md`")
	file.close()
	return prompt_path


## Bereinigt verbrauchte Transient-Dateien (nach finalize).
func cleanup_transients() -> void:
	var msg_path: String = _repo_root.path_join(".commit_msg.txt")
	if FileAccess.file_exists(msg_path):
		DirAccess.remove_absolute(msg_path)


static func _write_changelog(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("DOKI: CHANGELOG nicht schreibbar: %s" % path)
		return
	file.store_string(content)
	file.close()