extends RefCounted
class_name McpVisionColor

## McpVisionColor — Color-search operations (find_color, find_all_colors, count).
## All methods are static. Called by McpVision facade.


static func find_color(img: Image, target_hex: String, tolerance: float = 0.05,
		search_rect: Dictionary = {}) -> Dictionary:
	if not img or img.is_empty():
		return {"error": "No image"}

	var tc := McpVisionHelpers.hex_to_color(target_hex)
	var sr: Dictionary = McpVisionHelpers.resolve_search_rect(img, search_rect)
	var iw := img.get_width()
	var ih := img.get_height()

	for py in range(sr.y, sr.y + sr.h):
		if py >= ih: break
		for px in range(sr.x, sr.x + sr.w):
			if px >= iw: break
			var c := img.get_pixel(px, py)
			if McpVisionHelpers.color_within(c, tc, tolerance):
				return {"found": true, "x": px, "y": py, "hex": McpVisionHelpers.color_to_hex(c)}

	return {"found": false}


static func find_all_colors(img: Image, target_hex: String, tolerance: float = 0.05,
		min_size: int = 4) -> Dictionary:
	if not img or img.is_empty():
		return {"error": "No image"}

	var tc := McpVisionHelpers.hex_to_color(target_hex)
	var iw := img.get_width()
	var ih := img.get_height()

	var hits: Array = []
	for y in ih:
		for x in iw:
			var c := img.get_pixel(x, y)
			if McpVisionHelpers.color_within(c, tc, tolerance):
				hits.append({"x": x, "y": y})

	if hits.is_empty():
		return {"found": false, "regions": [], "count": 0}

	var regions: Array = []
	var visited := {}
	for hit in hits:
		var k := "%d,%d" % [hit.x, hit.y]
		if k in visited:
			continue
		visited[k] = true
		var cluster := _expand_cluster(hits, hit, visited)
		if cluster.w >= min_size and cluster.h >= min_size:
			regions.append({"x": cluster.x, "y": cluster.y, "w": cluster.w, "h": cluster.h})

	regions.sort_custom(func(a, b): return a.w * a.h > b.w * b.h)
	return {"found": true, "regions": regions, "count": regions.size()}


static func _expand_cluster(hits: Array, seed: Dictionary, visited: Dictionary) -> Dictionary:
	var min_x: int = seed.x
	var max_x: int = seed.x
	var min_y: int = seed.y
	var max_y: int = seed.y
	var queue: Array = [seed]
	var cluster_size: int = 4

	while not queue.is_empty():
		var p = queue.pop_back()
		for dy in range(-cluster_size, cluster_size + 1):
			for dx in range(-cluster_size, cluster_size + 1):
				var k := "%d,%d" % [p.x + dx, p.y + dy]
				if k in visited:
					continue
				visited[k] = true
				for h in hits:
					if h.x == p.x + dx and h.y == p.y + dy:
						min_x = mini(min_x, h.x)
						max_x = maxi(max_x, h.x)
						min_y = mini(min_y, h.y)
						max_y = maxi(max_y, h.y)
						queue.append(h)
						break

	return {"x": min_x, "y": min_y, "w": max_x - min_x + 1, "h": max_y - min_y + 1}


static func count_color_pixels(img: Image, target_hex: String, tolerance: float = 0.05,
		rect: Dictionary = {}) -> Dictionary:
	if not img or img.is_empty():
		return {"error": "No image"}

	var tc := McpVisionHelpers.hex_to_color(target_hex)
	var sr: Dictionary = McpVisionHelpers.resolve_search_rect(img, rect)
	var iw := img.get_width()
	var ih := img.get_height()
	var count := 0
	var total := 0

	for py in range(sr.y, sr.y + sr.h):
		if py >= ih: break
		for px in range(sr.x, sr.x + sr.w):
			if px >= iw: break
			total += 1
			if McpVisionHelpers.color_within(img.get_pixel(px, py), tc, tolerance):
				count += 1

	return {"matching": count, "total": total, "ratio": float(count) / float(total) if total > 0 else 0.0}