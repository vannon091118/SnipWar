class_name ChronicleArchiveView
extends Control

## ChronicleArchiveView — Vollwertiges Pergament-Dossier für die Weltgeschichte.
## Bietet 3 Tabs:
##   [1] WELTCHRONIK: Chronologischer Ereignis-Feed mit Epochen-, Typ- & Wichtigkeitsfiltern
##   [2] MACHTGEFÜGE: Fraktions-Statuskarten & gerichtete Beziehungsmatrix
##   [3] PERSÖNLICHKEITEN: Historische Figuren-Biografien, Karriere-Meilensteine & Auszeichnungen

const DEFAULT_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

enum TabMode { CHRONICLE, RELATIONS, FIGURES }

var _theme: UIThemeConfig = DEFAULT_THEME
var _chronicle_save: ChronicleSaveData
var _chronicle_node: Node
var _current_tab: TabMode = TabMode.CHRONICLE

# UI-Referenzen
var _tab_buttons: HBoxContainer
var _content_body: MarginContainer

# Tab 1: Chronik
var _chronicle_container: VBoxContainer
var _era_filter: OptionButton
var _importance_filter: OptionButton
var _faction_filter: OptionButton
var _events_scroll: ScrollContainer
var _events_vbox: VBoxContainer

# Tab 2: Machtgefüge
var _relations_container: VBoxContainer

# Tab 3: Persönlichkeiten
var _figures_container: HSplitContainer
var _figure_list_vbox: VBoxContainer
var _figure_detail_vbox: VBoxContainer
var _selected_char_id: StringName = &""


func setup(theme_config: UIThemeConfig = null) -> void:
	_theme = theme_config if theme_config != null else DEFAULT_THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func populate(chronicle_source: Variant = null) -> void:
	if chronicle_source is ChronicleSaveData:
		_chronicle_save = chronicle_source
	elif chronicle_source is Node:
		_chronicle_node = chronicle_source
		if chronicle_source.has_method("get_save"):
			_chronicle_save = chronicle_source.get_save()
	elif _chronicle_save == null:
		# Fallback: Versuche Autoload
		var root: Node = Engine.get_main_loop().root if Engine.get_main_loop() != null else null
		if root != null:
			var auto: Node = root.get_node_or_null("WorldChronicle")
			if auto != null:
				_chronicle_node = auto
				if auto.has_method("get_save"):
					_chronicle_save = auto.get_save()

	_rebuild_active_tab()


func _build_ui() -> void:
	var main_vbox := VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 12)
	add_child(main_vbox)

	# 1. Tab Bar
	_tab_buttons = HBoxContainer.new()
	_tab_buttons.name = "TabBar"
	_tab_buttons.add_theme_constant_override("separation", 10)
	main_vbox.add_child(_tab_buttons)

	var tab_names: Array[String] = ["[1] WELTCHRONIK", "[2] MACHTGEFÜGE & DIPLOMATIE", "[3] PERSÖNLICHKEITEN"]
	for i in range(tab_names.size()):
		var btn := Button.new()
		btn.text = tab_names[i]
		btn.custom_minimum_size = Vector2(210, 38)
		btn.pressed.connect(_switch_tab.bind(i as TabMode))
		_tab_buttons.add_child(btn)

	# 2. Content Host
	_content_body = MarginContainer.new()
	_content_body.name = "ContentBody"
	_content_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(_content_body)


func _switch_tab(mode: TabMode) -> void:
	_current_tab = mode
	_rebuild_active_tab()


func _rebuild_active_tab() -> void:
	# Bestehenden Inhalt leeren
	for child in _content_body.get_children():
		_content_body.remove_child(child)
		child.queue_free()

	if _chronicle_save == null:
		var empty_lbl := Label.new()
		empty_lbl.text = "Keine historischen Aufzeichnungen verfügbar. Bitte starten Sie eine Simulation."
		_content_body.add_child(empty_lbl)
		return

	match _current_tab:
		TabMode.CHRONICLE:
			_build_chronicle_tab()
		TabMode.RELATIONS:
			_build_relations_tab()
		TabMode.FIGURES:
			_build_figures_tab()


