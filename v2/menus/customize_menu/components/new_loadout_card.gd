@tool
## "+ New" tile shown at the end of the loadout grid. Disables itself when at cap.
class_name NewLoadoutCard extends Button

signal new_pressed


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	pressed.connect(func(): new_pressed.emit())
