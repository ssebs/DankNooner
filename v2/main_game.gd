@tool
class_name MainGame extends Node

@export_tool_button("Run Validation") var run_validation = _run_validation


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	print(tr("GAME_TITLE"))


func _run_validation() -> void:
	var validator = load("res://utils/validation/auto_validator.gd")
	validator.validate_tree(get_tree())
	print("Validation complete!")