# =============================================================================
# TAB 1: WELTCHRONIK
# =============================================================================

func _build_chronicle_tab() -> void:
	_chronicle_container = VBoxContainer.new()
	_chronicle_container.add_theme_constant_override("separation", 10)
	_content_body.add_child(_chronicle_container)

	# Filterleiste
	var filter_bar := HBoxContainer.new()
	filter_bar.add_theme_constant_override("separation", 16)
	_chronicle_container.add_child(filter_bar)

	# Epochen-Filter
	var era_lbl := Label.new()
	era_lbl.text = "Epoche:"
	filter_bar.add_child(era_lbl)
	_era_filter = OptionButton.new()
	_era_filter.add_item("Alle Epochen", 0)
	for i in range(_chronicle_save.eras.size()):
		var era: Dictionary = _chronicle_save.eras[i]
		_era_filter.add_item(str(era.get("name", "Epoche %d" % i)), i + 1)
	_era_filter.item_selected.connect(func(_idx): _refresh_events_list())
	filter_bar.add_child(_era_filter)

	# Wichtigkeits-Filter
	var imp_lbl := Label.new()
	imp_lbl.text = "Relevanz:"
	filter_bar.add_child(imp_lbl)
	_importance_filter = OptionButton.new()
	_importance_filter.add_item("Alle Ereignisse", 0)
	_importance_filter.add_item("Bedeutend (Normal+)", 1)
	_importance_filter.add_item("Nur Wendepunkte", 2)
	_importance_filter.item_selected.connect(func(_idx): _refresh_events_list())
	filter_bar.add_child(_importance_filter)

	# Fraktions-Filter
	var fac_lbl := Label.new()
	fac_lbl.text = "Fraktion:"
	filter_bar.add_child(fac_lbl)
	_faction_filter = OptionButton.new()
	_faction_filter.add_item("Alle Fraktionen", 0)
	var faction_ids: Array[StringName] = _chronicle_save.faction_ids()
	for faction_index in range(faction_ids.size()):
		_faction_filter.add_item(String(faction_ids[faction_index]).capitalize(), faction_index + 1)
	_faction_filter.item_selected.connect(func(_idx): _refresh_events_list())
	filter_bar.add_child(_faction_filter)

	# Scroll Container für Events
	_events_scroll = ScrollContainer.new()
	_events_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chronicle_container.add_child(_events_scroll)

	_events_vbox = VBoxContainer.new()
	_events_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_events_vbox.add_theme_constant_override("separation", 8)
	_events_scroll.add_child(_events_vbox)

	_refresh_events_list()


func _refresh_events_list() -> void:
	if _events_vbox == null or _chronicle_save == null:
		return

	for child in _events_vbox.get_children():
		_events_vbox.remove_child(child)
		child.queue_free()

	var events: Array[HistoryEvent] = _chronicle_save.all_events()

	# Epochen-Filter
	var era_idx: int = _era_filter.selected
	if era_idx > 0 and era_idx - 1 < _chronicle_save.eras.size():
		var era: Dictionary = _chronicle_save.eras[era_idx - 1]
		var sy: int = int(era.get("start_year", -9999))
		var ey: int = int(era.get("end_year", 9999))
		events = events.filter(func(e): return e.year >= sy and e.year <= ey)

	# Wichtigkeits-Filter
	var imp_idx: int = _importance_filter.selected
	if imp_idx == 1:
		events = events.filter(func(e): return e.importance >= 0.40)
	elif imp_idx == 2:
		events = events.filter(func(e): return e.importance >= 0.70)

	# Fraktions-Filter
	var fac_idx: int = _faction_filter.selected
	if fac_idx > 0:
		var faction_ids: Array[StringName] = _chronicle_save.faction_ids()
		var faction_index: int = fac_idx - 1
		if faction_index < faction_ids.size():
			var selected_faction: StringName = faction_ids[faction_index]
			events = events.filter(func(e):
				return e.actors.has(selected_faction) or e.winner == selected_faction or e.loser == selected_faction
			)

	# Liste befüllen
	var count: int = 0
	for ev in events:
		if count > 150:
			break
		_events_vbox.add_child(_create_event_card(ev))
		count += 1


