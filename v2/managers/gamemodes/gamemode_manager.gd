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
var current_level_name: LevelManager.LevelName = LevelManager.LevelName.LEVEL_SELECT_LABEL


func _ready():
	if Engine.is_editor_hint():
		return
	multiplayer_manager.player_connected.connect(_on_player_connected)


## Called by server to start the game for all players
@rpc("call_local", "reliable")
func start_game(level_name: LevelManager.LevelName):
	current_level_name = level_name
	match_state = MatchState.IN_GAME
	level_manager.spawn_level(level_name, InputStateManager.InputState.IN_GAME)
	_spawn_all_players()


## Called when returning to lobby
func end_game():
	match_state = MatchState.IN_LOBBY
	current_level_name = LevelManager.LevelName.LEVEL_SELECT_LABEL


func _spawn_all_players():
	for p in multiplayer_manager.lobby_players:
		level_manager.spawn_player(p)


func _on_player_connected(id: int, _all_players: Dictionary):
	if !multiplayer.is_server():
		return

	if match_state == MatchState.IN_GAME:
		# Late-joiner: tell them to load the level, then spawn them
		_sync_game_to_late_joiner.rpc_id(id, current_level_name)


## Server calls this on a late-joining client to sync them into the active game
@rpc("authority", "call_remote", "reliable")
func _sync_game_to_late_joiner(level_name: LevelManager.LevelName):
	match_state = MatchState.IN_GAME
	current_level_name = level_name
	level_manager.spawn_level(level_name, InputStateManager.InputState.IN_GAME)

	# Wait a frame for the level scene tree to be ready before spawning
	await get_tree().process_frame

	# Request server to spawn our player after level is loaded
	_request_late_spawn.rpc_id(1, multiplayer.get_unique_id())


## Late-joining client requests the server to spawn their player
@rpc("any_peer", "call_local", "reliable")
func _request_late_spawn(peer_id: int):
	if !multiplayer.is_server():
		return
	level_manager.spawn_player(peer_id)


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if settings_manager == null:
		issues.append("settings_manager must not be empty")
	if multiplayer_manager == null:
		issues.append("multiplayer_manager must not be empty")
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")

	return issues
