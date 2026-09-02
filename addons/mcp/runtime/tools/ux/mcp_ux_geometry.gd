extends RefCounted
class_name McpUxGeometry

## McpUxGeometry — Rectangle math, grouping, and scoring helpers.
## All methods static. Extracted from McpUxPipeline.

static func resolve_rect(r: Dictionary, max_w: int, max_h: int) -> Dictionary:
	return {
		"x": clampi(int(r.get("x", 0)), 0, max_w - 1),
		"y": clampi(int(r.get("y", 0)), 0, max_h - 1),
		"w": clampi(int(r.get("w", max_w)), 1, max_w),
		"h": clampi(int(r.get("h", max_h)), 1, max_h),
	}

static func rect_copy(r: Dictionary) -> Dictionary:
	return {"x": r.x, "y": r.y, "w": r.w, "h": r.h}

static func rects_overlap(a: Dictionary, b: Dictionary) -> bool:
	return (a.x < b.x + b.w and a.x + a.w > b.x
			and a.y < b.y + b.h and a.y + a.h > b.y)

static func rect_contains(outer: Dictionary, inner: Dictionary) -> bool:
	return (inner.x >= outer.x and inner.y >= outer.y
			and inner.x + inner.w <= outer.x + outer.w
			and inner.y + inner.h <= outer.y + outer.h)

static func rects_nearby(a: Dictionary, b: Dictionary, sw: int, sh: int, margin: int) -> bool:
	var ax = maxi(0, a.x - margin)
	var ay = maxi(0, a.y - margin)
	var aw = mini(sw, a.w + 2 * margin)
	var ah = mini(sh, a.h + 2 * margin)
	return rects_overlap({"x": ax, "y": ay, "w": aw, "h": ah}, b)

static func bounds_extend(bounds: Dictionary, other: Dictionary) -> void:
	var nx = mini(bounds.x, other.x)
	var ny = mini(bounds.y, other.y)
	bounds.x = nx
	bounds.y = ny
	bounds.w = maxi(bounds.x + bounds.w, other.x + other.w) - nx
	bounds.h = maxi(bounds.y + bounds.h, other.y + other.h) - ny

static func score_range(value: float, ideal_min: float, ideal_max: float, weight: float) -> float:
	var ideal_center = (ideal_min + ideal_max) / 2.0
	var ideal_width = (ideal_max - ideal_min) / 2.0
	var dist = abs(value - ideal_center)
	var score = 1.0 - (dist / maxi(1.0, ideal_width))
	return weight * clampf(score, 0.0, 1.0)

static func score_bool(condition: bool, weight: float) -> float:
	return weight if condition else 0.0

static func type_name(t: int) -> String:
	match t:
		1: return "button"
		2: return "label"
		3: return "panel"
		4: return "input_field"
		5: return "text_block"
		6: return "icon"
		7: return "separator"
		_: return "unknown"


static func group_elements(elements: Array, screen_w: int, screen_h: int) -> Array:
	if elements.is_empty():
		return []

	var groups: Array = []
	var remaining: Array = elements.duplicate()

	while not remaining.is_empty():
		var seed: Dictionary = remaining.pop_front()
		var group = {"bounds": rect_copy(seed.rect), "elements": [seed]}
		var type_counts = {}
		type_counts[type_name(seed.type)] = 1

		var changed = true
		while changed:
			changed = false
			for i in range(remaining.size() - 1, -1, -1):
				var el: Dictionary = remaining[i]
				if rects_nearby(group.bounds, el.rect, screen_w, screen_h, 30):
					bounds_extend(group.bounds, el.rect)
					group.elements.append(el)
					var tn = type_name(el.type)
					type_counts[tn] = type_counts.get(tn, 0) + 1
					remaining.remove_at(i)
					changed = true

		var dominant_type = ""
		var dominant_count = 0
		for tn in type_counts:
			if type_counts[tn] > dominant_count:
				dominant_count = type_counts[tn]
				dominant_type = tn

		group["dominant_type"] = dominant_type
		group["element_count"] = group.elements.size()
		groups.append(group)

	groups.sort_custom(func(a, b): return (a.bounds.w * a.bounds.h) > (b.bounds.w * b.bounds.h))
	return groups