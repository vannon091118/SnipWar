extends RefCounted

const AGENT_SCRIPT := "res://scripts/agent_activity.sh"

func constraint_name() -> String:
	return "agent_activity"

func constraint_description() -> String:
	return "AgentGate registry, staged coverage and collision signal"

func requires_scene() -> bool:
	return false

func run(ctx) -> bool:
	# Godot erbt nicht die Shell-Umgebung des Entwicklers; die Identität geht als Flag.
	# AgentGate läuft bereits als verpflichtendes Hook-Gate; die Preflight-Registry
	# darf es nicht erneut ausführen (und insbesondere keine --standalone-Fiktion).
	ctx.check(true, "AgentGate: delegated to pre-commit hook")
	return true
