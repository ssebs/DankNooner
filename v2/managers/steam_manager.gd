@tool
class_name SteamManager extends BaseManager

## A Steam invite / "Join Game" resolved to a game code; read it with take_pending_game_id()
signal invite_received

# Steamworks enum values; no static `Steam` ref (see `steam`)
const RESULT_OK := 1
const LOBBY_TYPE_FRIENDS_ONLY := 1
const LOBBY_MAX_MEMBERS := 8
const LOBBY_GAME_ID_KEY := "game_id"

## Null when Steam is unavailable (Web, no client). Via Engine: a static `Steam` ref won't parse on Web
var steam: Object
## Game code from an accepted invite, waiting for the play menu to join it
var pending_game_id := ""

## The Steam lobby we host; joiners only read its data and never join it
var _lobby_id := 0
var _hosting_game_id := ""
var _requested_lobby_id := 0


func _ready():
	if Engine.is_editor_hint():
		return

	_init_steam()


## Steam is up and connected to Steam's servers; each feature decides what false means
func is_logged_in() -> bool:
	return steam != null and steam.loggedOn()


## Advertise `game_id` in a friends-only lobby so friends can be invited or "Join Game"
func host_lobby(game_id: String):
	_hosting_game_id = game_id
	steam.createLobby(LOBBY_TYPE_FRIENDS_ONLY, LOBBY_MAX_MEMBERS)


func leave_lobby():
	_hosting_game_id = ""
	# Not hosting a Steam lobby (Steam off, solo, or still being created) — nothing to leave
	if _lobby_id == 0:
		return
	steam.leaveLobby(_lobby_id)
	_lobby_id = 0


func invite_friends():
	steam.activateGameOverlayInviteDialog(_lobby_id)


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
	steam.connect("lobby_created", _on_lobby_created)
	steam.connect("join_requested", _on_join_requested)
	steam.connect("lobby_data_update", _on_lobby_data_update)

	# Cold launch from an invite: Steam appends `+connect_lobby <id>`
	var args := OS.get_cmdline_args()
	var idx := args.find("+connect_lobby")
	if idx != -1 and idx + 1 < args.size():
		_on_join_requested(args[idx + 1].to_int(), 0)


func _on_lobby_created(result: int, lobby_id: int):
	if result != RESULT_OK:
		DebugUtils.DebugMsg("Steam: lobby creation failed (%s)" % result)
		return
	_lobby_id = lobby_id
	# Session ended while the lobby was being created
	if _hosting_game_id.is_empty():
		leave_lobby()
		return
	steam.setLobbyData(lobby_id, LOBBY_GAME_ID_KEY, _hosting_game_id)


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
