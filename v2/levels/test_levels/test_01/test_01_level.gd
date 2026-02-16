@tool
extends LevelDefinition

@onready var multiplayer_spawner: MultiplayerSpawner = %MultiplayerSpawner


func _ready():
	if Engine.is_editor_hint():
		return

	multiplayer_spawner.despawned.connect(_on_spawner_despawned)


## MultiplayerSpawner despawns nodes when server disconnects
## Emit server_disconnected to trigger menu transition
func _on_spawner_despawned(_node: Node):
	if level_manager and level_manager.multiplayer_manager:
		level_manager.multiplayer_manager.server_disconnected.emit()
