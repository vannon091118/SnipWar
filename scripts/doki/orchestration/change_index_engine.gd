class_name DOKI_ChangeIndexEngine
extends RefCounted
## Entitäten-Extraktion aus dem Staged-Diff — NEU implementiert (das alte System
## hatte hier einen TODO-Stub: AnalyzeDiff gab immer eine leere Liste zurück).
##
## Extrahiert pro geänderter Datei:
## - F-### : Datei-Entität (Typ "file")
## - C-### : Komponenten-Entitäten (Klassen/Funktionen/Signale aus +/- Zeilen)
## Mit Zeilennummern (Hunk-Header `@@ -a,b +c,d @@`) und gestagten Insertions/Deletions.

var _store: DOKI_ChangeIndexStore


func _init(store: DOKI_ChangeIndexStore) -> void:
	_store = store


## Analysiert `git diff --cached` und liefert { entities: [...], data_changes: [...], entity_ids: [...] }.
## - staged_files: Array von Pfaden (aus GitHelper)
## - diff_output: roher `git diff --cached` String
## - index: change_index.json (in-place erweitert um neue Entitäten)
## - p_id: aktuelle Plot-ID
func analyze(staged_files: Array, diff_output: String, index: Dictionary, p_id: int) -> Dictionary:
	var entities: Array = []
	var entity_ids: Array = []
	var data_changes: Array = []

	# Datei-Entitäten (F-###) — stabil über Commits
	for file_path in staged_files:
		var entity_id: String = _store.ensure_entity(index, file_path, "file", file_path.get_file(), p_id)
		entity_ids.append(entity_id)
		entities.append({
			"id": entity_id,
			"type": "file",
			"name": file_path.get_file(),
			"path": file_path,
		})

	# Komponenten aus dem Diff (C-###) mit Zeilennummern
	var hunks: Array = _parse_hunks(diff_output)
	for hunk in hunks:
		var path: String = hunk["path"]
		var start_line: int = hunk["start_line"]
		var added_lines: Array = hunk["lines"]
		var symbols: Dictionary = _extract_symbols(added_lines, start_line)
		for symbol_name in symbols.keys():
			var lines: Array = symbols[symbol_name]
			var entity_id: String = _store.ensure_entity(index, path, "component", symbol_name, p_id)
			if not entity_ids.has(entity_id):
				entity_ids.append(entity_id)
			entities.append({
				"id": entity_id,
				"type": "component",
				"name": symbol_name,
				"path": path,
				"lines": lines,
			})
			# History-Eintrag (Determinismus: nur p_id + Zeilen, keine Zeitstempel)
			var entity: Dictionary = index["entities"][entity_id]
			entity["status"] = "modified"
			entity["last_p"] = p_id
			entity["history"].append({"p_id": p_id, "lines": lines})
			index["entities"][entity_id] = entity

	# Daten-Änderungen (Insertions/Deletions pro Datei)
	var counts: Dictionary = {}
	for hunk in hunks:
		var path: String = hunk["path"]
		if not counts.has(path):
			counts[path] = {"insertions": 0, "deletions": 0}
		counts[path]["insertions"] += hunk["insertions"]
		counts[path]["deletions"] += hunk["deletions"]
	for file_path in staged_files:
		var c: Dictionary = counts.get(file_path, {"insertions": 0, "deletions": 0})
		data_changes.append({"file": file_path, "insertions": c["insertions"], "deletions": c["deletions"]})

	return {"entities": entities, "entity_ids": entity_ids, "data_changes": data_changes}


## ─── Diff-Parsing ────────────────────────────────────────────────────────
## Zerlegt `git diff --cached` in Hunks: {path, start_line, lines:[...], insertions, deletions}
static func _parse_hunks(diff_output: String) -> Array:
	var hunks: Array = []
	var current_path: String = ""
	var new_path: String = ""
	var in_hunk: bool = false
	var hunk_start: int = 0
	var hunk_lines: Array = []
	var insertions: int = 0
	var deletions: int = 0
	var hunk_re := RegEx.new()
	hunk_re.compile("^@@ -(\\d+)(?:,\\d+)? \\+(\\d+)(?:,\\d+)? @@")

	for line in diff_output.split("\n"):
		if line.begins_with("diff --git "):
			# hunk abschließen
			if in_hunk:
				hunks.append({"path": current_path, "start_line": hunk_start, "lines": hunk_lines.duplicate(), "insertions": insertions, "deletions": deletions})
				in_hunk = false
			current_path = ""
			new_path = ""
			continue
		if line.begins_with("--- "):
			continue
		if line.begins_with("+++ "):
			new_path = line.substr(4).strip_edges()
			# Git-Diff-Pfad-Präfixe entfernen ("b/scripts/x.gd" → "scripts/x.gd"),
			# sonst matchen C-Entitäten nie auf staged_files → Duplikate je Commit.
			if new_path.begins_with("b/") or new_path.begins_with("a/"):
				new_path = new_path.substr(2)
			current_path = new_path if not new_path.is_empty() else current_path
			continue
		var m: RegExMatch = hunk_re.search(line)
		if m != null:
			if in_hunk:
				hunks.append({"path": current_path, "start_line": hunk_start, "lines": hunk_lines.duplicate(), "insertions": insertions, "deletions": deletions})
			in_hunk = true
			hunk_start = int(m.get_string(2))
			hunk_lines = []
			insertions = 0
			deletions = 0
			continue
		if in_hunk:
			if line.begins_with("+"):
				insertions += 1
				hunk_lines.append(line)
			elif line.begins_with("-"):
				deletions += 1
	if in_hunk:
		hunks.append({"path": current_path, "start_line": hunk_start, "lines": hunk_lines.duplicate(), "insertions": insertions, "deletions": deletions})
	return hunks


## Symbolnamen aus hinzugefügten Zeilen extrahieren: func/class/const/var + Identifier.
## Liefert {symbol_name: [zeilennummern]} (absolute Zeilennummern im neuen File).
static func _extract_symbols(added_lines: Array, start_line: int) -> Dictionary:
	var symbols: Dictionary = {}
	var symbol_re := RegEx.new()
	symbol_re.compile("^\\+?\\s*(func|class_name|class|const|signal)\\s+([a-zA-Z_][a-zA-Z0-9_]*)")
	for i in added_lines.size():
		var line: String = str(added_lines[i])
		var m: RegExMatch = symbol_re.search(line)
		if m != null:
			var symbol_name: String = m.get_string(2)
			# Skript-Dateien: "class_name X" → X; direkt benannte funcs/classes
			var line_number: int = start_line + i
			if not symbols.has(symbol_name):
				symbols[symbol_name] = []
			symbols[symbol_name].append(line_number)
	return symbols