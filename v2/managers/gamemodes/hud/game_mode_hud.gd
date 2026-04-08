@tool
class_name GameModeHUD extends Control

signal hud_closed
signal hud_submitted

@export var gamemode_name: String
@export var gamemode_description: String

@onready var submit_btn: Button = %SubmitBtn
@onready var close_btn: Button = %CloseBtn

@onready var gm_name: Label = %GamemodeName
@onready var gm_desc: Label = %GamemodeDesc


func _ready():
	gm_name.text = tr(gamemode_name)
	gm_desc.text = tr(gamemode_description)

	submit_btn.pressed.connect(func(): hud_submitted.emit())
	close_btn.pressed.connect(func(): hud_closed.emit())
