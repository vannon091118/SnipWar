; Minimal foreign project for the portable MCP smoke test.
; NOT SnipWar: no GameState/EventLog autoloads, no MCP autoloads, no MCP settings.
; The only thing we enable is the GDScript MCP Bridge plugin — everything else
; must be self-registered by the addon.

config_version=5

[application]

config/name="PortableMCP_Smoke"
run/main_scene="res://bootstrap_button.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")

[editor_plugins]

enabled=PackedStringArray("res://addons/gdscript_mcp/plugin.cfg")

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"