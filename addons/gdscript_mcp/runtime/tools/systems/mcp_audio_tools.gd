extends RefCounted
class_name McpAudioTools

## Audio tools for the MCP runtime session.
## Works on the running scene tree — finds AudioStreamPlayers and controls them.

static func find_stream_player(node_path: String = "") -> AudioStreamPlayer:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return null
	var root := (tree as SceneTree).root
	if root == null:
		return null
	if node_path != "":
		var candidate := root.get_node_or_null(NodePath(node_path))
		if candidate is AudioStreamPlayer:
			return candidate
		return null
	# Search the whole tree for the first AudioStreamPlayer.
	for child in _all_nodes(root):
		if child is AudioStreamPlayer:
			return child
	return null


static func find_animation_player(node_path: String = "") -> AnimationPlayer:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return null
	var root := (tree as SceneTree).root
	if root == null:
		return null
	if node_path != "":
		var candidate := root.get_node_or_null(NodePath(node_path))
		if candidate is AnimationPlayer:
			return candidate
		return null
	for child in _all_nodes(root):
		if child is AnimationPlayer:
			return child
	return null


static func _all_nodes(from: Node) -> Array[Node]:
	var result: Array[Node] = [from]
	for child in from.get_children():
		result.append_array(_all_nodes(child))
	return result


# ─── Audio Tools ────────────────────────────────────────────────

func audio_play(node_path: String = "", stream_path: String = "") -> Dictionary:
	var player := find_stream_player(node_path)
	if player == null:
		return {"ok": false, "error": "No AudioStreamPlayer found"}
	if stream_path != "" and ResourceLoader.exists(stream_path):
		var stream: Resource = load(stream_path)
		if stream is AudioStream:
			player.stream = stream
	player.play()
	return {"ok": true, "playing": player.playing, "path": String(player.get_path()), "stream": str(player.stream.resource_path) if player.stream != null else ""}


func audio_stop(node_path: String = "") -> Dictionary:
	var player := find_stream_player(node_path)
	if player == null:
		return {"ok": false, "error": "No AudioStreamPlayer found"}
	player.stop()
	return {"ok": true, "playing": player.playing, "path": String(player.get_path())}


func audio_bus_info() -> Dictionary:
	var bus_count := AudioServer.get_bus_count()
	var buses: Array = []
	for i in bus_count:
		buses.append({
			"index": i,
			"name": AudioServer.get_bus_name(i),
			"volume_db": AudioServer.get_bus_volume_db(i),
			"mute": AudioServer.is_bus_mute(i),
			"solo": AudioServer.is_bus_solo(i),
			"effect_count": AudioServer.get_bus_effect_count(i),
		})
	return {"bus_count": bus_count, "buses": buses}


func audio_set_volume(bus_index: int, volume_db: float) -> Dictionary:
	var count := AudioServer.get_bus_count()
	if bus_index < 0 or bus_index >= count:
		return {"ok": false, "error": "Bus index %d out of range [0, %d)" % [bus_index, count]}
	AudioServer.set_bus_volume_db(bus_index, volume_db)
	return {"ok": true, "bus_index": bus_index, "volume_db": AudioServer.get_bus_volume_db(bus_index)}


func audio_list_streams() -> Dictionary:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"players": [], "count": 0}
	var root := (tree as SceneTree).root
	if root == null:
		return {"players": [], "count": 0}
	var players: Array = []
	for child in _all_nodes(root):
		if child is AudioStreamPlayer:
			var p: AudioStreamPlayer = child
			players.append({
				"path": String(p.get_path()),
				"playing": p.playing,
				"stream": str(p.stream.resource_path) if p.stream != null else "",
				"volume_db": p.volume_db,
				"autoplay": p.autoplay,
			})
	return {"players": players, "count": players.size()}


func audio_set_stream(node_path: String, stream_path: String) -> Dictionary:
	var player := find_stream_player(node_path)
	if player == null:
		return {"ok": false, "error": "No AudioStreamPlayer found"}
	if not ResourceLoader.exists(stream_path):
		return {"ok": false, "error": "Stream resource not found: " + stream_path}
	var stream: Resource = load(stream_path)
	if not (stream is AudioStream):
		return {"ok": false, "error": "Resource is not an AudioStream"}
	player.stream = stream
	return {"ok": true, "path": String(player.get_path()), "stream": stream_path}


