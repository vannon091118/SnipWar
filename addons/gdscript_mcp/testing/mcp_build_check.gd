extends SceneTree

## Build-time parse check for the new Slice B/C autonomy modules.
## Usage: godot --headless --path . --script res://addons/.../mcp_build_check.gd

const FILES := [
	"res://addons/gdscript_mcp/runtime/autonomy/mcp_path_validator.gd",
	"res://addons/gdscript_mcp/runtime/autonomy/mcp_workspace_journal.gd",
	"res://addons/gdscript_mcp/runtime/autonomy/mcp_project_tools.gd",
]


func _init() -> void:
	var failed := false
	for path in FILES:
		var resource: Resource = load(path)
		if resource == null or not resource.can_instantiate():
			print("[FAIL] " + path)
			failed = true
		else:
			print("[OK]   " + path)
	quit(1 if failed else 0)