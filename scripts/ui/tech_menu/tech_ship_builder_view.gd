class_name TechShipBuilderView
extends RefCounted

## Manages modular ship parts shop, assembly, disassembly, fleet launch, and assembly countdowns.

const SHIPYARD_UPGRADE_ID: StringName = &"shipyard"

var _theme_config: UIThemeConfig
var _ship_manager: ShipManager
var builder_source: OptionButton
var builder_hull: OptionButton
var builder_drive: OptionButton
var builder_weapon: OptionButton
var builder_shield: OptionButton
var builder_scanner: OptionButton
var builder_modules: Array[OptionButton] = []
var builder_dynamic: VBoxContainer
var builder_job_labels: Dictionary = {}
var builder_job_progress: Dictionary = {}

func setup(ship_manager: ShipManager, theme_config: UIThemeConfig) -> void:
	_ship_manager = ship_manager
	_theme_config = theme_config

func clear_state() -> void:
	builder_source = null
	builder_hull = null
	builder_drive = null
	builder_weapon = null
	builder_shield = null
	builder_scanner = null
	builder_modules.clear()
	builder_dynamic = null
	builder_job_labels.clear()
	builder_job_progress.clear()

func build_ship_builder_section(
	container: VBoxContainer,
	state: Node,
	planets: Array[Planet],
	on_refresh_callback: Callable
) -> void:
	if container == null or _ship_manager == null or state == null:
		return

	container.add_child(UIBaseUtils.make_separator())
	container.add_child(UIBaseUtils.make_label("SCHIFFSWERFT — SHOP", _theme_config.heading_text_color, _theme_config.section_font_size))
	container.add_child(UIBaseUtils.make_label("Teile kaufen, im Hangar montieren und bei Bedarf wieder zerlegen.", _theme_config.muted_text_color, _theme_config.small_font_size))
	container.add_child(UIBaseUtils.make_label("Startplanet (eigene Werft)", _theme_config.secondary_text_color, _theme_config.small_font_size))

	builder_source = OptionButton.new()
	builder_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_scout_sources(builder_source, planets, state)
	builder_source.item_selected.connect(func(_idx: int): populate_builder_dynamic(state, on_refresh_callback))
	container.add_child(builder_source)

	builder_dynamic = VBoxContainer.new()
	builder_dynamic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hangar_backdrop := TextureRect.new()
	hangar_backdrop.name = "ShipHangarBackdrop"
	hangar_backdrop.texture = _theme_config.ship_hangar_background_texture
	hangar_backdrop.custom_minimum_size = Vector2(0.0, 72.0)
	hangar_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hangar_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	hangar_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	builder_dynamic.add_child(hangar_backdrop)
	builder_dynamic.add_theme_constant_override("separation", _theme_config.list_separation)
	container.add_child(builder_dynamic)
	populate_builder_dynamic(state, on_refresh_callback)

