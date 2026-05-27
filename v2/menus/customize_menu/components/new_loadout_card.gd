@tool
## "+ New" tile shown at the end of the loadout grid. Disables itself when at cap.
class_name NewLoadoutCard extends Control

signal new_pressed

@onready var btn: Button = %Btn


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	btn.pressed.connect(func(): new_pressed.emit())


func disable_btn():
	btn.disabled = true