func _create_event_card(event: HistoryEvent) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	card.add_child(hbox)

	# Jahr
	var yr_lbl := Label.new()
	yr_lbl.text = "Jahr %4d" % event.year
	yr_lbl.custom_minimum_size = Vector2(85, 0)
	yr_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6))
	hbox.add_child(yr_lbl)

	# Typ-Pille
	var type_lbl := Label.new()
	type_lbl.text = "[%s]" % String(event.event_type).to_upper()
	type_lbl.custom_minimum_size = Vector2(120, 0)
	if event.is_conflict():
		type_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	elif event.is_diplomatic():
		type_lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 0.5))
	else:
		type_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	hbox.add_child(type_lbl)

	# Text & Details
	var desc_vbox := VBoxContainer.new()
	desc_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(desc_vbox)

	var text_lbl := Label.new()
	text_lbl.text = _resolve_event_text(event)
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_vbox.add_child(text_lbl)

	if not String(event.cause_event_id).is_empty():
		var cause_lbl := Label.new()
		cause_lbl.text = "↳ Ursache: Ref #%s" % String(event.cause_event_id)
		cause_lbl.add_theme_font_size_override("font_size", 11)
		cause_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		desc_vbox.add_child(cause_lbl)

	return card


func _resolve_event_text(event: HistoryEvent) -> String:
	if _chronicle_node != null and _chronicle_node.has_method("resolve_text"):
		return _chronicle_node.resolve_text(event)
	return event.trigger


# =============================================================================
# TAB 2: MACHTGEFÜGE & DIPLOMATIE
# =============================================================================

func _build_relations_tab() -> void:
	_relations_container = VBoxContainer.new()
	_relations_container.add_theme_constant_override("separation", 20)
	_content_body.add_child(_relations_container)

	var header_lbl := Label.new()
	header_lbl.text = "POLITISCHES GLEICHGEWICHT & BEZIEHUNGS-MATRIX (JAHR 0)"
	header_lbl.add_theme_font_size_override("font_size", 16)
	header_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	_relations_container.add_child(header_lbl)

	# Beziehungs-Karten
	var matrix_vbox := VBoxContainer.new()
	matrix_vbox.add_theme_constant_override("separation", 10)
	_relations_container.add_child(matrix_vbox)

	var factions: Array[StringName] = _chronicle_save.faction_ids()
	var rels: Dictionary = _chronicle_save.relationships

	for fid_a in factions:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		matrix_vbox.add_child(row)

		var from_lbl := Label.new()
		from_lbl.text = "%-16s gegenüber:" % String(fid_a).capitalize()
		from_lbl.custom_minimum_size = Vector2(220, 0)
		row.add_child(from_lbl)

		for fid_b in factions:
			if fid_a == fid_b:
				continue
			var key: String = "%s→%s" % [String(fid_a), String(fid_b)]
			var score: int = int(rels.get(key, 0))

			var rel_pill := Label.new()
			rel_pill.text = "%s: %+d" % [String(fid_b).capitalize(), score]
			rel_pill.custom_minimum_size = Vector2(160, 0)

			if score <= -40:
				rel_pill.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
			elif score < 0:
				rel_pill.add_theme_color_override("font_color", Color(0.9, 0.6, 0.4))
			elif score >= 30:
				rel_pill.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
			else:
				rel_pill.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))

			row.add_child(rel_pill)


# =============================================================================
# TAB 3: PERSÖNLICHKEITEN
# =============================================================================

