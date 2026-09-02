@tool
class_name McpTestScenario
extends Resource

## McpTestScenario — Predefined, deterministic MCP test scenario stored as .tres.
## Generic: not coupled to any specific game, only Godot + MCP tools.
##
## Usage: Create .tres files in res://addons/gdscript_mcp/testing/scenarios/
##         McpTestRunner reads them, boots the scene, calls MCP tools,
##         and validates expected results.

## Unique identifier (e.g. "main_menu_buttons")
@export var id: String = ""

## Human-readable description
@export var description: String = ""

## Path to .tscn to instantiate (relative to res://)
## Empty = use current empty SceneTree root (no boot)
@export var scene_path: String = ""

## Frames to wait after instantiating the scene before running steps
@export var wait_frames: int = 30

## Whether this scenario requires a real renderer (screenshots, pixel ops)
@export var requires_renderer: bool = false

## Enabled by default in the test runner
@export var enabled_by_default: bool = true

## Steps: array of {tool="runtime_ux_analyze", args={...}, expect_key="elements.size", expect_op=">=", expect_value=3}
## Supported expect_ops: "==", "!=", ">=", "<=", ">", "<", "contains", "has_key"
@export var steps: Array[Dictionary] = []