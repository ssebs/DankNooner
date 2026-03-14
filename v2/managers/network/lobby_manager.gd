@tool
class_name LobbyManager extends BaseManager

signal lobby_players_updated(players: Dictionary)

@export var connection_manager: ConnectionManager
@export var save_manager: SaveManager

## Maps peer ID (int) → PlayerDefinition
var lobby_players: Dictionary[int, PlayerDefinition] = {}


func _ready():
	if Engine.is_editor_hint():
		return
	connection_manager.player_connected.connect(_on_player_connected)
	connection_manager.player_disconnected.connect(_on_player_disconnected)
	connection_manager.connection_reset.connect(_on_connection_reset)
	save_manager.save_item_updated.connect(_on_save_item_updated)
	save_manager.save_changed.connect(_on_save_changed)


#region Public API
## Client calls this to send their PlayerDefinition to server; server updates dict and broadcasts
@rpc("any_peer", "call_local", "reliable")
func update_player_metadata(peer_id: int, player_def_dict: Dictionary):
	if !multiplayer.is_server():
		return

	var player_def = PlayerDefinition.new()
	player_def.from_dict(player_def_dict)
	lobby_players[peer_id] = player_def
	_sync_lobby_players.rpc(_lobby_players_to_dict())


#endregion

## Server broadcasts full lobby_players dict to all clients
@rpc("call_local", "reliable")
func _sync_lobby_players(players_dict: Dictionary):
	lobby_players.clear()
	for peer_id_str in players_dict:
		var peer_id = int(peer_id_str)
		var player_def = PlayerDefinition.new()
		player_def.from_dict(players_dict[peer_id_str])
		lobby_players[peer_id] = player_def
	lobby_players_updated.emit(lobby_players)


func _lobby_players_to_dict() -> Dictionary:
	var result = {}
	for peer_id in lobby_players:
		result[peer_id] = lobby_players[peer_id].to_dict()
	return result


func _on_save_item_updated(key: String, value: Variant):
	if key != "player_definition":
		return
	_push_player_metadata(value)


func _on_save_changed(current_save: Dictionary):
	_push_player_metadata(current_save.get("player_definition"))


func _push_player_metadata(player_def: PlayerDefinition):
	if multiplayer.multiplayer_peer == null:
		return
	update_player_metadata.rpc_id(1, multiplayer.get_unique_id(), player_def.to_dict())


#region signal handlers
func _on_player_connected(id: int):
	lobby_players[id] = PlayerDefinition.new()


func _on_player_disconnected(id: int):
	lobby_players.erase(id)
	if multiplayer.is_server():
		_sync_lobby_players.rpc(_lobby_players_to_dict())


func _on_connection_reset():
	lobby_players.clear()


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if connection_manager == null:
		issues.append("connection_manager must not be empty")
	if save_manager == null:
		issues.append("save_manager must not be empty")

	return issues
