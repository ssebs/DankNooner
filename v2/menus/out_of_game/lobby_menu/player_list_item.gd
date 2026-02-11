@tool
class_name PlayerListItem extends MarginContainer

@export var player_definition: PlayerDefinition = preload(
	"res://resources/entities/player/default_player_definition.tres"
)

@onready var icon: TextureRect = %PlayerIcon
@onready var player_name: Label = %PlayerName
@onready var ping: Label = %PingLabel
@onready var host_label: Label = %HostLabel


func _ready():
	update_ui_from_player_definition()


func update_ui_from_player_definition():
	icon.texture = player_definition.ui_icon
	player_name.text = player_definition.username
