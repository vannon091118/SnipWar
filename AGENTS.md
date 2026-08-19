# SnipWar Agent Notes

## Godot checks
- Godot not on PATH: `C:/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe`.
- `--headless --path . --quit-after 2` = main-scene smoke test; `--headless --path . --script res://scripts/preflight.gd` = persistent test suite (no GUT). Temp lifecycle checks use `res://.tmp_*.gd` and must be removed.
- Headless uses the Dummy renderer, so `Window.get_texture()` is null; visual captures need the desktop Compatibility/OpenGL renderer, and `Window.size` must be set again after scene init (the window override otherwise keeps the first 960×540 capture at the physical size).
- A headless editor scan can exit 0 despite an `EditorFileServer` port-6010 conflict aborting its scan thread; trust runtime preflight + smoke test. Render-budget assertions estimate CanvasItem submissions, not GPU frame times.
- Seed-variation check: `set_layout_seed(...)`, wait two frames, compare positions, restore the original `world_config.layout_seed`.

## Architecture constraints
- `Background` z=-100, `PlanetField` z=20; `PlanetField`/`MeteorField` must stay at local position zero (WorldConfig bounds are authored in local space, so editor offsets shift/clip the map). Background batch children inherit the background z; z-order changes can cover meteors or planets.
- Shared `WorldConfig` (Background/PlanetField/MeteorField): Bootstrap mutates only `layout_seed` (randomizes unless `ScenarioDefinition.randomize_layout_seed` is false, then applies the map's fixed seed); the background consumes `decorative_seed`. `design_size` mirrors the Godot viewport; project settings can't reference a Resource, so preflight keeps both in sync.
- Scenario selection runs in the Background root `_enter_tree()` before PlanetField enters the tree; Bootstrap `_ready()` is too late for catalog generation. `ScenarioCatalog` selects for a fresh scene; changing the catalog on a live PlanetField does not hot-swap.
- `SeededLayout._enter_tree()` must generate catalog planets before sibling `PlanetNetwork._ready()`. `planet_field.tscn` holds only static modules (NavigationField, PlanetNetwork, WorkerManager); `Planet` children are runtime catalog instances inserted before `PlanetNetwork` and must stay unowned in the editor. Only `Planet` children are laid out.
- `Planet.layout_size` derives from `Planet.size_profile` (not an enum); new profiles require updating the Resource array + IDs together. The size/profile setter restarts the spawn timer; `starting_workers` applies only after the final size assignment. Seed variation must shuffle slots AND size/detail identity.
- `PlanetDetails` is a generic child module: `PlanetDefinition` applies its profile pre-tree, `seeded_layout` applies the final detail seed after `_ready()`; it must not finalize during `_ready()` alone. Detail cap counts logical types via `get_detail_types()` (an `asteroid_belt` is one detail despite five orbit nodes); `optional_count_range` is separate from `max_details`. Each detail references `PlanetDetailFidelity` (`full`/`throttled`/`static`); negative angular speeds are valid.
- `GameState` (autoload `/root/GameState`) is the SSOT for ownership/factions AND resources; the Background seeds it from the active map catalog before PlanetField enters the tree. Planets must be in-tree before resolving the autoload (`apply_definition` runs during `_enter_tree`); initial workers are seeded only after layout profiles are assigned. `Planet.resolve_arrival()` owns the MVP rule: friendly adds, incoming <= defenders repels, incoming > defenders captures with survivors; ownership changes only via `GameState.faction_changed`.
- Resources are invisible, data-only `GameResource` objects from a `ResourcePool`; `GameState.deal_resources(catalog, pool, seed)` deals them seed-deterministically at game start — homeworlds get distinct resources, the rest is round-robin balanced (counts differ by at most one). No planet→resource mapping exists; maps may override the global pool via `MapDefinition.resource_pool`. Bootstrap deals after the final layout seed is set.
- `ScenarioDefinition` owns the route rule (`default=all_planets`, `wide=neighbors_only`) and applies it to the shared WorldConfig before PlanetField enters the tree; keep scenario/map/world routing synchronized. `route_mode` constrains destination lists and stored routes.
- One Moon/Comet waypoint per layout-neighbor edge; AStar2D routes every destination through this graph, and preview + WorkerManager consume the same global-coordinate path. `NavigationField` resolves WorldConfig from its parent and must rebuild after layout changes; its route method is `find_route()` (never `get_path`).
- Transit: `WorkerManager._dispatch_clusters` packs largest-first into K=1/M=5/L=100 groups and launches all in one frame; clusters carry `source_faction`, and arrival resolves friendly/repel/capture before freeing the visual cluster (first group may capture, later groups reinforce). `PlanetNetwork` and `WorkerManager` must share the same `TransitConfig` resource identity; validation requires a capacity-one tier. Spawn tiers: XL=3/5s, L=2/7s, variable=1/10s.
- Flight duration uses only logical unit load (no speed jump at the visual tier switch). `ClusterTierDefinition.capacity` vs `display_max_units` intentionally differ (K=1/4, M=5/99); `WorkerCluster.pixel_width()` is the shared footprint helper and `TransitConfig.overlap_budget` keeps margin under the 30% overlap limit. Formation is a deterministic V/wedge with the same offsets at source and destination; clusters stay transit-only (counters, not resting sprites) and expose `Attachments` for future assets. Don't keep unused `WorkerState` values.
- `PlanetNetwork` owns routing/lines and injects `UIThemeConfig` into the dynamically created `PlanetNetworkUI` (CanvasLayer); panel offsets recompute on viewport `size_changed`. `StarfieldBackground` batches stars/dust via `MultiMeshInstance2D` and folds/grain via `draw_multiline()` with configurable alpha buckets; viewport resize must rebuild transforms, and `batch_texture_size` tunes shape textures, not density.

### Change/commit together (one contract, not independent edits)
- Transit/dispatch: `flight_time.gd`, `dispatch.gd`, transit/cluster-tier configs+resources, `planet_network.gd`, `planet_network_ui.gd`, `ui_theme_config.gd`/`ui_theme_default.tres`, `worker_cluster.*`, `worker_manager.gd`, `planet.gd`, `game_state.gd`, `preflight.gd`.
- Navigation: navigation config/waypoint scripts+resources, `navigation_field.gd`, `navigation_waypoint.gd`, `seeded_layout.gd`, `planet_network.gd`, `worker_manager.gd`, transit/flight scripts, `preflight.gd`. Keep generation O(n): `NavigationField.rebuild()` indexes layout slots and `PlanetNetwork` caches neighbors, invalidated by `SeededLayout` after every layout change.
- Planet/catalog: `planet.tscn`, `planet.gd`, `planet_details.gd`, `planet_detail_orbit.gd`, `seeded_layout.gd`, world/size/planet/detail configs+resources, planet/detail SVGs. `planet_details.gd` reuses meteor SVGs for asteroid/comet extras.
- Presentation: `starfield_background.gd`, background/meteor configs+resources+scenes.
- Scenarios: map/scenario scripts+resources, `world_wide.tres`, `starfield_background.*`, `bootstrap.gd`, `preflight.gd`, `DESIGN.md`.
- GameState/resources: `project.godot` (autoload), `game_state.gd`, `planet.gd`, `seeded_layout.gd`, size profiles+resources, starting-faction planets, `scripts/config/game_resource.gd`, `scripts/config/resource_pool.gd`, `resources/config/resource_pool_default.tres`, `resources/config/resources/*`, `map_definition.gd`, `bootstrap.gd`, `starfield_background.gd`, `preflight.gd`.

## Interaction and assets
- Planet clicks need the planet `Area2D`/shape; cluster graphics stay collision-free. The persistent destination tab UI must be created with `call_deferred()` (avoids "parent node is busy setting up children").
- Cluster visuals are cell-shaded mech silhouettes (K=fighter, M=triad, L=capital) at configured sizes with an `Attachments` node; no per-unit transit sprites, no resting/idle unit assets, no cluster stacking or oversized radius rings.
- New SVG planet/detail assets generate tracked `.svg.import` files during the headless scan; commit the import sidecars with their sources.

## Godot pitfalls
- Godot 4.7 `@export_enum` requires String/Integer-compatible variables, not `StringName`. Resource/waypoint scripts consumed by `@tool` planet/layout scripts must also be `@tool`, or editor-time generation can produce placeholders.
- `NavigationWaypoint.configure()` may run before the node enters the tree during graph rebuild; don't rely on `@onready`, and add the node before assigning its global position so PlanetField offsets aren't applied twice.
- A `MultiMeshInstance2D` requires `MultiMesh.mesh` (a `QuadMesh`) before `instance_count`; texture+transforms alone trigger the Compatibility renderer's misleading `mesh.is_null()` errors.
- Meteor sizes are pixel-based: `meteor_field.gd` converts 4-10 px targets using each SVG texture width; keep this contract instead of restoring relative scales.
- `SceneTree.quit()` doesn't halt the current function; test scripts must `return` after `quit()`. Headless `--script` runs hang when `_init` errors or returns before `quit()`; only fail via `_check`→`quit(1)` and always end with `quit()`. Keep `--quit-after 2` for the smoke test only.
- GDScript `:=` fails inference on `Node`-typed children and preflight helper returns; use explicit types/casts (e.g. `(ocean as Node2D).global_position`). `int / int` warns `INTEGER_DIVISION`; use `int(a / 2.0)` for a float quotient.
- Connect a Tween's `finished` to a non-base-class method with `Callable(node, "_method")`; `node._method` is an unsafe member access.
- Compatibility renderer may log `Debug CanvasItem Redraw is not available yet` (benign). A cyan circle around each planet is the collision-debug overlay for `ClickArea/CollisionShape2D` (radius 120); disable `Debug > Visible Collision Shapes` for captures.

## Documentation and presentation
- README: original wording, 4K target vs prototype distinction, unfinished gameplay explicit. `VISION.md` non-binding; `DESIGN.md` is the MVP contract; keep future concept language conditional. Use explicit `<a id="...">` anchors for README badges (GitHub slugs unreliable).

## Design direction
- Hybrid built in vertical slices: strategic galaxy map now, tactical battle view later. Dispatch: slider 1..available → live flight-time/route preview (more units = slower) → pack largest-first into K/M/L → launch all groups; source counter drops at launch, destination rises on arrival. Three fixed capacities for now (K=1, M=5, L=100; 7 → M+K+K). Flight-time formula stays balanced, simple, rescalable. Cell-shaded paperclip comic; mechs not implemented. Durable decisions live in `DESIGN.md`; consult it before changing dispatch, transit, or future mech layers.

## Repository
- Nested Git repo; operate from the project root. Local commit author identity may be absent; use per-command `GIT_AUTHOR_*`/`GIT_COMMITTER_*` instead of changing Git config.

## Git hooks
- `core.hooksPath` is `.githooks` (keep active): `pre-commit` runs preflight, `commit-msg` requires one explanatory sentence per staged file, `post-commit` pushes. For an explicitly local-only commit, run both gates manually then one-shot `git -c core.hooksPath=/dev/null commit`; this leaves the hook configuration unchanged.
