extends SceneTree

## Entry test for Python/GDScript Audio Pipeline:
## Drives McpToolRegistry to verify runtime_audio_analyze & runtime_audio_slice_auto
## calling audio_analyzer.py CLI and returning clean JSON structures.

const EVIDENCE_PATH := "user://mcp_evidence/audio_analyzer_entry.json"

var _checks: int = 0
var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  [PASS] " + label)
	else:
		_failures += 1
		print("  [FAIL] " + label)


func _init() -> void:
	create_timer(15.0).timeout.connect(func() -> void:
		print("[t] WATCHDOG TIMEOUT")
		quit(3)
	)
	var registry: RefCounted = load("res://addons/gdscript_mcp/runtime/core/mcp_tool_registry.gd").new()
	var evidence: Array = []

	print("AUDIO_ANALYZER_ENTRY: Testing hybrid audio pipeline...")

	# T1 — dispatch runtime_audio_analyze on main_menu.ogg
	var res1: Dictionary = registry.dispatch("runtime_audio_analyze", {
		"audio_path": "res://assets/audio/music/main_menu.ogg"
	})
	evidence.append({"id": "t1_audio_analyze", "result": res1})
	_check(res1 is Dictionary and res1.get("ok", false) == true, "T1 audio_analyze returned ok=true")
	_check(res1.get("file", "") == "main_menu.ogg", "T1 audio_analyze file matches main_menu.ogg")
	_check(float(res1.get("duration", 0.0)) > 80.0, "T1 audio_analyze duration > 80s")
	_check(res1.get("peaks", []) is Array and not res1.get("peaks", []).is_empty(), "T1 audio_analyze returned peaks array")

	# T2 — dispatch runtime_audio_slice_auto on main_menu.ogg into a temp dir
	var res2: Dictionary = registry.dispatch("runtime_audio_slice_auto", {
		"audio_path": "res://assets/audio/music/main_menu.ogg",
		"output_dir": "user://test_audio_slices"
	})
	evidence.append({"id": "t2_audio_slice_auto", "result": res2})
	_check(res2 is Dictionary and res2.get("ok", false) == true, "T2 audio_slice_auto returned ok=true")
	_check(int(res2.get("slices_created", 0)) > 0, "T2 audio_slice_auto created > 0 slices")

	# T3 — dispatch runtime_audio_render_evidence on paper_rustle.ogg
	var res3: Dictionary = registry.dispatch("runtime_audio_render_evidence", {
		"audio_path": "res://assets/audio/sfx/paper_rustle.ogg",
		"output_dir": "user://test_audio_evidence"
	})
	evidence.append({"id": "t3_audio_render_evidence", "result": res3})
	_check(res3 is Dictionary and res3.get("ok", false) == true, "T3 audio_render_evidence returned ok=true")
	_check(res3.get("artifacts", []) is Array and not res3.get("artifacts", []).is_empty(), "T3 audio_render_evidence returned artifacts array")

	# T4 — dispatch runtime_audio_compare between paper_rustle.ogg and space_noise.ogg
	var res4: Dictionary = registry.dispatch("runtime_audio_compare", {
		"audio_path_a": "res://assets/audio/sfx/paper_rustle.ogg",
		"audio_path_b": "res://assets/audio/sfx/space_noise.ogg"
	})
	evidence.append({"id": "t4_audio_compare", "result": res4})
	_check(res4 is Dictionary and res4.get("ok", false) == true, "T4 audio_compare returned ok=true")
	var comparison: Dictionary = res4.get("comparison", {})
	_check(comparison.get("similarity_score", -1.0) >= 0.0 and comparison.get("similarity_score", -1.0) <= 1.0, "T4 audio_compare returned valid similarity score")

	# T5 — dispatch runtime_audio_review on paper_rustle.ogg
	var res5: Dictionary = registry.dispatch("runtime_audio_review", {
		"audio_path": "res://assets/audio/sfx/paper_rustle.ogg"
	})
	evidence.append({"id": "t5_audio_review", "result": res5})
	_check(res5 is Dictionary and res5.get("ok", false) == true, "T5 audio_review returned ok=true")
	_check(res5.get("analysis", {}) is Dictionary and not res5.get("analysis", {}).is_empty(), "T5 audio_review returned analysis dict")
	_check(res5.get("classification", {}) is Dictionary and not res5.get("classification", {}).is_empty(), "T5 audio_review returned classification dict")
	_check(res5.get("evidence_artifacts", []) is Array, "T5 audio_review returned evidence_artifacts array")
	_check(res5.get("recommendations", []) is Array, "T5 audio_review returned recommendations array")

	# Write evidence JSON
	DirAccess.make_dir_recursive_absolute("user://mcp_evidence")
	var f := FileAccess.open(EVIDENCE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(evidence, "  "))
		f.close()

	print("AUDIO_ANALYZER_ENTRY: %d/%d checks passed" % [_checks - _failures, _checks])
	if _failures == 0:
		print("AUDIO_ANALYZER_ENTRY: PASS")
		quit(0)
	else:
		print("AUDIO_ANALYZER_ENTRY: FAIL (%d errors)" % _failures)
		quit(1)
