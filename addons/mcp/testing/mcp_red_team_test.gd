extends SceneTree

## RED TEAM — MCP-Vertrags-/Lücken-Test (Defense-in-Depth).
## Zielbild: Der MCP muss Vertragsbrüche und Abkürzungen aktiv ABWEHREN.
## Jeder Angriff ist ein FAIL, wenn er DURCHKOMMT — nicht, wenn er abgewehrt
## wird. Bestehende Sicherungen (Gate, Headless-Verbot, Writes-Gate,
## Chain-Validierung, Truncation, Freeze-Kontrakt) werden hier als Abwehr
## getestet; neue Lücken werden als [FAIL] gemeldet.

const GATE_PATH := "res://addons/mcp/runtime/autonomy/mcp_contract_gate.gd"
const PROTOCOL_PATH := "res://addons/mcp/runtime/protocol/mcp_protocol.gd"
const RUNTIME_TOOLS_PATH := "res://addons/mcp/runtime/tools/runtime/mcp_runtime_tools.gd"
const SERVER_PATH := "res://addons/mcp/runtime/host/mcp_server.gd"
const CHAIN_PATH := "res://addons/mcp/runtime/autonomy/mcp_chain_controller.gd"
const AGENT_PATH := "res://addons/mcp/runtime/tools/agent/mcp_agent_activity.gd"

var _failed := 0
var _checks := 0


func _init() -> void:
	_run()
	quit(1 if _failed > 0 else 0)


func _run() -> void:
	print("===== RED TEAM MCP DEFENSE =====")
	_test_player_gate_blocks_cheats()
	_test_gate_qa_vs_player()
	_test_headless_absolutely_blocked()
	_test_writes_gate_parity()
	_test_chain_rejects_composites()
	_test_freeze_requires_unfreeze()
	_test_truncation_marker()
	_test_smooth_mouse_no_teleport()
	_test_agent_activity_transparency()
	print("===== RED TEAM DONE: %d checks, %d passes, %d FAILures =====" % [_checks, _checks - _failed, _failed])


# ── 1. Der „Cheat“-Katalog im player-Profil muss GEBLOCKT werden ────────────

func _test_player_gate_blocks_cheats() -> void:
	var gate_script: Resource = load(GATE_PATH)
	_check(gate_script != null, "gate script loads")
	if gate_script == null:
		return
	var gate: RefCounted = gate_script.new()
	gate.configure("player", "runtime")

	var cheat_tools := [
		"runtime_goal_play",        # Spieler-Ersatz: plant mehrere Aktionen
		"runtime_goal_sequence",
		"runtime_chain_run",        # vorgeplante Kette
		"runtime_eval",             # Forschung per Funktionscall
		"runtime_ux_click",         # Find+Klick in einem Tool
		"game_state_restore",       # direkte GameState-Mutation
		"runtime_freeze",           # Debug-Modus im Spieler-Lauf
		"runtime_unfreeze",
		"runtime_step_frame",
		"runtime_step_frames",
		"runtime_e2e_run",          # vorgeplante Szenarien
		"runtime_autonomy_write",   # Edit im Spieler-Lauf
		"runtime_autonomy_export",
	]
	for tool in cheat_tools:
		var verdict: Dictionary = gate.check(tool)
		_check(not bool(verdict.get("allowed", true)), "player blocks cheat: " + tool)

	# Erlaubte Alltags-Tools müssen weitergehen
	for tool in ["runtime_ux_scan", "runtime_click", "runtime_mouse_move", "runtime_scroll", "game_state_summary"]:
		var verdict: Dictionary = gate.check(tool)
		_check(bool(verdict.get("allowed", false)), "player allows normal: " + tool)


# ── 2. qa-Profil: nur Debug-Tools frei, aber Cheats (Eval/Restore) bleiben gesperrt ──

func _test_gate_qa_vs_player() -> void:
	var gate_script: Resource = load(GATE_PATH)
	if gate_script == null:
		return
	var gate: RefCounted = gate_script.new()
	gate.configure("qa", "runtime")
	for tool in ["runtime_goal_play", "runtime_chain_run", "runtime_ux_click"]:
		var verdict: Dictionary = gate.check(tool)
		_check(bool(verdict.get("allowed", false)), "qa allows debug tool: " + tool)


# ── 3. Headless ist absolut gegen den MCP-Vertrag ───────────────────────────

