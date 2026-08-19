@tool
class_name FloatingText
extends Node2D

var _label: Label

func _ready() -> void:
	_ensure_label()

func _ensure_label() -> void:
	if _label == null:
		_label = Label.new()
		_label.name = "TextLabel"
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 14)
		_label.add_theme_constant_override("outline_size", 2)
		_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		add_child(_label)

static func spawn(parent: Node, text: String, start_pos: Vector2, color: Color = Color.WHITE, duration: float = 1.0) -> FloatingText:
	if parent == null:
		return null
	var ft := FloatingText.new()
	ft.position = start_pos
	parent.add_child(ft)
	ft._ensure_label()
	ft._label.text = text
	ft._label.add_theme_color_override("font_color", color)

	var tw: Tween = ft.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ft, "position:y", start_pos.y - 35.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ft, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ft.queue_free)
	return ft
