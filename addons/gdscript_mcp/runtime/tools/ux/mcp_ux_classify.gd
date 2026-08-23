extends RefCounted
class_name McpUxClassify

## McpUxClassify — Classify candidate rectangles into UI element types.
## Thresholds tunable via constants. All methods static.

# Thresholds
const BUTTON_MIN_W = 80
const BUTTON_MAX_W = 400
const BUTTON_MIN_H = 28
const BUTTON_MAX_H = 80
const BUTTON_ASPECT_MIN = 2.0
const BUTTON_ASPECT_MAX = 18.0
const LABEL_MIN_W = 40
const LABEL_MAX_H = 30
const PANEL_MIN_SIZE = 100

const ELEMENT_BUTTON = 1
const ELEMENT_LABEL = 2
const ELEMENT_PANEL = 3
const ELEMENT_INPUT = 4
const ELEMENT_TEXT = 5
const ELEMENT_ICON = 6
const ELEMENT_SEPARATOR = 7
const ELEMENT_UNKNOWN = 0


static func classify(img: Image, rect: Dictionary, text_regions: Array) -> Dictionary:
	var rw: int = rect.w
	var rh: int = rect.h
	var aspect = float(rw) / float(rh) if rh > 0 else 0.0

	if rw < 10 or rh < 10:
		return {"type": ELEMENT_UNKNOWN, "rect": rect, "center": {"x": rect.x + rw/2, "y": rect.y + rh/2}, "confidence": 0.0}
	if rw > img.get_width() * 0.95 and rh > img.get_height() * 0.95:
		return {"type": ELEMENT_UNKNOWN, "rect": rect, "center": {"x": rect.x + rw/2, "y": rect.y + rh/2}, "confidence": 0.0}

	var dom = McpVisionDetect._dominant_color_in_rect(img, rect.x, rect.y, rw, rh)
	var uniformity = McpUxText.compute_uniformity(img, rect)
	var center = {"x": rect.x + rw / 2, "y": rect.y + rh / 2}

	var text_inside = 0
	for tr in text_regions:
		var trd = tr as Dictionary
		if _rect_overlaps(rect, trd) or _rect_contains(rect, trd):
			text_inside += 1

	var label_hint = McpUxText.read_text_hint(img, rect)

	# BUTTON
	if rw >= BUTTON_MIN_W and rw <= BUTTON_MAX_W and rh >= BUTTON_MIN_H and rh <= BUTTON_MAX_H and aspect >= BUTTON_ASPECT_MIN:
		var btn = 0.0
		btn += McpUxGeometry.score_range(aspect, 2.5, 8.0, 0.3)
		btn += McpUxGeometry.score_range(rh, 35, 60, 0.3)
		btn += McpUxGeometry.score_bool(text_inside > 0, 0.2)
		btn += McpUxGeometry.score_range(uniformity, 0.5, 1.0, 0.2)
		if btn >= 0.4:
			return {"type": ELEMENT_BUTTON, "rect": rect, "center": center, "confidence": clampf(btn, 0.0, 1.0), "label_hint": label_hint, "uniformity": uniformity, "dominant_color": McpVisionHelpers.color_to_hex(dom), "interactable": true}

	# LABEL
	if rw >= LABEL_MIN_W and rh <= LABEL_MAX_H and text_inside > 0:
		var lbl = 0.0
		lbl += McpUxGeometry.score_bool(text_inside > 0, 0.5)
		lbl += McpUxGeometry.score_bool(rh <= 25, 0.25)
		lbl += McpUxGeometry.score_range(aspect, 3.0, 20.0, 0.25)
		if lbl >= 0.4:
			return {"type": ELEMENT_LABEL, "rect": rect, "center": center, "confidence": clampf(lbl, 0.0, 1.0), "label_hint": label_hint, "uniformity": uniformity, "dominant_color": McpVisionHelpers.color_to_hex(dom), "interactable": false}

	# PANEL
	if rw >= PANEL_MIN_SIZE and rh >= PANEL_MIN_SIZE:
		var pnl = 0.0
		pnl += McpUxGeometry.score_bool(rw > 150 and rh > 150, 0.4)
		pnl += McpUxGeometry.score_range(uniformity, 0.4, 0.9, 0.4)
		pnl += McpUxGeometry.score_range(aspect, 0.5, 4.0, 0.2)
		if pnl >= 0.35:
			return {"type": ELEMENT_PANEL, "rect": rect, "center": center, "confidence": clampf(pnl, 0.0, 1.0), "label_hint": label_hint, "uniformity": uniformity, "dominant_color": McpVisionHelpers.color_to_hex(dom), "interactable": false}

	# INPUT
	if rw >= 100 and rw <= 400 and rh >= 24 and rh <= 50 and text_inside <= 1 and aspect > 3.0 and uniformity > 0.7:
		return {"type": ELEMENT_INPUT, "rect": rect, "center": center, "confidence": 0.55, "label_hint": label_hint, "uniformity": uniformity, "dominant_color": McpVisionHelpers.color_to_hex(dom), "interactable": true}

	# TEXT_BLOCK
	if text_inside > 0 and rh > 15 and rh < 200:
		return {"type": ELEMENT_TEXT, "rect": rect, "center": center, "confidence": 0.4, "label_hint": label_hint, "uniformity": uniformity, "dominant_color": McpVisionHelpers.color_to_hex(dom), "interactable": false}

	return {"type": ELEMENT_UNKNOWN, "rect": rect, "center": center, "confidence": 0.0, "uniformity": uniformity}


static func _rect_overlaps(a: Dictionary, b: Dictionary) -> bool:
	return (a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y)

static func _rect_contains(outer: Dictionary, inner: Dictionary) -> bool:
	return (inner.x >= outer.x and inner.y >= outer.y and inner.x + inner.w <= outer.x + outer.w and inner.y + inner.h <= outer.y + outer.h)