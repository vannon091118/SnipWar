class_name DOKI_SidePlotEngine
extends RefCounted
## Side-Plot-Erkennung — NEU implementiert (das alte System hatte hier nur einen
## TODO-Stub: MERGE_HEAD wurde nie ausgewertet, die SidePlot-Promptblöcke im
## VoiceComposer waren totes Material).
##
## Erkennt Merge-Kontext über .git/MERGE_HEAD und stellt den narrativen
## Kontext für den VoiceComposer bereit: Branch, Divergenzpunkt, Commits des
## Seitenpfads, beteiligte Narratoren (aus der Chain).

var _repo_root: String


func _init(repo_root: String) -> void:
	_repo_root = repo_root


func is_merge_in_progress() -> bool:
	return _git_file_exists("MERGE_HEAD")


func is_rebase_in_progress() -> bool:
	return _git_file_exists("rebase-merge") or _git_file_exists("rebase-apply")


## Baut den kompletten SidePlot-Kontext (leeres Dict wenn kein Merge).
func build_context(chain_entries: Array) -> Dictionary:
	if not is_merge_in_progress():
		return {}

	var merge_head: String = _read_git_file("MERGE_HEAD").strip_edges()
	if merge_head.is_empty():
		return {}

	var target_branch: String = _run_git("symbolic-ref --quiet --short HEAD").strip_edges()
	var source_branch: String = _branch_of_commit(merge_head)
	var merge_base: String = _run_git("merge-base HEAD %s" % merge_head).strip_edges()

	# Alle Commits des Seitenpfads seit Divergenzpunkt (exkl. merge_base).
	var side_commits_raw := _run_git("log --oneline --no-merges %s..%s" % [merge_base, merge_head])
	var side_commits: Array = []
	for line in side_commits_raw.split("\n"):
		var l: String = line.strip_edges()
		if not l.is_empty():
			side_commits.append(l)

	var merge_subject: String = _run_git("show -s --format=%s %s" % [merge_head.strip_edges()]).strip_edges()

	# Narratoren des Seitenpfads: Chain-Einträge auf dem Seitenpfad (via git log hashes).
	var side_hashes: Array = []
	var log_raw := _run_git("log --format=%H %s..%s" % [merge_base, merge_head])
	for line in log_raw.split("\n"):
		var l: String = line.strip_edges()
		if not l.is_empty():
			side_hashes.append(l)

	var narrators: Array = []
	var narrator_set := {}
	for e in chain_entries:
		var h: String = str(e.get("hash", ""))
		if side_hashes.has(h) or side_hashes.has(h.substr(0, 7)):
			var n: String = str(e.get("narrator", ""))
			if not n.is_empty() and not narrator_set.has(n):
				narrator_set[n] = true
				narrators.append(n)

	return {
		"active": true,
		"merge_head": merge_head.strip_edges().substr(0, 7),
		"target_branch": target_branch,
		"source_branch": source_branch,
		"divergence_hash": merge_base.substr(0, 7) if merge_base.length() > 7 else merge_base,
		"commit_count": side_commits.size(),
		"commit_summary": "\n".join(side_commits),
		"narrators": narrators,
		"merge_subject": merge_subject,
	}


func _branch_of_commit(commit_hash: String) -> String:
	# Beste Annäherung an den Quell-Branch: Branch des MERGE_HEAD-Commit.
	var branches: String = _run_git("branch --contains %s" % commit_hash.strip_edges())
	for line in branches.split("\n"):
		var l: String = line.strip_edges().lstrip("*").strip_edges()
		if not l.is_empty() and l != "HEAD":
			return l
	return "unbekannter Branch"


func _git_file_exists(name: String) -> bool:
	var git_dir: String = _run_git("rev-parse --git-path %s" % name).strip_edges()
	if git_dir.is_empty():
		return false
	return FileAccess.file_exists(git_dir)


func _read_git_file(name: String) -> String:
	var git_dir: String = _run_git("rev-parse --git-path %s" % name).strip_edges()
	if git_dir.is_empty() or not FileAccess.file_exists(git_dir):
		return ""
	return FileAccess.get_file_as_string(git_dir)


func _run_git(args: String) -> String:
	var output: Array = []
	var exit_code: int = OS.execute("git", args.split(" "), output, true)
	if exit_code != 0:
		return ""
	return str(output[0]) if output.size() > 0 else ""