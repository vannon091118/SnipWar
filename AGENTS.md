# SnipWar Agent Notes

## Godot checks
- Godot is not on PATH; use `C:/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe`.
- `--headless --path . --quit-after 2` exercises the real main scene; temporary lifecycle checks run with `--headless --path . --script res://.tmp_*.gd` and must be removed afterward.
- No GUT framework; `scripts/preflight.gd` is the persistent headless test suite (`--headless --path . --script res://scripts/preflight.gd`).
- A headless editor scan can exit 0 while reporting an `EditorFileServer` port-6010 conflict and aborting its scan thread; trust runtime preflight and the main-scene smoke test for execution validation.
- The seed-variation check calls `PlanetField.set_layout_seed(...)`, waits two frames for deferred regeneration, compares positions, then restores the original `world_config.layout_seed` before the remaining assertions.

## Architecture constraints
- `Background` is z=-100 and `PlanetField` uses relative z=20; lowering the field below the background makes the background draw over the planets.
- The runtime Bootstrap replaces the editor fallback seed 241119 on F5; the seed is configured in `PlanetField.world_config`, not the `Background` root.
- `WorldConfig` is shared by Background, PlanetField, and MeteorField; Bootstrap mutates only `layout_seed`, while the background consumes `decorative_seed`. Keep these consumers on the same resource when changing world dimensions or seeds.
- `WorldConfig.design_size` intentionally mirrors the Godot viewport in `project.godot`; project settings cannot reference a Resource, so preflight must keep both values synchronized.
- The scale preflight cases duplicate WorldConfig and PlanetCatalog, set them before adding a fresh PlanetField to the tree, then verify bounds, unique slots, counts, and route connectivity for multiple logical world sizes.
- `NavigationField` resolves WorldConfig from its `PlanetField` parent and must rebuild after layout positions change; otherwise custom scale cases retain stale scene-local columns or seeds.
- One Moon/Comet waypoint represents each layout-neighbor edge; AStar2D routes every selected destination through this graph, and both preview and WorkerManager must consume the same global-coordinate path.
- Runtime re-layout assigns `Planet.size_profile` and its derived `layout_size` after the initial scene setup; the layout/profile setter must restart an existing spawn timer so generated size and spawn cadence remain synchronized.
- `seeded_layout.gd` must only lay out `Planet` children; the Toxic orbit child is intentionally not a planet slot.
- `SeededLayout._enter_tree()` must generate catalog planets before sibling `PlanetNetwork` enters `_ready()`; generating in `_ready()` makes the network miss planet signal connections and UI entries.
- `planet_field.tscn` intentionally contains only `PlanetNetwork` and `WorkerManager`; direct `Planet` children are runtime instances from `PlanetCatalog` and must be inserted before `PlanetNetwork`.
- Catalog-generated `Planet` nodes must remain unowned in the editor; assigning scene ownership would serialize stale generated children into `planet_field.tscn` and undermine catalog authority.
- `seeded_layout.gd` resolves `WorldConfig` profile IDs from its `size_profiles` array; `Planet.layout_size` is derived from `Planet.size_profile`, not an enum. New profiles require updating the Resource array and IDs together.
- Seed variation must shuffle slot assignment as well as size/detail identity; fixed XL corners or a fixed L crossing make different seeds look nearly identical.
- `PlanetDetails` is a child module inside `planet.tscn`; `PlanetDefinition` applies its profile before the dynamic `Planet` enters the tree, while `seeded_layout.gd` applies the final detail seed after `Planet._ready()`. It must not finalize its detail set during `_ready()` alone.
- `PlanetDefinition` owns identity, role, faction, texture, and detail profile; `PlanetDetails` must remain generic and must not reintroduce planet-ID-specific detail branches such as the former Toxic special case.
- The detail cap counts logical types via `get_detail_types()`; an `asteroid_belt` is one detail even though it creates five orbit nodes. Toxic's belt must not be reintroduced as a separate field-level orbit.
- `PlanetDetailProfile.optional_count_range` is separate from `max_details`: the default profile selects 0–3 optional details, while Toxic selects 0–1 after its two guaranteed details. Guaranteed details still count toward the cap.
- Planet size belongs to the Node2D layout scale; keep `planet.gd`'s `visual_scale` at 1.0 to avoid double scaling.
- The current minimal meteor design uses four direct Sprite2D children controlled by `meteor_field.gd`; no per-meteor scene/script is required.
- `planet_details.gd` owns seeded extras; Toxic always showcases a satellite plus an asteroid belt and may add a comet, while other planets get up to three deterministic detail types. The cyan orbital-ring detail was removed: no planet shows an unplanned halo and `planet_detail_ring.gd`/`planet_detail_ring.gd.uid` are gone.
- `WorkerCluster` nodes are transit-only visuals; planet spawning and resting forces update only `Planet.worker_count`. `WorkerManager._dispatch_clusters` packs largest-first into K=1, M=5, and L=100 groups and launches every group in the same frame; arrivals add their logical amount and free the visual cluster.
- `ClusterTierDefinition.capacity` controls greedy packing while `display_max_units` controls visual tier selection; they intentionally differ (K=1/4, M=5/99). Do not merge these thresholds.
- `PlanetNetwork` and `WorkerManager` must share the same `TransitConfig`; otherwise flight previews and actual transit can use different tuning.
- TransitConfig validation requires a capacity-one tier so greedy packing can represent every positive unit count; preserve this invariant for custom tier sets.
- `WorkerCluster.pixel_width(unit_count, transit_config)` is the shared sprite-footprint helper for transit formation spacing. `TransitConfig.overlap_budget` leaves a safety margin under the user's 30% overlap limit; no idle cluster placement exists.
- Transit groups use a route-aligned deterministic V/wedge formation with the same offsets at source and destination, so the fleet remains ordered until arrival. The cluster still exposes `Attachments` for later object assets such as cannons, drones, and upgrades.
- Spawn tiers are part of the MVP contract: XL = 3 workers/5 s, L = 2/7 s, variable planets = 1/10 s.
- `flight_time.gd`, `dispatch.gd`, `scripts/config/transit_config.gd`, `scripts/config/cluster_tier_definition.gd`, `resources/config/transit_default.tres`, `resources/config/cluster_tiers/*`, `planet_network.gd`, `planet_network_ui.gd`, `scripts/config/ui_theme_config.gd`, `resources/config/ui_theme_default.tres`, `worker_cluster.gd`, `worker_cluster.tscn`, `worker_manager.gd`, and `preflight.gd` change/commit together; preflight uses PlanetNetworkUI getters and the manager's `_arrive_cluster()` wrapper. The flight formula uses only logical unit load; visual K/M/L thresholds must not add a discontinuous speed jump.
- Navigation changes span `scripts/config/navigation_config.gd`, `resources/config/navigation_default.tres`, `scripts/objects/planets/navigation_field.gd`, `scripts/objects/planets/navigation_waypoint.gd`, its scene/SVG import sidecars, `seeded_layout.gd`, `planet_network.gd`, `worker_manager.gd`, `transit_config.gd`, `flight_time.gd`, and `preflight.gd`; update them as one pathing contract.
- `planet.tscn`, `planet.gd`, `planet_details.gd`, `planet_detail_orbit.gd`, `seeded_layout.gd`, `scripts/config/world_config.gd`, `scripts/config/planet_size_profile.gd`, `scripts/config/planet_definition.gd`, `scripts/config/planet_catalog.gd`, `scripts/config/planet_detail_definition.gd`, `scripts/config/planet_detail_profile.gd`, `resources/config/world_default.tres`, `resources/config/planet_sizes/*`, `resources/config/planet_catalog.tres`, `resources/config/planets/*`, `resources/config/planet_details/*`, and the planet/detail SVG/import assets change together for catalog-driven content. `planet_details.gd` reuses meteor SVGs for asteroid/comet extras; `planet_detail_ring.gd` no longer exists and must not return without a concept-level decision.
- `scripts/backgrounds/starfield_background.gd`, `scripts/config/background_config.gd`, `scripts/config/background_nebula_definition.gd`, `resources/config/background_default.tres`, `resources/config/background_nebula/*`, `scripts/objects/meteors/meteor_field.gd`, `scripts/config/meteor_config.gd`, `resources/config/meteor_default.tres`, and their scenes change together for presentation tuning.
- `PlanetNetwork` resolves destinations and passes them to `WorkerManager`; keep the manager independent of the network lookup. `planet_network.gd` owns routing/lines, while `planet_network_ui.gd` owns the CanvasLayer controls and emits UI signals.
- `WorldConfig.route_mode` is `all_planets` for the MVP, so the UI lists every other planet while neighbor lines remain orientation hints; `neighbors_only` is the explicit alternative and must constrain both destination lists and stored routes.
- `PlanetNetwork` injects `UIThemeConfig` into the dynamically created `PlanetNetworkUI`; panel offsets must be recomputed on viewport `size_changed`, not replaced with fixed pixel positions.
- `BackgroundConfig` controls starfield density/visual ranges and `MeteorConfig` controls meteor size/speed; WorldConfig remains the source for world bounds and decorative seed, and the scene assignments must stay connected.
- Do not keep unused `WorkerState` values as placeholders; add a state only when its transition behavior exists.
- Flight duration uses a smooth logical-unit load only, so the visual tier switch does not make speed jump; normalized tuning is `distance / TransitConfig.distance_unit × base_seconds_per_distance_unit`. Transit arrival tests should call the manager's `_arrive_cluster()` wrapper, assert movement via "distance to destination decreased", and inspect launch formation synchronously because a frame wait can move fast clusters before exact source offsets are checked.

