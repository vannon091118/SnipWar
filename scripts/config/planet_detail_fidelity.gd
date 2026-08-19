@tool
class_name PlanetDetailFidelity
extends Resource

const MOTION_FULL := "full"
const MOTION_THROTTLED := "throttled"
const MOTION_STATIC := "static"

@export_enum("full", "throttled", "static") var orbit_motion_mode: String = MOTION_FULL
@export_range(0.0, 0.25, 0.005) var orbit_update_interval: float = 0.0

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if orbit_motion_mode != MOTION_FULL and orbit_motion_mode != MOTION_THROTTLED and orbit_motion_mode != MOTION_STATIC:
		errors.append("planet detail orbit_motion_mode is invalid")
	if not is_finite(orbit_update_interval) or orbit_update_interval < 0.0:
		errors.append("planet detail orbit_update_interval is invalid")
	if orbit_motion_mode == MOTION_THROTTLED and orbit_update_interval <= 0.0:
		errors.append("throttled planet detail motion requires a positive orbit_update_interval")
	if orbit_motion_mode != MOTION_THROTTLED and orbit_update_interval > 0.0:
		errors.append("orbit_update_interval is only valid for throttled planet detail motion")
	return errors

func is_animated() -> bool:
	return orbit_motion_mode != MOTION_STATIC
