@tool
class_name GameModeEventConfirmHUD extends Control

signal hud_closed
signal hud_submitted

@onready var submit_btn: Button = %SubmitBtn
@onready var close_btn: Button = %CloseBtn

@onready var gm_name: Label = %GamemodeName
@onready var gm_desc: Label = %GamemodeDesc


func _ready():
	hide_ui()


func show_ui():
	self.show()
	submit_btn.pressed.connect(_on_submit_pressed)
	close_btn.pressed.connect(_on_close_pressed)


func hide_ui():
	self.hide()
	if submit_btn.pressed.has_connections():
		submit_btn.pressed.disconnect(_on_submit_pressed)
	if close_btn.pressed.has_connections():
		close_btn.pressed.disconnect(_on_close_pressed)


func set_gamemode_hud_and_show_ui(gamemode_name: String, gamemode_description: String):
	gm_name.text = tr(gamemode_name)
	gm_desc.text = tr(gamemode_description)
	show_ui()


func _on_submit_pressed():
	hud_submitted.emit()


func _on_close_pressed():
	hud_closed.emit()
