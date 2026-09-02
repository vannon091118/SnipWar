extends SceneTree

## Slice B/C contract test: workspace journal + project tools + path validator.
## Covers success, failure, and fail-closed edge cases (traversal, prefixes,
## res:// writes, hash mismatch, ambiguous patches, rollback, baseline verify).

const PATH_VALIDATOR_PATH := "res://addons/gdscript_mcp/runtime/autonomy/mcp_path_validator.gd"
const JOURNAL_PATH := "res://addons/gdscript_mcp/runtime/autonomy/mcp_workspace_journal.gd"
const PROJECT_TOOLS_PATH := "res://addons/gdscript_mcp/runtime/autonomy/mcp_project_tools.gd"

const TEST_SESSION := "slice_bc_test_session"
const TEST_PROJECT := "slice_bc_test_project"

var _failed := 0


func _init() -> void:
	_run()


func _run() -> void:
	var validator_script: Resource = load(PATH_VALIDATOR_PATH)
	var journal_script: Resource = load(JOURNAL_PATH)
	var tools_script: Resource = load(PROJECT_TOOLS_PATH)
	_check(validator_script != null, "path validator script loads")
	_check(journal_script != null, "workspace journal script loads")
	_check(tools_script != null, "project tools script loads")
	if _failed > 0:
		_finish()
		return

	_test_path_validator(validator_script.new())
	var journal: RefCounted = journal_script.new()
	_test_journal(journal)
	_test_project_tools(tools_script.new(), journal)

	print("Slice B/C workspace contract test: %d failure(s)" % _failed)
	_finish()


func _test_path_validator(validator: RefCounted) -> void:
	# Allowed roots
	_check(bool(validator.is_allowed_path("res://foo.gd").get("ok", false)), "res:// path allowed")
	_check(bool(validator.is_allowed_path("user://foo.gd").get("ok", false)), "user:// path allowed")
	# Fail-closed: absolute OS paths, traversal, control characters, empty
	_check(not bool(validator.is_allowed_path("C:/Windows/system32/cmd.exe").get("ok", true)), "absolute OS path rejected")
	_check(not bool(validator.is_allowed_path("/etc/passwd").get("ok", true)), "absolute unix path rejected")
	_check(not bool(validator.is_allowed_path("res://../escape.gd").get("ok", true)), "path traversal rejected")
	_check(not bool(validator.is_allowed_path("res://a/../b.gd").get("ok", true)), "embedded traversal rejected")
	_check(not bool(validator.is_allowed_path("res://foo" + char(1) + "bar.gd").get("ok", true)), "control characters rejected")
	_check(not bool(validator.is_allowed_path("").get("ok", true)), "empty path rejected")
	# Prefix restriction
	var prefixed_ok: Dictionary = validator.is_allowed_path("res://mcp_tools/foo.gd", ["res://mcp_tools"])
	_check(bool(prefixed_ok.get("ok", false)), "path inside allowed prefix accepted")
	var prefixed_bad: Dictionary = validator.is_allowed_path("res://other/foo.gd", ["res://mcp_tools"])
	_check(not bool(prefixed_bad.get("ok", true)), "path outside allowed prefix rejected")
	# Within-root checks
	_check(bool(validator.is_within_root("res://a/b.gd", "res://a").get("ok", false)), "path within root accepted")
	_check(not bool(validator.is_within_root("res://b.gd", "res://a").get("ok", true)), "path outside root rejected")
	_check(not bool(validator.is_within_root("res://ab/c.gd", "res://a").get("ok", true)), "root prefix sibling rejected")
	# Hashing
	var hash_a: String = validator.sha256_of_text("hello")
	var hash_b: String = validator.sha256_of_text("hello")
	var hash_c: String = validator.sha256_of_text("hello!")
	_check(hash_a == hash_b, "sha256 is deterministic")
	_check(hash_a != hash_c, "sha256 changes with content")
	_check(hash_a.length() == 64, "sha256 hex length is 64")
	# Secure read round-trip on a real file
	var self_read: Dictionary = validator.secure_read(PATH_VALIDATOR_PATH)
	_check(bool(self_read.get("ok", false)), "secure_read opens existing res:// file")
	if bool(self_read.get("ok", false)):
		_check(str(self_read.get("sha256", "")) == hash_a or str(self_read.get("sha256", "")) != "", "secure_read returns a sha256")
		_check(int(self_read.get("bytes", 0)) > 0, "secure_read returns byte count")


