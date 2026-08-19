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
- `planet_details.gd` owns seeded extras; Toxic always showcases a satellite plus an asteroid belt and may add a comet, while other planets get up to three deterministic detail types. The cyan orbital-ring detail was removed: no planet shows an unplanned halo and `planet_detail_ring.gd`/`planet_detail_ring.gd.uid` are gone.
- `WorkerCluster` nodes are the garrison and transit representation; `WorkerManager._dispatch_clusters` creates exactly one cluster for the complete logical send. The asset tier changes at K=1–4, M=5–99, and L=100+; partial sends split a garrison cluster and refresh its tier asset, while arrivals re-register the full logical amount.
- `WorkerCluster.pixel_width(unit_count)` is the shared sprite-footprint helper. Garrison placement uses `WorkerManager.OVERLAP_BUDGET` (0.85 of diameter, leaving a safety margin under the user's 30% overlap limit) to choose stable perimeter slots; clusters never intentionally stack on the planet center.
- A dispatch is one simultaneous visible object, so there is no transit fleet stacking to solve for the current three-tier contract. The cluster still exposes `Attachments` for later object assets such as cannons, drones, and upgrades.
- Spawn tiers are part of the MVP contract: XL = 3 workers/5 s, L = 2/7 s, variable planets = 1/10 s.
- `flight_time.gd`, `dispatch.gd`, `planet_network.gd`, `planet_network_ui.gd`, `worker_cluster.gd`, `worker_cluster.tscn`, `worker_manager.gd`, and `preflight.gd` change/commit together; preflight uses PlanetNetworkUI getters and cluster internals (`_registered_planet`, `_arrive`). The flight formula uses only logical unit load; visual K/M/L thresholds must not add a discontinuous speed jump.
- `planet.tscn`, `planet.gd`, `planet_details.gd`, `planet_detail_orbit.gd`, `seeded_layout.gd`, and the planet SVG/import assets change together for seeded details. `planet_details.gd` reuses meteor SVGs for asteroid/comet extras; `planet_detail_ring.gd` no longer exists and must not return without a concept-level decision.
- `PlanetNetwork` resolves destinations and passes them to `WorkerManager`; keep the manager independent of the network lookup. `planet_network.gd` owns routing/lines, while `planet_network_ui.gd` owns the CanvasLayer controls and emits UI signals.
- Do not keep unused `WorkerState` values as placeholders; add a state only when its transition behavior exists.
- Flight duration uses a smooth logical-unit load only, so the visual tier switch does not make speed jump; headless tests call `cluster._arrive()` directly and assert movement via "distance to destination decreased", never by awaiting flight end or exact positions.

## Interaction and assets
- Planet clicks require the planet `Area2D`/shape; cluster graphics remain collision-free. The persistent destination tab UI must be created with `call_deferred()` because adding viewport UI during child setup triggers Godot's "parent node is busy setting up children" error.
- Cluster visuals use cell-shaded mech silhouettes (K=fighter, M=triad, L=capital) at fixed visible sizes (`TIER_PIXELS` = 12/20/30 px) and expose an `Attachments` node for future cannons, drones, or upgrades; do not restore per-unit transit sprites. Cluster-stacking and oversized radius rings are not part of the planned style.
- The current dispatch contract intentionally renders one cluster per send. Do not reintroduce one sprite per logical unit or largest-first multi-cluster packing without revisiting the three-tier rule and overlap budget.
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
- A planet-side cyan halo usually comes from `PlanetDetailRing` drawing the non-toxic `Color(0.48, 0.82, 1.0, 0.58)` arc, NOT from any planet SVG. Inspect `PlanetDetails` children before blaming the asset.
- GDScript 4 warns `INTEGER_DIVISION` on `int / int`; use `int(a / 2.0)` when a float quotient is intended.
- Connect a Tween's `finished` to a method not on the statically-typed base class with `Callable(node, "_method")`; `node._method` is an unsafe member access.

## Documentation and presentation
- README product copy should use original wording, distinguish the 4K presentation target from the current prototype, and state unfinished gameplay explicitly.
- GitHub slugs for decorated/non-ASCII headings are unreliable; use explicit `<a id="...">` anchors for README badge links.

## Design direction (SnipWar concept)
- SnipWar is a hybrid built in vertical slices: strategic galaxy map now, tactical battle view as a later layer.
- Unit dispatch: slider 1..available → live flight-time/route preview (more logical units = slower) → represent the complete send with one K/M/L cluster asset → launch it immediately; source counter drops at launch, destination counter rises on arrival.
- Three visual thresholds are fixed for now: K represents 1–4 logical units, M represents 5–99, and L represents 100+. Every selected amount is one cluster; tier changes are visual and do not alter the smooth flight-time formula.
- Flight-time formula must stay balanced, simple, and easy to rescale.
- Visual style is cell-shaded paperclip comic; lighting and shading matter most. Mechs are not implemented — only the overworld layer and mechanics tests exist.
- Design decisions are captured in `.claude/skills/konzept/memory/konzept-snipwar-mech-*.md`; consult it before implementing dispatch or mechs.

## Repository
- This project has its own nested Git repository; operate from the project root rather than the enclosing user-home repository.
- Local commit author identity may be absent; use per-command `GIT_AUTHOR_*`/`GIT_COMMITTER_*` environment variables instead of changing Git config.

## Git hooks
- Local `core.hooksPath` is `.githooks`: `pre-commit` runs `res://scripts/preflight.gd`, `commit-msg` requires one reason sentence per staged file, and `post-commit` pushes the current branch to `origin`.
