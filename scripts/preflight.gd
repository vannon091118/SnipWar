extends SceneTree

## Persistent SnipWar test suite (no GUT). This file is only the orchestrator:
## it boots a shared PreflightContext and runs each per-domain constraint module in
## order. Constraint order matters — modules share one GameState autoload with no
## reset between them (see AGENTS.md). Individual checks live in scripts/preflight/.

const _Context := preload("res://scripts/preflight/preflight_context.gd")

const _ConstraintScripts: Array = [
	preload("res://scripts/preflight/constraint_generation_pipeline.gd"),
	preload("res://scripts/preflight/constraint_effects_and_traits.gd"),
	preload("res://scripts/preflight/constraint_flight_and_dispatch.gd"),
	preload("res://scripts/preflight/constraint_world_generator_scaling.gd"),
	preload("res://scripts/preflight/constraint_scene_boot.gd"),
	preload("res://scripts/preflight/constraint_resources_and_seed.gd"),
	preload("res://scripts/preflight/constraint_world_planets_and_dispatch.gd"),
	preload("res://scripts/preflight/constraint_world_details_and_scale.gd"),
	preload("res://scripts/preflight/constraint_upgrades_missions_and_ai.gd"),
	preload("res://scripts/preflight/constraint_scout_and_discovery.gd"),
	preload("res://scripts/preflight/constraint_ship_builder.gd"),
	preload("res://scripts/preflight/constraint_event_log.gd"),
	preload("res://scripts/preflight/constraint_camera_and_input.gd"),
	preload("res://scripts/preflight/constraint_pause_and_context.gd"),
	preload("res://scripts/preflight/constraint_layers_2_and_3.gd"),
	preload("res://scripts/preflight/constraint_ingame_player_and_transitions.gd"),
]


func _init() -> void:
	var ctx: PreflightContext = _Context.new(self)
	var ran := 0
	for constraint_script in _ConstraintScripts:
		var constraint: RefCounted = constraint_script.new()
		ctx.active_constraint = constraint.constraint_name()
		print("[preflight] " + ctx.active_constraint)
		var ok: bool = await constraint.run(ctx)
		ran += 1
		if not ok:
			return
	print("PASS: SnipWar preflight (%d constraints)" % ran)
	quit()
