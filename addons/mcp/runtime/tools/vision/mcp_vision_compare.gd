extends RefCounted
class_name McpVisionCompare

## McpVisionCompare — Image diff, frame-change detection, stability wait, template matching.
## All methods are static. Called by McpVision facade.

const HISTOGRAM_BINS = 16


# ═══════════════════════════════════════════════════════════════
# Diff & Stability
# ═══════════════════════════════════════════════════════════════

static func image_diff(previous_img: Image, threshold: int, curr_img: Image) -> Dictionary:
	var safe_threshold := maxi(0, threshold)
	if previous_img == null or previous_img.is_empty():
		return {"error": "No previous image provided"}
	if curr_img == null or curr_img.is_empty():
		return {"error": "No current image provided — capture must happen at facade level"}

	var pw := previous_img.get_width()
	var ph := previous_img.get_height()
	var cw := curr_img.get_width()
	var ch := curr_img.get_height()

	if pw != cw or ph != ch:
		return {"error": "Image dimensions mismatch: %dx%d vs %dx%d" % [pw, ph, cw, ch]}

	var changed := 0
	var hot_x_min := cw
	var hot_x_max := 0
	var hot_y_min := ch
	var hot_y_max := 0

	var sample_step: int = maxi(1, mini(cw, ch) / 480)
	for y in range(0, ch, sample_step):
		for x in range(0, cw, sample_step):
			var pc := previous_img.get_pixel(x, y)
			var cc := curr_img.get_pixel(x, y)
			if not McpVisionHelpers.color_within(cc, pc, 0.02):
				changed += 1
				hot_x_min = mini(hot_x_min, x)
				hot_x_max = maxi(hot_x_max, x)
				hot_y_min = mini(hot_y_min, y)
				hot_y_max = maxi(hot_y_max, y)

	var stable := changed <= safe_threshold
	var hotspots := []
	if changed > 0:
		hotspots.append({
			"x": hot_x_min, "y": hot_y_min,
			"w": maxi(1, hot_x_max - hot_x_min + 1),
			"h": maxi(1, hot_y_max - hot_y_min + 1)
		})

	var sampled_total: int = maxi(1, int(ceil(float(cw * ch) / float(sample_step * sample_step))))
	return {
		"changed_pixels": changed,
		"total_pixels": sampled_total,
		"sample_step": sample_step,
		"change_ratio": float(changed) / float(sampled_total),
		"stable": stable,
		"hotspots": hotspots,
	}


static func frame_changed_since(previous_img: Image, threshold: int, curr_img: Image) -> Dictionary:
	var diff := image_diff(previous_img, threshold, curr_img)
	if diff.has("error"):
		return diff
	return {"changed": not diff.stable, "changed_pixels": diff.changed_pixels, "change_ratio": diff.change_ratio}


# ═══════════════════════════════════════════════════════════════
# Template Matching (NCC with histogram prefilter)
# ═══════════════════════════════════════════════════════════════

static func find_template(template_b64: String, threshold: float, search_rect: Dictionary,
		haystack_img: Image) -> Dictionary:
	return _find_template_internal(template_b64, threshold, search_rect, false, haystack_img)


static func find_template_all(template_b64: String, threshold: float, search_rect: Dictionary,
		haystack_img: Image) -> Dictionary:
	return _find_template_internal(template_b64, threshold, search_rect, true, haystack_img)