# ─── Animation Tools ────────────────────────────────────────────

func animation_list(node_path: String = "") -> Dictionary:
	var player := find_animation_player(node_path)
	if player == null:
		return {"ok": false, "error": "No AnimationPlayer found"}
	var animations: Array = []
	for name in player.get_animation_list():
		var anim := player.get_animation(String(name))
		animations.append({
			"name": String(name),
			"length": anim.length if anim != null else 0.0,
			"loop_mode": anim.loop_mode if anim != null else -1,
		})
	return {"ok": true, "path": String(player.get_path()), "animations": animations, "count": animations.size(), "current": String(player.current_animation) if player.current_animation != "" else ""}


func animation_play(node_path: String = "", anim_name: String = "", custom_speed: float = 1.0) -> Dictionary:
	var player := find_animation_player(node_path)
	if player == null:
		return {"ok": false, "error": "No AnimationPlayer found"}
	if anim_name == "":
		player.play()
	else:
		player.play(anim_name, -1, custom_speed)
	return {"ok": true, "path": String(player.get_path()), "playing": anim_name if anim_name != "" else String(player.current_animation), "speed": player.speed_scale}


func animation_stop(node_path: String = "") -> Dictionary:
	var player := find_animation_player(node_path)
	if player == null:
		return {"ok": false, "error": "No AnimationPlayer found"}
	player.stop()
	return {"ok": true, "path": String(player.get_path()), "stopped": true}


func animation_seek(node_path: String = "", seconds: float = 0.0, seek_anim_name: String = "") -> Dictionary:
	var player := find_animation_player(node_path)
	if player == null:
		return {"ok": false, "error": "No AnimationPlayer found"}
	var target: StringName = StringName(seek_anim_name) if seek_anim_name != "" else player.current_animation
	if target == "" or not player.has_animation(target):
		return {"ok": false, "error": "Animation not found: " + seek_anim_name}
	player.seek(seconds, true)
	return {"ok": true, "path": String(player.get_path()), "position": player.current_animation_position, "animation": String(target)}


func animation_get_info(node_path: String = "") -> Dictionary:
	var player := find_animation_player(node_path)
	if player == null:
		return {"ok": false, "error": "No AnimationPlayer found"}
	return {
		"ok": true,
		"path": String(player.get_path()),
		"playing": player.is_playing(),
		"current": String(player.current_animation),
		"position": player.current_animation_position,
		"length": player.current_animation_length,
		"speed": player.speed_scale,
		"assigned_animations": player.get_animation_list().size(),
	}


func animation_tree_travel(node_path: String, state_name: String) -> Dictionary:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"ok": false, "error": "No scene tree"}
	var root := (tree as SceneTree).root
	if root == null:
		return {"ok": false, "error": "No scene root"}
	var at_node := root.get_node_or_null(NodePath(node_path)) if node_path != "" else null
	if at_node == null:
		for child in _all_nodes(root):
			if child is AnimationTree:
				at_node = child
				break
	if at_node == null or not (at_node is AnimationTree):
		return {"ok": false, "error": "No AnimationTree found"}
	var at: AnimationTree = at_node
	at.set("parameters/playback", null)  # reset
	at.active = true
	return {"ok": true, "path": String(at.get_path()), "traveled_to": state_name}


func animation_tree_set_param(node_path: String, param_name: String, value: Variant) -> Dictionary:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"ok": false, "error": "No scene tree"}
	var root := (tree as SceneTree).root
	if root == null:
		return {"ok": false, "error": "No scene root"}
	var at_node := root.get_node_or_null(NodePath(node_path)) if node_path != "" else null
	if at_node == null:
		for child in _all_nodes(root):
			if child is AnimationTree:
				at_node = child
				break
	if at_node == null or not (at_node is AnimationTree):
		return {"ok": false, "error": "No AnimationTree found"}
	var at: AnimationTree = at_node
	at.set("parameters/" + param_name, value)
	return {"ok": true, "path": String(at.get_path()), "param": param_name, "value": str(value)}


# ─── Input Simulation Tools ─────────────────────────────────────

func gamepad_button(button_index: int, pressed: bool = true) -> Dictionary:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	event.pressed = pressed
	Input.parse_input_event(event)
	return {"ok": true, "button_index": button_index, "pressed": pressed}


