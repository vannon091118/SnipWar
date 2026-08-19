@tool
class_name EffectDefinition
extends Resource

const OP_MULTIPLY: StringName = &"multiply"
const OP_ADD: StringName = &"add"

@export var target_stat: StringName = &""
@export var operation: StringName = OP_MULTIPLY
@export var value: float = 0.0
@export var description: String = ""

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(target_stat).is_empty():
		errors.append("effect target_stat is empty")
	if operation != OP_MULTIPLY and operation != OP_ADD:
		errors.append("effect operation '%s' is invalid (expected '%s' or '%s')" % [operation, OP_MULTIPLY, OP_ADD])
	return errors

func apply_to(base_value: float) -> float:
	if operation == OP_MULTIPLY:
		return base_value * value
	elif operation == OP_ADD:
		return base_value + value
	return base_value
