@tool
class_name PlayerListItem extends MarginContainer

@export var player_definition: PlayerDefinition = preload(
	"res://resources/player/default_player_definition.tres"
)

@onready var icon: TextureRect = %PlayerIcon
## Fills and is cropped to the round frame; the logo keeps its padding since it reaches its corners
@onready var avatar_icon: TextureRect = %AvatarIcon
@onready var player_name: Label = %PlayerName
@onready var ping: Label = %PingLabel
@onready var host_label: Label = %HostLabel


func _ready():
	update_ui_from_player_definition()


func update_ui_from_player_definition():
	icon.texture = player_definition.ui_icon
	icon.show()
	avatar_icon.hide()
	player_name.text = player_definition.username


func set_avatar(texture: Texture2D):
	avatar_icon.texture = texture
	avatar_icon.show()
	icon.hide()


func set_ping(value: String):
	ping.text = tr("LOBBY_PING_LABEL").format({"value": value})
