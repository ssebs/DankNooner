class_name MainLevel extends Node3D

@onready var main_menu: MainMenu  = %MainMenu
func _ready():
    main_menu.do_close.connect(on_close_menu)

func on_close_menu():
    main_menu.hide()
    main_menu.set_process_input(false)
