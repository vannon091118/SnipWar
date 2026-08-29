class_name HistoricalRenderer
extends Node2D

## Rendert HistoricalSnapshots als Node2D-Baum: ein Planet-Knoten je Planet
## mit SVG-Textur und Fraktionsfarbe (Presentation-Schicht, §14).
##
## Kennt NUR HistoricalSnapshot — keinen Simulator, keine Narrative-Regeln.
## Das Layout ist deterministisch aus der Planet-ID abgeleitet (Ring-Layout),
## damit derselbe Snapshot immer dasselbe Bild ergibt.

const PLANET_TEXTURES: Array[Texture2D] = [
	preload("res://assets/objects/planets/planet_01_ember.svg"),
	preload("res://assets/objects/planets/planet_02_ocean.svg"),
	preload("res://assets/objects/planets/planet_03_ice.svg"),
	preload("res://assets/objects/planets/planet_05_desert.svg"),
]

const FACTION_COLORS: Dictionary = {
	&"a": Color(0.35, 0.62, 0.95),
	&"b": Color(0.95, 0.45, 0.35),
	&"neutral": Color(0.75, 0.75, 0.75),
	&"": Color(0.45, 0.45, 0.45),
}

const RING_RADIUS := 220.0
const PLANET_SCALE := 0.9

var _planet_nodes: Dictionary = {}  # planet_id → Node2D


func show_snapshot(snapshot: HistoricalSnapshot) -> void:
	if snapshot == null:
		return
	for pid in snapshot.ownership:
		var node := _ensure_planet(pid as StringName)
		var owner: StringName = snapshot.owner_of(pid as StringName)
		node.position = _layout_position(pid as StringName)
		node.modulate = FACTION_COLORS.get(owner, FACTION_COLORS[&""]) as Color
		node.visible = true
	# Planeten, die im aktuellen Snapshot nicht mehr existieren, ausblenden.
	for pid in _planet_nodes:
		if not snapshot.ownership.has(pid):
			(_planet_nodes[pid] as Node2D).visible = false


func planet_count() -> int:
	var count := 0
	for pid in _planet_nodes:
		if (_planet_nodes[pid] as Node2D).visible:
			count += 1
	return count


func _ensure_planet(planet_id: StringName) -> Node2D:
	if _planet_nodes.has(planet_id):
		return _planet_nodes[planet_id] as Node2D
	var node := Node2D.new()
	node.name = "Planet_" + String(planet_id)
	var sprite := Sprite2D.new()
	sprite.texture = PLANET_TEXTURES[abs(hash(planet_id)) % PLANET_TEXTURES.size()]
	sprite.scale = Vector2.ONE * PLANET_SCALE
	node.add_child(sprite)
	add_child(node)
	_planet_nodes[planet_id] = node
	return node


func _layout_position(planet_id: StringName) -> Vector2:
	var h := hash(planet_id)
	var angle := float(h % 360) * PI / 180.0
	return Vector2(cos(angle), sin(angle)) * RING_RADIUS