## Interaction and assets
- Planet clicks require the planet `Area2D`/shape; cluster graphics remain collision-free. The persistent destination tab UI must be created with `call_deferred()` because adding viewport UI during child setup triggers Godot's "parent node is busy setting up children" error.
- Cluster visuals use cell-shaded mech silhouettes (K=fighter, M=triad, L=capital) at configured visible sizes from `ClusterTierDefinition` and expose an `Attachments` node for future cannons, drones, or upgrades; do not restore per-unit transit sprites. Cluster-stacking and oversized radius rings are not part of the planned style.
- The current dispatch contract renders clusters only while they are in transit; planets show counters, not idle unit assets. Do not add resting sprites or replace the packed K/M/L groups with one sprite per logical unit without revisiting the visibility and overlap rules.
- New SVG planet/detail assets cause Godot to generate tracked `.svg.import` files during the headless scan; commit the import sidecars with their source SVGs.

## Godot pitfalls
- Godot 4.7 `@export_enum` requires String/Integer-compatible variables, not `StringName`.
- Resource and waypoint scripts consumed by `@tool` planet/layout scripts must also be marked `@tool`; otherwise editor-time generation can produce placeholders or skip waypoint configuration even when runtime preflight passes.
- `NavigationWaypoint.configure()` may run before the node enters the tree during graph rebuild; do not rely on an `@onready` Sprite2D there, and add the node before assigning its global position so PlanetField offsets are not applied twice.
- `NavigationField`'s route method must not be named `get_path`: that collides with native `Node.get_path()` and causes a misleading signature/override parse error; use a distinct name such as `find_route()`.
- Meteor respawn must disable processing before emitting the exit signal; the callback immediately respawns and re-enables the meteor.
- Meteor sizes are pixel-based: `meteor_field.gd` converts 4-10 px targets using each SVG texture width; keep this visible-size contract instead of restoring relative 0.004-0.01 scales.
- `SceneTree.quit()` does not halt the current function; test scripts must `return` after `quit()` or the success path falls through to the failure branch.
- GDScript `:=` errors with "value doesn't have a set type" on members of `Node`-typed children; use explicit types and casts like `(ocean as Node2D).global_position`.
- In SceneTree preflight helpers, use explicit types for values returned from `Node` calls and conditional expressions; `:=` can produce an unhelpful constructor/inference parse error for values such as route counts and boolean assertions.
- Headless `--script` runs hang (timeout) when `_init` errors or returns before `quit()`; only fail via `_check`→`quit(1)` and always end with `quit()`.
- Keep `--quit-after 2` for the main-scene smoke test only; using it on `preflight.gd` can terminate before its `PASS` result and hide the real failure.
- The Compatibility renderer may emit `Debug CanvasItem Redraw is not available yet` during startup; treat it as an engine/debug warning unless preflight or the smoke test fails.
- A cyan circle around every planet in an editor-run game is the Godot collision-debug overlay for `Planet/ClickArea/CollisionShape2D` (radius 120), not a planet asset or detail effect. Disable `Debug > Visible Collision Shapes` for visual captures; changing `SceneTree.debug_collisions_hint` at runtime is not reliable.
- GDScript 4 warns `INTEGER_DIVISION` on `int / int`; use `int(a / 2.0)` when a float quotient is intended.
- Connect a Tween's `finished` to a method not on the statically-typed base class with `Callable(node, "_method")`; `node._method` is an unsafe member access.

