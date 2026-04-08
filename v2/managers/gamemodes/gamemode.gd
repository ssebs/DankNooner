@tool
## Should only be running on server
class_name GameMode extends State

@export var gamemode_manager: GamemodeManager
@export var spawn_manager: SpawnManager


func Enter(_state_context: StateContext):
	if Engine.is_editor_hint():
		return


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
