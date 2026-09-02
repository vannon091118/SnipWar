extends RefCounted
class_name McpContractGate

## McpContractGate — Session-Profile-Gate für den verbindlichen Spieler-Vertrag
## (siehe addons/gdscript_mcp/PLAYTEST_HANDOFF.md).
##
## Profile:
##   player  (Standard für Runtime-Sessions) — der Agent sieht und steuert das
##           Spiel wie ein Spieler: ein Atom pro Tool-Call, UI-basierte Aktionen,
##           read-only Beobachtung. Orchestrierungs- und Abkürzungs-Tools sind
##           gesperrt (Goal Player, Chains, Eval, Find+Klick, Freeze/Step,
##           GameState-Restore, E2E-Szenarien, Autonomy-Writes).
##   qa      — QA/Debug-Modus: Goal Player, Chains, Find+Klick, Freeze/Step und
##           E2E-Szenarien freigeschaltet. Eval bleibt an den Developer-Flag
##           gebunden, Autonomy-Writes an --mcp-autonomy-writes.
##   dev     — Alles aus qa plus direkte GameState-/Code-Zugriffe unter den
##           bestehenden Flags (--mcp-developer, --mcp-autonomy-writes).
##
## Headless ist für MCP-Sessions grundsätzlich verboten (kein Renderer, keine
## Screenshots, kein sichtbares Gameplay) — das wird bereits beim Serverstart
## erzwungen (mcp_server.gd) und hier nur als Konstante dokumentiert.

const PROFILE_PLAYER := "player"
const PROFILE_QA := "qa"
const PROFILE_DEV := "dev"
const PROFILES := [PROFILE_PLAYER, PROFILE_QA, PROFILE_DEV]

## Tools, die ein sichtbarer Spieler-Lauf nie verwenden darf:
## - Goal-/Chain-Orchestrierung wäre ein „Spielerersatz" (mehrere Aktionen geplant)
## - runtime_eval ist ein direkter Code-Call („Forschung per Funktionscall")
## - runtime_ux_click verbirgt Find + Klick in einem Tool
## - Freeze/Step sind Debug-Modi, kein Spieler-Erlebnis
## - game_state_restore mutiert GameState direkt
## - runtime_e2e_run führt vorgeplante Szenarien aus
## - Autonomy-Write-Tools sind Edit-Werkzeuge
const PLAYER_BLOCKED_TOOLS := [
	"runtime_goal_play",
	"runtime_goal_sequence",
	"runtime_goal_check",
	"runtime_goal_history",
	"runtime_chain_run",
	"runtime_eval",
	"runtime_ux_click",
	"runtime_freeze",
	"runtime_unfreeze",
	"runtime_step_frame",
	"runtime_step_frames",
	"game_state_restore",
	"runtime_e2e_run",
	"runtime_autonomy_workspace_begin",
	"runtime_autonomy_write",
	"runtime_autonomy_patch",
	"runtime_autonomy_rollback",
	"runtime_autonomy_rollback_all",
	"runtime_autonomy_workspace_import",
	"runtime_autonomy_export",
	"runtime_playthrough_preset_load",
	"runtime_playthrough_compare",
]

var _profile := PROFILE_PLAYER
var _role := "runtime"
var _blocked_calls := 0


func configure(profile: String, role: String = "runtime") -> void:
	_role = role if role != "" else "runtime"
	var requested := str(profile).strip_edges().to_lower()
	# Editor-Sessions sind von Natur aus Editier-Sessions; Runtime-Sessions sind
	# standardmäßig Spieler-Sessions. Ein explizites Profil schlägt beide.
	if requested in PROFILES:
		_profile = requested
	elif _role == "editor":
		_profile = PROFILE_DEV
	else:
		_profile = PROFILE_PLAYER
	_blocked_calls = 0


func get_profile() -> String:
	return _profile


func get_blocked_calls() -> int:
	return _blocked_calls


## Prüft, ob ein Tool-Call im aktuellen Profil erlaubt ist.
## Liefert {allowed: bool, profile: String, reason: String}.
func check(tool_name: String) -> Dictionary:
	if _profile == PROFILE_PLAYER and tool_name in PLAYER_BLOCKED_TOOLS:
		_blocked_calls += 1
		return {
			"allowed": false,
			"profile": _profile,
			"tool": tool_name,
			"code": "CONTRACT_VIOLATION",
			"reason": "Tool %s ist im Spieler-Profil gesperrt (verbindlicher Spieler-Vertrag). QA-/Debug-Modus: --mcp-profile=qa oder dev." % tool_name,
		}
	return {"allowed": true, "profile": _profile, "tool": tool_name}


## Headless ist absolut gegen den MCP-Vertrag: kein sichtbares Gameplay, keine
## Screenshots, kein OCR. Serverstart verweigert das bereits; diese statische
## Prüfung dient Tests und mcp_runtime.gd.
static func validate_renderer(headless: bool) -> Dictionary:
	if headless:
		return {
			"ok": false,
			"code": "CONTRACT_VIOLATION",
			"reason": "MCP erfordert einen sichtbaren Renderer; --headless ist gegen den MCP-Vertrag",
		}
	return {"ok": true}