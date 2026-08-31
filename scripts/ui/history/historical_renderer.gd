@tool
class_name HistoricalRenderer
extends Node2D

## Rendert HistoricalSnapshots als echte Galaxy-Map:
## Planeten an realen Positionen, Navigations-Edges, Sterne,
## Fraktions-Embleme, Flotten-Marker, Kampf-Effekte.
##
## Kennt NUR HistoricalSnapshot + WorldConfig (Presentation-Boundary).

const FACTION_COLORS: Dictionary = {
    &"a": Color(0.35, 0.62, 0.95),
    &"b": Color(0.95, 0.45, 0.35),
    &"neutral": Color(0.75, 0.75, 0.75),
    &"": Color(0.45, 0.45, 0.45),
}

# These will be loaded in _ready
var planet_textures: Array[Texture2D] = []
var star_textures: Array[Texture2D] = []
var emblem_textures: Dictionary = {}
var fleet_marker: Texture2D
var bg_texture: Texture2D

var _planet_nodes: Dictionary = {}   # planet_id → Node2D
var _star_nodes: Array[Node2D] = []
var _edge_lines: Array[Line2D] = []
var _fleet_markers: Dictionary = {}  # planet_id → Node2D
var _world_config: WorldConfig
var _planet_positions: Dictionary = {}  # planet_id → Vector2

func _ready() -> void:
    # Load planet textures
    planet_textures = [
        load("res://assets/objects/planets/planet_01_ember.svg"),
        load("res://assets/objects/planets/planet_02_ocean.svg"),
        load("res://assets/objects/planets/planet_03_ice.svg"),
        load("res://assets/objects/planets/planet_04_violet.svg"),
        load("res://assets/objects/planets/planet_05_desert.svg"),
        load("res://assets/objects/planets/planet_06_toxic_red.svg"),
        load("res://assets/objects/planets/planet_07_storm.svg"),
        load("res://assets/objects/planets/planet_08_volcanic.svg"),
        load("res://assets/objects/planets/planet_09_paper.svg"),
        load("res://assets/objects/planets/planet_10_golden.svg"),
    ]
    # Load star textures
    star_textures = [
        load("res://assets/objects/stars/star_main_sequence.svg"),
        load("res://assets/objects/stars/star_red_giant.svg"),
        load("res://assets/objects/stars/star_blue_dwarf.svg"),
        load("res://assets/objects/stars/star_nebula_core.svg"),
    ]
    # Load emblem textures
    emblem_textures = {
        &"a": load("res://assets/ui/factions/faction_emblem_a.svg"),
        &"b": load("res://assets/ui/factions/faction_emblem_b.svg"),
        &"neutral": load("res://assets/ui/factions/faction_emblem_neutral.svg"),
    }
    fleet_marker = load("res://assets/ui/fleet/fleet_marker_player.svg")
    bg_texture = load("res://assets/ui/backgrounds/bg_deep_space.svg")

## Planet-Positionen aus dem echten Layout setzen (vor show_snapshot)
func set_planet_positions(positions: Dictionary) -> void:
    _planet_positions = positions.duplicate()

func set_world_config(config: WorldConfig) -> void:
    _world_config = config

func show_snapshot(snapshot: HistoricalSnapshot) -> void:
    if snapshot == null:
        return
    _render_background()
    _render_stars(snapshot)
    _render_edges(snapshot)
    _render_planets(snapshot)
    _render_fleet_markers(snapshot)

func _render_background() -> void:
    var bg: Sprite2D = get_node_or_null("Background") as Sprite2D
    if bg == null:
        bg = Sprite2D.new()
        bg.name = "Background"
        bg.texture = bg_texture
        bg.scale = Vector2(5.0, 5.0)
        bg.z_index = -100
        add_child(bg)

func _render_stars(_snapshot: HistoricalSnapshot) -> void:
    # Sterne an Cluster-Positionen (deterministisch aus Seed)
    # Placeholder: 5 Sterne in Ring-Layout
    for i in range(5):
        if i < _star_nodes.size():
            continue
        var star := Sprite2D.new()
        star.texture = star_textures[i % star_textures.size()]
        var angle := TAU * float(i) / 5.0
        star.position = Vector2(cos(angle), sin(angle)) * 400.0
        star.scale = Vector2.ONE * 0.4
        star.z_index = -50
        add_child(star)
        _star_nodes.append(star)

func _render_edges(_snapshot: HistoricalSnapshot) -> void:
    # Placeholder: Verbinde benachbarte Planeten
    pass

func _render_planets(snapshot: HistoricalSnapshot) -> void:
    for pid in snapshot.ownership:
        var node := _ensure_planet(pid as StringName)
        var pos: Vector2 = _planet_positions.get(pid, Vector2.ZERO)
        if pos == Vector2.ZERO:
            # Fallback: Ring-Layout
            var h := hash(pid)
            var angle := float(h % 360) * PI / 180.0
            pos = Vector2(cos(angle), sin(angle)) * 220.0
        node.position = pos
        var owner: StringName = snapshot.owner_of(pid as StringName)
        node.modulate = FACTION_COLORS.get(owner, FACTION_COLORS[&""]) as Color
        _apply_visual_state(node, snapshot.visual_state.get(pid, {}))
        node.visible = true
    # Planeten die nicht im Snapshot sind ausblenden
    for pid in _planet_nodes:
        if not snapshot.ownership.has(pid):
            (_planet_nodes[pid] as Node2D).visible = false

func _apply_visual_state(node: Node2D, state: Dictionary) -> void:
    var colony_level: int = int(state.get("colony_level", 0))
    var industry_level: int = int(state.get("industry_level", 0))
    var research_level: int = int(state.get("research_level", 0))
    var defense_level: int = int(state.get("defense_level", 0))
    # Faction Ring
    var ring: Line2D = node.get_node_or_null("FactionRing") as Line2D
    if ring == null:
        ring = Line2D.new()
        ring.name = "FactionRing"
        ring.width = 2.0
        var points := PackedVector2Array()
        for i in range(25):
            var angle := TAU * float(i) / 24.0
            points.append(Vector2(cos(angle), sin(angle)) * 34.0)
        ring.points = points
        node.add_child(ring)
    ring.visible = colony_level > 0
    # Development Label
    var details: Label = node.get_node_or_null("DevelopmentState") as Label
    if details == null:
        details = Label.new()
        details.name = "DevelopmentState"
        details.position = Vector2(-32, 38)
        details.add_theme_font_size_override("font_size", 8)
        node.add_child(details)
    details.text = "I%d R%d D%d" % [industry_level, research_level, defense_level]
    details.visible = colony_level > 0

func _render_fleet_markers(_snapshot: HistoricalSnapshot) -> void:
    pass

func _ensure_planet(planet_id: StringName) -> Node2D:
    if _planet_nodes.has(planet_id):
        return _planet_nodes[planet_id] as Node2D
    var node := Node2D.new()
    node.name = "Planet_" + String(planet_id)
    var sprite := Sprite2D.new()
    if planet_textures.size() > 0:
        sprite.texture = planet_textures[abs(hash(planet_id)) % planet_textures.size()]
    sprite.scale = Vector2.ONE * 0.8
    node.add_child(sprite)
    add_child(node)
    _planet_nodes[planet_id] = node
    return node

func planet_count() -> int:
    var count := 0
    for pid in _planet_nodes:
        if (_planet_nodes[pid] as Node2D).visible:
            count += 1
    return count