func populate_builder_dynamic(state: Node, on_refresh_callback: Callable) -> void:
	if builder_dynamic == null or state == null or _ship_manager == null:
		return
	for child in builder_dynamic.get_children():
		if child.name == "ShipHangarBackdrop":
			continue
		builder_dynamic.remove_child(child)
		child.queue_free()

	builder_hull = null
	builder_drive = null
	builder_weapon = null
	builder_shield = null
	builder_scanner = null
	builder_modules.clear()
	builder_job_labels.clear()
	builder_job_progress.clear()

	var source: Planet = selected_option_planet(builder_source)
	if source == null:
		builder_dynamic.add_child(UIBaseUtils.make_label("Keine eigene Werft vorhanden — zuerst Orbitale Werft bauen.", _theme_config.muted_text_color, _theme_config.small_font_size))
		return

	var catalog: ShipPartCatalog = _ship_manager.get_part_catalog()
	var inventory: Dictionary = state.get_ship_part_inventory(source.planet_id)

	builder_dynamic.add_child(UIBaseUtils.make_label("TEILE KAUFEN", _theme_config.heading_text_color, _theme_config.section_font_size))
	for part in catalog.parts:
		if part == null:
			continue
		var owned: int = int(inventory.get(part.id, 0))
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", _theme_config.card_padding)
		var label := UIBaseUtils.make_label("%s — %d %s  (Besitz: %d)" % [part.display_name, part.cost_amount, String(part.cost_resource), owned], _theme_config.secondary_text_color, _theme_config.small_font_size)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var buy := Button.new()
		buy.text = "KAUFEN"
		buy.disabled = not _ship_manager.can_buy_part(source, part.id)
		if buy.disabled:
			buy.tooltip_text = "Kosten: %d %s" % [part.cost_amount, String(part.cost_resource)]
		buy.pressed.connect(func():
			if _ship_manager.buy_part(source, part.id):
				populate_builder_dynamic(state, on_refresh_callback)
		)
		row.add_child(buy)
		builder_dynamic.add_child(row)

	builder_dynamic.add_child(UIBaseUtils.make_separator())
	builder_dynamic.add_child(UIBaseUtils.make_label("MONTAGE", _theme_config.heading_text_color, _theme_config.section_font_size))
	builder_dynamic.add_child(UIBaseUtils.make_label("Hülle", _theme_config.secondary_text_color, _theme_config.small_font_size))
	builder_hull = _builder_slot_option(inventory, ShipPartDefinition.SLOT_HULL)
	builder_dynamic.add_child(builder_hull)

	builder_dynamic.add_child(UIBaseUtils.make_label("Antrieb", _theme_config.secondary_text_color, _theme_config.small_font_size))
	builder_drive = _builder_slot_option(inventory, ShipPartDefinition.SLOT_DRIVE)
	builder_dynamic.add_child(builder_drive)

	builder_dynamic.add_child(UIBaseUtils.make_label("Waffe (optional — macht das Schiff militärisch)", _theme_config.secondary_text_color, _theme_config.small_font_size))
	builder_weapon = _builder_slot_option(inventory, ShipPartDefinition.SLOT_WEAPON, true)
	builder_dynamic.add_child(builder_weapon)

	builder_dynamic.add_child(UIBaseUtils.make_label("Schild", _theme_config.secondary_text_color, _theme_config.small_font_size))
	builder_shield = _builder_slot_option(inventory, ShipPartDefinition.SLOT_SHIELD)
	builder_dynamic.add_child(builder_shield)

	builder_dynamic.add_child(UIBaseUtils.make_label("Scanner", _theme_config.secondary_text_color, _theme_config.small_font_size))
	builder_scanner = _builder_slot_option(inventory, ShipPartDefinition.SLOT_SCANNER)
	builder_dynamic.add_child(builder_scanner)

	for index in catalog.max_module_slots:
		builder_dynamic.add_child(UIBaseUtils.make_label("Modul %d" % (index + 1), _theme_config.secondary_text_color, _theme_config.small_font_size))
		var module_option: OptionButton = _builder_slot_option(inventory, ShipPartDefinition.SLOT_MODULE, true)
		builder_modules.append(module_option)
		builder_dynamic.add_child(module_option)

	var assemble := Button.new()
	assemble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	assemble.text = "KOMBINIEREN"
	assemble.disabled = not _builder_can_assemble()
	assemble.pressed.connect(func():
		_on_assemble_ship(source, state, on_refresh_callback)
	)
	builder_dynamic.add_child(assemble)

	builder_dynamic.add_child(UIBaseUtils.make_separator())
	builder_dynamic.add_child(UIBaseUtils.make_label("GEBAUTE SCHIFFE", _theme_config.heading_text_color, _theme_config.section_font_size))

	var build_jobs: Dictionary = state.get_ship_build_jobs(source.planet_id)
	if not build_jobs.is_empty():
		builder_dynamic.add_child(UIBaseUtils.make_label("IM BAU:", _theme_config.accent_text_color, _theme_config.small_font_size))
		for job_ship_value in build_jobs:
			var job_ship_id: StringName = job_ship_value as StringName
			var remaining: float = state.ship_build_remaining(source.planet_id, job_ship_id)
			var job_assembly: ShipAssembly = build_jobs[job_ship_id] as ShipAssembly
			var job_label := UIBaseUtils.make_label("Montage läuft — %s (%.0f s verbleibend)" % [_assembly_role(job_assembly), remaining], _theme_config.muted_text_color, _theme_config.small_font_size)
			job_label.tooltip_text = _assembly_tooltip(catalog, job_assembly, remaining)
			job_label.set_meta("ship_id", job_ship_id)
			builder_job_labels[job_ship_id] = job_label
			builder_dynamic.add_child(job_label)
			var total_time: float = _assembly_build_time(catalog, job_assembly)
			var progress := ProgressBar.new()
			progress.name = "ShipBuildProgress"
			progress.custom_minimum_size = Vector2(0.0, 6.0)
			progress.min_value = 0.0
			progress.max_value = maxf(total_time, 1.0)
			progress.value = clampf(total_time - remaining, 0.0, progress.max_value)
			progress.show_percentage = false
			progress.set_meta("ship_id", job_ship_id)
			progress.set_meta("total_time", total_time)
			progress.tooltip_text = "Montagefortschritt"
			builder_job_progress[job_ship_id] = progress
			builder_dynamic.add_child(progress)

	var assemblies: Dictionary = state.get_ship_assemblies(source.planet_id)
	if assemblies.is_empty():
		builder_dynamic.add_child(UIBaseUtils.make_label("Noch keine Schiffe montiert.", _theme_config.muted_text_color, _theme_config.small_font_size))
	else:
		for ship_value in assemblies:
			var ship_id: StringName = ship_value as StringName
			var ship_row := HBoxContainer.new()
			ship_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ship_row.add_theme_constant_override("separation", _theme_config.card_padding)
			var ship_label := UIBaseUtils.make_label(_assembly_description(catalog, assemblies[ship_id]), _theme_config.secondary_text_color, _theme_config.small_font_size)
			ship_label.tooltip_text = _assembly_tooltip(catalog, assemblies[ship_id], 0.0)
			ship_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ship_row.add_child(ship_label)

			var disassemble := Button.new()
			disassemble.text = "ZERLEGEN"
			disassemble.pressed.connect(func():
				_ship_manager.disassemble_ship(source, ship_id)
				populate_builder_dynamic(state, on_refresh_callback)
			)
			ship_row.add_child(disassemble)

			var launch := Button.new()
			var assembly: ShipAssembly = assemblies[ship_id] as ShipAssembly
			if assembly == null:
				continue
			var assembly_role: StringName = assembly.role
			launch.text = "KOLONISIEREN" if assembly_role == &"colony" else "STARTEN"
			var launch_destination: Planet = _first_ship_destination(source, assembly_role)
			launch.disabled = launch_destination == null
			launch.tooltip_text = "Kein zulässiges Ziel verfügbar." if launch_destination == null else "Ziel: %s" % launch_destination.name
			launch.pressed.connect(func():
				var dest: Planet = _first_ship_destination(source, assembly_role)
				if dest != null:
					_ship_manager.dispatch_ship(source, dest, ship_id, assembly_role)
				populate_builder_dynamic(state, on_refresh_callback)
			)
			ship_row.add_child(launch)
			builder_dynamic.add_child(ship_row)

