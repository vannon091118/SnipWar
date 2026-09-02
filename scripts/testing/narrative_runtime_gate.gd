extends SceneTree

func _initialize() -> void:
	var root := ProjectSettings.globalize_path("res://")
	var python := "python"
	# Pfad-Migration: Runtime lebt unter .doki/narrative_runtime (Package-Kontext
	# via sys.path, damit die relativen Imports funktionieren).
	var py_code := "import sys; sys.path.insert(0, r'%s'); from narrative_runtime.gate_cli import main; raise SystemExit(main())" % root.path_join(".doki")
	var output: int = OS.execute(python, ["-c", py_code, "--root", root], [], true)
	if output != OK:
		push_error("NARRATIVE_RUNTIME_GATE failed with exit code %d" % output)
		quit(1)
		return
	print("NARRATIVE_RUNTIME_GATE: PASSED")
	quit(0)
