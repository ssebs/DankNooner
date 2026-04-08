@tool
class_name GamemodeManager extends BaseManager

## connected to player_crashed
signal player_spawned(peer_id: int)
## connected to player_spawned
signal player_crashed(peer_id: int)
signal player_latejoined(peer_id: int)
signal player_disconnected(peer_id: int)

enum MatchState {
	IN_LOBBY,
	IN_GAME,
}
enum TGameMode { FREE_FROAM, STREET_RACE, STUNT_RACE, TUTORIAL }

@export var menu_manager: MenuManager
@export var settings_manager: SettingsManager
@export var connection_manager: ConnectionManager
@export var lobby_manager: LobbyManager
@export var level_manager: LevelManager
@export var spawn_manager: SpawnManager
@export var audio_manager: AudioManager
@export var input_state_manager: InputStateManager

@export var state_machine: StateMachine

@export var free_roam_mode: FreeRoamGameMode
@export var street_race_mode: StreetRaceGameMode
@export var tutorial_mode: TutorialGameMode

var match_state: MatchState = MatchState.IN_LOBBY
var current_game_mode: TGameMode = TGameMode.FREE_FROAM
var current_level_name: LevelManager.LevelName = LevelManager.LevelName.LEVEL_SELECT_LABEL

var _gamemode_map: Dictionary[TGameMode,GameMode] = {}


func _ready():
	if Engine.is_editor_hint():
		return

	_gamemode_map = {
		TGameMode.FREE_FROAM: free_roam_mode,
		TGameMode.STREET_RACE: street_race_mode,
		TGameMode.TUTORIAL: tutorial_mode,
	}

	connection_manager.client_connection_succeeded.connect(_on_client_connection_succeeded)
	connection_manager.player_connected.connect(_on_player_connected)
	connection_manager.player_disconnected.connect(_on_player_disconnected)
	spawn_manager.player_spawned.connect(_on_player_spawned)


## Called by server to start the game for all players
@rpc("call_local", "reliable")
func start_game(level_name: LevelManager.LevelName):
	current_level_name = level_name
	match_state = MatchState.IN_GAME
	level_manager.spawn_level(level_name, InputStateManager.InputState.IN_GAME)


## Called when returning to lobby
func end_game():
	match_state = MatchState.IN_LOBBY
	current_level_name = LevelManager.LevelName.LEVEL_SELECT_LABEL

	audio_manager.stop_all()


## Actually tell spawn manager to spawn all players in lobby_manager, RPC around
func latespawn_player(peer_id: int):
	# Spawn the new player for everyone
	var player_def: PlayerDefinition = lobby_manager.lobby_players[peer_id]
	spawn_manager.rpc_spawn_player.rpc(peer_id, player_def.to_dict())

	# Send existing players to the late-joiner
	for existing_id in lobby_manager.lobby_players:
		if existing_id == peer_id:
			continue
		var existing_player_def: PlayerDefinition = lobby_manager.lobby_players[existing_id]
		spawn_manager.rpc_spawn_player.rpc_id(peer_id, existing_id, existing_player_def.to_dict())


func _on_player_spawned(player: PlayerEntity):
	if !multiplayer.is_server():
		return
	player_spawned.emit(player.name)  # TODO - verify
	player.crashed.connect(_on_player_crashed)


func _on_player_crashed(peer_id: int):
	if !multiplayer.is_server():
		return
	player_crashed.emit(peer_id)


#region network handlers
func _on_player_disconnected(peer_id: int):
	if !multiplayer.is_server():
		return

	player_disconnected.emit(peer_id)


func _on_player_connected(peer_id: int):
	_on_client_connection_succeeded(peer_id)


func _on_client_connection_succeeded(peer_id: int):
	if !multiplayer.is_server():
		return

	DebugUtils.DebugMsg("_on_client_connection_succeeded %s" % peer_id)

	if match_state == MatchState.IN_GAME:
		# TODO - depend on gamemode
		_sync_game_to_late_joiner.rpc_id(peer_id, current_level_name)


#endregion

#region late-joiner sync
## Server calls this on a late-joining client to sync them into the active game
@rpc("any_peer", "reliable")
func _sync_game_to_late_joiner(level_name: LevelManager.LevelName):
	DebugUtils.DebugMsg("_sync_game_to_late_joiner")
	match_state = MatchState.IN_GAME
	current_level_name = level_name
	level_manager.spawn_level(level_name, InputStateManager.InputState.IN_GAME)

	# Request server to spawn our player after level is loaded
	_request_late_spawn.rpc_id(1, multiplayer.get_unique_id())


## Late-joining client requests the server to spawn their player
@rpc("any_peer", "call_local", "reliable")
func _request_late_spawn(peer_id: int):
	if !multiplayer.is_server():
		return

	player_latejoined.emit(peer_id)


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if settings_manager == null:
		issues.append("settings_manager must not be empty")
	if connection_manager == null:
		issues.append("connection_manager must not be empty")
	if lobby_manager == null:
		issues.append("lobby_manager must not be empty")
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	if spawn_manager == null:
		issues.append("spawn_manager must not be empty")
	if free_roam_mode == null:
		issues.append("free_roam_mode must not be empty")
	if street_race_mode == null:
		issues.append("street_race_mode must not be empty")
	if tutorial_mode == null:
		issues.append("tutorial_mode must not be empty")
	if state_machine == null:
		issues.append("state_machine must not be empty")

	return issues