func update_countdowns(state: Node, on_refresh_callback: Callable) -> void:
	if state == null or _ship_manager == null:
		return
	var source: Planet = selected_option_planet(builder_source)
	if source == null:
		return
	var build_jobs: Dictionary = state.get_ship_build_jobs(source.planet_id)
	for ship_id_value in builder_job_labels:
		var ship_id: StringName = ship_id_value as StringName
		if not state.ship_build_in_progress(source.planet_id, ship_id) or not build_jobs.has(ship_id):
			if on_refresh_callback.is_valid():
				on_refresh_callback.call()
			return
		var job_label: Label = builder_job_labels[ship_id] as Label
		var job: ShipAssembly = build_jobs[ship_id] as ShipAssembly
		if job == null:
			continue
		var remaining: float = state.ship_build_remaining(source.planet_id, ship_id)
		job_label.text = "Montage läuft — %s (%.0f s · %d%%)" % [_assembly_role(job), remaining, _build_progress_percent(builder_job_progress.get(ship_id) as ProgressBar, remaining)]
		job_label.tooltip_text = _assembly_tooltip(_ship_manager.get_part_catalog(), job, remaining)
		var progress: ProgressBar = builder_job_progress.get(ship_id) as ProgressBar
		if progress != null and is_instance_valid(progress):
			var total_time: float = float(progress.get_meta("total_time", progress.max_value))
			progress.value = clampf(total_time - remaining, 0.0, progress.max_value)

func selected_option_planet(option: OptionButton) -> Planet:
	if option == null or option.selected < 0 or option.selected >= option.item_count:
		return null
	return option.get_item_metadata(option.selected) as Planet

