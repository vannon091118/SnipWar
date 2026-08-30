# Temporary probe — identify extra Field children at node_count_drift.
# Hooked via v2_context.verify_checkpoint by name match; removed after audit.
class_name PreflightV2ProbeFieldLeak
extends RefCounted

static func describe(field: Node) -> String:
	if field == null:
		return "field is null"
	var lines: PackedStringArray = PackedStringArray()
	lines.append("field=%s child_count=%d" % [field.name, field.get_child_count()])
	for child in field.get_children():
		lines.append("  - %s class=%s script=%s" % [child.name, child.get_class(), (child.get_script().resource_path if child.get_script() else "none")])
	return "\n".join(lines)