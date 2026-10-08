class_name GamemodeStateContext extends StateContext

## Where FreeRoamGameMode puts riders when returning to free roam.
enum ReturnSpawn {
	LEVEL_GRID,  # one level grid marker each
	STAY,  # where they are (finished a race)
	RESPAWN_POINT,  # last checkpoint, or the event's start (cancelled event)
}

## The event being entered; null when returning to free roam.
var event: GameModeEvent
var peer_id: int = -1
var return_spawn: ReturnSpawn = ReturnSpawn.LEVEL_GRID
