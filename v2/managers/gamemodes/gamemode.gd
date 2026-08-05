@tool
## Should only be running on server
class_name GameModeType extends State

## ROAD_RACE is the plain checkpoint race (closed roads, no traffic). STREET_RACE is the
## same race run through live traffic. STUNT_RACE is reserved and not implemented yet.
##
## GameModeEventDefinition.target_gamemode stores these as ints in level scenes, so
## INSERTING a value here renumbers every event circle after it — update those scenes to
## match, or append instead.
enum Kind { FREE_ROAM, ROAD_RACE, STREET_RACE, STUNT_RACE, TUTORIAL, CHALLENGE }

@export var gamemode_manager: GamemodeManager
@export var spawn_manager: SpawnManager


## Whether a late joiner can be dropped straight into this mode. Modes needing
## mid-match context (races: start circle + runner state) return false; the late
## joiner free-roams the level instead and syncs up at the next mode change.
func is_late_joinable() -> bool:
	return false


func Enter(_state_context: StateContext):
	if Engine.is_editor_hint():
		return


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
