@tool
class_name SettingsMenuState extends MenuState

@export var menu_manager: MenuManager
@export var main_menu_state: MenuState

@onready var back_btn: Button = %BackBtn


func Enter():
    ui.show()
    back_btn.pressed.connect(_on_back_pressed)


func Exit():
    ui.hide()
    back_btn.pressed.disconnect(_on_back_pressed)


func _on_back_pressed():
    transitioned.emit(main_menu_state)
