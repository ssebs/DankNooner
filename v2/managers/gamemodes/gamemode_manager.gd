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
@export var spawn_manager: SpawnManager
@export var audio_manager: AudioManager
@export var input_state_manager: InputStateManager

var match_state: MatchState = MatchState.IN_LOBBY
var game_mode: GameMode = GameMode.FREE_FROAM
var current_level_name: LevelManager.LevelName = LevelManager.LevelName.LEVEL_SELECT_LABEL

# peer_id -> [bike_skin_path, character_skin_path]
var _player_skins: Dictionary = {}


func _ready():
	if Engine.is_editor_hint():
		return
	multiplayer_manager.client_connection_succeeded.connect(_on_client_connection_succeeded)
	multiplayer_manager.player_connected.connect(_on_player_connected)
	multiplayer_manager.player_disconnected.connect(_on_player_disconnected)


## Called by lobby menu to report a player's skin choices to the server
@rpc("call_local", "any_peer", "reliable")
func update_player_skins(peer_id: int, bike_skin_path: String, character_skin_path: String):
	if !multiplayer.is_server():
		return
	_player_skins[peer_id] = [bike_skin_path, character_skin_path]


## Called by server to start the game for all players
@rpc("call_local", "reliable")
func start_game(level_name: LevelManager.LevelName):
	current_level_name = level_name
	match_state = MatchState.IN_GAME
	level_manager.spawn_level(level_name, InputStateManager.InputState.IN_GAME)

	_spawn_all_players()  # TODO - use gamemodemanager to spawn!


## Called when returning to lobby
func end_game():
	match_state = MatchState.IN_LOBBY
	current_level_name = LevelManager.LevelName.LEVEL_SELECT_LABEL

	audio_manager.stop_all()


func _spawn_all_players():
	if !multiplayer.is_server():
		return

	for peer_id in multiplayer_manager.lobby_players:
		var username = multiplayer_manager.lobby_players[peer_id]
		var skins = _player_skins.get(peer_id, ["", ""])
		_rpc_spawn_player.rpc(peer_id, username, skins[0], skins[1])


#region network handlers
func _on_player_connected(peer_id: int, _all_players: Dictionary):
	_on_client_connection_succeeded(peer_id)


func _on_player_disconnected(peer_id: int):
	if !multiplayer.is_server():
		return

	_player_skins.erase(peer_id)

	if match_state == MatchState.IN_GAME:
		_rpc_despawn_player.rpc(peer_id)


func _on_client_connection_succeeded(peer_id: int):
	if !multiplayer.is_server():
		return

	print("_on_client_connection_succeeded %s" % peer_id)

	if match_state == MatchState.IN_GAME:
		_sync_game_to_late_joiner.rpc_id(peer_id, current_level_name)


#endregion

#region spawn RPCs
## Server calls this on a late-joining client to sync them into the active game
@rpc("any_peer", "reliable")
func _sync_game_to_late_joiner(level_name: LevelManager.LevelName):
	print("_sync_game_to_late_joiner")
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

	# Spawn the new player for everyone
	var username = multiplayer_manager.lobby_players[peer_id]
	var skins = _player_skins.get(peer_id, ["", ""])
	_rpc_spawn_player.rpc(peer_id, username, skins[0], skins[1])

	# Send existing players to the late-joiner
	for existing_id in multiplayer_manager.lobby_players:
		if existing_id == peer_id:
			continue
		var existing_username = multiplayer_manager.lobby_players[existing_id]
		var existing_skins = _player_skins.get(existing_id, ["", ""])
		_rpc_spawn_player.rpc_id(
			peer_id, existing_id, existing_username, existing_skins[0], existing_skins[1]
		)


## Server broadcasts to all peers to spawn a player
@rpc("call_local", "reliable")
func _rpc_spawn_player(
	peer_id: int, username: String, bike_skin_path: String, character_skin_path: String
):
	spawn_manager.add_player_locally(peer_id, username, bike_skin_path, character_skin_path)


## Server broadcasts to all peers to despawn a player
@rpc("call_local", "reliable")
func _rpc_despawn_player(peer_id: int):
	spawn_manager.remove_player_locally(peer_id)


#endregion


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
	if spawn_manager == null:
		issues.append("spawn_manager must not be empty")

	return issues
