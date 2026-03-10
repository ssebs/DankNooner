@tool
## How to use -
## Add node to _Editor_Tools in MainGame
## Add Camera3D as Child, move to position using Align Transform with View
## Set export vars
## Save
## Add this to level_manager
class_name LevelPreviewImgGen extends Node

@export var level_manager: LevelManager
@export var level_name: LevelManager.LevelName
@export var cam: Camera3D
@export_tool_button("Save img") var btn_1 = save_img

var img_path: String = "res://levels/previews/"


func _ready():
	level_manager.spawn_level(level_name, InputStateManager.InputState.IN_MENU)


func save_img():
	# take screenshot from camera
	# save to img_path/level.name.jpg
	pass
