@tool
## Should only be running on server
class_name GameModeType extends State

enum Kind { FREE_FROAM, STREET_RACE, STUNT_RACE, TUTORIAL }

@export var gamemode_manager: GamemodeManager
@export var spawn_manager: SpawnManager


func Enter(_state_context: StateContext):
	if Engine.is_editor_hint():
		return


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
