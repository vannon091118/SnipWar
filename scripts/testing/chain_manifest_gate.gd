extends SceneTree
## Mechanical chain-manifest gate: validates EVERY MCP chain manifest against
## the actual tool registry and the chain controller's contracts — hard gate,
## exit code 1 on ANY violation, 0 only when every manifest is clean.
##
## Enforced contracts (fail-closed, no exceptions):
##   1. Step tool names must exist (registry tools ∪ host tools ∪ preflight_constraint)
##   2. host tools are DERIVED from mcp_server.gd source (no drift possible)
##   3. expect.op must be one of the ops _expect_check() implements
##   4. SKIP FLAGS ARE FORBIDDEN: no "skip"/"skipped"/"ignore", no enabled=false,
##      no disabled=true on any step (kein Spielraum, kein Fake-Testing)
##   5. mode must be a controller-supported mode (auto|headless|visible)
##   6. Duplicate step names are rejected (trace ambiguity)
##  7. EVERY non-wait step MUST assert: assertion or expect (KEINE weichen
##     Gates — fehlende Postcondition ist ein HARD FAIL, kein Warning)
##
## Reads nothing but manifests; writes nothing.
##
## Usage:
##   "$GODOT_BIN" --headless --path . --script res://scripts/testing/chain_manifest_gate.gd

const CHAIN_DIR := "res://addons/mcp/mcp_chains"
const SERVER_PATH := "res://addons/mcp/runtime/host/mcp_server.gd"
const REGISTRY_PATH := "res://addons/mcp/runtime/core/mcp_tool_registry.gd"

const EXPECT_OPS := ["==", "!=", ">=", "<=", ">", "<", "contains", "has_key"]
const SUPPORTED_MODES := ["auto", "headless", "visible"]
const WAIT_TOOLS := ["runtime_wait_ms", "runtime_wait_frames"]
const COMPOSITE_TOOLS := ["runtime_ux_click", "runtime_goal_play", "runtime_goal_sequence", "runtime_chain_run"]
const VISIBLE_MODE_TOOLS := ["runtime_goal_check", "runtime_goal_history"]
const CONTROLLER_SPECIAL := ["preflight_constraint"]
const REQUIRED_HOST_TOOLS := ["runtime_mcp_status", "runtime_mcp_events", "runtime_agent_activity", "runtime_run_trace", "editor_logs_read"]

const EVIDENCE_PATH := "user://mcp_evidence/chain_manifest_gate.json"
# PID-keyed Tmp-Pfad: parallele Läufe kollidieren nicht auf derselben Tmp-Datei.
var EVIDENCE_TMP := ""

var _failures: Array[String] = []

func _init() -> void:
	EVIDENCE_TMP = "user://mcp_evidence/chain_manifest_gate.%d.tmp" % OS.get_process_id()
	var registry_script := load(REGISTRY_PATH) as Script
	if registry_script == null:
		_failures.append("Cannot load McpToolRegistry — gate cannot verify tool names")
		_finish()
		return
	var registry: RefCounted = registry_script.new()
	if not registry.has_method("get_all_tools"):
		_failures.append("McpToolRegistry has no get_all_tools() — gate contract broken")
		_finish()
		return

	var known: Dictionary = {}
	for def in registry.get_all_tools():
		if def is Dictionary and def.has("name"):
			known[str(def.get("name", ""))] = true

	var host_tools := _derive_host_tools()
	for tool in host_tools:
		known[tool] = true
	for tool in CONTROLLER_SPECIAL:
		known[tool] = true

	print("CHAIN_GATE: ", known.size(), " known tools (registry + ", host_tools.size(), " host + special)")
	var missing_host: Array = []
	for expected in REQUIRED_HOST_TOOLS:
		if not host_tools.has(expected):
			missing_host.append(expected)
	if not missing_host.is_empty():
		_failures.append("Host dispatch does NOT cover: " + ", ".join(PackedStringArray(missing_host)))

	_scan_directory(CHAIN_DIR, known)
	_finish()

