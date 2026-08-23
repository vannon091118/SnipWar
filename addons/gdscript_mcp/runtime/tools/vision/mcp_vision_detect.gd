extends RefCounted
class_name McpVisionDetect

## McpVisionDetect — UI detection: edge rects, text regions, grid sampling, dominant color.
## All methods are static. Called by McpVision facade.


# ═══════════════════════════════════════════════════════════════
# Edge-Based Rect Detection
# ═══════════════════════════════════════════════════════════════

static func detect_rects(img: Image, edge_sensitivity: float = 0.15, min_size: int = 8) -> Dictionary:
	if not img or img.is_empty():
		return {"error": "No image"}

	var iw := img.get_width()
	var ih := img.get_height()

	# Edge maps
	var hedges: Array = []
	for y in ih:
		hedges.append([])
		for x in iw - 1:
			var c0: Color = img.get_pixel(x, y)
			var c1: Color = img.get_pixel(x + 1, y)
			var diff: float = abs(c0.r - c1.r) + abs(c0.g - c1.g) + abs(c0.b - c1.b)
			hedges[y].append(diff > edge_sensitivity)

	var vedges: Array = []
	for y in ih - 1:
		vedges.append([])
		for x in iw:
			var c0: Color = img.get_pixel(x, y)
			var c1: Color = img.get_pixel(x, y + 1)
			var diff: float = abs(c0.r - c1.r) + abs(c0.g - c1.g) + abs(c0.b - c1.b)
			vedges[y].append(diff > edge_sensitivity)

	var rects: Array = []
	var scan_step: int = 4
	var visited_rects: Dictionary = {}

	for y in range(0, ih - min_size, scan_step):
		for x in range(0, iw - min_size, scan_step):
			var has_top := false
			var has_bottom := false
			var has_left := false
			var has_right := false

			# Top edge
			var edge_count := 0
			for ex in range(x, mini(x + min_size * 2, iw - 1)):
				if hedges[y][ex]:
					edge_count += 1
			has_top = edge_count >= 2

			# Bottom edge
			var by := mini(y + min_size, ih - 1)
			if by < ih:
				edge_count = 0
				for ex in range(x, mini(x + min_size * 2, iw - 1)):
					if hedges[by][ex]:
						edge_count += 1
				has_bottom = edge_count >= 2

			# Left edge
			if y < ih - 1:
				edge_count = 0
				for ey in range(y, mini(y + min_size, ih - 1)):
					if x < iw and vedges[ey][x]:
						edge_count += 1
				has_left = edge_count >= 2

			# Right edge
			var rx := mini(x + min_size, iw - 1)
			if y < ih - 1 and rx < iw:
				edge_count = 0
				for ey in range(y, mini(y + min_size, ih - 1)):
					if vedges[ey][rx]:
						edge_count += 1
				has_right = edge_count >= 2

			if (has_top or has_bottom) and (has_left or has_right):
				var rw := rx - x + 1
				var rh := by - y + 1
				var rkey := "%d,%d,%d,%d" % [x, y, rw, rh]
				if rkey in visited_rects:
					continue
				visited_rects[rkey] = true
				if rw >= min_size and rh >= min_size:
					rects.append({"x": x, "y": y, "w": rw, "h": rh})

	return {"rects": rects, "count": rects.size()}


# ═══════════════════════════════════════════════════════════════
# Text Region Detection
# ═══════════════════════════════════════════════════════════════

static func detect_text_regions(img: Image, dark_on_light: bool = true, min_chars: int = 3,
		min_size: int = 8) -> Dictionary:
	if not img or img.is_empty():
		return {"error": "No image"}

	var iw := img.get_width()
	var ih := img.get_height()

	# Average luminance
	var avg_lum := 0.0
	var sample_step := 4
	var samples := 0
	for y in range(0, ih, sample_step):
		for x in range(0, iw, sample_step):
			var c := img.get_pixel(x, y)
			avg_lum += (c.r + c.g + c.b) / 3.0
			samples += 1
	avg_lum /= float(samples)

	var text_blocks: Array = []
	var block_w := 40
	var block_h := 16

	for y in range(0, ih - block_h, block_h / 2):
		for x in range(0, iw - block_w, block_w / 2):
			var block_lum := 0.0
			var count := 0
			for by in range(y, mini(y + block_h, ih), 2):
				for bx in range(x, mini(x + block_w, iw), 2):
					var c := img.get_pixel(bx, by)
					block_lum += (c.r + c.g + c.b) / 3.0
					count += 1
			if count == 0:
				continue
			block_lum /= float(count)

			var contrast := abs(block_lum - avg_lum)
			var direction_ok := (dark_on_light and block_lum < avg_lum) or (not dark_on_light and block_lum > avg_lum)
			if contrast > 0.2 and direction_ok:
				text_blocks.append({"x": x, "y": y, "w": block_w, "h": block_h, "contrast": contrast})

	return {"regions": text_blocks, "count": text_blocks.size(), "avg_luminance": avg_lum}


# ═══════════════════════════════════════════════════════════════
# Grid Sampling
# ═══════════════════════════════════════════════════════════════

static func sample_grid(img: Image, rows: int, cols: int, rect: Dictionary = {}) -> Dictionary:
	if not img or img.is_empty():
		return {"error": "No image"}
	if rows < 1 or cols < 1:
		return {"error": "rows and cols must be >= 1"}

	var sr: Dictionary = McpVisionHelpers.resolve_search_rect(img, rect)
	var cell_w: int = maxi(1, sr.w / cols)
	var cell_h: int = maxi(1, sr.h / rows)
	var grid: Array = []

	for row in rows:
		var grid_row: Array = []
		for col in cols:
			var cx: int = sr.x + col * cell_w
			var cy: int = sr.y + row * cell_h
			var dc: Color = _dominant_color_in_rect(img, cx, cy, cell_w, cell_h)
			grid_row.append(McpVisionHelpers.color_to_hex(dc))
		grid.append(grid_row)

	return {"grid": grid, "rows": rows, "cols": cols, "cell_w": cell_w, "cell_h": cell_h}


# ═══════════════════════════════════════════════════════════════
# Dominant Color
# ═══════════════════════════════════════════════════════════════

static func dominant_color(img: Image, rect: Dictionary = {}) -> Dictionary:
	if not img or img.is_empty():
		return {"error": "No image"}

	var sr: Dictionary = McpVisionHelpers.resolve_search_rect(img, rect)
	var dc := _dominant_color_in_rect(img, sr.x, sr.y, sr.w, sr.h)
	return {"r": dc.r, "g": dc.g, "b": dc.b, "a": dc.a, "hex": McpVisionHelpers.color_to_hex(dc)}


static func _dominant_color_in_rect(img: Image, x: int, y: int, w: int, h: int) -> Color:
	var iw := img.get_width()
	var ih := img.get_height()
	var buckets := {}
	var max_count := 0
	var best_color := Color.BLACK
	var quant_level := 6

	for py in range(y, mini(y + h, ih)):
		for px in range(x, mini(x + w, iw)):
			var c := img.get_pixel(px, py)
			var r := int(c.r * quant_level)
			var g := int(c.g * quant_level)
			var b := int(c.b * quant_level)
			var key := "%d,%d,%d" % [r, g, b]
			var count = buckets.get(key, 0) + 1
			buckets[key] = count
			if count > max_count:
				max_count = count
				best_color = c

	return best_color