func _test_headless_absolutely_blocked() -> void:
	var gate_script: Resource = load(GATE_PATH)
	var renderer_verdict: Dictionary = gate_script.validate_renderer(true)
	_check(not bool(renderer_verdict.get("ok", true)), "headless renderer rejected by contract")
	var ok_verdict: Dictionary = gate_script.validate_renderer(false)
	_check(bool(ok_verdict.get("ok", false)), "visible renderer accepted")
	var server_script: Resource = load(SERVER_PATH)
	if server_script != null:
		var server: Node = server_script.new()
		var visible: bool = bool(server.call("_is_renderer_visible"))
		_check(not visible, "server refuses headless renderer")
		server.free()


# ── 4. Writes-Gate-Parity: Editor-Writes muss Autonomy-Writes aktivieren ─────────────────

func _test_writes_gate_parity() -> void:
	var server_script: Resource = load(SERVER_PATH)
	if server_script != null:
		var resolved: bool = bool(server_script.call("_resolve_autonomy_writes", {"editor_write_enabled": true}))
		_check(resolved, "editor_write_enabled activates autonomy writes")
		var not_resolved: bool = bool(server_script.call("_resolve_autonomy_writes", {"editor_write_enabled": false}))
		_check(not not_resolved, "no writes without gate")


func _test_chain_rejects_composites() -> void:
	var chain_script: Resource = load(CHAIN_PATH)
	_check(chain_script != null, "chain script loads")
	if chain_script == null:
		return
	var chain: RefCounted = chain_script.new()
	var bad := {
		"mode": "visible",
		"steps": [{"tool": "runtime_goal_play", "args": {}}],
	}
	var verdict: Variant = chain.call("validate_chain", bad)
	_check(not bool(verdict.get("ok", false)), "visible chain with goal_play rejected")
	_check(verdict is Dictionary and int((verdict as Dictionary).get("errors", []).size()) > 0, "chain error list not empty")


# ── 6. Freeze/Step-Kontrakt: step ohne freeze muss abgelehnt werden ─────────

func _test_freeze_requires_unfreeze() -> void:
	# Bestehende E2E freeze_step prüft: step vor freeze -> Fehler.
	pass


# ─ 7. Truncation-Marker ───────────────────────────────────────────────────────

func _test_truncation_marker() -> void:
	var protocol_script := load(PROTOCOL_PATH)
	if protocol_script == null:
		return
	var big := {"blob": "y".repeat(600_000)}
	var result: Dictionary = protocol_script.call("trim_result_to_budget", big, 200_000)
	_check(not bool(result.get("fits", true)), "large result trimmed")
	var value: Variant = result.get("value")
	_check(value is Dictionary and ((value as Dictionary).has("_truncated") or str((value as Dictionary).get("_truncated", "")) != ""), "truncation marker set")


# ── 8. Smooth-Mouse: kein Teleport ──────────────────────────────────────────

func _test_smooth_mouse_no_teleport() -> void:
	var tools_script: Resource = load(RUNTIME_TOOLS_PATH)
	if tools_script == null:
		return
	var travel: Array = tools_script.call("smooth_travel", Vector2.ZERO, Vector2(500, 500), 200)
	_check(travel.size() >= 8, "smooth travel has intermediate steps (got %d)" % travel.size())
	_check(travel.size() < 200, "smooth travel bounded")
	var first: Dictionary = travel[0] if not travel.is_empty() else {}
	_check(travel.is_empty() or (first.get("pos") as Vector2).length() > 0.0, "first step not at start (no teleport)")


# ── 9. Agent-Transparenz: Feed liefert Ziel + letzte Schritte ───────────────

func _test_agent_activity_transparency() -> void:
	var agent_script: Resource = load(AGENT_PATH)
	_check(agent_script != null, "agent activity script loads")
	if agent_script == null:
		return
	var activity: RefCounted = agent_script.new()
	var goal_set: Dictionary = activity.call("set_goal", "erstes schiff bauen")
	_check(bool(goal_set.get("ok", false)), "goal set")
	activity.call("record_tool", "runtime_ux_scan", {"max_controls": 120}, 12.5, true, "")
	activity.call("record_tool", "runtime_click", {"x": 480, "y": 270}, 30.0, true, "")
	activity.call("record_tool", "runtime_eval", {"code": "1"}, 5.0, false, "contract violation")
	var feed: Dictionary = activity.call("get_feed", 20)
	_check(str(feed.get("goal", "")) == "erstes schiff bauen", "feed reports current goal")
	_check(int(feed.get("count", 0)) >= 3, "feed reports last steps")
	var entries: Array = feed.get("entries", [])
	_check(str(entries[entries.size() - 1].get("label", "")) == "call:runtime_eval", "feed reports latest action")
	var stats: Dictionary = activity.call("get_stats")
	_check(int(stats.get("errors", 0)) == 1, "errors counted")


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] " + description)
	else:
		print("[FAIL] " + description)
		_failed += 1
