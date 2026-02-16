@tool
class_name GamemodeManager extends BaseManager

enum MatchState {
	IN_LOBBY,
	IN_GAME,
}
enum GameMode { FREE_FROAM, STREET_RACE, STUNT_RACE, TRACK_RACE }

@export var menu_manager: MenuManager
@export var settings_manager: SettingsManager
@export var multiplayer_manager: MultiplayerManager
@export var level_manager: LevelManager
@export var input_state_manager: InputStateManager

var match_state: MatchState = MatchState.IN_LOBBY
var game_mode: GameMode = GameMode.FREE_FROAM
