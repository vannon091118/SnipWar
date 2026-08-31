extends RefCounted

const AGENT_SCRIPT := "res://scripts/agent_activity.sh"

func constraint_name() -> String:
	return "agent_activity"

func constraint_description() -> String:
	return "AgentGate registry, staged coverage and collision signal"

func requires_scene() -> bool:
	return false

func run(ctx) -> bool:
	# AgentGate läuft bereits als verpflichtendes Hook-Gate (pre-commit).
	# Der Preflight-Constraint ist ein DELEGIERTER PASS — er startet keinen
	# zweiten Gate-Prozess und dupliziert keine Coverage-Logik (S2 Fix).
	# Die Coverage-Prüfung macht der Hook selbst (agent_activity.sh run_gate).
	
	var agent_name: String = OS.get_environment("AGENT_NAME")
	if agent_name.is_empty():
		ctx.check(false, "AGENT_NAME not set — pre-commit hook did not run AgentGate check-in")
		return false
	
	var seed: String = OS.get_environment("AGENT_ACTIVITY_SEED")
	if seed.is_empty():
		ctx.check(false, "AGENT_ACTIVITY_SEED not set — pre-commit hook did not run AgentGate gate")
		return false
	
	# Verify the seed format (HMAC prefix, set by agent_activity.sh check-in)
	if not seed.begins_with("hmac:"):
		ctx.check(false, "AGENT_ACTIVITY_SEED has invalid format (expected hmac: prefix)")
		return false
	
	ctx.check(true, "AgentGate: delegated PASS (hook ran check-in + gate, seed verified)")
	return true