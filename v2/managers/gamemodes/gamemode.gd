@tool
## Should only be running on server
class_name GameModeType extends State

## RACE, STUNT_RACE and TIME_ATTACK are all RaceGameMode (see its race_type).
##
## GameModeEventDefinition.target_gamemode stores these as ints in level scenes, so
## INSERTING a value here renumbers every event circle after it — update those scenes to
## match, or append instead.
enum Kind { FREE_ROAM, RACE, STUNT_RACE, TIME_ATTACK, TUTORIAL, STUNT_CHALLENGE, LONG_JUMP }

@export var gamemode_manager: GamemodeManager
@export var spawn_manager: SpawnManager


## Server-side: a player asked for a full respawn (hold R, pause menu). Return true when the
## mode handled it; false falls through to the normal respawn at the last checkpoint.
func handle_full_respawn(_peer_id: int) -> bool:
	return false


## Server-side: the host pressed Cancel Event. Return true when the mode ended the event itself
## (e.g. to show results); false returns straight to free roam.
func handle_cancel_event() -> bool:
	return false


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
