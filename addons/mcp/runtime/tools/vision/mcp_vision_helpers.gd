extends RefCounted
class_name McpVisionHelpers

## McpVisionHelpers — Shared static utilities used by all vision sub-modules.
## Agent-supplied template decoding, hex color conversion, bounds helpers.


static func image_to_base64(img: Image, format_name: String = "png") -> String:
	var byte_arr: PackedByteArray
	if format_name == "jpg" or format_name == "jpeg":
		byte_arr = img.save_jpg_to_buffer(90)
	else:
		byte_arr = img.save_png_to_buffer()
	return Marshalls.raw_to_base64(byte_arr)


static func b64_to_image(b64: String) -> Image:
	if b64.length() < 4:
		return null
	var byte_arr: PackedByteArray = Marshalls.base64_to_raw(b64)
	if byte_arr.size() < 4:
		return null
	var is_png: bool = byte_arr.size() >= 8 and byte_arr[0] == 0x89 and byte_arr[1] == 0x50 and byte_arr[2] == 0x4E and byte_arr[3] == 0x47
	var is_jpg: bool = byte_arr.size() >= 2 and byte_arr[0] == 0xFF and byte_arr[1] == 0xD8
	if not is_png and not is_jpg:
		return null
	var img := Image.new()
	if is_png:
		var err := img.load_png_from_buffer(byte_arr)
		if err != OK:
			return null
		return img
	var err := img.load_jpg_from_buffer(byte_arr)
	if err != OK:
		return null
	return img


static func hex_to_color(hex: String) -> Color:
	var h := hex.strip_edges().lstrip("#")
	if h.length() == 3:
		h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
	if h.length() < 6:
		return Color.BLACK
	return Color(
		float(h.substr(0, 2).hex_to_int()) / 255.0,
		float(h.substr(2, 2).hex_to_int()) / 255.0,
		float(h.substr(4, 2).hex_to_int()) / 255.0,
		1.0
	)


static func color_to_hex(c: Color) -> String:
	return "#%02x%02x%02x" % [
		int(clampf(c.r, 0.0, 1.0) * 255),
		int(clampf(c.g, 0.0, 1.0) * 255),
		int(clampf(c.b, 0.0, 1.0) * 255)
	]


static func color_within(c: Color, target: Color, tolerance: float) -> bool:
	var dr := abs(c.r - target.r)
	var dg := abs(c.g - target.g)
	var db := abs(c.b - target.b)
	return dr <= tolerance and dg <= tolerance and db <= tolerance


static func resolve_search_rect(img: Image, rect_spec: Dictionary) -> Dictionary:
	var image_width := img.get_width()
	var image_height := img.get_height()
	if image_width <= 0 or image_height <= 0:
		return {"x": 0, "y": 0, "w": 0, "h": 0}
	var x := clampi(int(rect_spec.get("x", 0)), 0, image_width - 1)
	var y := clampi(int(rect_spec.get("y", 0)), 0, image_height - 1)
	var max_width := image_width - x
	var max_height := image_height - y
	var w := clampi(int(rect_spec.get("w", max_width)), 1, max_width)
	var h := clampi(int(rect_spec.get("h", max_height)), 1, max_height)
	return {"x": x, "y": y, "w": w, "h": h}