func _builder_slot_option(inventory: Dictionary, slot_type: StringName, allow_none: bool = false) -> OptionButton:
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var catalog: ShipPartCatalog = _ship_manager.get_part_catalog()
	if allow_none:
		option.add_item("— (kein Modul)")
		option.set_item_metadata(0, &"")
	for part in catalog.for_slot(slot_type):
		if int(inventory.get(part.id, 0)) > 0:
			option.add_item(part.display_name)
			option.set_item_metadata(option.item_count - 1, part.id)
	option.disabled = option.item_count == 0
	return option

func _builder_selected_part(option: OptionButton) -> StringName:
	if option == null or option.selected < 0 or option.selected >= option.item_count:
		return &""
	var meta: Variant = option.get_item_metadata(option.selected)
	return meta as StringName if meta != null else &""

func _builder_can_assemble() -> bool:
	var source: Planet = selected_option_planet(builder_source)
	if source == null or builder_hull == null or builder_drive == null or builder_shield == null or builder_scanner == null:
		return false
	var hull_id := _builder_selected_part(builder_hull)
	var drive_id := _builder_selected_part(builder_drive)
	var shield_id := _builder_selected_part(builder_shield)
	var scanner_id := _builder_selected_part(builder_scanner)
	if String(hull_id).is_empty() or String(drive_id).is_empty() or String(shield_id).is_empty() or String(scanner_id).is_empty():
		return false
	var weapon_id := _builder_selected_part(builder_weapon)
	var module_ids: Array = []
	for option in builder_modules:
		var module_id := _builder_selected_part(option)
		if not String(module_id).is_empty():
			module_ids.append(module_id)
	return _ship_manager.can_assemble_ship(source, hull_id, scanner_id, module_ids, weapon_id, drive_id, shield_id)

func _on_assemble_ship(source: Planet, state: Node, on_refresh_callback: Callable) -> void:
	if source == null or builder_hull == null or builder_drive == null or builder_shield == null or builder_scanner == null:
		return
	var hull_id := _builder_selected_part(builder_hull)
	var drive_id := _builder_selected_part(builder_drive)
	var shield_id := _builder_selected_part(builder_shield)
	var scanner_id := _builder_selected_part(builder_scanner)
	var weapon_id := _builder_selected_part(builder_weapon)
	var module_ids: Array = []
	for option in builder_modules:
		var module_id := _builder_selected_part(option)
		if not String(module_id).is_empty():
			module_ids.append(module_id)
	_ship_manager.assemble_ship(source, hull_id, scanner_id, module_ids, weapon_id, drive_id, shield_id)
	populate_builder_dynamic(state, on_refresh_callback)

func _first_ship_destination(source: Planet, role: StringName) -> Planet:
	if source == null or _ship_manager == null:
		return null
	var destinations: Array[Planet] = _ship_manager.get_ship_destinations(source, role)
	return destinations[0] if not destinations.is_empty() else null

func _assembly_description(catalog: ShipPartCatalog, assembly: ShipAssembly) -> String:
	if assembly == null:
		return ""
	var hull := catalog.resolve(assembly.hull_id)
	var drive := catalog.resolve(assembly.drive_id)
	var weapon := catalog.resolve(assembly.weapon_id)
	var shield := catalog.resolve(assembly.shield_id)
	var scanner := catalog.resolve(assembly.scanner_id)
	var hull_name: String = hull.display_name if hull != null else String(assembly.hull_id)
	var drive_name: String = drive.display_name if drive != null else String(assembly.drive_id)
	var scanner_name: String = scanner.display_name if scanner != null else String(assembly.scanner_id)
	var shield_name: String = shield.display_name if shield != null else String(assembly.shield_id)
	var component_names: Array[String] = []
	if not hull_name.is_empty():
		component_names.append(hull_name)
	if not drive_name.is_empty():
		component_names.append(drive_name)
	if weapon != null:
		component_names.append(weapon.display_name)
	if not shield_name.is_empty():
		component_names.append(shield_name)
	if not scanner_name.is_empty():
		component_names.append(scanner_name)
	for module_id in assembly.module_ids:
		var module := catalog.resolve(module_id)
		component_names.append(module.display_name if module != null else String(module_id))
	return "%s · %s" % [_assembly_role(assembly), " + ".join(component_names)]