func _test_journal(journal: RefCounted) -> void:
	_check(not journal.is_bound(), "journal is unbound before begin_run")
	var begin: Dictionary = journal.begin_run(TEST_PROJECT, TEST_SESSION, "test", 12345)
	_check(bool(begin.get("ok", true)), "begin_run succeeds")
	_check(journal.is_bound(), "journal is bound after begin_run")
	_check(str(journal.status().get("state", "")) == "CLEAN", "journal starts CLEAN")
	_check(str(journal.session_id) == TEST_SESSION, "journal stores session id")
	_check(str(journal.root_path).begins_with("user://mcp_workspaces/"), "journal root lives under user://mcp_workspaces")

	var root: String = str(journal.root_path)
	var target: String = root.path_join("sample.gd")

	# Preimage for a new file (does not exist yet)
	var pre_new: Dictionary = journal.journal_preimage(target, "v0", true)
	_check(bool(pre_new.get("ok", false)), "journal_preimage accepts new file")
	_check(str(pre_new.get("transaction_id", "")).begins_with("tx_"), "preimage returns a transaction id")
	_check(str(journal.status().get("state", "")) == "DIRTY", "journal turns DIRTY after preimage")

	# Write the file, then commit with its after-hash
	var write_file := FileAccess.open(ProjectSettings.globalize_path(target), FileAccess.WRITE)
	write_file.store_string("v1")
	write_file.close()
	var after_hash: String = journal.scan_dir_files(root).get("sample.gd", "") if journal.has_method("scan_dir_files") else ""
	if after_hash == "":
		after_hash = _sha_of(target)
	var commit: Dictionary = journal.commit(str(pre_new.get("transaction_id", "")), after_hash, TEST_SESSION)
	_check(bool(commit.get("ok", false)), "commit accepts after-hash")

	# Rollback removes the file again (it did not exist before)
	var rollback: Dictionary = journal.rollback(str(pre_new.get("transaction_id", "")), TEST_SESSION)
	_check(bool(rollback.get("ok", false)), "rollback restores preimage state")
	_check(not FileAccess.file_exists(target), "rollback removed file that did not exist before")

	# Preimage for an existing file, mutate, rollback restores content
	var seed_file := FileAccess.open(ProjectSettings.globalize_path(target), FileAccess.WRITE)
	seed_file.store_string("original")
	seed_file.close()
	var exist: Dictionary = journal.journal_preimage(target, "original", true)
	var exist_tx: String = str(exist.get("transaction_id", ""))
	var wf := FileAccess.open(ProjectSettings.globalize_path(target), FileAccess.WRITE)
	wf.store_string("mutated")
	wf.close()
	var rb: Dictionary = journal.rollback(exist_tx, TEST_SESSION)
	_check(bool(rb.get("ok", false)), "rollback restores existing file content")
	var rf := FileAccess.open(target, FileAccess.READ)
	_check(rf != null and rf.get_as_text() == "original", "rolled-back file content matches preimage")
	if rf != null:
		rf.close()

	# rollback_all across both txs restores every preimage and returns CLEAN
	var all: Dictionary = journal.rollback_all(TEST_SESSION)
	_check(bool(all.get("ok", false)), "rollback_all succeeds")
	_check(str(journal.status().get("state", "")) == "CLEAN", "journal returns to CLEAN")

	# Baseline: the run started with an empty workspace. Clear the restored
	# file, then the workspace matches the baseline fingerprint.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	var baseline: Dictionary = journal.verify_baseline(TEST_SESSION)
	_check(bool(baseline.get("clean", false)), "baseline verify passes after rollback")

	# Baseline detects foreign writes (files changed outside the journal)
	var foreign := FileAccess.open(ProjectSettings.globalize_path(root.path_join("foreign.txt")), FileAccess.WRITE)
	foreign.store_string("unexpected")
	foreign.close()
	var dirty: Dictionary = journal.verify_baseline(TEST_SESSION)
	_check(not bool(dirty.get("clean", true)), "baseline detects foreign writes")
	_check(dirty.get("new_files", []).size() >= 1, "baseline lists foreign files as new")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join("foreign.txt")))
	var clean_again: Dictionary = journal.verify_baseline(TEST_SESSION)
	_check(bool(clean_again.get("clean", false)), "baseline is clean again after removing foreign file")

	# Session mismatch is refused everywhere
	_check(not bool(journal.verify_session("wrong").get("ok", true)), "wrong session rejected")
	_check(not bool(journal.rollback("tx_x", "wrong").get("ok", true)), "rollback with wrong session rejected")

	# finish refuses pending transactions
	var pending: Dictionary = journal.journal_preimage(target, "x", true)
	var finish_result: Dictionary = journal.finish(TEST_SESSION)
	_check(not bool(finish_result.get("ok", true)), "finish refuses uncommitted transactions")
	journal.commit(str(pending.get("transaction_id", "")), _sha_of(target), TEST_SESSION)
	var finish_ok: Dictionary = journal.finish(TEST_SESSION)
	_check(bool(finish_ok.get("ok", false)), "finish passes with no pending transactions")

	# Cleanup the run workspace
	_remove_recursive(journal.root_path)


