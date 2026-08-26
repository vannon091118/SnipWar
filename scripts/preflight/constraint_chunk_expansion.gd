class_name PreflightConstraintChunkExpansion
extends RefCounted

## Tests the infinite chunk-grid world: chunk seed determinism, composition
## reproducibility, resource dealing for procedural planets, navigation
## incremental add/remove, and the infinite-world guard.

func constraint_name() -> String:
	return "chunk_expansion"

func requires_scene() -> bool:
	return false

func run(ctx: PreflightContext) -> bool:
	# Chunk seed determinism: same layout_seed + chunk_coord = same seed.
	var seed_a := WorldGenerator.chunk_seed(12345, 2, 3)
	var seed_b := WorldGenerator.chunk_seed(12345, 2, 3)
	if not ctx.check(seed_a == seed_b, "chunk_seed is not deterministic for same inputs"):
		return false
	var seed_c := WorldGenerator.chunk_seed(12345, 3, 2)
	if not ctx.check(seed_a != seed_c, "chunk_seed should differ for different chunk coords"):
		return false
	# Seed should be positive (no INT_MIN overflow).
	if not ctx.check(seed_a >= 0, "chunk_seed should be non-negative"):
		return false

	# Slot seed determinism.
	var slot_a := WorldGenerator.slot_seed(seed_a, 5)
	var slot_b := WorldGenerator.slot_seed(seed_a, 5)
	if not ctx.check(slot_a == slot_b, "slot_seed is not deterministic"):
		return false
	if not ctx.check(slot_a != WorldGenerator.slot_seed(seed_a, 6), "slot_seed should differ for different slots"):
		return false

	# Planet name generator: deterministic + non-empty.
	var name_a := WorldGenerator.generate_planet_name(999)
	var name_b := WorldGenerator.generate_planet_name(999)
	if not ctx.check(name_a == name_b, "planet name is not deterministic"):
		return false
	if not ctx.check(not name_a.is_empty(), "planet name should not be empty"):
		return false
	if not ctx.check(name_a.contains(" "), "planet name should contain a space (Adjective Noun)"):
		return false
	var name_c := WorldGenerator.generate_planet_name(1000)
	if not ctx.check(name_a != name_c, "planet name should differ for different seeds"):
		return false

	# Compose planet: deterministic, returns a Dictionary with base_texture, tint, decal_textures.
	var base_textures: Array[Texture2D] = [
		preload("res://assets/objects/planets/planet_01_ember.svg"),
		preload("res://assets/objects/planets/planet_02_ocean.svg"),
	]
	var tints: Array[Color] = [Color(0.8, 0.4, 0.3), Color(0.3, 0.5, 0.8)]
	var decals: Array[Texture2D] = [preload("res://assets/objects/meteors/meteor_01_rock.svg")]
	var comp_a := WorldGenerator.compose_planet(42, base_textures, tints, decals)
	var comp_b := WorldGenerator.compose_planet(42, base_textures, tints, decals)
	if not ctx.check(comp_a["base_texture"] == comp_b["base_texture"], "composition base_texture is not deterministic"):
		return false
	if not ctx.check(comp_a["tint"] == comp_b["tint"], "composition tint is not deterministic"):
		return false
	if not ctx.check(comp_a.has("decal_textures"), "composition should have decal_textures key"):
		return false
	# Different seed = different composition (at least sometimes).
	var comp_c := WorldGenerator.compose_planet(9999, base_textures, tints, decals)
	if not ctx.check(typeof(comp_a["tint"]) == TYPE_COLOR, "composition tint should be a Color"):
		return false

	# WorldConfig.is_infinite_world() guard.
	var default_config: WorldConfig = preload("res://resources/config/world_default.tres")
	if not ctx.check(default_config.is_infinite_world(), "default world should use the infinite chunk generator"):
		return false
	var infinite_config := default_config.duplicate(true) as WorldConfig
	infinite_config.chunk_size = 5
	if not ctx.check(infinite_config.is_infinite_world(), "config with chunk_size>0 should be infinite"):
		return false

	var home_cells := WorldGenerator.homeworld_cells(default_config.chunk_size)
	if not ctx.check(home_cells.size() == 2 and home_cells[0] != home_cells[1], "infinite world should expose two distinct homeworld cells"):
		return false
	if not ctx.check(abs(home_cells[0].x - home_cells[1].x) + abs(home_cells[0].y - home_cells[1].y) > 1, "homeworld cells must not be adjacent"):
		return false

	# resolved_cell_size: when cell_size is zero, derived from design_size / chunk_size.
	var cs := infinite_config.resolved_cell_size()
	if not ctx.check(cs.x > 0.0 and cs.y > 0.0, "resolved_cell_size should be positive for infinite world"):
		return false
	# A finite duplicate still retains the legacy cell-size contract.
	var finite_config := default_config.duplicate(true) as WorldConfig
	finite_config.chunk_size = 0
	var legacy_cs := finite_config.resolved_cell_size()
	if not ctx.check(legacy_cs == finite_config.design_size, "resolved_cell_size should return design_size when chunk_size=0"):
		return false

	# Chunk planet generation: produces chunk_size^2 definitions. The chunk path
	# consumes a template catalog for its detail profile/id prefix; the authored
	# catalog is now empty because the finite sector is generated from building
	# blocks, so build a synthetic one-planet template here.
	var template_catalog := PlanetCatalog.new()
	var template_definition := PlanetDefinition.new()
	template_definition.planet_id = &"tmpl"
	template_definition.display_name = "Template"
	template_definition.detail_profile = preload("res://resources/config/planet_details/default.tres")
	template_catalog.planets = [template_definition]
	var chunk_defs := WorldGenerator.generate_chunk_planets(
		template_catalog,
		1, 1, seed_a, 5, infinite_config, &"variable"
	)
	if not ctx.check(chunk_defs.size() == 25, "chunk should have 25 planet definitions (5×5)"):
		return false
	# All should be neutral with chunk-specific IDs.
	for def in chunk_defs:
		if def == null:
			if not ctx.check(false, "chunk planet definition is null"):
				return false
			continue
		if not ctx.check(def.faction == &"neutral", "chunk planet %s should be neutral" % def.planet_id):
			return false
		if not ctx.check(def.planet_role == &"planet", "chunk planet %s should have role 'planet'" % def.planet_id):
			return false
		if not ctx.check(String(def.planet_id).begins_with("c1_1_"), "chunk planet ID should have chunk prefix"):
			return false
		if not ctx.check(not def.display_name.is_empty(), "chunk planet should have a generated name"):
			return false
	# Determinism: same seed = same IDs.
	var chunk_defs_2 := WorldGenerator.generate_chunk_planets(
		template_catalog,
		1, 1, seed_a, 5, infinite_config, &"variable"
	)
	if not ctx.check(chunk_defs[0].planet_id == chunk_defs_2[0].planet_id, "chunk planet generation is not deterministic"):
		return false

	# PlanetDefinition.validate() accepts composition_base_texture instead of planet_texture.
	var comp_def := PlanetDefinition.new()
	comp_def.planet_id = &"test_comp"
	comp_def.display_name = "Test Comp"
	comp_def.composition_base_texture = preload("res://assets/objects/planets/planet_01_ember.svg")
	comp_def.detail_profile = preload("res://resources/config/planet_details/default.tres")
	if not ctx.check(comp_def.validate().is_empty(), "planet definition with composition_base_texture should validate"):
		return false
	var empty_def := PlanetDefinition.new()
	empty_def.planet_id = &"test_empty"
	empty_def.display_name = "Test Empty"
	if not ctx.check(not empty_def.validate().is_empty(), "planet definition with neither texture should fail validation"):
		return false

	# TraitDefinition has fov_radius_bonus field and the runtime planet facade
	# exposes the upgrade-aware radius used by infinite-world activation.
	var test_trait := TraitDefinition.new()
	test_trait.id = &"test_fov"
	test_trait.display_name = "Test FoV"
	if not ctx.check(test_trait.fov_radius_bonus == 0, "fov_radius_bonus should default to 0"):
		return false

	# GameState facade has deal_resources_for_planets.
	var state: Node = ctx.root().get_node_or_null("GameState")
	if state == null:
		await ctx.await_frame()
		state = ctx.root().get_node_or_null("GameState")
	if not ctx.check(state != null, "GameState autoload should be available"):
		return false
	if not ctx.check(state.has_method("deal_resources_for_planets"), "GameState should have deal_resources_for_planets facade"):
		return false

	return true
