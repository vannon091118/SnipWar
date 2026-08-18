# SnipWar Agent Notes

## Godot checks
- Godot is not on PATH; use `C:/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe`.
- `--headless --path . --quit-after 2` exercises the real main scene; temporary lifecycle checks run with `--headless --path . --script res://.tmp_*.gd` and must be removed afterward.

## Architecture constraints
- `Background` is z=-100 and `PlanetField` uses relative z=20; lowering the field below the background makes the background draw over the planets.
- The runtime Bootstrap replaces the editor fallback seed 241119 on F5; the seed is configured on `PlanetField`, not the `Background` root.
- `seeded_layout.gd` must only lay out children exposing `layout_size`; the Toxic orbit child is intentionally not a planet slot.
- Planet size belongs to the Node2D layout scale; keep `planet.gd`'s `visual_scale` at 1.0 to avoid double scaling.
- The current minimal meteor design uses four direct Sprite2D children controlled by `meteor_field.gd`; no per-meteor scene/script is required.
- ToxicOrbit resolves the `planet_toxic` group; avoid restoring a relative NodePath target.
- Workers are intentionally stationary after spawning; planets own the spawn state/timer and `worker_count`, while `WorkerManager` only instantiates/registers them and preserves the selected destination for later movement.
- Spawn tiers are part of the MVP contract: XL = 3 workers/5 s, L = 2/7 s, variable planets = 1/10 s.

## Interaction and assets
- Planet clicks require the planet `Area2D`/shape; worker graphics remain collision-free. The persistent destination tab UI must be created with `call_deferred()` because adding viewport UI during child setup triggers Godot's "parent node is busy setting up children" error.
- Worker visuals use the same pixel contract as meteors: `worker.gd` derives its Sprite2D scale from the SVG width for a 10 px target; do not replace it with a relative scale.

## Godot pitfalls
- Godot 4.7 `@export_enum` requires String/Integer-compatible variables, not `StringName`.
- Meteor respawn must disable processing before emitting the exit signal; the callback immediately respawns and re-enables the meteor.
- Meteor sizes are pixel-based: `meteor_field.gd` converts 4-10 px targets using each SVG texture width; keep this visible-size contract instead of restoring relative 0.004-0.01 scales.

## Repository
- This project has its own nested Git repository; operate from the project root rather than the enclosing user-home repository.
- Local commit author identity may be absent; use per-command `GIT_AUTHOR_*`/`GIT_COMMITTER_*` environment variables instead of changing Git config.

## Git hooks
- Local `core.hooksPath` is `.githooks`: `pre-commit` runs `res://scripts/preflight.gd`, `commit-msg` requires one reason sentence per staged file, and `post-commit` pushes the current branch to `origin`.
