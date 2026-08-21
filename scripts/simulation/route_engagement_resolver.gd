@tool
class_name RouteEngagementResolver
extends RefCounted

const DEFAULT_POINT_EPSILON := 0.5
const DEFAULT_TIME_WINDOW := 2.0

static func detect_engagement(
	route_a: Array[Vector2],
	speed_a: float,
	route_b: Array[Vector2],
	speed_b: float,
	point_epsilon: float = DEFAULT_POINT_EPSILON,
	time_window: float = DEFAULT_TIME_WINDOW
) -> Dictionary:
	if route_a.size() < 2 or route_b.size() < 2:
		return {}
	if speed_a <= 0.0 or speed_b <= 0.0:
		return {}
	var candidates: Array[Dictionary] = []
	var cumulative_a := _cumulative_lengths(route_a)
	var cumulative_b := _cumulative_lengths(route_b)
	var total_a: float = float(cumulative_a.back())
	var total_b: float = float(cumulative_b.back())

	for point_a_index in route_a.size():
		for point_b_index in route_b.size():
			if route_a[point_a_index].distance_to(route_b[point_b_index]) > point_epsilon:
				continue
			var point: Vector2 = (route_a[point_a_index] + route_b[point_b_index]) * 0.5
			var time_a := _time_at_distance(float(cumulative_a[point_a_index]), speed_a)
			var time_b := _time_at_distance(float(cumulative_b[point_b_index]), speed_b)
			var point_type: StringName = &"waypoint_convergence"
			if point_a_index == route_a.size() - 1 and point_b_index == route_b.size() - 1:
				point_type = &"destination_arrival"
			candidates.append(_candidate(point, time_a, time_b, point_type, maxf(time_a, time_b)))

	for index_a in range(route_a.size() - 1):
		var a_start: Vector2 = route_a[index_a]
		var a_end: Vector2 = route_a[index_a + 1]
		for index_b in range(route_b.size() - 1):
			var b_start: Vector2 = route_b[index_b]
			var b_end: Vector2 = route_b[index_b + 1]
			var crossing: Variant = _segment_intersection(a_start, a_end, b_start, b_end, point_epsilon)
			if crossing == null:
				continue
			var crossing_point: Vector2 = crossing as Vector2
			var distance_a: float = float(cumulative_a[index_a]) + a_start.distance_to(crossing_point)
			var distance_b: float = float(cumulative_b[index_b]) + b_start.distance_to(crossing_point)
			var time_a := _time_at_distance(distance_a, speed_a)
			var time_b := _time_at_distance(distance_b, speed_b)
			if absf(time_a - time_b) <= time_window:
				candidates.append(_candidate(crossing_point, time_a, time_b, &"path_crossing", maxf(time_a, time_b)))

	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(first: Dictionary, second: Dictionary):
		if not is_equal_approx(float(first["sort_time"]), float(second["sort_time"])):
			return float(first["sort_time"]) < float(second["sort_time"])
		return String(first["type"]) < String(second["type"])
	)
	var result: Dictionary = candidates[0].duplicate()
	result.erase("sort_time")
	result["total_length_a"] = total_a
	result["total_length_b"] = total_b
	return result

static func _candidate(point: Vector2, time_a: float, time_b: float, point_type: StringName, sort_time: float) -> Dictionary:
	return {
		"point": point,
		"time_a": time_a,
		"time_b": time_b,
		"type": point_type,
		"sort_time": sort_time,
	}

static func _cumulative_lengths(route: Array[Vector2]) -> Array[float]:
	var result: Array[float] = [0.0]
	for index in range(1, route.size()):
		result.append(float(result.back()) + route[index - 1].distance_to(route[index]))
	return result

static func _time_at_distance(distance: float, speed: float) -> float:
	return maxf(distance, 0.0) / maxf(speed, 0.001)

static func _segment_intersection(first_start: Vector2, first_end: Vector2, second_start: Vector2, second_end: Vector2, epsilon: float) -> Variant:
	var first_delta := first_end - first_start
	var second_delta := second_end - second_start
	var denominator := first_delta.cross(second_delta)
	if is_zero_approx(denominator):
		if first_start.distance_to(second_start) <= epsilon:
			return first_start
		if first_start.distance_to(second_end) <= epsilon:
			return first_start
		if first_end.distance_to(second_start) <= epsilon:
			return first_end
		if first_end.distance_to(second_end) <= epsilon:
			return first_end
		return null
	var offset := second_start - first_start
	var first_factor := offset.cross(second_delta) / denominator
	var second_factor := offset.cross(first_delta) / denominator
	if first_factor < -epsilon or first_factor > 1.0 + epsilon or second_factor < -epsilon or second_factor > 1.0 + epsilon:
		return null
	return first_start + first_delta * clampf(first_factor, 0.0, 1.0)
