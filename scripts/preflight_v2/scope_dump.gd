extends SceneTree

## Scope dump for the external verification driver (scripts/verify.py).
##
## The ChangeImpactResolver (paths → contracts → constraints) stays the single
## source of truth in GDScript; this tiny headless script exposes its result as
## JSON so the out-of-engine driver never duplicates the mapping tables.
##
## Usage:
##   godot --headless --path . --script res://scripts/preflight_v2/scope_dump.gd \
##     -- --paths-file=<absolute path to JSON array of repo-relative paths>
##
## Output: one line "@@SCOPE_JSON@@" + JSON result of ChangeImpactResolver.resolve().

const RESOLVER := preload("res://scripts/preflight_v2/change_impact_resolver.gd")

const MARKER := "@@SCOPE_JSON@@"

func _init() -> void:
	var paths_file := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--paths-file="):
			paths_file = arg.trim_prefix("--paths-file=")

	var result: Dictionary
	if paths_file.is_empty() or not FileAccess.file_exists(paths_file):
		result = { "ok": false, "error": "no paths file provided" }
	else:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(paths_file))
		if parsed is Array:
			result = RESOLVER.resolve(parsed)
		else:
			result = { "ok": false, "error": "paths file is not a JSON array" }

	print(MARKER + JSON.stringify(result))
	quit(0)
	return
