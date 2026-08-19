class_name GameStateAccess

static func autoload(node: Node) -> Node:
	if Engine.is_editor_hint() or node == null or not node.is_inside_tree():
		return null
	return node.get_tree().root.get_node_or_null("GameState")
