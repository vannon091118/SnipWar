extends SceneTree

## Slice D write-gate contract test: workspace tools in the planner
## respect the mutations_allowed gate and journal all writes.

const PLANNER_PATH := "res://addons/mcp/runtime/autonomy/mcp_capability_planner.gd"
const VALIDATOR_PATH := "res://addons/mcp/runtime/autonomy/mcp_path_validator.gd"

var _failed := 0


class ContractRegistry extends RefCounted:
	var definitions: Array = []

	func get_all_tools() -> Array:
		return definitions.duplicate(true)


func _init() -> void:
	_run()


func _run() -> void:
	var planner_script: Resource = load(PLANNER_PATH)
	_check(planner_script != null, "planner script loads")
	if _failed > 0:
		_finish()
		return

	var registry := ContractRegistry.new()
	var planner: RefCounted = planner_script.new()
	planner.setup(registry, null, null)
	var caps: Dictionary = planner.capabilities()
	_check(not bool(caps.get("mutations_allowed", true)), "mutations disallowed by default")
	_check(int(caps.get("count", 0)) > 0, "catalog includes workspace tools")

	# ── Read works without authorization or workspace ──────────────
	var read: Variant = planner.dispatch_tool("runtime_autonomy_read", {"path": PLANNER_PATH})
	_check(bool((read as Dictionary).get("ok", false)), "read works without write authorization")
	_check(int((read as Dictionary).get("bytes", 0)) > 100, "read returns bytes")

	# Symbols also works read-only
	var syms: Variant = planner.dispatch_tool("runtime_autonomy_symbols", {"path": PLANNER_PATH})
	_check((syms as Dictionary).get("funcs", []) is Array, "symbols work read-only")

	# ── Writes blocked by default ─────────────────────────────────
	var write: Variant = planner.dispatch_tool("runtime_autonomy_write", {"path": "x", "content": "x"})
	_check(not bool((write as Dictionary).get("ok", true)), "write blocked without authorization")
	_check(str((write as Dictionary).get("error_class", "")) == "BLOCKED", "blocked write reports BLOCKED")

	var begin: Variant = planner.dispatch_tool("runtime_autonomy_workspace_begin", {})
	_check(not bool((begin as Dictionary).get("ok", true)), "workspace_begin blocked without authorization")

	# ── Authorize, then plan selects begin correctly ────────────────
	planner.set_mutations_allowed(true)

	# Plan a workspace begin
	var plan_result: Dictionary = planner.plan("workspace", [], "any", false)
	_check(str(plan_result.get("verdict", "")) == "PASS", "plan selects workspace_begin when authorized")
	# Plan for a write intent with workspace_bound missing still fails
	var plan_write: Dictionary = planner.plan("write", ["file_change"], "any", false)
	_check(str(plan_write.get("verdict", "")) == "BLOCKED", "write plan blocked without bound workspace")

	# ── Begin workspace ────────────────────────────────────────────
	begin = planner.dispatch_tool("runtime_autonomy_workspace_begin", {})
	_check(bool((begin as Dictionary).get("ok", false)), "begin succeeds after authorization")
	_check(bool((begin as Dictionary).has("session_id")), "begin returns session_id")
	var ws: Dictionary = (begin as Dictionary).get("workspace", {})
	var root: String = str(ws.get("root_path", ""))
	_check(root.begins_with("user://mcp_workspaces/"), "workspace root under user://mcp_workspaces")
	_check(bool(begin.has("session_id")), "begin returns session_id")

	# Status, files, baseline
	var status: Variant = planner.dispatch_tool("runtime_autonomy_workspace_status", {})
	_check(bool((status as Dictionary).get("ok", false)), "workspace_status succeeds")
	var files: Variant = planner.dispatch_tool("runtime_autonomy_workspace_files", {})
	_check(int((files as Dictionary).get("count", -1)) >= 0, "workspace_files returns count")
	var bline: Variant = planner.dispatch_tool("runtime_autonomy_workspace_baseline", {})
	_check(bool((bline as Dictionary).get("clean", false)), "baseline is clean after begin")

	# ── Write inside workspace ─────────────────────────────────────
	var target: String = root.path_join("notes.md")
	var written: Variant = planner.dispatch_tool("runtime_autonomy_write", {
		"path": target,
		"content": "# hello",
	})
	_check(bool((written as Dictionary).get("ok", false)), "write inside workspace succeeds")
	_check(str((written as Dictionary).get("transaction_id", "")).begins_with("tx_"), "write returns transaction id")
	_check(str((written as Dictionary).get("after_hash", "")) != "", "write returns after-hash")

	# Read back
	var back: Variant = planner.dispatch_tool("runtime_autonomy_read", {"path": target})
	_check(str((back as Dictionary).get("text", "")).contains("# hello"), "read returns written content")

	# ── res:// write still blocked ─────────────────────────────────
	var res_write: Variant = planner.dispatch_tool("runtime_autonomy_write", {
		"path": "res://addons/mcp/blocked.gd",
		"content": "x",
	})
	_check(not bool((res_write as Dictionary).get("ok", true)), "res:// write blocked even when authorized")

	# ── Patch ──────────────────────────────────────────────────────
	var patched: Variant = planner.dispatch_tool("runtime_autonomy_patch", {
		"path": target,
		"old_text": "# hello",
		"new_text": "# patched",
	})
	_check(bool((patched as Dictionary).get("ok", false)), "patch applies single occurrence")

	# ── Patch fail-closed: missing / ambiguous ─────────────────────
	var not_found: Variant = planner.dispatch_tool("runtime_autonomy_patch", {
		"path": target,
		"old_text": "# missing",
		"new_text": "# x",
	})
	_check(not bool((not_found as Dictionary).get("ok", true)), "patch with missing old_text fails")
	var dup_target := root.path_join("dup.txt")
	planner.dispatch_tool("runtime_autonomy_write", {"path": dup_target, "content": "dup\ndup\n"})
	var ambiguous: Variant = planner.dispatch_tool("runtime_autonomy_patch", {
		"path": dup_target,
		"old_text": "dup",
		"new_text": "x",
	})
	_check(not bool((ambiguous as Dictionary).get("ok", true)), "patch with ambiguous old_text fails")

	# ── Search ─────────────────────────────────────────────────────
	var found: Variant = planner.dispatch_tool("runtime_autonomy_search", {"needle": "patched"})
	_check(int((found as Dictionary).get("count", 0)) >= 1, "search finds patched content")

	# ── Baseline detects the write ─────────────────────────────────
	bline = planner.dispatch_tool("runtime_autonomy_workspace_baseline", {})
	_check(not bool((bline as Dictionary).get("clean", true)), "baseline reports dirty workspace")

	# ── Write plan now selects the write tool (workspace bound) ────
	plan_write = planner.plan("write", ["file_change"], "any", false)
	_check(str(plan_write.get("verdict", "")) == "PASS", "write plan passes when workspace bound")

	# ── Probe is still read-only ───────────────────────────────────
	var plan_probe: Dictionary = planner.plan("probe write", ["file_change"], "visible", true)
	_check(str(plan_probe.get("verdict", "")) == "BLOCKED", "probe plan excludes mutating tools")

	# ── Rollback ───────────────────────────────────────────────────
	var rollback: Variant = planner.dispatch_tool("runtime_autonomy_rollback", {
		"transaction_id": str((written as Dictionary).get("transaction_id", "")),
	})
	_check(bool((rollback as Dictionary).get("ok", false)), "rollback succeeds")

	# ── Import / Export (gated apply) ───────────────────────────────
	var fixture_path := "res://addons/mcp/testing/import_export_fixture.gd"
	var fixture_content := "extends RefCounted\n\nvar marker := 1\n\nfunc get_marker() -> int:\n\treturn marker\n"
	var fixture_f := FileAccess.open(fixture_path, FileAccess.WRITE)
	fixture_f.store_string(fixture_content)
	fixture_f.close()

	# Import copies the file into the workspace
	var imported: Variant = planner.dispatch_tool("runtime_autonomy_workspace_import", {"path": fixture_path})
	_check(bool((imported as Dictionary).get("ok", false)), "import copies res:// file into workspace")
	var ws_import_path: String = str((imported as Dictionary).get("workspace_path", ""))
	_check(ws_import_path.begins_with(root + "/imports/"), "import lands under workspace imports/")
	_check(str((imported as Dictionary).get("origin_hash", "")) != "", "import records origin hash")

	# Imports listing
	var imports_list: Variant = planner.dispatch_tool("runtime_autonomy_imports", {})
	_check(int((imports_list as Dictionary).get("count", 0)) >= 1, "imports list reports the import")

	# Patch the workspace copy (marker 1 → 2)
	var fixture_patch: Variant = planner.dispatch_tool("runtime_autonomy_patch", {
		"path": ws_import_path,
		"old_text": "var marker := 1",
		"new_text": "var marker := 2",
	})
	_check(bool((fixture_patch as Dictionary).get("ok", false)), "workspace copy patchable after import")

	# Dry-run export (apply=false) validates but never writes
	var dry_run: Variant = planner.dispatch_tool("runtime_autonomy_export", {"path": fixture_path})
	_check(bool((dry_run as Dictionary).get("ok", false)), "export dry-run succeeds")
	_check(bool((dry_run as Dictionary).get("dry_run", false)), "export dry-run is not applied")
	var dry_valid: Dictionary = (dry_run as Dictionary).get("validation", {})
	_check(bool(dry_valid.get("ok", false)), "export validation passes")
	var fixture_after_dry := FileAccess.open(fixture_path, FileAccess.READ)
	var dry_text := fixture_after_dry.get_as_text()
	fixture_after_dry.close()
	_check(dry_text == fixture_content, "dry-run export leaves res:// untouched")

	# Apply export (apply=true) writes back to the project
	var applied: Variant = planner.dispatch_tool("runtime_autonomy_export", {"path": fixture_path, "apply": true})
	_check(bool((applied as Dictionary).get("ok", false)), "export apply succeeds")
	_check(bool((applied as Dictionary).get("applied", false)), "export reports applied")
	var export_tx: String = str((applied as Dictionary).get("transaction_id", ""))
	_check(export_tx != "", "export journals a transaction")
	var fixture_after_apply := FileAccess.open(fixture_path, FileAccess.READ)
	var applied_text := fixture_after_apply.get_as_text()
	fixture_after_apply.close()
	_check(applied_text.contains("var marker := 2"), "res:// file updated after export apply")

	# Rollback restores the original project file
	var export_rb: Variant = planner.dispatch_tool("runtime_autonomy_rollback", {"transaction_id": export_tx})
	_check(bool((export_rb as Dictionary).get("ok", false)), "export rollback succeeds")
	var fixture_after_rb := FileAccess.open(fixture_path, FileAccess.READ)
	var rb_text := fixture_after_rb.get_as_text()
	fixture_after_rb.close()
	_check(rb_text == fixture_content, "res:// file restored after export rollback")

	# Origin-changed guard: mutate res:// directly, then export without force
	var mutate_f := FileAccess.open(fixture_path, FileAccess.READ_WRITE)
	mutate_f.seek_end()
	mutate_f.store_string("\n# external edit\n")
	mutate_f.close()
	var refused: Variant = planner.dispatch_tool("runtime_autonomy_export", {"path": fixture_path, "apply": true})
	_check(not bool((refused as Dictionary).get("ok", true)), "export refused when origin changed")
	var forced: Variant = planner.dispatch_tool("runtime_autonomy_export", {"path": fixture_path, "apply": true, "force": true})
	_check(bool((forced as Dictionary).get("ok", false)), "export applies with force=true")

	# Invalid content is refused by validation even with force
	var invalid_f := FileAccess.open(ws_import_path, FileAccess.WRITE)
	invalid_f.store_string("this is not valid gd :::")
	invalid_f.close()
	var invalid_export: Variant = planner.dispatch_tool("runtime_autonomy_export", {"path": fixture_path, "apply": true, "force": true})
	_check(not bool((invalid_export as Dictionary).get("ok", true)), "export refuses invalid content")

	# ── Rollback all + end ─────────────────────────────────────────
	var rb_all: Variant = planner.dispatch_tool("runtime_autonomy_rollback_all", {})
	_check(bool((rb_all as Dictionary).get("ok", false)), "rollback_all succeeds")
	var ended: Variant = planner.dispatch_tool("runtime_autonomy_workspace_end", {})
	_check(bool((ended as Dictionary).get("ok", false)), "workspace_end succeeds")

	# ── Writes blocked after end (no bound workspace) ─────────────
	var write2: Variant = planner.dispatch_tool("runtime_autonomy_write", {
		"path": root.path_join("x.txt"),
		"content": "x",
	})
	_check(not bool((write2 as Dictionary).get("ok", true)), "write blocked after workspace end")

	# ── Clean up the run workspace + fixture so res:// stays pristine ──
	_remove_recursive(ProjectSettings.globalize_path(root))
	if FileAccess.file_exists(fixture_path):
		DirAccess.remove_absolute(fixture_path)

	print("Slice D write-gate contract test: %d failure(s)" % _failed)
	_finish()


func _remove_recursive(abs_path: String) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry not in [".", ".."]:
			var full := abs_path.path_join(entry)
			if dir.current_is_dir():
				_remove_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(abs_path)


func _finish() -> void:
	quit(1 if _failed > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] " + description)
	else:
		print("[FAIL] " + description)
		_failed += 1