extends RefCounted
class_name McpVisionCapture

## Capture only. Encoding and transport are handled by the local artifact store.

const MAX_DIMENSION := 4096


func capture_screenshot(format_name: String = "png") -> Dictionary:
	var viewport_node := get_viewport_for_capture()
	if viewport_node == null:
		return {"error": "No visible viewport available"}
	var texture := viewport_node.get_texture()
	if texture == null or not texture.get_rid().is_valid():
		return {"error": "Viewport texture is unavailable"}
	if texture.get_width() <= 0 or texture.get_height() <= 0:
		return {"error": "Viewport texture is zero-sized"}
	await RenderingServer.frame_post_draw
	var image := texture.get_image()
	if image == null or image.is_empty():
		return {"error": "Captured image is empty"}
	if image.get_width() > MAX_DIMENSION or image.get_height() > MAX_DIMENSION:
		return {"error": "Captured image exceeds dimension limit"}
	return {
		"image": image,
		"format": "jpg" if format_name == "jpg" or format_name == "jpeg" else "png",
		"width": image.get_width(),
		"height": image.get_height(),
	}


static func get_viewport_for_capture() -> Viewport:
	if OS.has_feature("headless") or "--headless" in OS.get_cmdline_args():
		return null
	var main_loop := Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return null
	var root := (main_loop as SceneTree).root
	if root == null:
		return null
	return root if root.get_texture() != null and root.get_texture().get_rid().is_valid() else null


func capture_screenshot_sync(format_name: String = "png") -> Dictionary:
	var viewport_node := get_viewport_for_capture()
	if viewport_node == null:
		return {"error": "No visible viewport available"}
	var texture := viewport_node.get_texture()
	if texture == null or not texture.get_rid().is_valid():
		return {"error": "Viewport texture is unavailable"}
	var image := texture.get_image()
	if image == null or image.is_empty():
		return {"error": "Captured image is empty"}
	if image.get_width() > MAX_DIMENSION or image.get_height() > MAX_DIMENSION:
		return {"error": "Captured image exceeds dimension limit"}
	return {
		"image": image,
		"format": "jpg" if format_name == "jpg" or format_name == "jpeg" else "png",
		"width": image.get_width(),
		"height": image.get_height(),
	}


static func get_pixel(image: Image, x: int, y: int) -> Dictionary:
	if image == null or image.is_empty():
		return {"error": "No image"}
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return {"error": "Coordinates out of bounds"}
	var color := image.get_pixel(x, y)
	return {"r": color.r, "g": color.g, "b": color.b, "a": color.a, "hex": McpVisionHelpers.color_to_hex(color)}


static func get_pixel_region(image: Image, x: int, y: int, width: int, height: int, step: int = 4) -> Dictionary:
	if image == null or image.is_empty():
		return {"error": "No image"}
	var safe_step := maxi(1, step)
	var rows: Array = []
	var py := maxi(0, y)
	while py < y + height and py < image.get_height():
		var row: Array = []
		var px := maxi(0, x)
		while px < x + width and px < image.get_width():
			row.append(McpVisionHelpers.color_to_hex(image.get_pixel(px, py)))
			px += safe_step
		rows.append(row)
		py += safe_step
	return {"grid": rows, "step": safe_step}
