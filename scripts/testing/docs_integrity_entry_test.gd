extends SceneTree
## Entry-point falsification for the docs_integrity constraint (MCP-08 follow-up):
## every detector rule must BLOCK synthetic defects; clean content and the REAL
## target docs must pass with zero findings. Pure analysis — no scene boot.
## exit 1 if any case deviates.

func _mark(case_id: String) -> void:
	# stderr = ungepuffert — Lokalisierung echten Hänge, trotz Datei-Umleitung.
	printerr("[t] enter " + case_id)

func _init() -> void:
	# Fail-closed: schlägt das Laden des SUT fehl (Parse-Fehler, Race mit
	# parallelem Rescan) → sauberer Exit statt Headless-Hang.
	var constraint_script: Script = load("res://scripts/preflight/constraint_docs_integrity.gd")
	var constraint: RefCounted = null
	if constraint_script != null:
		constraint = constraint_script.new() as RefCounted
	if constraint == null or not constraint.has_method("_analyze_lines"):
		push_error("[docs_integrity_entry_test] SUT not loadable/instantiable — aborting")
		print("[docs_integrity_entry_test] FAIL sut_load (parse error or race)")
		quit(2)
		return
	var failures: Array[String] = []
	print("[t] sut ok, starting cases...")

	# --- 1) Duplikat-Heading blockt ---
	print("[t] case 1")
	_mark("case1")
	var f1: Array[String] = []
	var lines1: Array[String] = ["# Top", "## Runde", "text", "## Runde"]
	constraint._analyze_lines(lines1, "synthetic", f1)
	_expect(f1, "duplicate heading", 1, "duplicate_heading_blocks", failures)

	# --- 2) Duplikat-Tabellenblock blockt ---
	print("[t] case 2")
	_mark("case2")
	var table: Array[String] = [
		"| # | Befund |",
		"|---|--------|",
		"| A | x      |",
	]
	var f2: Array[String] = []
	var lines2: Array[String] = []
	lines2.append_array(table)
	lines2.append("")
	lines2.append_array(table)
	constraint._analyze_lines(lines2, "synthetic", f2)
	_expect(f2, "duplicate table block", 1, "duplicate_table_blocks", failures)

	# --- 3) Fehlender/ungültiger Separator blockt ---
	print("[t] case 3")
	_mark("case3")
	var f3: Array[String] = []
	var lines3: Array[String] = [
		"| # | Befund |",
		"| A | x      |",
	]
	constraint._analyze_lines(lines3, "synthetic", f3)
	_expect(f3, "separator missing/invalid", 1, "missing_separator_blocks", failures)

	# --- 4) Zell-Drift blockt ---
	print("[t] case 4")
	_mark("case4")
	var f4: Array[String] = []
	var lines4: Array[String] = [
		"| # | Befund | Status |",
		"|---|--------|--------|",
		"| A | x      |",
	]
	constraint._analyze_lines(lines4, "synthetic", f4)
	_expect(f4, "cell drift", 1, "cell_drift_blocks", failures)

	# --- 5) Abgeschnittene Zeile blockt ---
	print("[t] case 5")
	_mark("case5")
	var f5: Array[String] = []
	var lines5: Array[String] = [
		"| # | Befund |",
		"|---|--------|",
		"| A | x",
	]
	constraint._analyze_lines(lines5, "synthetic", f5)
	_expect(f5, "does not end with '|'", 1, "truncated_row_blocks", failures)

	# --- 6) Escaped Pipe erzeugt keinen Drift ---
	print("[t] case 6")
	_mark("case6")
	var f6: Array[String] = []
	var lines6: Array[String] = [
		"| # | Befund |",
		"|---|--------|",
		"| A | x \\| y |",
	]
	constraint._analyze_lines(lines6, "synthetic", f6)
	_expect(f6, "", 0, "escaped_pipe_no_false_positive", failures)

	# --- 7) Sauberes Dok: 0 Findings ---
	print("[t] case 7")
	_mark("case7")
	var f7: Array[String] = []
	var lines7: Array[String] = [
		"# Doc",
		"",
		"## Abschnitt",
		"| # | A |",
		"|---|---|",
		"| 1 | b |",
		"",
		"## Anderer",
		"Fließtext.",
	]
	constraint._analyze_lines(lines7, "clean", f7)
	_expect(f7, "", 0, "clean_doc_passes", failures)

	# --- 8) ECHTE Zieldateien: müssen Finding-frei sein ---
	print("[t] case 8")
	_mark("case8")
	var f8: Array[String] = []
	for path in ["res://docs/FINDINGS.md", "res://CHANGELOG.md"]:
		var text := FileAccess.get_file_as_string(path)
		var lines: Array[String] = []
		for raw in text.split("\n"):
			lines.append(String(raw).trim_suffix("\r"))
		constraint._analyze_lines(lines, path.replace("res://", ""), f8)
	_expect(f8, "", 0, "real_docs_pass", failures)

	if failures.is_empty():
		print("[docs_integrity_entry_test] PASS — 8/8 cases as expected")
		print(JSON.stringify({"ok": true, "cases": 8}))
		quit(0)
		return
	for failure in failures:
		push_error("[docs_integrity_entry_test] " + failure)
		print("[docs_integrity_entry_test] FAIL " + failure)
	quit(1)
	return


func _expect(findings: Array[String], want_substr: String, want_count: int,
		case_id: String, failures: Array[String]) -> void:
	var matches := 0
	if want_substr != "":
		for finding in findings:
			if finding.contains(want_substr):
				matches += 1
	if matches != want_count or (want_substr == "" and findings.size() != 0):
		failures.append("%s: expected %d match(es) for '%s', got findings=%s"
			% [case_id, want_count, want_substr, ", ".join(findings)])
