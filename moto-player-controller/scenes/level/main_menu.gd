class_name MainMenu extends Control

signal do_close()

@onready var close_btn: Button = %CloseBtn

func _ready():
    close_btn.pressed.connect(func():
        do_close.emit()
    )

func _input(_event):
    if Input.is_action_just_pressed("brake_rear"):
        do_close.emit()
