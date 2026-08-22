class_name CaptureDecisionOverlay
extends CanvasLayer

## Post-combat decision UI: the victorious player chooses between adopting,
## looting or neutralizing the defeated planet.

signal capture_decision_made(decision: StringName)

const DECISION_ADOPT := &"adopt"
const DECISION_LOOT := &"loot"
const DECISION_NEUTRALIZE := &"neutralize"

const DEFAULT_TRANSFORMER_CONFIG: TransformerConfig = preload("res://resources/config/transformer_default.tres")

var _root: Control

func present(planet: Planet = null) -> void:
	layer = 90
	if _root == null:
		_build_ui(planet)
	visible = true

func _build_ui(planet: Planet = null) -> void:
	_root = Control.new()
	_root.name = "RootControl"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(360.0, 220.0)
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for edge in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		margin.add_theme_constant_override(edge, 16)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "PLANET BESIEGT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)

	var subtitle := Label.new()
	if planet != null and not planet.display_name.is_empty() and planet.display_name != String(planet.name):
		subtitle.text = "Wie soll mit %s verfahren werden?" % planet.display_name
	else:
		subtitle.text = "Wie soll mit dem Planeten verfahren werden?"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 14)
	column.add_child(subtitle)

	column.add_child(_decision_button("ÜBERNEHMEN", DECISION_ADOPT, "Behalte den Planeten und seine Gebäude."))
	column.add_child(_decision_button("AUSRAUBEN", DECISION_LOOT, "Plündere lokale Vorräte, beschädige Gebäude."))
	column.add_child(_decision_button("NEUTRALISIEREN", DECISION_NEUTRALIZE, "10-Minuten-Neutralisierung, Gebäude werden entfernt."))

func _decision_button(text: String, decision: StringName, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.pressed.connect(Callable(self, "_on_decision_pressed").bind(decision))
	return button

func _on_decision_pressed(decision: StringName) -> void:
	visible = false
	capture_decision_made.emit(decision)