func _test_project_tools(tools: RefCounted, journal: RefCounted) -> void:
	_check(not tools.is_workspace_bound(), "project tools unbound before setup")
	var begin: Dictionary = journal.begin_run(TEST_PROJECT, TEST_SESSION, "test", 6789)
	var root: String = str(journal.root_path)
	tools.setup(root, TEST_SESSION, journal)
	_check(tools.is_workspace_bound(), "project tools bound after setup")
	_check(str(tools.workspace_root()) == root, "workspace root stored")

	# Read: allowed for res:// and user://
	var res_read: Dictionary = tools.read(PATH_VALIDATOR_PATH)
	_check(bool(res_read.get("ok", false)), "read opens res:// file")
	_check(int(res_read.get("bytes", 0)) > 0, "read returns byte count")
	var missing_read: Dictionary = tools.read("res://addons/gdscript_mcp/nope_does_not_exist.gd")
	_check(not bool(missing_read.get("ok", true)), "read reports missing file")

	# Write: inside workspace only; res:// and outside paths blocked
	var target: String = root.path_join("proj/notes.md")
	var written: Dictionary = tools.write(target, "# hello\n", "", TEST_SESSION)
	_check(bool(written.get("ok", false)), "write inside workspace succeeds")
	_check(str(written.get("transaction_id", "")) != "", "write returns transaction id")
	_check(str(written.get("after_hash", "")) != "", "write returns after-hash")
	_check(FileAccess.file_exists(target), "write created the file")

	var res_write: Dictionary = tools.write("res://addons/gdscript_mcp/forbidden.gd", "x", "", TEST_SESSION)
	_check(not bool(res_write.get("ok", true)), "res:// write blocked")
	var outside_write: Dictionary = tools.write("user://mcp_workspaces/outside_probe.txt", "x", "", TEST_SESSION)
	_check(not bool(outside_write.get("ok", true)), "write outside workspace blocked")

	# Hash mismatch refuses the write
	var stale: Dictionary = tools.write(target, "# changed\n", "deadbeef", TEST_SESSION)
	_check(not bool(stale.get("ok", true)), "write with stale hash refused")
	_check(str(stale.get("before", "")) == str(written.get("after_hash", "")), "hash mismatch reports before-hash")

	# Patch: exact match, not-found, ambiguous
	var patched: Dictionary = tools.patch_content(target, "# hello", "# patched", "", TEST_SESSION)
	_check(bool(patched.get("ok", false)), "patch applies single occurrence")
	var not_found: Dictionary = tools.patch_content(target, "# missing", "# x", "", TEST_SESSION)
	_check(not bool(not_found.get("ok", true)), "patch with missing old_text fails")
	tools.write(target, "dup\ndup\n", "", TEST_SESSION)
	var ambiguous: Dictionary = tools.patch_content(target, "dup", "x", "", TEST_SESSION)
	_check(not bool(ambiguous.get("ok", true)), "patch with ambiguous old_text fails")

	# Search finds content in workspace files
	var search_result: Dictionary = tools.search("dup", 10)
	_check(bool(search_result.get("ok", false)), "search succeeds")
	_check(int(search_result.get("count", 0)) >= 1, "search finds the needle")

	# Symbols on a GDScript file
	var script_path: String = root.path_join("proj/demo.gd")
	tools.write(script_path, "class_name DemoClass\nextends RefCounted\n\nvar speed := 1.0\nconst MAX := 9\n\nfunc run() -> void:\n\tprint(speed)\n", "", TEST_SESSION)
	var symbols: Dictionary = tools.find_symbols(script_path)
	_check("DemoClass" in symbols.get("classes", []), "symbols detect class_name")
	_check(symbols.get("funcs", []).size() >= 1 and str(symbols.get("funcs", [])[0].get("name", "")) == "run", "symbols detect func")
	_check("speed" in symbols.get("vars", []) and "MAX" in symbols.get("vars", []), "symbols detect var and const")

	# Rollback via project tools restores the pre-write state
	var before_target: String = str(written.get("before_hash", ""))
	var tx_id: String = str(written.get("transaction_id", ""))
	var rb: Dictionary = tools.rollback_transaction(tx_id, TEST_SESSION)
	_check(bool(rb.get("ok", false)), "project tools rollback succeeds")
	var after_rollback: Dictionary = tools.read(target)
	_check(str(after_rollback.get("sha256", "")) == before_target, "rollback restores original content")

	# Cleanup the run workspace
	_remove_recursive(journal.root_path)


func _sha_of(path: String) -> String:
	var validator_script: Resource = load(PATH_VALIDATOR_PATH)
	return validator_script.sha256_of_file(path) if validator_script != null else ""


func _remove_recursive(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	var dir := DirAccess.open(abs)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry not in [".", ".."]:
			var full := abs.path_join(entry)
			if dir.current_is_dir():
				_remove_recursive(ProjectSettings.globalize_path(full))
			else:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(abs)


func _finish() -> void:
	quit(1 if _failed > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] " + description)
	else:
		print("[FAIL] " + description)
		_failed += 1