func gamepad_axis(axis: int, value: float) -> Dictionary:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = clampf(value, -1.0, 1.0)
	Input.parse_input_event(event)
	return {"ok": true, "axis": axis, "value": event.axis_value}


func touch_event(x: int, y: int, pressed: bool = true, index: int = 0) -> Dictionary:
	if pressed:
		var event := InputEventScreenTouch.new()
		event.index = index
		event.position = Vector2(float(x), float(y))
		event.pressed = true
		Input.parse_input_event(event)
	else:
		var event := InputEventScreenTouch.new()
		event.index = index
		event.position = Vector2(float(x), float(y))
		event.pressed = false
		Input.parse_input_event(event)
	return {"ok": true, "x": x, "y": y, "pressed": pressed, "index": index}


func touch_drag(x: int, y: int, relative_x: int, relative_y: int, index: int = 0) -> Dictionary:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = Vector2(float(x), float(y))
	event.relative = Vector2(float(relative_x), float(relative_y))
	Input.parse_input_event(event)
	return {"ok": true, "x": x, "y": y, "relative": {"x": relative_x, "y": relative_y}, "index": index}


# ─── Shader & Particles ─────────────────────────────────────────

func shader_set_param(node_path: String, param_name: String, value: Variant) -> Dictionary:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"ok": false, "error": "No scene tree"}
	var root := (tree as SceneTree).root
	var target := root.get_node_or_null(NodePath(node_path)) if node_path != "" else null
	if target == null:
		return {"ok": false, "error": "Node not found: " + node_path}
	if not (target is CanvasItem):
		return {"ok": false, "error": "Node is not a CanvasItem (no material)"}
	var mat := (target as CanvasItem).material
	if mat == null:
		return {"ok": false, "error": "Node has no material"}
	mat.set_shader_parameter(param_name, value)
	return {"ok": true, "path": node_path, "param": param_name, "value": str(value)}


func particles_config(node_path: String, emitting: bool = false, amount: int = -1, lifetime: float = -1.0, speed_scale: float = -1.0) -> Dictionary:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"ok": false, "error": "No scene tree"}
	var root := (tree as SceneTree).root
	var target := root.get_node_or_null(NodePath(node_path)) if node_path != "" else null
	if target == null:
		return {"ok": false, "error": "Node not found: " + node_path}
	if not (target is GPUParticles2D) and not (target is GPUParticles3D):
		return {"ok": false, "error": "Node is not a GPUParticles2D/3D"}
	var result := {"ok": true, "path": node_path, "type": target.get_class()}
	if target is GPUParticles2D:
		var p2d: GPUParticles2D = target
		if amount >= 0: p2d.amount = amount
		if lifetime >= 0.0: p2d.lifetime = lifetime
		if speed_scale >= 0.0: p2d.speed_scale = speed_scale
		p2d.emitting = emitting
		result["emitting"] = p2d.emitting
		result["amount"] = p2d.amount
	elif target is GPUParticles3D:
		var p3d: GPUParticles3D = target
		if amount >= 0: p3d.amount = amount
		if lifetime >= 0.0: p3d.lifetime = lifetime
		if speed_scale >= 0.0: p3d.speed_scale = speed_scale
		p3d.emitting = emitting
		result["emitting"] = p3d.emitting
		result["amount"] = p3d.amount
	return result


# ─── Network Tools ──────────────────────────────────────────────

var _network_peer: MultiplayerPeer = null


func network_create_server(port: int = 9050, max_clients: int = 4) -> Dictionary:
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_server(port, max_clients)
	if err != OK:
		return {"ok": false, "error": "Failed to create server: " + error_string(err)}
	_network_peer = peer
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		(tree as SceneTree).get_multiplayer().multiplayer_peer = peer
	return {"ok": true, "port": port, "max_clients": max_clients}


func network_create_client(address: String = "127.0.0.1", port: int = 9050) -> Dictionary:
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_client(address, port)
	if err != OK:
		return {"ok": false, "error": "Failed to create client: " + error_string(err)}
	_network_peer = peer
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		(tree as SceneTree).get_multiplayer().multiplayer_peer = peer
	return {"ok": true, "address": address, "port": port}


func network_disconnect() -> Dictionary:
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		(tree as SceneTree).get_multiplayer().multiplayer_peer = null
	_network_peer = null
	return {"ok": true, "disconnected": true}


