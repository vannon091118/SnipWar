class_name PreflightConstraintDocsIntegrity
extends RefCounted

## Mechanische Integritätsprüfung der zentralen Doku (docs/FINDINGS.md,
## CHANGELOG.md). Erkennt die Fehlerklasse "duplizierte QA-Tabellenblöcke /
## Abschnitte" sowie kaputte Markdown-Tabellen (Zell-Drift, fehlender oder
## ungültiger Separator, verwaiste '|'-Zeilen). Reine Textanalyse — kein
## Scene-Boot, keine Mutations. Parse-Logik ist pure (Zeilen rein, Findings
## raus), damit die Detektoren synthetisch falsifizierbar bleiben.

const TARGET_DOCS: Array[String] = [
	"res://docs/FINDINGS.md",
	"res://CHANGELOG.md",
]

const HEADING_PATTERN := "^(#{1,6})\\s+(.+?)\\s*#*\\s*$"
const SEPARATOR_CHARS := "|:- "

func constraint_name() -> String:
	return "docs_integrity"

func constraint_description() -> String:
	return "Central docs integrity: duplicated headings/table blocks, broken markdown table structure"

func requires_scene() -> bool:
	return false

func run(ctx: PreflightContext) -> bool:
	var all_findings: Array[String] = []
	var total_headings := 0
	var total_tables := 0
	for path in TARGET_DOCS:
		var label := path.replace("res://", "")
		var text := ctx.code_index.get_file_content(path)
		if text.is_empty():
			all_findings.append("%s: file missing" % label)
			continue
		var lines: Array[String] = []
		for raw in text.split("\n"):
			lines.append(String(raw).trim_suffix("\r"))
		var counts := _analyze_lines(lines, label, all_findings)
		total_headings += int(counts["headings"])
		total_tables += int(counts["tables"])
		print("[docs_integrity] %s: %d headings, %d table blocks" % [label, int(counts["headings"]), int(counts["tables"])])
	if not all_findings.is_empty():
		var shown := mini(all_findings.size(), 40)
		for i in range(shown):
			print("[docs_integrity]   FINDING %s" % all_findings[i])
		if all_findings.size() > shown:
			print("[docs_integrity]   ... %d weitere Findings" % (all_findings.size() - shown))
	return ctx.check(all_findings.is_empty(),
		"Docs integrity: %d headings, %d table blocks across %d files, %d findings" % [
			total_headings, total_tables, TARGET_DOCS.size(), all_findings.size(),
		],
		{"findings": all_findings})


## Pure Analyse: keine IO, keine Member-Mutation außer den Ergebnissen.
## headings/tables werden als Summen zurückgeschrieben (by-ref via Array
## wäre geschwätzig; GDScript int-Parameter sind by-value, daher Rückgabe).
func _analyze_lines(lines: Array[String], label: String, findings: Array[String]) -> Dictionary:
	var heading_regex := RegEx.new()
	heading_regex.compile(HEADING_PATTERN)
	var heading_seen: Dictionary = {}
	var table_seen: Dictionary = {}
	var headings := 0
	var tables := 0

	var index := 0
	while index < lines.size():
		var line := lines[index]

		# --- Heading-Duplikate (Level + exakter Text) ---
		var h := heading_regex.search(line)
		if h != null:
			headings += 1
			var key := "%d|%s" % [h.get_string(1).length(), h.get_string(2)]
			var occurrences: Array = heading_seen.get(key, [])
			occurrences.append(index + 1)
			heading_seen[key] = occurrences
			if occurrences.size() == 2:
				findings.append("%s:%d duplicate heading '%s %s' (first at line %d)"
					% [label, index + 1, h.get_string(1), h.get_string(2), occurrences[0]])
			index += 1
			continue

		# --- Tabellenblöcke: konsekutive '|'-Zeilen ---
		if line.strip_edges().begins_with("|"):
			var block_start := index
			var block: Array[String] = []
			while index < lines.size() and lines[index].strip_edges().begins_with("|"):
				block.append(lines[index])
				index += 1
			tables += 1
			_check_table_block(block, label, block_start, findings)
			var signature := ""
			for bline in block:
				signature += "%s\n" % _normalize(bline)
			var occurrences: Array = table_seen.get(signature, [])
			occurrences.append(block_start + 1)
			table_seen[signature] = occurrences
			if occurrences.size() == 2:
				findings.append("%s:%d duplicate table block (first at line %d, %d lines)"
					% [label, block_start + 1, occurrences[0], block.size()])
			continue

		index += 1

	return {"headings": headings, "tables": tables}


func _check_table_block(block: Array[String], label: String, block_start: int,
		findings: Array[String]) -> void:
	var first_line := block_start + 1
	if block.size() < 2:
		findings.append("%s:%d table block with %d line(s) — header+separator required"
			% [label, first_line, block.size()])
		return
	var header_pipes := _count_unescaped_pipes(block[0])
	if not _is_separator(block[1]):
		findings.append("%s:%d table separator missing/invalid at line %d"
			% [label, first_line, block_start + 2])
	for i in range(block.size()):
		var row := block[i].strip_edges()
		if not row.ends_with("|"):
			findings.append("%s:%d table row does not end with '|' (truncated?)"
				% [label, block_start + i + 1])
		var pipes := _count_unescaped_pipes(block[i])
		if pipes != header_pipes:
			findings.append("%s:%d table cell drift at line %d: %d pipes, header has %d"
				% [label, block_start + i + 1, block_start + i + 1, pipes, header_pipes])


func _is_separator(line: String) -> bool:
	var trimmed := line.strip_edges()
	if not trimmed.contains("-"):
		return false
	for character in trimmed:
		if not SEPARATOR_CHARS.contains(character):
			return false
	return true


func _count_unescaped_pipes(line: String) -> int:
	var count := 0
	for i in range(line.length()):
		if line[i] == "|" and (i == 0 or line[i - 1] != "\\"):
			count += 1
	return count


func _normalize(line: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\s+")
	return regex.sub(line.strip_edges(), " ", true)
