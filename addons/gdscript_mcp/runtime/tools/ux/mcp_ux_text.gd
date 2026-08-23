extends RefCounted
class_name McpUxText

## McpUxText — Text hint reading via luminance contrast analysis.
## Not real OCR — patterns like "text", "dense_text", "sparse_text", "few_chars".
## All methods static.

const MIN_CONTRAST = 0.1


static func read_text_hint(img: Image, rect: Dictionary) -> String:
	var r = McpUxGeometry.resolve_rect(rect, img.get_width(), img.get_height())
	var iw = img.get_width()
	var ih = img.get_height()

	var cy: int = r.y + r.h / 2
	if cy < 0 or cy >= ih:
		return ""
	cy = clampi(cy, 0, ih - 1)

	var bg_lum = 0.0
	var sample_count = 0
	for x in range(r.x, mini(r.x + r.w, iw), 3):
		var c = img.get_pixel(x, r.y + 2)
		bg_lum += (c.r + c.g + c.b) / 3.0
		sample_count += 1
	bg_lum /= maxi(1, sample_count)

	var transitions = 0
	var dark_pixels = 0
	for x in range(r.x + 2, mini(r.x + r.w - 2, iw), 1):
		var c = img.get_pixel(x, cy)
		var lum = (c.r + c.g + c.b) / 3.0
		if abs(lum - bg_lum) > MIN_CONTRAST:
			transitions += 1
			if lum < bg_lum:
				dark_pixels += 1

	if transitions <= 3:
		return ""

	var pattern = "few_chars"
	if transitions > r.w * 0.4:
		pattern = "dense_text"
	elif transitions > r.w * 0.15:
		pattern = "sparse_text"

	# Detect luminance stripes (segmented UI like tab bars)
	var lum_values = []
	for x in range(r.x, mini(r.x + r.w, iw), 2):
		var c2 = img.get_pixel(x, cy)
		lum_values.append((c2.r + c2.g + c2.b) / 3.0)
	var stripe_count = 0
	if lum_values.size() >= 3:
		for i in range(lum_values.size() - 1):
			if abs(lum_values[i] - lum_values[i + 1]) > 0.1:
				stripe_count += 1
	var segmented = stripe_count > lum_values.size() * 0.3

	if segmented:
		return "segmented_" + pattern
	return pattern


static func compute_uniformity(img: Image, rect: Dictionary) -> float:
	var r = McpUxGeometry.resolve_rect(rect, img.get_width(), img.get_height())
	var iw = img.get_width()
	var ih = img.get_height()
	var step = maxi(1, mini(r.w, r.h) / 5)

	var r_sum = 0.0
	var g_sum = 0.0
	var b_sum = 0.0
	var count = 0

	for y in range(r.y, mini(r.y + r.h, ih), step):
		for x in range(r.x, mini(r.x + r.w, iw), step):
			var c = img.get_pixel(x, y)
			r_sum += c.r
			g_sum += c.g
			b_sum += c.b
			count += 1

	if count == 0:
		return 0.0

	var r_mean = r_sum / count
	var g_mean = g_sum / count
	var b_mean = b_sum / count

	var variance = 0.0
	for y in range(r.y, mini(r.y + r.h, ih), step):
		for x in range(r.x, mini(r.x + r.w, iw), step):
			var c = img.get_pixel(x, y)
			var dr = c.r - r_mean
			var dg = c.g - g_mean
			var db = c.b - b_mean
			variance += (dr*dr + dg*dg + db*db) / 3.0
	variance /= maxi(1, count)

	var uniformity = 1.0 - (variance / 0.33)
	return clampf(uniformity, 0.0, 1.0)