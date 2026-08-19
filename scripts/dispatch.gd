class_name Dispatch

static func amount_range(available: int) -> Vector2i:
	if available <= 0:
		return Vector2i.ZERO
	return Vector2i(1, available)
