# SnipWar Agent Notes

## Godot checks
- Godot is not on PATH; use `C:/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe`.
- `--headless --path . --quit-after 2` exercises the real main scene; temporary lifecycle checks run with `--headless --path . --script res://.tmp_*.gd` and must be removed afterward.
- No GUT framework; `scripts/preflight.gd` is the persistent headless test suite (`--headless --path . --script res://scripts/preflight.gd`).
- The seed-variation check changes `PlanetField.layout_seed`, waits two frames for deferred regeneration, compares positions, then restores the original seed before the remaining assertions.

## Architecture constraints
- `Background` is z=-100 and `PlanetField` uses relative z=20; lowering the field below the background makes the background draw over the planets.
- The runtime Bootstrap replaces the editor fallback seed 241119 on F5; the seed is configured on `PlanetField`, not the `Background` root.
- Runtime re-layout assigns `Planet.layout_size` after the initial scene setup; its setter must restart an existing spawn timer so generated size and spawn cadence remain synchronized.
- `seeded_layout.gd` must only lay out `Planet` children; the Toxic orbit child is intentionally not a planet slot.
- Seed variation must shuffle slot assignment as well as size/detail identity; fixed XL corners or a fixed L crossing make different seeds look nearly identical.
- `PlanetDetails` is a child module inside `planet.tscn`; its final seed arrives from `seeded_layout.gd` after child `_ready()`, so it must not finalize its detail set during `_ready()` alone.
- The detail cap counts logical types via `get_detail_types()`; an `asteroid_belt` is one detail even though it creates five orbit nodes. Toxic's belt must not be reintroduced as a separate field-level orbit.
- Planet size belongs to the Node2D layout scale; keep `planet.gd`'s `visual_scale` at 1.0 to avoid double scaling.
- The current minimal meteor design uses four direct Sprite2D children controlled by `meteor_field.gd`; no per-meteor scene/script is required.
- `planet_details.gd` owns seeded extras; Toxic always showcases a satellite plus an asteroid belt, with an optional third ring, while other planets get up to three deterministic detail types.
- `WorkerCluster` nodes are the garrison and transit representation; `WorkerManager._dispatch_clusters` packs K=1/M=5/L=100 groups and launches every selected cluster in the same frame. Partial sends split garrison clusters and refresh their tier asset; arrivals re-register the logical unit count with the destination.
- Dispatched clusters start at perpendicular fleet offsets so same-tier groups fly side-by-side instead of stacking on top of each other; preflight asserts separation in (0, 30 px) and shift under 15 px from the source planet.
- Spawn tiers are part of the MVP contract: XL = 3 workers/5 s, L = 2/7 s, variable planets = 1/10 s.
- `flight_time.gd`, `dispatch.gd`, `planet_network.gd`, `planet_network_ui.gd`, `worker_cluster.gd`, `worker_cluster.tscn`, `worker_manager.gd`, and `preflight.gd` change/commit together; preflight uses PlanetNetworkUI getters and cluster internals (`_registered_planet`, `_arrive`).
- `planet.tscn`, `planet.gd`, `planet_details.gd`, `planet_detail_orbit.gd`, `planet_detail_ring.gd`, `seeded_layout.gd`, and the planet SVG/import assets change together for seeded details.
- `PlanetNetwork` resolves destinations and passes them to `WorkerManager`; keep the manager independent of the network lookup. `planet_network.gd` owns routing/lines, while `planet_network_ui.gd` owns the CanvasLayer controls and emits UI signals.
- Do not keep unused `WorkerState` values as placeholders; add a state only when its transition behavior exists.
- Flight duration uses logical-unit load plus packed-cluster count, so real dispatches remain long; headless tests call `cluster._arrive()` directly and assert movement via "distance to destination decreased", never by awaiting flight end or exact positions.

## Interaction and assets
- Planet clicks require the planet `Area2D`/shape; cluster graphics remain collision-free. The persistent destination tab UI must be created with `call_deferred()` because adding viewport UI during child setup triggers Godot's "parent node is busy setting up children" error.
- Cluster visuals use fixed K/M/L generic SVG assets and expose an `Attachments` node for future cannons, drones, or upgrades; do not restore per-unit transit sprites.
- Dispatched groups fly as a side-by-side fleet rather than a stacked column; the perpendicular offset is computed from the route direction so multiple same-tier clusters stay visible during transit.
- New SVG planet/detail assets cause Godot to generate tracked `.svg.import` files during the headless scan; commit the import sidecars with their source SVGs.

## Godot pitfalls
- Godot 4.7 `@export_enum` requires String/Integer-compatible variables, not `StringName`.
- Meteor respawn must disable processing before emitting the exit signal; the callback immediately respawns and re-enables the meteor.
- Meteor sizes are pixel-based: `meteor_field.gd` converts 4-10 px targets using each SVG texture width; keep this visible-size contract instead of restoring relative 0.004-0.01 scales.
- `SceneTree.quit()` does not halt the current function; test scripts must `return` after `quit()` or the success path falls through to the failure branch.
- GDScript `:=` errors with "value doesn't have a set type" on members of `Node`-typed children; use explicit types and casts like `(ocean as Node2D).global_position`.
- Headless `--script` runs hang (timeout) when `_init` errors or returns before `quit()`; only fail via `_check`→`quit(1)` and always end with `quit()`.
- Keep `--quit-after 2` for the main-scene smoke test only; using it on `preflight.gd` can terminate before its `PASS` result and hide the real failure.
- The Compatibility renderer may emit `Debug CanvasItem Redraw is not available yet` during startup; treat it as an engine/debug warning unless preflight or the smoke test fails.
- GDScript 4 warns `INTEGER_DIVISION` on `int / int`; use `int(a / 2.0)` when a float quotient is intended.
- Connect a Tween's `finished` to a method not on the statically-typed base class with `Callable(node, "_method")`; `node._method` is an unsafe member access.

## Documentation and presentation
- README product copy should use original wording, distinguish the 4K presentation target from the current prototype, and state unfinished gameplay explicitly.
- GitHub slugs for decorated/non-ASCII headings are unreliable; use explicit `<a id="...">` anchors for README badge links.

## Design direction (SnipWar concept)
- SnipWar is a hybrid built in vertical slices: strategic galaxy map now, tactical battle view as a later layer.
- Unit dispatch: slider 1..available → live flight-time/route preview (more logical units/clusters = slower) → pack into K/M/L cluster assets → launch all groups together; source counter drops at launch, destination counter rises on arrival.
- Cluster compression uses fixed capacities K=1, M=5, L=100; selected logical units pack largest-first and all resulting cluster assets launch together. The flight formula counts packed groups, so two units are two K clusters and incur two-cluster load before the M threshold.
- Flight-time formula must stay balanced, simple, and easy to rescale.
- Visual style is cell-shaded paperclip comic; lighting and shading matter most. Mechs are not implemented — only the overworld layer and mechanics tests exist.
- Design decisions are captured in `.claude/skills/konzept/memory/konzept-snipwar-mech-*.md`; consult it before implementing dispatch or mechs.

## Repository
- This project has its own nested Git repository; operate from the project root rather than the enclosing user-home repository.
- Local commit author identity may be absent; use per-command `GIT_AUTHOR_*`/`GIT_COMMITTER_*` environment variables instead of changing Git config.

## Git hooks
- Local `core.hooksPath` is `.githooks`: `pre-commit` runs `res://scripts/preflight.gd`, `commit-msg` requires one reason sentence per staged file, and `post-commit` pushes the current branch to `origin`.
