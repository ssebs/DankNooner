@tool
class_name PlayerListItem extends MarginContainer

@export var player_definition: PlayerDefinition

@onready var icon: TextureRect = %PlayerIcon
@onready var player_name: Label = %PlayerName
@onready var ping: Label = %PingLabel


func _ready():
	update_ui_from_player_definition()


func update_ui_from_player_definition():
	icon.texture = player_definition.ui_icon
	player_name.text = player_definition.username
