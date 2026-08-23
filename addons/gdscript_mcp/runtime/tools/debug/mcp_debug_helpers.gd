extends RefCounted
class_name McpDebugHelpers

## McpDebugHelpers — Shared serialization helper used by debug sub-modules.


static func to_serializable(v: Variant) -> Variant:
	if v == null:
		return null
	if v is int or v is float or v is bool or v is String:
		return v
	if v is StringName:
		return String(v)
	if v is Array:
		var arr: Array = []
		for item in v:
			arr.append(to_serializable(item))
		return arr
	if v is Dictionary:
		var d: Dictionary = {}
		for key in v:
			d[str(key)] = to_serializable(v[key])
		return d
	if v is Vector2:
		return {"x": v.x, "y": v.y}
	if v is Rect2:
		return {"x": v.position.x, "y": v.position.y, "w": v.size.x, "h": v.size.y}
	if v is Color:
		return {"r": v.r, "g": v.g, "b": v.b, "a": v.a}
	if v is PackedByteArray:
		return "<binary " + str(v.size()) + " bytes>"
	if v is Object:
		return {"_class": "<Object>", "_id": -1}
	return str(v)