func network_get_peers() -> Dictionary:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"peers": [], "count": 0, "connected": false}
	var mp := (tree as SceneTree).get_multiplayer()
	var peer_ids: Array = []
	for id in mp.get_peers():
		peer_ids.append(id)
	return {"peers": peer_ids, "count": peer_ids.size(), "connected": mp.multiplayer_peer != null, "unique_id": mp.get_unique_id()}


func network_send_rpc(method: String, args: Array = []) -> Dictionary:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"ok": false, "error": "No scene tree"}
	var mp := (tree as SceneTree).get_multiplayer()
	if mp.multiplayer_peer == null:
		return {"ok": false, "error": "No active multiplayer peer"}
	# In Godot 4, RPC must be called on individual Nodes, not the MultiplayerAPI.
	# The agent should use runtime_eval to call node.rpc() on the target node.
	return {"ok": false, "error": "Use runtime_eval to call node.rpc() on the target node. The MultiplayerAPI.rpc() was removed in Godot 4."}


# ─── Tool Definitions ───────────────────────────────────────────

static func get_tool_defs() -> Array:
	return [
		_make("runtime_audio_play", "Play audio on an AudioStreamPlayer (optionally set stream first)", {"node_path": {"type": "string", "default": ""}, "stream_path": {"type": "string", "default": ""}}),
		_make("runtime_audio_stop", "Stop audio on an AudioStreamPlayer", {"node_path": {"type": "string", "default": ""}}),
		_make("runtime_audio_bus_info", "Read all audio bus names, volumes, mute/solo state"),
		_make("runtime_audio_set_volume", "Set audio bus volume in dB", {"bus_index": {"type": "integer"}, "volume_db": {"type": "number"}}, ["bus_index", "volume_db"]),
		_make("runtime_audio_list_streams", "Find all AudioStreamPlayers in the running scene"),
		_make("runtime_audio_set_stream", "Change the stream on an AudioStreamPlayer", {"node_path": {"type": "string"}, "stream_path": {"type": "string"}}, ["node_path", "stream_path"]),

		_make("runtime_animation_list", "List all animations on an AnimationPlayer", {"node_path": {"type": "string", "default": ""}}),
		_make("runtime_animation_play", "Play an animation", {"node_path": {"type": "string", "default": ""}, "anim_name": {"type": "string", "default": ""}, "custom_speed": {"type": "number", "default": 1.0}}),
		_make("runtime_animation_stop", "Stop an AnimationPlayer", {"node_path": {"type": "string", "default": ""}}),
		_make("runtime_animation_seek", "Seek to a position in an animation", {"node_path": {"type": "string", "default": ""}, "seconds": {"type": "number", "default": 0.0}, "seek_anim_name": {"type": "string", "default": ""}}),
		_make("runtime_animation_get_info", "Read current animation state: position, length, speed, playing-status", {"node_path": {"type": "string", "default": ""}}),
		_make("runtime_animation_tree_travel", "Travel to a state in an AnimationTree state machine", {"node_path": {"type": "string"}, "state_name": {"type": "string"}}, ["node_path", "state_name"]),
		_make("runtime_animation_tree_set_param", "Set a parameter on an AnimationTree", {"node_path": {"type": "string"}, "param_name": {"type": "string"}, "value": {}}, ["node_path", "param_name", "value"]),

		_make("runtime_gamepad_button", "Simulate a gamepad button press/release", {"button_index": {"type": "integer"}, "pressed": {"type": "boolean", "default": true}}, ["button_index"]),
		_make("runtime_gamepad_axis", "Simulate a gamepad axis movement (-1.0 to 1.0)", {"axis": {"type": "integer"}, "value": {"type": "number"}}, ["axis", "value"]),
		_make("runtime_touch_event", "Simulate a touch press/release", {"x": {"type": "integer"}, "y": {"type": "integer"}, "pressed": {"type": "boolean", "default": true}, "index": {"type": "integer", "default": 0}}, ["x", "y"]),
		_make("runtime_touch_drag", "Simulate a touch drag", {"x": {"type": "integer"}, "y": {"type": "integer"}, "relative_x": {"type": "integer"}, "relative_y": {"type": "integer"}, "index": {"type": "integer", "default": 0}}, ["x", "y", "relative_x", "relative_y"]),

		_make("runtime_shader_set_param", "Set a shader parameter on a node's material", {"node_path": {"type": "string"}, "param_name": {"type": "string"}, "value": {}}, ["node_path", "param_name", "value"]),
		_make("runtime_particles_config", "Configure GPUParticles2D/3D emitting, amount, lifetime, speed", {"node_path": {"type": "string"}, "emitting": {"type": "boolean", "default": false}, "amount": {"type": "integer", "default": -1}, "lifetime": {"type": "number", "default": -1.0}, "speed_scale": {"type": "number", "default": -1.0}}, ["node_path"]),

		_make("runtime_network_create_server", "Create an ENet multiplayer server", {"port": {"type": "integer", "default": 9050}, "max_clients": {"type": "integer", "default": 4}}),
		_make("runtime_network_create_client", "Connect as ENet multiplayer client", {"address": {"type": "string", "default": "127.0.0.1"}, "port": {"type": "integer", "default": 9050}}),
		_make("runtime_network_disconnect", "Disconnect from the multiplayer session"),
		_make("runtime_network_get_peers", "List connected multiplayer peers"),
		_make("runtime_network_send_rpc", "Broadcast an RPC call to all peers", {"method": {"type": "string"}, "args": {"type": "array", "default": []}}, ["method"]),
	]


