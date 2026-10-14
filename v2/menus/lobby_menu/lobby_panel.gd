@tool
## Game ID + copy, Steam invite and player list. Shared by the lobby and pause menus.
class_name LobbyPanel extends VBoxContainer

@onready var ip_label: Label = %IPLabel
@onready var ip_copy_btn: Button = %IPCopyBtn
@onready var invite_btn: Button = %InviteBtn
@onready var player_list: PlayerListUI = %PlayersList
@onready var ping_timer: Timer = %PingTimer

var _connection_manager: ConnectionManager
var _lobby_manager: LobbyManager
var _steam_manager: SteamManager


## Call from the owning menu's Enter(). can_invite: whether this peer owns the Steam lobby
func open(
	connection_manager: ConnectionManager, lobby_manager: LobbyManager,
	steam_manager: SteamManager, can_invite: bool
) -> void:
	_connection_manager = connection_manager
	_lobby_manager = lobby_manager
	_steam_manager = steam_manager

	ip_copy_btn.pressed.connect(copy_game_id)
	invite_btn.pressed.connect(_steam_manager.invite_friends)
	_steam_manager.avatar_loaded.connect(player_list.set_avatar)
	_connection_manager.game_id_set.connect(_on_game_id_set)
	_lobby_manager.lobby_players_updated.connect(_on_lobby_players_updated)
	ping_timer.timeout.connect(_on_ping_timer_timeout)
	ping_timer.start()

	invite_btn.visible = (
		can_invite and _connection_manager.connection_mode == ConnectionManager.ConnectionMode.STEAM
	)
	_on_game_id_set(_connection_manager.conn_addr)
	_on_lobby_players_updated(_lobby_manager.lobby_players)


## Call from the owning menu's Exit()
func close() -> void:
	player_list.clear()

	ip_copy_btn.pressed.disconnect(copy_game_id)
	invite_btn.pressed.disconnect(_steam_manager.invite_friends)
	_steam_manager.avatar_loaded.disconnect(player_list.set_avatar)
	_connection_manager.game_id_set.disconnect(_on_game_id_set)
	_lobby_manager.lobby_players_updated.disconnect(_on_lobby_players_updated)
	ping_timer.timeout.disconnect(_on_ping_timer_timeout)
	ping_timer.stop()


func copy_game_id() -> void:
	# Not the label: joining takes a bare IP, without the port
	DisplayServer.clipboard_set(_connection_manager.conn_addr)
	UiToast.ShowToast("Game ID copied to clipboard!")


## IP/Port mode adds the port, which the host has to forward
func _on_game_id_set(conn_addr: String) -> void:
	ip_label.text = conn_addr
	ip_copy_btn.disabled = conn_addr.is_empty()
	# Empty on connection reset
	if (
		!conn_addr.is_empty()
		and _connection_manager.connection_mode == ConnectionManager.ConnectionMode.IP_PORT
	):
		ip_label.text += ":%d" % UtilsConstants.PORT


func _on_lobby_players_updated(players: Dictionary) -> void:
	player_list.update_from_dict(players)
	# Each viewer fetches avatars from its own Steam client; without Steam the default icon stays
	if !_steam_manager.is_logged_in():
		return
	for player_def: PlayerDefinition in players.values():
		if player_def.steam_id != 0:
			_steam_manager.request_avatar(player_def.steam_id)


## Only clients measure ping (netfox's time sync RTT to the host)
func _on_ping_timer_timeout() -> void:
	if !NetworkTime.is_initial_sync_done() or multiplayer.is_server():
		return
	request_report_ping.rpc_id(1, roundi(NetworkTime.remote_rtt * 1000.0))


## Client → server: the sender reports its own ping
@rpc("any_peer", "call_remote", "unreliable")
func request_report_ping(ping_ms: int) -> void:
	if !multiplayer.is_server():
		return
	_sync_ping.rpc(multiplayer.get_remote_sender_id(), ping_ms)


@rpc("call_local", "unreliable")
func _sync_ping(peer_id: int, ping_ms: int) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	player_list.set_ping(peer_id, ping_ms)
