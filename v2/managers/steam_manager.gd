@tool
class_name SteamManager extends BaseManager

## A Steam invite / "Join Game" resolved to a game code; read it with take_pending_game_id()
signal invite_received
signal avatar_loaded(steam_id: int, texture: ImageTexture)

# Steamworks enum values; no static `Steam` ref (see `steam`)
const RESULT_OK := 1
const CHAT_ROOM_ENTER_SUCCESS := 1
const LOBBY_TYPE_FRIENDS_ONLY := 1
const LOBBY_GAME_ID_KEY := "game_id"
# getPlayerAvatar size: 1 small, 2 medium (64px), 3 large
const AVATAR_MEDIUM := 2

## Null when Steam is unavailable (Web, no client). Via Engine: a static `Steam` ref won't parse on Web
var steam: Object
## Game code from an accepted invite, waiting for the play menu to join it
var pending_game_id := ""

## The Steam lobby we host, or joined (only the Steam transport joins; others just read its data)
var _lobby_id := 0
## Cleared by leave_lobby(), so a lobby that finishes creating/joining after that is left
var _in_session := false
var _requested_lobby_id := 0


func _ready():
	if Engine.is_editor_hint():
		return

	_init_steam()


## Steam is up and connected to Steam's servers; each feature decides what false means
func is_logged_in() -> bool:
	return steam != null and steam.loggedOn()


## Friends-only lobby so friends can be invited or "Join Game". Returns its ID, 0 on failure
func host_lobby() -> int:
	_in_session = true
	steam.createLobby(LOBBY_TYPE_FRIENDS_ONLY, UtilsConstants.MAX_LOBBY_SIZE)
	var created: Array = await Signal(steam, "lobby_created")
	if created[0] != RESULT_OK:
		DebugUtils.DebugMsg("Steam: lobby creation failed (%s)" % created[0])
		return 0
	return _keep_lobby(created[1])


## Returns the lobby owner's Steam ID to connect to, 0 on failure
func join_lobby(lobby_id: int) -> int:
	_in_session = true
	steam.joinLobby(lobby_id)
	var joined: Array = await Signal(steam, "lobby_joined")
	if joined[3] != CHAT_ROOM_ENTER_SUCCESS:
		DebugUtils.DebugMsg("Steam: couldn't join lobby %s (%s)" % [lobby_id, joined[3]])
		return 0
	if _keep_lobby(lobby_id) == 0:
		return 0
	return steam.getLobbyOwner(lobby_id)


## The code invitees join with
func set_lobby_game_id(game_id: String):
	# Lobby creation failed or the session ended — nothing to advertise
	if _lobby_id == 0:
		return
	steam.setLobbyData(_lobby_id, LOBBY_GAME_ID_KEY, game_id)


func leave_lobby():
	_in_session = false
	# No Steam lobby (Steam off, solo, or still being created) — nothing to leave
	if _lobby_id == 0:
		return
	steam.leaveLobby(_lobby_id)
	_lobby_id = 0


func invite_friends():
	steam.activateGameOverlayInviteDialog(_lobby_id)


## Emits avatar_loaded when Steam has it; users Steam doesn't know (non-friends) never load
func request_avatar(steam_id: int):
	steam.getPlayerAvatar(AVATAR_MEDIUM, steam_id)


func take_pending_game_id() -> String:
	var game_id := pending_game_id
	pending_game_id = ""
	return game_id


func _init_steam():
	if !Engine.has_singleton("Steam"):
		DebugUtils.DebugMsg("Steam: not available on this build")
		return

	# App ID from project settings, embedded callbacks. No restartAppIfNecessary(): it blocks offline play
	var result: Dictionary = Engine.get_singleton("Steam").steamInitEx(0, true)
	if result["status"] != 0:
		DebugUtils.DebugMsg("Steam: init failed (%s): %s" % [result["status"], result["verbal"]])
		return

	steam = Engine.get_singleton("Steam")
	steam.connect("join_requested", _on_join_requested)
	steam.connect("lobby_data_update", _on_lobby_data_update)
	steam.connect("avatar_loaded", _on_avatar_loaded)

	# Cold launch from an invite: Steam appends `+connect_lobby <id>`
	var args := OS.get_cmdline_args()
	var idx := args.find("+connect_lobby")
	if idx != -1 and idx + 1 < args.size():
		_on_join_requested(args[idx + 1].to_int(), 0)


func _keep_lobby(lobby_id: int) -> int:
	# Session ended while the lobby was being created/joined
	if !_in_session:
		steam.leaveLobby(lobby_id)
		return 0
	_lobby_id = lobby_id
	return lobby_id


func _on_join_requested(lobby_id: int, _friend_id: int):
	_requested_lobby_id = lobby_id
	steam.requestLobbyData(lobby_id)


func _on_lobby_data_update(success: int, lobby_id: int, member_id: int):
	# Also fires for our own hosted lobby and per-member updates
	if lobby_id != _requested_lobby_id or member_id != lobby_id:
		return
	_requested_lobby_id = 0
	if !success:
		DebugUtils.DebugMsg("Steam: couldn't read invite lobby %s" % lobby_id)
		return
	pending_game_id = steam.getLobbyData(lobby_id, LOBBY_GAME_ID_KEY)
	invite_received.emit()


func _on_avatar_loaded(steam_id: int, size: int, data: PackedByteArray):
	var image := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	avatar_loaded.emit(steam_id, ImageTexture.create_from_image(image))
