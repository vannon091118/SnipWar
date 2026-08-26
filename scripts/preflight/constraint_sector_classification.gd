class_name PreflightConstraintSectorClassification
extends RefCounted

## Pure-math validation of the density-field sector system: anchor generation
## determinism, role classification, edge typing and config validation.

const FLAVOR_CATALOG: SectorFlavorCatalog = preload("res://resources/config/sector_flavor_catalog_default.tres")

func constraint_name() -> String:
	return "sector_classification"

func requires_scene() -> bool:
	return false

func run(ctx: PreflightContext) -> bool:
	var world_size := Vector2(960.0, 540.0)
	var flavors: Array[SectorFlavor] = FLAVOR_CATALOG.flavors

	# Anchor generation: requested count is produced for a small sector count.
	var anchors := SectorClassifier.generate_anchors(424242, 3, world_size, flavors)
	if not ctx.check(anchors.size() == 3, "generate_anchors should produce the requested anchor count"):
		return false

	# Determinism: same seed -> identical anchors.
	var anchors_again := SectorClassifier.generate_anchors(424242, 3, world_size, flavors)
	var deterministic := anchors.size() == anchors_again.size()
	if deterministic:
		for index in anchors.size():
			if anchors[index].position != anchors_again[index].position:
				deterministic = false
				break
	if not ctx.check(deterministic, "generate_anchors must be deterministic for the same seed"):
		return false

	# Different seed -> different layout.
	var anchors_other := SectorClassifier.generate_anchors(424243, 3, world_size, flavors)
	if not ctx.check(anchors[0].position != anchors_other[0].position, "generate_anchors should differ for different seeds"):
		return false

	# Poisson-disk minimum separation between anchors.
	var min_separation := INF
	for i in anchors.size():
		for j in range(i + 1, anchors.size()):
			min_separation = minf(min_separation, anchors[i].position.distance_to(anchors[j].position))
	if not ctx.check(min_separation > 0.0, "anchors must keep a positive minimum separation"):
		return false

	# Classification: anchor position -> core, far position -> void.
	var noise := SectorClassifier.create_noise(424242)
	var core := SectorClassifier.classify_position(anchors[0].position, anchors, noise)
	if not ctx.check(core["role"] == SectorClassifier.ROLE_CORE, "anchor position should classify as core"):
		return false
	var far := SectorClassifier.classify_position(Vector2(999999.0, 999999.0), anchors, noise)
	if not ctx.check(far["role"] == SectorClassifier.ROLE_VOID, "far position should classify as void"):
		return false

	# Edge typing.
	if not ctx.check(SectorClassifier.edge_type(&"dense_core", &"dense_core") == SectorClassifier.EDGE_INTRA, "same sector ids should be intra_sector"):
		return false
	if not ctx.check(SectorClassifier.edge_type(&"dense_core", &"void") == SectorClassifier.EDGE_VOID, "void sector should be void_edge"):
		return false
	if not ctx.check(SectorClassifier.edge_type(&"dense_core", &"sparse_arm") == SectorClassifier.EDGE_INTER, "different sector ids should be inter_sector"):
		return false

	# Flavor presets validate.
	if not ctx.check(FLAVOR_CATALOG.validate().is_empty(), "default sector flavor catalog must validate"):
		return false

	# Catalog resolve covers every preset id.
	var resolve_ok := true
	for flavor in FLAVOR_CATALOG.flavors:
		if FLAVOR_CATALOG.resolve(flavor.id) != flavor:
			resolve_ok = false
			break
	if not ctx.check(resolve_ok, "SectorFlavorCatalog.resolve must return every preset"):
		return false

	# WorldConfig validation: sector_count must stay below the planet count.
	var config := WorldConfig.new()
	config.sector_count = 5
	config.sector_flavors = flavors
	var errors := config.validate_for_planet_count(4)
	var found := false
	for error in errors:
		if String(error).contains("sector_count"):
			found = true
			break
	if not ctx.check(found, "WorldConfig must reject sector_count >= planet_count"):
		return false

	# Disabled sector system -> resolved_sector_count is 0 (opt-in).
	if not ctx.check(config.duplicate(true).resolved_sector_count() == 5 and WorldConfig.new().resolved_sector_count() == 0, "resolved_sector_count must reflect the opt-in flag"):
		return false

	# Deterministic classification across repeated calls.
	var again := SectorClassifier.classify_position(anchors[0].position, anchors, noise)
	if not ctx.check(again["depth"] == core["depth"] and again["role"] == core["role"], "classify_position must be deterministic"):
		return false

	return true
