@tool
class_name GameModeEventConfirmHUD extends Control

signal hud_closed
signal hud_submitted

@onready var submit_btn: Button = %SubmitBtn
@onready var close_btn: Button = %CloseBtn

@onready var gm_name: Label = %GamemodeName
@onready var gm_desc: Label = %GamemodeDesc

var _gamemode_name: String
var _gamemode_description: String


func _ready():
	gm_name.text = tr(_gamemode_name)
	gm_desc.text = tr(_gamemode_description)


func show_ui():
	self.show()
	submit_btn.pressed.connect(_on_submit_pressed)
	close_btn.pressed.connect(_on_close_pressed)


func hide_ui():
	self.hide()
	submit_btn.pressed.disconnect(_on_submit_pressed)
	close_btn.pressed.disconnect(_on_close_pressed)


func set_gamemode_hud_and_show(gamemode_name: String, gamemode_description: String):
	_gamemode_name = gamemode_name
	_gamemode_description = gamemode_description
	show_ui()


func _on_submit_pressed():
	hud_submitted.emit()


func _on_close_pressed():
	hud_closed.emit()
