class_name SectorAnchor
extends RefCounted

## Runtime anchor produced by SectorClassifier.generate_anchors(). Pure data —
## not a Resource, not a Node.

var position: Vector2 = Vector2.ZERO
var radius: float = 100.0
var flavor: SectorFlavor
var seed_offset: int = 0