## Documentation and presentation
- README product copy should use original wording, distinguish the 4K presentation target from the current prototype, and state unfinished gameplay explicitly.
- `VISION.md` is a non-binding, feasibility-checked outlook; `DESIGN.md` remains the concrete MVP contract. Keep future concept language conditional until a separate implementation decision exists.
- GitHub slugs for decorated/non-ASCII headings are unreliable; use explicit `<a id="...">` anchors for README badge links.

## Design direction (SnipWar concept)
- SnipWar is a hybrid built in vertical slices: strategic galaxy map now, tactical battle view as a later layer.
- Unit dispatch: slider 1..available → live flight-time/route preview (more logical units = slower) → pack largest-first into K/M/L cluster assets → launch all groups simultaneously; source counter drops at launch, destination counter rises on arrival.
- Three fixed cluster capacities are used for now: K=1, M=5, L=100. A quantity such as 7 becomes M+K+K; the smooth flight-time formula remains based on logical unit load, while formation geometry keeps all visible groups ordered.
- Flight-time formula must stay balanced, simple, and easy to rescale.
- Visual style is cell-shaded paperclip comic; lighting and shading matter most. Mechs are not implemented — only the overworld layer and mechanics tests exist.
- Durable design decisions are captured in the root `DESIGN.md`; consult it before changing dispatch, transit, or future mech layers.

## Repository
- This project has its own nested Git repository; operate from the project root rather than the enclosing user-home repository.
- Local commit author identity may be absent; use per-command `GIT_AUTHOR_*`/`GIT_COMMITTER_*` environment variables instead of changing Git config.

## Git hooks
- Local `core.hooksPath` is `.githooks` and must remain active: `pre-commit` runs `res://scripts/preflight.gd`, while `commit-msg` rejects any commit that lacks one explanatory sentence for every staged file. Do not bypass the hooks; the repository's `post-commit` policy is separate from the explanation gate.
- For an explicitly local-only commit, run `./.githooks/pre-commit` and `./.githooks/commit-msg` manually, then use one-shot `git -c core.hooksPath=/dev/null commit`; this skips only the automatic push after both gates have run and leaves the local hook configuration unchanged.
