class_name MultiplayerSteam extends Node

signal connection_failed(reason: String)
signal connection_succeeded(peer_id: int)

@export var steam_manager: SteamManager

var _lobby_id := 0


## Hosts over Steam's relay. The hosted lobby's ID is the game code
func start_server(_solo: bool = false) -> MultiplayerPeer:
	_lobby_id = await steam_manager.host_lobby()
	if _lobby_id == 0:
		return null

	# Via ClassDB: a static `SteamMultiplayerPeer` ref won't parse on Web
	var peer = ClassDB.instantiate("SteamMultiplayerPeer")
	if peer.create_host(0) != OK:
		DebugUtils.DebugErrMsg("failed to create Steam host")
		return null
	return peer


## No-op: ConnectionManager leaves the hosted lobby
func stop_server():
	pass


## Joins the Steam lobby, then connects to its owner. Returns OK on success.
func connect_client(lobby_id: String) -> Error:
	var join_error: String = await steam_manager.join_lobby(lobby_id.to_int())
	if !join_error.is_empty():
		connection_failed.emit(join_error)
		return ERR_CANT_CONNECT

	var peer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: Error = peer.create_client(steam_manager.get_lobby_owner(), 0)
	if err != OK:
		connection_failed.emit(tr("CONN_ERR_STEAM_HOST"))
		return err

	multiplayer.multiplayer_peer = peer
	connection_succeeded.emit(peer.get_unique_id())
	return OK


func disconnect_client():
	steam_manager.leave_lobby()


func get_addr() -> String:
	return str(_lobby_id)
