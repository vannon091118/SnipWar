extends RefCounted
class_name McpCustomToolLoader

## Hot-reload custom MCP tools from res://mcp_tools/.
## Any .gd file in that directory providing get_tool_defs() + dispatch_tool()
## is automatically registered with a "custom_" prefix.

const CUSTOM_TOOLS_DIR := "res://mcp_tools/"


static func discover_tools() -> Array:
	var tools: Array = []
	var da := DirAccess.open(CUSTOM_TOOLS_DIR)
	if da == null:
		return tools
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if entry.ends_with(".gd") and not entry.begins_with("."):
			var full_path := CUSTOM_TOOLS_DIR.path_join(entry)
			var script: Resource = load(full_path)
			if script != null:
				var instance = script.new()
				if instance.has_method("get_tool_defs"):
					var defs: Array = instance.get_tool_defs()
					for def in defs:
						if def is Dictionary:
							var name := str(def.get("name", ""))
							if not name.begins_with("custom_"):
								def["name"] = "custom_" + name
							tools.append(def)
		entry = da.get_next()
	da.list_dir_end()
	return tools


static func dispatch(tool_name: String, args: Dictionary) -> Variant:
	var clean_name := tool_name.trim_prefix("custom_")
	var da := DirAccess.open(CUSTOM_TOOLS_DIR)
	if da == null:
		return {"error": "Custom tools directory not found: " + CUSTOM_TOOLS_DIR}
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if entry.ends_with(".gd") and not entry.begins_with("."):
			var full_path := CUSTOM_TOOLS_DIR.path_join(entry)
			var script: Resource = load(full_path)
			if script != null:
				var instance = script.new()
				if instance.has_method("dispatch_tool"):
					var result: Variant = instance.dispatch_tool(clean_name, args)
					if result is Dictionary:
						var err := str(result.get("error", ""))
						if err == "" or not err.contains("Unknown"):
							return result
		entry = da.get_next()
	da.list_dir_end()
	return {"error": "Unknown custom tool: " + tool_name}