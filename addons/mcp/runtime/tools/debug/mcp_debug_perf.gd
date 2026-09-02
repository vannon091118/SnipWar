extends RefCounted
class_name McpDebugPerf

## McpDebugPerf — Engine metrics & rendering stats (extracted from McpDebug).
## Instance holds frame-timing state. All public API via instance methods.

var _last_usec: int = 0


func get_perf_metrics() -> Dictionary:
	var result: Dictionary = {}
	result["fps"] = Performance.get_monitor(Performance.TIME_FPS)
	result["process_ms"] = Performance.get_monitor(Performance.TIME_PROCESS)
	result["physics_ms"] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	result["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	result["canvas_items"] = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	result["objects"] = Performance.get_monitor(Performance.OBJECT_COUNT)
	result["resources"] = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	result["nodes"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	result["orphan_nodes"] = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	result["physics_2d_active"] = Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)
	result["physics_2d_collisions"] = Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)
	result["static_memory"] = Performance.get_monitor(Performance.MEMORY_STATIC)
	result["static_memory_max"] = Performance.get_monitor(Performance.MEMORY_STATIC_MAX)
	result["video_memory"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	result["audio_latency"] = Performance.get_monitor(Performance.AUDIO_OUTPUT_LATENCY)
	return result


func get_rendering_stats() -> Dictionary:
	return {
		"video_mem_used": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"canvas_items": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
	}


func get_engine_info() -> Dictionary:
	var ml: Object = Engine.get_main_loop()
	var is_game: bool = ml is SceneTree
	var version: Dictionary = Engine.get_version_info()
	var root_count: int = -1
	if is_game:
		root_count = (ml as SceneTree).root.get_child_count()
	return {
		"engine_version": version.get("string", "unknown"),
		"engine_major": version.get("major", 0),
		"engine_minor": version.get("minor", 0),
		"arch": OS.get_processor_name(),
		"os_name": OS.get_name(),
		"locale": OS.get_locale(),
		"headless": OS.has_feature("headless"),
		"editor": Engine.is_editor_hint(),
		"game_running": is_game,
		"root_child_count": root_count,
	}


func get_frame_timing() -> Dictionary:
	var now: int = Time.get_ticks_usec()
	var delta: int = 0
	if _last_usec > 0:
		delta = now - _last_usec
	_last_usec = now
	var fps: float = 0.0
	if delta > 0:
		fps = 1000000.0 / float(delta)
	return {"timestamp_usec": now, "delta_usec": delta, "delta_ms": float(delta) / 1000.0, "fps": fps}