func _derive_host_tools() -> Array:
	var host_tools: Array = []
	var server := FileAccess.get_file_as_string(SERVER_PATH)
	if server == "":
		_failures.append("Cannot read mcp_server.gd — host tools cannot be derived")
		return host_tools
	var regex := RegEx.new()
	# Exakt die Verzweigungen in _dispatch_host_tool_for_chain: tool_name == "x"
	regex.compile('tool_name\\s*==\\s*[&\\\']?"?([a-z][a-z0-9_]+)"?')
	for m in regex.search_all(server):
		var name := m.get_string(1)
		if name not in host_tools:
			host_tools.append(name)
	return host_tools

func _scan_directory(dir_path: String, known: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_failures.append("Cannot open chain dir: " + dir_path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir() and entry.ends_with(".json"):
			_validate_manifest(dir_path.path_join(entry), known)
		entry = dir.get_next()
	dir.list_dir_end()

func _validate_manifest(path: String, known: Dictionary) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		_failures.append(path + "  (unreadable or empty manifest)")
		return
	var parsed = JSON.parse_string(text)
	if parsed == null:
		_failures.append(path + "  (invalid JSON)")
		return
	var manifest: Dictionary = parsed
	var manifest_id := str(manifest.get("id", "?"))
	if manifest_id != path.get_file().get_basename():
		_failures.append("%s  id=%s does not match file name %s" % [path, manifest_id, path.get_file()])
	var mode := str(manifest.get("mode", "auto"))
	if mode not in SUPPORTED_MODES:
		_failures.append("%s  mode=%s not in %s" % [path, mode, str(SUPPORTED_MODES)])

	var steps: Array = manifest.get("steps", [])
	if steps.is_empty():
		_failures.append(path + "  has no steps (empty chain is meaningless)")
		return

	var seen_names: Dictionary = {}
	for index in steps.size():
		var step: Dictionary = steps[index]
		var label := "%s step %d (%s)" % [path, index + 1, step.get("name", "?")]
		_check_skip_flags(step, label)

		# 1. Tool existiert
		var tool_name := str(step.get("tool", ""))
		if tool_name == "":
			_failures.append(label + "  missing 'tool'")
		elif not known.has(tool_name):
			_failures.append(label + "  UNKNOWN TOOL '" + tool_name + "' — nicht in Registry, nicht Host, nicht Controller-Special")

		# 8. Composite-Tools verboten (ein atomarer Tool-Call pro Step)
		if tool_name in COMPOSITE_TOOLS:
			_failures.append(label + "  COMPOSITE TOOL '" + tool_name + "' verboten — ein atomarer Tool-Call pro Step")

		# 9. Screenshot braucht immer einen Reason
		if tool_name == "runtime_screenshot" and str(step.get("reason", "")).strip_edges() == "":
			_failures.append(label + "  screenshot requires a reason; capture only on ambiguity")

		# 10. Visible-Mode: keine GameState-/History-Tools
		if mode == "visible" and (tool_name.begins_with("game_") or tool_name in VISIBLE_MODE_TOOLS):
			_failures.append(label + "  uses non-player/game-state tool '" + tool_name + "' in visible mode")

		# 11. runtime_ux_find: bounded context (kein /root-Broadcast)
		if tool_name == "runtime_ux_find" and str(step.get("args", {}).get("root_path", "/root")) == "/root":
			_failures.append(label + "  uses broad UI scope; prefer the current panel root_path (bounded context required)")

		# 6. Doppelte Step-Namen
		var step_name := str(step.get("name", ""))
		if step_name != "":
			if seen_names.has(step_name):
				_failures.append(label + "  duplicate step name '" + step_name + "' (Trace-Mehrdeutigkeit)")
			seen_names[step_name] = true

		# 3. expect.op erlaubt
		if step.has("expect"):
			var expect: Variant = step.get("expect")
			if expect is Dictionary:
				var op := str((expect as Dictionary).get("op", "=="))
				if op not in EXPECT_OPS:
					_failures.append(label + "  expect.op '" + op + "' not in " + str(EXPECT_OPS))
			else:
				_failures.append(label + "  expect must be an object {key, op, value}")

		# 7. HART: Jeder Nicht-Wait-Step MUSS eine Postcondition haben (keine
		#    weichen Gates — fehlende Assertion/Expect = FAIL, kein Spielraum)
		var has_assertion := step.has("assertion") and str(step.get("assertion", "")).strip_edges() != ""
		var has_expect := step.has("expect")
		if tool_name not in WAIT_TOOLS and not has_assertion and not has_expect:
			_failures.append(label + "  NO POSTCONDITION: non-wait steps MUST assert (assertion oder expect) — kein blindes Tool-Feuer")

	# 12. Visible-Ketten >20 Steps: Splitting-Contract (nach der Schleife, einmal)
	if mode == "visible" and steps.size() > 20:
		_failures.append(path + "  long visible chain (" + str(steps.size()) + " steps); split at panel transitions to preserve player-like decisions")

func _check_skip_flags(step: Dictionary, label: String) -> void:
	for key in ["skip", "skipped", "ignore"]:
		if step.has(key):
			var value: Variant = step.get(key)
			var blocked := _is_truthy(value)
			if blocked:
				_failures.append(label + "  SKIP-FLAG FORBIDDEN: '" + key + "' würde den Step überspringen (kein Spielraum, kein Fake-Testing)")
	if step.has("enabled"):
		var value: Variant = step.get("enabled")
		var disabled := false
		if typeof(value) == TYPE_BOOL:
			disabled = not value
		elif typeof(value) == TYPE_STRING:
			disabled = String(value).to_lower() in ["false", "0", "no", "off"]
		if disabled:
			_failures.append(label + "  SKIP-FLAG FORBIDDEN: enabled=false würde den Step überspringen (kein Spielraum, kein Fake-Testing)")
	if step.has("disabled"):
		var value: Variant = step.get("disabled")
		if _is_truthy(value):
			_failures.append(label + "  SKIP-FLAG FORBIDDEN: disabled=true würde den Step überspringen (kein Spielraum, kein Fake-Testing)")

func _is_truthy(value: Variant) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_STRING:
			return String(value).to_lower() in ["true", "yes", "1", "on"]
		TYPE_INT:
			return value != 0
	return value != null

func _finish() -> void:
	var passed := _failures.is_empty()
	_write_evidence({
		"gate": "chain_manifest_gate",
		"result": "PASS" if passed else "FAIL",
		"violations": _failures,
	})
	if not passed:
		print("CHAIN_GATE: FAIL — ", _failures.size(), " violations:")
		for failure in _failures:
			print("  ✗ ", failure)
		print("EVIDENCE: ", ProjectSettings.globalize_path(EVIDENCE_PATH))
		print("CHAIN_GATE: exit=1")
		quit(1)
	else:
		print("CHAIN_GATE: PASS — all manifests contract-clean, 0 warnings")
		print("EVIDENCE: ", ProjectSettings.globalize_path(EVIDENCE_PATH))
		print("CHAIN_GATE: exit=0")
		quit(0)

func _write_evidence(data: Dictionary) -> void:
	var dir := DirAccess.open("user://")
	if dir == null or not dir.dir_exists("mcp_evidence"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://mcp_evidence"))
	var file := FileAccess.open(EVIDENCE_TMP, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write evidence (chain_manifest_gate): " + EVIDENCE_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(EVIDENCE_TMP), ProjectSettings.globalize_path(EVIDENCE_PATH))
	_cleanup_stale_tmps()


func _cleanup_stale_tmps() -> void:
	var d := DirAccess.open("user://mcp_evidence")
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while not entry.is_empty():
		if entry.begins_with("chain_manifest_gate.") and entry.ends_with(".tmp"):
			if entry != "chain_manifest_gate.%d.tmp" % OS.get_process_id():
				d.remove(entry)
		entry = d.get_next()
	d.list_dir_end()