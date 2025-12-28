class_name MainMenu extends Control

signal do_close()

func _input(_event):
    if Input.is_anything_pressed():
        do_close.emit()