func _build_figures_tab() -> void:
	_figures_container = HSplitContainer.new()
	_figures_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_figures_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_body.add_child(_figures_container)

	# Linke Spalte: Figuren-Liste
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(300, 0)
	_figures_container.add_child(left_scroll)

	_figure_list_vbox = VBoxContainer.new()
	_figure_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_figure_list_vbox.add_theme_constant_override("separation", 6)
	left_scroll.add_child(_figure_list_vbox)

	# Rechte Spalte: Figuren-Dossier
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_figures_container.add_child(right_scroll)

	_figure_detail_vbox = VBoxContainer.new()
	_figure_detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_figure_detail_vbox.add_theme_constant_override("separation", 12)
	right_scroll.add_child(_figure_detail_vbox)

	_populate_figures_list()


func _populate_figures_list() -> void:
	for child in _figure_list_vbox.get_children():
		_figure_list_vbox.remove_child(child)
		child.queue_free()

	var bios: Array[CharacterBiography] = _chronicle_save.biographies
	if bios.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Keine Figuren verzeichnet."
		_figure_list_vbox.add_child(empty_lbl)
		return

	for bio in bios:
		var btn := Button.new()
		var status_text: String = "lebt" if bio.is_alive() else "† %d" % bio.death_year
		btn.text = "%s (%s)\n%s | %s" % [bio.name, String(bio.faction).capitalize(), bio.current_rank, status_text]
		btn.custom_minimum_size = Vector2(0, 48)
		btn.pressed.connect(_show_figure_details.bind(bio.char_id))
		_figure_list_vbox.add_child(btn)

	if not bios.is_empty():
		_show_figure_details(bios[0].char_id)


func _show_figure_details(char_id: StringName) -> void:
	_selected_char_id = char_id
	for child in _figure_detail_vbox.get_children():
		_figure_detail_vbox.remove_child(child)
		child.queue_free()

	var bio: CharacterBiography = _chronicle_save.biography_for(char_id)
	if bio == null:
		return

	# Header
	var title_lbl := Label.new()
	title_lbl.text = "%s — %s (%s)" % [bio.name, bio.current_rank, String(bio.faction).capitalize()]
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	_figure_detail_vbox.add_child(title_lbl)

	# Lebensdaten
	var life_lbl := Label.new()
	var life_str: String = "Geboren: Jahr %d | " % bio.birth_year
	life_str += "Status: Noch im Dienst" if bio.is_alive() else "Verstorben: Jahr %d (%d Jahre alt)" % [bio.death_year, bio.lifetime_years()]
	life_lbl.text = life_str
	life_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_figure_detail_vbox.add_child(life_lbl)

	# Errungenschaften
	var ach_title := Label.new()
	ach_title.text = "HISTORISCHE ERRUNGENSCHAFTEN & MEILENSTEINE:"
	ach_title.add_theme_font_size_override("font_size", 14)
	ach_title.add_theme_color_override("font_color", Color(0.4, 0.85, 0.5))
	_figure_detail_vbox.add_child(ach_title)

	if bio.achievements.is_empty():
		var no_ach := Label.new()
		no_ach.text = "  (Keine besonderen Auszeichnungen verzeichnet)"
		_figure_detail_vbox.add_child(no_ach)
	else:
		for ach in bio.achievements:
			var ach_lbl := Label.new()
			ach_lbl.text = "  [+] %s" % ach
			_figure_detail_vbox.add_child(ach_lbl)

	# Fehlschläge / Schlachten
	var fail_title := Label.new()
	fail_title.text = "NIEDERLAGEN, VERWUNDUNGEN & SCHICKSALSSCHLÄGE:"
	fail_title.add_theme_font_size_override("font_size", 14)
	fail_title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	_figure_detail_vbox.add_child(fail_title)

	if bio.failures.is_empty():
		var no_fail := Label.new()
		no_fail.text = "  (Keine Niederlagen verzeichnet)"
		_figure_detail_vbox.add_child(no_fail)
	else:
		for fail in bio.failures:
			var fail_lbl := Label.new()
			fail_lbl.text = "  [-] %s" % fail
			_figure_detail_vbox.add_child(fail_lbl)
