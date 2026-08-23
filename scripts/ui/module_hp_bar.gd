class_name ModuleHpBar
extends Control

## Compact segmented module-HP bar rendered above ships (L2) and ship-based
## minions (L3). One segment per mounted module, sized by its influence share
## of the pool; segments shrink on TYPE_MODULE_HIT, gray out on
## TYPE_MODULE_DESTROYED and refill (up to their max) on TYPE_REPAIR. Pure
## CanvasItem drawing, no external assets.

const BAR_WIDTH := 64.0
const BAR_HEIGHT := 5.0

const COLOR_ALIVE := Color(0.35, 0.85, 0.4)
const COLOR_DAMAGED := Color(0.95, 0.8, 0.3)
const COLOR_CRITICAL := Color(0.95, 0.35, 0.3)
const COLOR_DESTROYED := Color(0.25, 0.25, 0.28)
const COLOR_BACKDROP := Color(0.0, 0.0, 0.0, 0.55)

## Segment payloads: {part_id, slot_type, max_hp, hp}.
var _segments: Array[Dictionary] = []


func _init() -> void:
	custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT + 2.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Seeds the segments from FleetSnapshot module payloads (max_hp per module).
func setup(module_states: Array) -> void:
	_segments.clear()
	for mod in module_states:
		if mod == null:
			continue
		var max_hp := maxf(float(mod.get("max_hp", 1.0)), 0.001)
		_segments.append({
			"part_id": mod.get("part_id", &"") as StringName,
			"slot_type": mod.get("slot_type", &"") as StringName,
			"max_hp": max_hp,
			"hp": max_hp,
		})
	queue_redraw()


func is_empty() -> bool:
	return _segments.is_empty()


## Damages the first alive segment matching the part (the replay does not
## carry the module instance index, so first-match is the visual contract).
func apply_hit(part_id: StringName, amount: float) -> void:
	if amount <= 0.0:
		return
	for seg in _segments:
		if seg.get("part_id", &"") == part_id and float(seg.get("hp", 0.0)) > 0.0:
			seg["hp"] = maxf(0.0, float(seg.get("hp", 0.0)) - amount)
			break
	queue_redraw()


func destroy_module(part_id: StringName) -> void:
	for seg in _segments:
		if seg.get("part_id", &"") == part_id:
			seg["hp"] = 0.0
			break
	queue_redraw()


## Repair events carry only the total healed amount; refill the most damaged
## segments first so the bar converges toward the tier cap.
func heal_total(amount: float) -> void:
	if amount <= 0.0:
		return
	var remaining := amount
	while remaining > 0.01:
		var best: Dictionary = {}
		var best_deficit := 0.0
		for seg in _segments:
			var deficit: float = float(seg.get("max_hp", 0.0)) - float(seg.get("hp", 0.0))
			if deficit > best_deficit:
				best = seg
				best_deficit = deficit
		if best.is_empty() or best_deficit <= 0.0:
			break
		var applied := minf(best_deficit, remaining)
		best["hp"] = float(best.get("hp", 0.0)) + applied
		remaining -= applied
	queue_redraw()


func _draw() -> void:
	if _segments.is_empty():
		return
	var total_max := 0.0
	for seg in _segments:
		total_max += float(seg.get("max_hp", 0.0))
	if total_max <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(BAR_WIDTH, BAR_HEIGHT)), COLOR_BACKDROP)
	var x := 0.0
	for seg in _segments:
		var max_hp := float(seg.get("max_hp", 0.0))
		var hp := float(seg.get("hp", 0.0))
		var width := BAR_WIDTH * max_hp / total_max
		var fraction := hp / max_hp
		var color := COLOR_DESTROYED
		if fraction > 0.5:
			color = COLOR_ALIVE
		elif fraction > 0.25:
			color = COLOR_DAMAGED
		elif fraction > 0.0:
			color = COLOR_CRITICAL
		draw_rect(Rect2(Vector2(x, 0.0), Vector2(maxf(width - 1.0, 1.0), BAR_HEIGHT)), color)
		x += width
