@tool
extends LevelDefinition


func _ready():
	if Engine.is_editor_hint():
		return
	# Server disconnect is handled by multiplayer.server_disconnected signal
	# which is already connected in MultiplayerManager.connect_client()
