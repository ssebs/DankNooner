@tool
## Should only be running on server
class_name GameModeType extends State

enum Kind { FREE_ROAM, STREET_RACE, STUNT_RACE, TUTORIAL, CHALLENGE }

@export var gamemode_manager: GamemodeManager
@export var spawn_manager: SpawnManager

## If set, the loadout picker should filter to loadouts whose `base_res_path` matches this
## bike. v1: field only — no consumers wired yet.
@export var forced_base_bike: BikeSkinDefinition = null


func Enter(_state_context: StateContext):
	if Engine.is_editor_hint():
		return


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
