class_name GamemodeStateContext extends StateContext

var gamemode_event: GameModeEventDefinition
var event_start_circle: EventStartCircle
var peer_id: int = -1
## Set when returning to free roam after finishing a race — tells FreeRoamGameMode to leave
## players where they finished instead of redistributing them to the grid.
var skip_spawn_redistribute: bool = false
