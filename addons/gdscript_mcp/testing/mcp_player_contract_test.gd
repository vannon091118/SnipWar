extends SceneTree

## Spieler-Vertrag / Session-Profile / Smooth-Cursor / Response-Budget-Tests.
## Headless by design — das ist ein Contract-Test (kein sichtbarer Spielerlauf):
## Er beweist, dass die Vertragslogik (Gate, Truncation, Smooth-Step-Mathe,
## Headless-Verweigerung) funktioniert, und zählt getrennt vom Live-Gameplay-PASS.

const GATE_PATH := "res://addons/gdscript_mcp/runtime/autonomy/mcp_contract_gate.gd"
const PROTOCOL_PATH := "res://addons/gdscript_mcp/runtime/protocol/mcp_protocol.gd"
const RUNTIME_TOOLS_PATH := "res://addons/gdscript_mcp/runtime/tools/runtime/mcp_runtime_tools.gd"
const SERVER_PATH := "res://addons/gdscript_mcp/runtime/host/mcp_server.gd"

const PLAYER_BLOCKED := [
	"runtime_goal_play", "runtime_goal_sequence", "runtime_goal_check", "runtime_goal_history",
	"runtime_chain_run", "runtime_eval", "runtime_ux_click",
	"game_state_restore", "runtime_freeze", "runtime_unfreeze",
	"runtime_step_frame", "runtime_step_frames", "runtime_e2e_run",
]

var _failed := 0


func _init() -> void:
	_run()
	quit(1 if _failed > 0 else 0)


func _run() -> void:
	_test_gate()
	_test_renderer_contract()
	_test_protocol_budget()
	_test_smooth_travel()


# ─── Contract-Gate (player/qa/dev) ─────────────────────────────────────────

func _test_gate() -> void:
	var gate_script: Resource = load(GATE_PATH)
	_check(gate_script != null, "contract gate script loads")
	if gate_script == null:
		return
	var gate: RefCounted = gate_script.new()

	gate.configure("player", "runtime")
	_check(gate.get_profile() == "player", "default runtime profile is player")

	for tool_name in PLAYER_BLOCKED:
		var blocked: Dictionary = gate.check(tool_name)
		_check(not bool(blocked.get("allowed", true)), "player profile blocks " + tool_name)
		_check(str(blocked.get("code", "")) == "CONTRACT_VIOLATION", tool_name + " reports CONTRACT_VIOLATION")

	for tool_name in ["runtime_ux_scan", "runtime_click", "runtime_mouse_move",
			"runtime_camera_move_to", "game_state_summary", "runtime_scroll"]:
		var allowed: Dictionary = gate.check(tool_name)
		_check(bool(allowed.get("allowed", false)), "player profile allows " + tool_name)

	_check(gate.get_blocked_calls() > 0, "gate counts blocked calls")

	gate.configure("qa", "runtime")
	for tool_name in ["runtime_goal_play", "runtime_chain_run", "runtime_ux_click", "runtime_freeze"]:
		var allowed: Dictionary = gate.check(tool_name)
		_check(bool(allowed.get("allowed", false)), "qa profile allows " + tool_name)

	gate.configure("dev", "runtime")
	_check(bool(gate.check("runtime_eval").get("allowed", false)), "dev profile allows runtime_eval")

	gate.configure("", "editor")
	_check(gate.get_profile() == "dev", "editor role defaults to dev profile")


# ─── Headless ist absolut gegen den MCP-Vertrag ────────────────────────────

func _test_renderer_contract() -> void:
	var gate_script: Resource = load(GATE_PATH)
	if gate_script == null:
		return
	var verdict: Dictionary = gate_script.validate_renderer(true)
	_check(not bool(verdict.get("ok", true)), "validate_renderer rejects headless")
	var ok_verdict: Dictionary = gate_script.validate_renderer(false)
	_check(bool(ok_verdict.get("ok", false)), "validate_renderer accepts visible renderer")

	# Der Server selbst muss im Headless-Modus den Start verweigern.
	var server_script: Resource = load(SERVER_PATH)
	_check(server_script != null, "server script loads")
	if server_script != null:
		var server: Node = server_script.new()
		var visible: bool = bool(server.call("_is_renderer_visible"))
		_check(not visible, "server refuses to run under a headless renderer")
		server.free()


# ─── Response-Budget-Truncation (M1/A6) ────────────────────────────────────

func _test_protocol_budget() -> void:
	var protocol_script: Resource = load(PROTOCOL_PATH)
	_check(protocol_script != null, "protocol script loads")
	if protocol_script == null:
		return
	var small := {"a": 1, "b": "x"}
	var small_result: Dictionary = protocol_script.trim_result_to_budget(small, 200_000)
	_check(bool(small_result.get("fits", false)), "small result fits budget unchanged")
	_check(small_result.get("value", {}) == small, "small result value unchanged")

	var big := {"list": [], "blob": "y".repeat(500_000)}
	var big_result: Dictionary = protocol_script.trim_result_to_budget(big, 200_000)
	_check(not bool(big_result.get("fits", true)), "oversized result is trimmed")
	var value: Variant = big_result.get("value", null)
	_check(value is Dictionary and (value as Dictionary).has("_truncated"), "trimmed dict carries _truncated marker")
	_check(int(big_result.get("original_bytes", 0)) > int(big_result.get("trimmed_bytes", 0)), "trim reduces byte size")
	_check(int(big_result.get("original_bytes", 0)) > 200_000, "original measured above budget")
	_check((big_result.get("truncated_fields", []) as Array).size() > 0, "truncated_fields lists dropped paths")


# ─── Smooth Cursor Travel (kein Teleport) ──────────────────────────────────

func _test_smooth_travel() -> void:
	var tools_script: Resource = load(RUNTIME_TOOLS_PATH)
	_check(tools_script != null, "runtime tools script loads")
	if tools_script == null:
		return
	var from := Vector2(10.0, 10.0)
	var to := Vector2(410.0, 210.0)
	var travel: Array = tools_script.smooth_travel(from, to, 120)
	_check(travel.size() >= 3, "smooth travel has at least 3 steps (got " + str(travel.size()) + ")")
	_check(travel.size() <= 96, "smooth travel respects hard step cap")

	var last: Dictionary = travel[travel.size() - 1]
	_check((last.get("pos") as Vector2).distance_to(to) < 0.01, "last step reaches target exactly")

	var previous_frame := 0
	var monotonic := true
	for i in range(travel.size()):
		var frame := int(travel[i].get("frame", 0))
		if frame <= previous_frame:
			monotonic = false
		previous_frame = frame
	_check(monotonic, "frames increase monotonically")

	_check(tools_script.smooth_travel(from, from, 120).is_empty(), "no travel when target == start")

	# Distanz-basiert: 400 px √(400²+200²) ≈ 447 px / 36 px ≈ 13 Schritte,
	# gedeckelt durch duration_ms 120 ms → 8 Schritte (16 ms/Frame).
	var capped: Array = tools_script.smooth_travel(from, to, 120)
	_check(capped.size() <= 8, "duration cap: 120ms => max 8 steps (got " + str(capped.size()) + ")")
	var uncapped: Array = tools_script.smooth_travel(from, to, 1000)
	_check(uncapped.size() > capped.size(), "longer duration allows more steps")


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PASS] " + description)
	else:
		print("[FAIL] " + description)
		_failed += 1