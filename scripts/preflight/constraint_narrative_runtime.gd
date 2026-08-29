class_name PreflightConstraintNarrativeRuntime
extends RefCounted

## Narrative Runtime Gate als Preflight-Constraint (NARRATIVE_ENGINE_DESIGN G19:
## fail-closed, Bestandteil des Preflight). Ruft die Python-Runtime (stdlib-only)
## im Verify-Modus auf — read-only, temporäre Archive — und prüft Exit-Code +
## alle G-Checks auf PASS.
##
## Das ist der einzige Berührungspunkt zwischen Godot-Seite und Runtime
## (Narrative Adapter): Der Gameplay-Core hat keine direkte Abhängigkeit zur
## Runtime; die Schnittstelle ist datenorientiert (CLI → JSON).

func constraint_name() -> String:
	return "narrative_runtime"

func constraint_description() -> String:
	return "Narrative Runtime Gate: stdlib-only, Purity, Event-IDs, Chain-Gaps, Rebuild==Incremental, Relationship/Belief/Thread/Public-State/Spotlight contracts"

func requires_scene() -> bool:
	return false

func run(ctx: PreflightContext) -> bool:
	var root := ProjectSettings.globalize_path("res://")
	var output: Array = []
	var exit_code: int = OS.execute("python", ["-m", "narrative_runtime.gate_cli", "--root", root], output, true)
	var raw := ""
	if not output.is_empty():
		raw = String(output[0]).strip_edges()
	if exit_code != OK:
		return ctx.check(false,
			"Narrative Runtime Gate: python exited %d — Runtime nicht konform oder Python fehlt (fail-closed)" % exit_code,
			{"output": raw.left(400)})
	var parsed := {}
	if raw.begins_with("{"):
		parsed = JSON.parse_string(raw) as Dictionary
	var all_pass := true
	var failed_gates: Array[String] = []
	if parsed.is_empty():
		all_pass = false
		failed_gates.append("no-json")
	else:
		for gate_name in parsed:
			if String(parsed[gate_name]) != "PASS":
				all_pass = false
				failed_gates.append(String(gate_name))
	return ctx.check(all_pass,
		"Narrative Runtime Gate: %d checks — %s" % [parsed.size(), "all PASS" if all_pass else "FAIL: %s" % ", ".join(failed_gates)],
		{"gates": parsed})