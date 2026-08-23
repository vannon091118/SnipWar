extends RefCounted
class_name McpUxDetect

## McpUxDetect — Layout grid sampling, color palette, scene type detection.
## All methods static. Extracted from McpUxPipeline.


static func layout_grid(vision: RefCounted, img: Image, rows: int, cols: int) -> Dictionary:
	var full_rect = {"x": 0, "y": 0, "w": img.get_width(), "h": img.get_height()}
	var raw = vision.sample_grid(img, rows, cols, full_rect)
	if raw.has("error"):
		return {"grid": [], "error": raw.error}

	var grid = raw.grid
	var regions: Array = []
	var visited = {}
	var cw: int = raw.cell_w
	var ch: int = raw.cell_h

	for row in grid.size():
		if not grid[row] is Array:
			continue
		var grid_row: Array = grid[row]
		for col in grid_row.size():
			var key = "%d,%d" % [row, col]
			if key in visited:
				continue
			var hex: String = grid_row[col]
			if hex == "": continue
			var x_min = col; var x_max = col
			var y_min = row; var y_max = row
			var queue = [key]
			visited[key] = true
			while not queue.is_empty():
				var pos: String = queue.pop_back()
				var parts = pos.split(",")
				var r = int(parts[0]); var c = int(parts[1])
				x_min = mini(x_min, c); x_max = maxi(x_max, c)
				y_min = mini(y_min, r); y_max = maxi(y_max, r)
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if dx == 0 and dy == 0: continue
						var nr = r + dy; var nc = c + dx
						var nk = "%d,%d" % [nr, nc]
						if nk in visited: continue
						if nr >= 0 and nr < grid.size() and nc >= 0 and nc < grid_row.size():
							if grid[nr][nc] == hex:
								visited[nk] = true
								queue.append(nk)

			var rw = (x_max - x_min + 1) * cw
			var rh = (y_max - y_min + 1) * ch
			if rw >= 20 and rh >= 20:
				regions.append({"color": hex, "x": x_min * cw, "y": y_min * ch, "w": rw, "h": rh})

	regions.sort_custom(func(a, b): return (a.w * a.h) > (b.w * b.h))
	return {"grid": grid, "rows": rows, "cols": cols, "cell_w": cw, "cell_h": ch, "regions": regions}


static func color_palette(img: Image) -> Array:
	var iw = img.get_width()
	var ih = img.get_height()
	var step = maxi(1, mini(iw, ih) / 20)
	var color_counts = {}

	for y in range(0, ih, step):
		for x in range(0, iw, step):
			var c = img.get_pixel(x, y)
			var hex = McpVisionHelpers.color_to_hex(c)
			color_counts[hex] = color_counts.get(hex, 0) + 1

	var sorted = []
	for hex in color_counts:
		sorted.append({"hex": hex, "count": color_counts[hex]})
	sorted.sort_custom(func(a, b): return a["count"] > b["count"])

	var palette = []
	for i in range(min(8, sorted.size())):
		palette.append(sorted[i].hex)
	return palette


static func detect_scene(img: Image, elements: Array, iw: int, ih: int) -> String:
	var counts = {"button": 0, "panel": 0, "label": 0, "input_field": 0}
	for el in elements:
		var tn = McpUxGeometry.type_name(el.type)
		counts[tn] = counts.get(tn, 0) + 1

	var total = elements.size()

	# Main menu: centered vertical buttons, dark background
	if total >= 2 and total <= 10 and counts.button >= 2:
		var cx_sum = 0.0
		for el in elements:
			cx_sum += el.center.x
		var avg_x = cx_sum / float(total)
		var x_spread = 0.0
		for el in elements:
			x_spread += abs(el.center.x - avg_x)
		x_spread /= float(total)
		if x_spread < iw * 0.25:
			var bg = img.get_pixel(10, 10)
			if (bg.r + bg.g + bg.b) / 3.0 < 0.4:
				return "main_menu"

	if counts.panel >= 1 and counts.button >= 1 and total >= 2 and total <= 8:
		return "dialog"

	if total > 3:
		var edge_count = 0
		for el in elements:
			if el.rect.x < 10 or el.rect.y < 10 or el.rect.x + el.rect.w > iw - 10:
				edge_count += 1
		if edge_count > total * 0.5:
			return "hud"

	if total > 5:
		return "game_view"
	return "unknown"