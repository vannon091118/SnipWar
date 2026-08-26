#!/usr/bin/env bash
# Portable MCP Addon Smoke-Test
# ---------------------------------
# Beweist auf einem MINIMALEN Fremdprojekt (ohne SnipWar), dass das Addon:
#   A) sich beim Plugin-Aktivieren automatisch registriert (Autoloads McpRuntime
#      + McpProjectAdapter und application/mcp/*-Settings) — geprüft über einen
#      Headless-Editor-Boot (Editor-Tooling, kein Live-Gameplay).
#   B) im sichtbaren Runtime einen echten `runtime_ux_scan` + `runtime_click`
#      liefert — über den sichtbaren McpTestRunner (sichtbarer Renderer, nie
#      headless; liefert echte [PASS]/[FAIL]-Zeilen).
#
# Usage:
#   bash addons/gdscript_mcp/testing/portable/run_portable_smoke.sh \
#        "/c/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe"
# Env: MCP_SMOKE_VERBOSE=1 für mehr Ausgabe, MCP_SMOKE_KEEP=1 zum Temp-Ordner behalten.

set -uo pipefail

GODOT_BIN="${1:-}"
if [[ -z "$GODOT_BIN" ]]; then
  echo "Usage: $0 <path-to-godot-bin>  (z. B. /c/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe)"
  exit 2
fi
if [[ ! -f "$GODOT_BIN" ]]; then
  echo "ERROR: Godot binary not found: $GODOT_BIN"
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_DIR="$SCRIPT_DIR/../.."                 # addons/gdscript_mcp
TPL_DIR="$SCRIPT_DIR/templates"

if [[ -n "${MCP_SMOKE_KEEP:-}" ]]; then
  FIXTURE="${MCP_SMOKE_DIR:-/tmp/gdscript_mcp_smoke_portable}"
  rm -rf "$FIXTURE"
else
  FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/gdscript_mcp_smoke.XXXXXX")"
fi
mkdir -p "$FIXTURE/addons"
cp -r "$ADDON_DIR" "$FIXTURE/addons/gdscript_mcp"
cp "$TPL_DIR/project.godot" "$FIXTURE/project.godot"
cp "$TPL_DIR/bootstrap_button.tscn" "$FIXTURE/bootstrap_button.tscn"

# Portables Szenario für den sichtbaren Runner (liegt im Addon-Kopier-Ordner).
cat > "$FIXTURE/addons/gdscript_mcp/testing/scenarios/portable_smoke.tres" <<'ENDOFTRES'
[gd_resource type="Resource" load_steps=2 format=3]

[ext_resource type="Script" path="res://addons/gdscript_mcp/testing/mcp_test_scenario.gd" id="1_scenario"]

[resource]
script = ExtResource("1_scenario")
id = "portable_smoke"
description = "Portable Smoke: foreign project, scan + click on a plain Control/Button (no SnipWar)."
scene_path = "res://bootstrap_button.tscn"
wait_frames = 30
requires_renderer = true
enabled_by_default = true
# runtime_ux_scan liefert {scene, interactables, controls, count}. Unter --script
# ist current_scene null → scene="unknown"; entscheidend sind interactables/count.
steps = Array[Dictionary]([{
"tool": "runtime_ux_scan",
"args": {"root_path": "/root", "max_depth": 3, "max_controls": 80},
"expect_key": "count",
"expect_op": ">=",
"expect_value": 1
}, {
"tool": "runtime_ux_find",
"args": {"description": "TESTPORTABLE"},
"expect_key": "found",
"expect_op": "==",
"expect_value": true
}, {
"tool": "runtime_click",
"args": {"path": "PortableRoot/TestButton", "x": -1, "y": -1},
"expect_key": "clicked",
"expect_op": "==",
"expect_value": true
}])
ENDOFTRES

fail=0

echo ""
echo "================= PHASE A — Plugin-Selbst-Registrierung (Headless-Editor) ================="
echo "Fixture: $FIXTURE"
"$GODOT_BIN" --headless --path "$FIXTURE" --editor --quit >/dev/null 2>&1
if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then
  echo "[A-FAIL] Headless-Editor-Boot des Fremdprojekts beendete mit Fehler."
  fail=1
else
  echo "[A-OK]   Editor-Boot OK. Prüfe registrierte Autoloads + Settings …"
  # project.godot speichert Autoloads mit Anführungszeichen: McpRuntime="*res://..."
  for key in "McpRuntime=\"*res://addons/gdscript_mcp/runtime/host/mcp_runtime.gd\"" \
             "McpProjectAdapter=\"*res://addons/gdscript_mcp/runtime/core/mcp_project_adapter.gd\""; do
    if grep -qF "$key" "$FIXTURE/project.godot"; then
      echo "  [A-OK] autoload: $key"
    else
      echo "  [A-FAIL] Autoload fehlt: $key"
      fail=1
    fi
  done
  for skey in "mcp/preflight_script=" "mcp/main_menu_scene=" "mcp/game_state_node=" \
              "mcp/event_log_node=" "mcp/project_adapter_node=" "mcp/game_state_script="; do
    if grep -qF "$skey" "$FIXTURE/project.godot"; then
      echo "  [A-OK] setting: application/$skey"
    else
      echo "  [A-FAIL] Setting fehlt: application/$skey"
      fail=1
    fi
  done
fi

echo ""
echo "================= PHASE B — Sichtbarer runtime_ux_scan/click (echter Renderer) ================="
# Sichtbarer Runner: verbietet Headless selbst (quit(2)). Öffnet ein echtes Fenster.
PHASE_B_OUT="$FIXTURE/phase_b_output.txt"
"$GODOT_BIN" --path "$FIXTURE" --script "res://addons/gdscript_mcp/testing/mcp_test_runner.gd" \
  --mcp-test-filter=portable_smoke --mcp-test-verbose >"$PHASE_B_OUT" 2>&1
if grep -q "\[PASS\] portable_smoke" "$PHASE_B_OUT"; then
  echo "[B-OK]   Sichtbarer portable_smoke-Run: PASS"
else
  echo "[B-FAIL] Kein PASS für portable_smoke. Ausgabe (Tail):"
  tail -n 40 "$PHASE_B_OUT"
  fail=1
fi

echo ""
if [[ $fail -eq 0 ]]; then
  echo "RESULT: PASSED (portable non-SnipWar smoke — Registration + scan/click)"
else
  echo "RESULT: FAILED"
fi

if [[ -z "${MCP_SMOKE_KEEP:-}" ]]; then
  rm -rf "$FIXTURE"
else
  echo "Temp-Fixture bleibt: $FIXTURE"
fi

exit $fail