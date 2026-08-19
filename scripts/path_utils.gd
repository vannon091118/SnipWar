class_name PathUtils

static func distance(path: Array[Vector2]) -> float:
	var total := 0.0
	for index in range(path.size() - 1):
		total += path[index].distance_to(path[index + 1])
	return total
