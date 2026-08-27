extends SceneTree

func _initialize() -> void:
	var root := ProjectSettings.globalize_path("res://")
	var python := "python"
	var output: int = OS.execute(python, ["-m", "narrative_runtime.gate_cli", "--root", root], [], true)
	if output != OK:
		push_error("NARRATIVE_RUNTIME_GATE failed with exit code %d" % output)
		quit(1)
		return
	print("NARRATIVE_RUNTIME_GATE: PASSED")
	quit(0)