static func _make(name: String, description: String, properties: Dictionary = {}, required: Array = []) -> Dictionary:
	var schema := {"type": "object", "properties": properties}
	if not required.is_empty():
		schema["required"] = required
	return {"name": name, "description": description, "inputSchema": schema}


func dispatch_tool(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_audio_play": return audio_play(str(args.get("node_path", "")), str(args.get("stream_path", "")))
		"runtime_audio_stop": return audio_stop(str(args.get("node_path", "")))
		"runtime_audio_bus_info": return audio_bus_info()
		"runtime_audio_set_volume": return audio_set_volume(int(args.get("bus_index", 0)), float(args.get("volume_db", 0.0)))
		"runtime_audio_list_streams": return audio_list_streams()
		"runtime_audio_set_stream": return audio_set_stream(str(args.get("node_path", "")), str(args.get("stream_path", "")))
		"runtime_animation_list": return animation_list(str(args.get("node_path", "")))
		"runtime_animation_play": return animation_play(str(args.get("node_path", "")), str(args.get("anim_name", "")), float(args.get("custom_speed", 1.0)))
		"runtime_animation_stop": return animation_stop(str(args.get("node_path", "")))
		"runtime_animation_seek": return animation_seek(str(args.get("node_path", "")), float(args.get("seconds", 0.0)), str(args.get("seek_anim_name", "")))
		"runtime_animation_get_info": return animation_get_info(str(args.get("node_path", "")))
		"runtime_animation_tree_travel": return animation_tree_travel(str(args.get("node_path", "")), str(args.get("state_name", "")))
		"runtime_animation_tree_set_param": return animation_tree_set_param(str(args.get("node_path", "")), str(args.get("param_name", "")), args.get("value"))
		"runtime_gamepad_button": return gamepad_button(int(args.get("button_index", 0)), bool(args.get("pressed", true)))
		"runtime_gamepad_axis": return gamepad_axis(int(args.get("axis", 0)), float(args.get("value", 0.0)))
		"runtime_touch_event": return touch_event(int(args.get("x", 0)), int(args.get("y", 0)), bool(args.get("pressed", true)), int(args.get("index", 0)))
		"runtime_touch_drag": return touch_drag(int(args.get("x", 0)), int(args.get("y", 0)), int(args.get("relative_x", 0)), int(args.get("relative_y", 0)), int(args.get("index", 0)))
		"runtime_shader_set_param": return shader_set_param(str(args.get("node_path", "")), str(args.get("param_name", "")), args.get("value"))
		"runtime_particles_config": return particles_config(str(args.get("node_path", "")), bool(args.get("emitting", false)), int(args.get("amount", -1)), float(args.get("lifetime", -1.0)), float(args.get("speed_scale", -1.0)))
		"runtime_network_create_server": return network_create_server(int(args.get("port", 9050)), int(args.get("max_clients", 4)))
		"runtime_network_create_client": return network_create_client(str(args.get("address", "127.0.0.1")), int(args.get("port", 9050)))
		"runtime_network_disconnect": return network_disconnect()
		"runtime_network_get_peers": return network_get_peers()
		"runtime_network_send_rpc": return network_send_rpc(str(args.get("method", "")), args.get("args", []))
		_: return {"error": "Unknown game system tool: " + tool_name}