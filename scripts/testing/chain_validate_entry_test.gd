extends SceneTree
## Entry-point falsification for the hardened chain validation contracts:
## drives the REAL McpChainController via the registry's runtime_chain_validate
## dispatch (SYNC path — the async path is only for runtime_chain_run).
## New hard rules must BLOCK; the real world_smoke manifest must PASS.
## Produces evidence: user://mcp_evidence/chain_validate_entry.json
## exit 1 if any case deviates.

const EVIDENCE_PATH := "user://mcp_evidence/chain_validate_entry.json"

func _init() -> void:
	print("[t] loading registry...")
	var registry: RefCounted = load("res://addons/mcp/runtime/core/mcp_tool_registry.gd").new()
	print("[t] registry new ok")
	var tool_count: int = registry.get_all_tools().size()
	print("[t] get_all_tools ok (", tool_count, " tools)")

	var failures: Array[String] = []
	var checks := [
		{
			"id": "nopost_blocks",
			"chain": {"mode": "auto", "steps": [{"name": "s", "tool": "runtime_ux_scan", "args": {}}]},
			"want_verdict": "BLOCKED",
			"want_substr": "no postcondition",
		},
		{
			"id": "composite_tool_blocks",
			"chain": {"mode": "auto", "steps": [{"name": "s", "tool": "runtime_ux_click", "args": {}, "assertion": "true"}]},
			"want_verdict": "BLOCKED",
			"want_substr": "composite tool",
		},
		{
			"id": "screenshot_without_reason_blocks",
			"chain": {"mode": "auto", "steps": [{"name": "s", "tool": "runtime_screenshot", "args": {}, "assertion": "result.context_id != \"\""}]},
			"want_verdict": "BLOCKED",
			"want_substr": "screenshot requires a reason",
		},
		{
			"id": "valid_inline_passes",
			"chain": {"mode": "auto", "steps": [
				{"name": "settle", "tool": "runtime_wait_ms", "args": {"ms": 1}, "assertion": "true"},
				{"name": "scan", "tool": "runtime_ux_scan", "args": {}, "assertion": "result.count > 0"},
				{"name": "shot", "tool": "runtime_screenshot", "args": {}, "reason": "entry-point evidence", "assertion": "result.context_id != \"\""},
			]},
			"want_verdict": "PASS",
			"want_substr": "",
		},
		{
			"id": "world_smoke_manifest_passes",
			"chain": {"chain_id": "world_smoke"},
			"want_verdict": "PASS",
			"want_substr": "",
		},
	]

	var evidence: Array = []
	for check in checks:
		print("[t] dispatch ", check.id, " ...")
		var result: Dictionary = registry.dispatch("runtime_chain_validate", check.chain)
		var verdict := str(result.get("verdict", "?"))
		# Vollständiger Befund: errors ODER top-level error (load_manifest-Fehler)
		var errors: Array = result.get("errors", [])
		var top_error := str(result.get("error", ""))
		var error_text := (" | ".join(PackedStringArray(errors)) if not errors.is_empty() else top_error)
		var want := str(check.want_verdict)
		var ok := verdict == want
		if ok and String(check.want_substr) != "":
			ok = error_text.contains(String(check.want_substr))
		print((("[%s] OK   verdict=%s" % [check.id, verdict]) if ok else ("[%s] FAIL verdict=%s want=%s errors=[%s]" % [check.id, verdict, want, error_text])))
		evidence.append({
			"case": check.id,
			"input": check.chain,
			"verdict": verdict,
			"errors": errors,
			"error": top_error,
			"expected": want,
			"pass": ok,
		})
		if not ok:
			failures.append(check.id)

	var passed := failures.is_empty()
	var summary := "PASS — 5/5 contract cases behave as specified" if passed else "FAIL — " + ", ".join(PackedStringArray(failures))
	_write_evidence({
		"tool": "runtime_chain_validate",
		"entry_points": ["registry.dispatch(sync)"],
		"result": summary,
		"cases": evidence,
	})
	print("CHAIN_VALIDATE_ENTRY: ", summary)
	print("EVIDENCE: ", ProjectSettings.globalize_path(EVIDENCE_PATH))
	quit(0 if passed else 1)

func _write_evidence(data: Dictionary) -> void:
	var dir := DirAccess.open("user://")
	if dir == null or not dir.dir_exists("mcp_evidence"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://mcp_evidence"))
	var file := FileAccess.open(EVIDENCE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write evidence: " + EVIDENCE_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()