static func _find_template_internal(template_b64: String, threshold: float,
		search_rect: Dictionary, find_all: bool, haystack: Image) -> Dictionary:
	var needle := McpVisionHelpers.b64_to_image(template_b64)
	if not needle:
		return {"error": "Invalid template image"}

	if not haystack or haystack.is_empty():
		return {"error": "No haystack image provided — capture must happen at facade level"}

	var nw := needle.get_width()
	var nh := needle.get_height()
	var hw := haystack.get_width()
	var hh := haystack.get_height()

	if nw > hw or nh > hh:
		return {"found": false, "reason": "Template larger than screenshot"}
	var sr := McpVisionHelpers.resolve_search_rect(haystack, search_rect)
	var max_origin_x: int = int(sr.x) + int(sr.w) - nw
	var max_origin_y: int = int(sr.y) + int(sr.h) - nh
	if max_origin_x < sr.x or max_origin_y < sr.y:
		return {"found": false, "reason": "Search rectangle is smaller than template"}
	var needle_hist: Array = _build_histogram(needle)
	var coarse_step: int = maxi(2, mini(nw, nh) / 4)
	var candidates: Array = []

	var cy: int = sr.y
	while cy <= max_origin_y:
		var cx: int = sr.x
		while cx <= max_origin_x:
			var window_hist: Array = _build_histogram_region(haystack, cx, cy, nw, nh)
			var hist_sim: float = _histogram_similarity(needle_hist, window_hist)
			if hist_sim > 0.3:
				var ncc: float = _compute_ncc(haystack, needle, cx, cy, nw, nh)
				if ncc >= threshold:
					candidates.append({"x": cx, "y": cy, "confidence": ncc})
					if not find_all:
						break
			cx += coarse_step
		if not find_all and not candidates.is_empty():
			break
		cy += coarse_step

	if candidates.is_empty():
		return {"found": false, "matches": []}

	var refined: Array = []
	for cand in candidates:
		var cd: Dictionary = cand
		var best_ncc: float = cd.confidence
		var best_x: int = cd.x
		var best_y: int = cd.y
		var min_dy := maxi(-2, sr.y - int(cd.y))
		var max_dy := mini(2, max_origin_y - int(cd.y))
		var min_dx := maxi(-2, sr.x - int(cd.x))
		var max_dx := mini(2, max_origin_x - int(cd.x))
		for dy in range(min_dy, max_dy + 1):
			for dx in range(min_dx, max_dx + 1):
				if dx == 0 and dy == 0:
					continue
				var ncc: float = _compute_ncc(haystack, needle, cd.x + dx, cd.y + dy, nw, nh)
				if ncc > best_ncc:
					best_ncc = ncc
					best_x = cd.x + dx
					best_y = cd.y + dy
		refined.append({"x": best_x, "y": best_y, "confidence": best_ncc, "w": nw, "h": nh})

	refined.sort_custom(func(a, b): return a.confidence > b.confidence)

	if find_all and refined.size() > 1:
		var deduped: Array = []
		for m in refined:
			var md: Dictionary = m
			var overlaps: bool = false
			for d in deduped:
				var dd: Dictionary = d
				if abs(md.x - dd.x) < nw / 2 and abs(md.y - dd.y) < nh / 2:
					overlaps = true
					break
			if not overlaps:
				deduped.append(md)
		refined = deduped

	var best: Dictionary = refined[0]
	return {"found": true, "x": best.x, "y": best.y, "confidence": best.confidence, "w": best.w, "h": best.h, "matches": refined}


# ═══════════════════════════════════════════════════════════════
# NCC Internals
# ═══════════════════════════════════════════════════════════════

static func _compute_ncc(haystack: Image, needle: Image, ox: int, oy: int, nw: int, nh: int) -> float:
	var n_sum := 0.0
	var hs_sum := 0.0
	var pixel_count := nw * nh

	for y in nh:
		for x in nw:
			var nc := needle.get_pixel(x, y)
			var hc := haystack.get_pixel(ox + x, oy + y)
			n_sum += nc.r + nc.g + nc.b
			hs_sum += hc.r + hc.g + hc.b

	var n_mean := n_sum / (pixel_count * 3.0)
	var hs_mean := hs_sum / (pixel_count * 3.0)

	var numerator := 0.0
	var denom_n := 0.0
	var denom_hs := 0.0

	for y in nh:
		for x in nw:
			var nc := needle.get_pixel(x, y)
			var hc := haystack.get_pixel(ox + x, oy + y)
			var nd := (nc.r + nc.g + nc.b) / 3.0 - n_mean
			var hd := (hc.r + hc.g + hc.b) / 3.0 - hs_mean
			numerator += nd * hd
			denom_n += nd * nd
			denom_hs += hd * hd

	var denom := sqrt(denom_n * denom_hs)
	if denom < 0.0001:
		return 0.0
	return numerator / denom


static func _build_histogram(img: Image) -> Array:
	var hist := []
	for i in HISTOGRAM_BINS:
		hist.append(0.0)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var lum := (c.r + c.g + c.b) / 3.0
			var bin := mini(int(lum * HISTOGRAM_BINS), HISTOGRAM_BINS - 1)
			hist[bin] += 1.0
	var total := float(img.get_width() * img.get_height())
	if total > 0:
		for i in HISTOGRAM_BINS:
			hist[i] /= total
	return hist


static func _build_histogram_region(img: Image, ox: int, oy: int, w: int, h: int) -> Array:
	var hist := []
	for i in HISTOGRAM_BINS:
		hist.append(0.0)
	var iw := img.get_width()
	var ih := img.get_height()
	var total := 0
	for y in range(oy, mini(oy + h, ih)):
		for x in range(ox, mini(ox + w, iw)):
			var c := img.get_pixel(x, y)
			var lum := (c.r + c.g + c.b) / 3.0
			var bin := mini(int(lum * HISTOGRAM_BINS), HISTOGRAM_BINS - 1)
			hist[bin] += 1.0
			total += 1
	if total > 0:
		for i in HISTOGRAM_BINS:
			hist[i] /= float(total)
	return hist


static func _histogram_similarity(h1: Array, h2: Array) -> float:
	var intersection := 0.0
	for i in HISTOGRAM_BINS:
		intersection += mini(h1[i], h2[i])
	return intersection