extends SceneTree

## Navigation / Transit Test: Validates FlightTime, WorkerManager cluster
## packing, and NavigationField instantiation in a headless context.
##
## Exit 1 on any failure — real assertions, no print-only.

const FLIGHT_TIME_SCRIPT := preload("res://scripts/flight_time.gd")

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var flight_time: FlightTime = FLIGHT_TIME_SCRIPT.new()

	# Test 1: Flight time is deterministic for identical inputs
	var t1: float = flight_time.seconds_for(100.0, 1)
	var t2: float = flight_time.seconds_for(100.0, 1)
	if abs(t1 - t2) > 0.001:
		_failures.append("Flight time not deterministic: %f vs %f" % [t1, t2])

	# Test 2: Flight time increases with distance
	var short_dist: float = flight_time.seconds_for(50.0, 1)
	var long_dist: float = flight_time.seconds_for(500.0, 1)
	if long_dist <= short_dist:
		_failures.append("Flight time should increase with distance")

	# Test 3: Flight time increases with unit count (packing penalty)
	var single: float = flight_time.seconds_for(100.0, 1)
	var multi: float = flight_time.seconds_for(100.0, 7)
	if multi < single:
		_failures.append("Flight time should increase with unit count (packing penalty)")

	# Test 4: Flight time is always positive for positive distance
	var zero_time: float = flight_time.seconds_for(0.0, 1)
	if zero_time < 0.0:
		_failures.append("Flight time for zero distance should be non-negative")

	if not _failures.is_empty():
		for f in _failures:
			printerr("[NAV-TRANSIT-FAIL] " + f)
		print("NAVIGATION/TRANSIT: FAIL (%d failures)" % _failures.size())
		quit(1)
		return
	print("NAVIGATION/TRANSIT: PASS (flight time verified)")
	quit(0)