func _assembly_role(assembly: ShipAssembly) -> String:
	if assembly == null:
		return ""
	var role: String = String(assembly.role)
	if role == "military":
		return "MILITÄR"
	if role == "colony":
		return "KOLONIE"
	return role.to_upper()

func _assembly_build_time(catalog: ShipPartCatalog, assembly: ShipAssembly) -> float:
	if catalog == null or assembly == null:
		return 0.0
	var total_time := 0.0
	for slot_type in [ShipPartDefinition.SLOT_HULL, ShipPartDefinition.SLOT_DRIVE, ShipPartDefinition.SLOT_WEAPON, ShipPartDefinition.SLOT_SHIELD, ShipPartDefinition.SLOT_SCANNER]:
		var part: ShipPartDefinition = catalog.resolve(_assembly_part_id(assembly, slot_type))
		if part != null:
			total_time += part.build_time
	for module_id in assembly.module_ids:
		var module: ShipPartDefinition = catalog.resolve(module_id)
		if module != null:
			total_time += module.build_time
	return total_time

func _build_progress_percent(progress: ProgressBar, remaining: float) -> int:
	if progress == null or not is_instance_valid(progress):
		return 0
	var total_time: float = float(progress.get_meta("total_time", progress.max_value))
	if total_time <= 0.0:
		return 100
	return int(round(clampf((total_time - remaining) / total_time, 0.0, 1.0) * 100.0))

func _assembly_tooltip(catalog: ShipPartCatalog, assembly: ShipAssembly, remaining: float) -> String:
	if assembly == null:
		return ""
	var lines: Array[String] = []
	lines.append("Rolle: %s" % _assembly_role(assembly))
	for slot_type in [ShipPartDefinition.SLOT_HULL, ShipPartDefinition.SLOT_DRIVE, ShipPartDefinition.SLOT_WEAPON, ShipPartDefinition.SLOT_SHIELD, ShipPartDefinition.SLOT_SCANNER]:
		var part: ShipPartDefinition = catalog.resolve(_assembly_part_id(assembly, slot_type))
		if part == null:
			continue
		var variant: ShipComponentVariant = catalog.resolve_variant(part, assembly.variant_id_for(slot_type))
		var combined_trait: TraitDefinition = catalog.combined_trait(part, variant)
		var line: String = "%s: %s" % [String(slot_type).capitalize(), part.display_name]
		if variant != null:
			line += " / %s" % variant.display_name
		if combined_trait != null:
			line += " — %s" % combined_trait.display_name
		lines.append(line)
	var fleet := FleetSnapshot.new()
	fleet.faction = GameState.FACTION_PLAYER
	fleet.ships = [assembly.copy()]
	fleet.calculate_stats(catalog)
	lines.append("Stats: HP %.0f · DPS %.1f · Reichweite %.0f · Speed x%.2f" % [fleet.total_hull_hp, fleet.total_dps, fleet.effective_range, fleet.transfer_speed_multiplier()])
	if remaining > 0.0:
		lines.append("Montage verbleibend: %.1f s" % remaining)
	return "\n".join(lines)

func _assembly_part_id(assembly: ShipAssembly, slot_type: StringName) -> StringName:
	if assembly == null:
		return &""
	match slot_type:
		ShipPartDefinition.SLOT_HULL:
			return assembly.hull_id
		ShipPartDefinition.SLOT_DRIVE:
			return assembly.drive_id
		ShipPartDefinition.SLOT_WEAPON:
			return assembly.weapon_id
		ShipPartDefinition.SLOT_SHIELD:
			return assembly.shield_id
		ShipPartDefinition.SLOT_SCANNER:
			return assembly.scanner_id
	return &""

func _populate_scout_sources(option: OptionButton, planets: Array[Planet], state: Node) -> void:
	if option == null:
		return
	option.clear()
	for planet in planets:
		if planet == null:
			continue
		var player_owned: bool = state.faction_of(planet.planet_id) == GameState.FACTION_PLAYER
		var has_shipyard: bool = state.has_planet_upgrade(planet.planet_id, SHIPYARD_UPGRADE_ID)
		var has_starter: bool = state.get_starter_scouts(GameState.FACTION_PLAYER) > 0
		if player_owned and (has_shipyard or has_starter):
			option.add_item(planet.name)
			option.set_item_metadata(option.item_count - 1, planet)
	option.disabled = option.item_count == 0
