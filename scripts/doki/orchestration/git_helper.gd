class_name DOKI_GitHelper
extends RefCounted
## Alle Git-Zugriffe zentral. Jeder Exit-Code != 0 wird hart behandelt —
## das alte System ignorierte Exit-Codes (auto-commit lief still ins Leere).

var _repo_root: String


func _init(repo_root: String) -> void:
	_repo_root = repo_root


## Führt git aus; returns {ok, stdout, stderr, exit_code}.
## Godot 4.7: `OS.execute(path, args, output, read_stderr=true)` — stderr landet
## im Output-Array auf Index 1 (kein separater stderr-Parameter).
func run(args: Array) -> Dictionary:
	var output: Array = []
	var full_args: Array = ["-C", _repo_root]
	full_args.append_array(args)
	var exit_code: int = OS.execute("git", full_args, output, true)
	return {
		"ok": exit_code == 0,
		"stdout": str(output[0]) if output.size() > 0 else "",
		"stderr": str(output[1]) if output.size() > 1 else "",
		"exit_code": exit_code,
	}


func check_repo() -> bool:
	return run(["rev-parse", "--is-inside-work-tree"])["ok"]


func head_hash_short() -> String:
	var r: Dictionary = run(["rev-parse", "--short", "HEAD"])
	return r["stdout"].strip_edges()


func head_hash_full() -> String:
	var r: Dictionary = run(["rev-parse", "HEAD"])
	return r["stdout"].strip_edges()


func head_subject() -> String:
	var r: Dictionary = run(["log", "-1", "--format=%s"])
	return r["stdout"].strip_edges()


func head_date() -> String:
	var r: Dictionary = run(["log", "-1", "--format=%ci"])
	return r["stdout"].strip_edges()


## Vollständige HEAD-Message (für amend-Erkennung im Gate).
func head_message() -> String:
	var r: Dictionary = run(["log", "-1", "--format=%B"])
	return r["stdout"]


## Tree-Hash von HEAD^{tree} (Kontext-Anker des Seeds — wie im Original).
func head_tree_hash() -> String:
	var r: Dictionary = run(["rev-parse", "HEAD^{tree}"])
	return r["stdout"].strip_edges()


func staged_files() -> Array:
	var r: Dictionary = run(["diff", "--cached", "--name-only"])
	var files: Array = []
	if not r["ok"]:
		return files
	for line in str(r["stdout"]).split("\n"):
		var l: String = line.strip_edges()
		if not l.is_empty():
			files.append(l)
	return files


## Roh-Ausgabe von `git diff --cached` (deterministischer Seed-Input).
func diff_cached() -> String:
	var r: Dictionary = run(["diff", "--cached"])
	return r["stdout"] if r["ok"] else ""


## Ungestagte Diffs auf Doku-Dateien (Check 8).
## CRLF-Warnzeilen („warning: ... LF will be replaced by CRLF“) werden
## gefiltert — sie sind kein Diff.
func unstaged_diffs() -> Array:
	var r: Dictionary = run(["diff", "--name-only"])
	var files: Array = []
	if not r["ok"]:
		return files
	for line in str(r["stdout"]).split("\n"):
		var l: String = line.strip_edges()
		if l.is_empty() or l.begins_with("warning:"):
			continue
		files.append(l)
	return files


## Letzte n Commits (älteste zuerst) für init --seed-last: [{hash, subject, date}]
func last_commits(n: int) -> Array:
	var r: Dictionary = run(["log", "-%d" % n, "--format=%H%x09%s%x09%ci"])
	var result: Array = []
	if not r["ok"]:
		return result
	for line in str(r["stdout"]).split("\n"):
		var parts: PackedStringArray = line.split("\t")
		if parts.size() >= 3:
			result.append({
				"hash": parts[0].strip_edges(),
				"subject": parts[1].strip_edges(),
				"date": parts[2].strip_edges(),
			})
	result.reverse()  # älteste zuerst
	return result


## Tree-Hash eines beliebigen Commits (für deterministisches History-Seeding).
func commit_tree_hash(commit_hash: String) -> String:
	var r: Dictionary = run(["rev-parse", "%s^{tree}" % commit_hash])
	return r["stdout"].strip_edges()


func stage(files: Array) -> Dictionary:
	var args: Array = ["add"]
	args.append_array(files)
	return run(args)


func is_merge_in_progress() -> bool:
	var r: Dictionary = run(["rev-parse", "--git-path", "MERGE_HEAD"])
	if not r["ok"]:
		return false
	return FileAccess.file_exists(r["stdout"].strip_edges())


func is_rebase_in_progress() -> bool:
	var r: Dictionary = run(["rev-parse", "--git-path", "rebase-merge"])
	if r["ok"] and FileAccess.file_exists(r["stdout"].strip_edges()):
		return true
	var r2: Dictionary = run(["rev-parse", "--git-path", "rebase-apply"])
	return r2["ok"] and FileAccess.file_exists(r2["stdout"].strip_edges())