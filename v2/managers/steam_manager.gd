@tool
class_name SteamManager extends BaseManager

## A Steam invite / "Join Game" resolved to a game code; read it with take_pending_game_id()
signal invite_received
signal avatar_loaded(steam_id: int, texture: ImageTexture)

# Steamworks enum values; no static `Steam` ref (see `steam`)
const RESULT_OK := 1
const CHAT_ROOM_ENTER_SUCCESS := 1
const LOBBY_TYPE_FRIENDS_ONLY := 1
const LOBBY_TYPE_PUBLIC := 2
const LOBBY_COMPARISON_EQUAL := 0
const LOBBY_DISTANCE_FILTER_WORLDWIDE := 3
const CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST := 2
const CHAT_ROOM_ENTER_RESPONSE_NOT_ALLOWED := 3
const CHAT_ROOM_ENTER_RESPONSE_FULL := 4
## Steam's reasons for refusing a lobby join => localization key. Not joinable reads as not allowed
const ENTER_RESPONSE_ERRORS: Dictionary[int, String] = {
	CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST: "CONN_ERR_LOBBY_GONE",
	CHAT_ROOM_ENTER_RESPONSE_NOT_ALLOWED: "CONN_ERR_LOBBY_LOCKED",
	CHAT_ROOM_ENTER_RESPONSE_FULL: "CONN_ERR_LOBBY_FULL",
}
const LOBBY_GAME_ID_KEY := "game_id"
# Browser rows: the host's name, LevelManager.LevelName (LEVEL_SELECT_LABEL while in the lobby menu)
const LOBBY_HOST_NAME_KEY := "host_name"
const LOBBY_LEVEL_KEY := "level"
## The browser only lists lobbies on this exact config/version: synced state changes between releases
const LOBBY_VERSION_KEY := "version"
# getPlayerAvatar size: 1 small, 2 medium (64px), 3 large
const AVATAR_MEDIUM := 2

## Null when Steam is unavailable (Web, no client). Via Engine: a static `Steam` ref won't parse on Web
var steam: Object
## Game code from an accepted invite, waiting for the play menu to join it
var pending_game_id := ""
## Our hosted lobby is listed in the server browser; it starts friends-only
var is_lobby_public := false

## The Steam lobby we host, or joined (only the Steam transport joins; others just read its data)
var _lobby_id := 0
## Cleared by leave_lobby(), so a lobby that finishes creating/joining after that is left
var _in_session := false
var _requested_lobby_id := 0
## Steam is still fetching these non-friends' info; their avatars are requested when it lands
var _pending_avatar_ids: Dictionary[int, bool] = {}


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
	if _keep_lobby(created[1]) == 0:
		return 0
	is_lobby_public = false
	steam.setLobbyData(_lobby_id, LOBBY_HOST_NAME_KEY, steam.getPersonaName())
	steam.setLobbyData(_lobby_id, LOBBY_VERSION_KEY, _get_version())
	return _lobby_id


## Returns "" on success (connect to get_lobby_owner()), else why the join failed
func join_lobby(lobby_id: int) -> String:
	_in_session = true
	steam.joinLobby(lobby_id)
	var joined: Array = await Signal(steam, "lobby_joined")
	var response: int = joined[3]
	if response != CHAT_ROOM_ENTER_SUCCESS:
		DebugUtils.DebugMsg("Steam: couldn't join lobby %s (%s)" % [lobby_id, response])
		var reason: String = ENTER_RESPONSE_ERRORS.get(response, "CONN_ERR_STEAM_LOBBY")
		return tr(reason).format({"lobby_id": lobby_id})
	if _keep_lobby(lobby_id) == 0:
		return tr("CONN_ERR_STEAM_LOBBY").format({"lobby_id": lobby_id})
	return ""


func get_lobby_owner() -> int:
	return steam.getLobbyOwner(_lobby_id)


## Public lobbies are listed in the server browser; friends-only ones are reached by invite
func set_lobby_public(public: bool):
	is_lobby_public = public
	steam.setLobbyType(_lobby_id, LOBBY_TYPE_PUBLIC if public else LOBBY_TYPE_FRIENDS_ONLY)


## Host: what the browser shows, and whether the lobby takes joins. A locked lobby drops out of
## search results and refuses joins and invites
func set_lobby_state(joinable: bool, level_name: LevelManager.LevelName):
	# Lobby creation failed or the session ended — nothing to advertise
	if _lobby_id == 0:
		return
	steam.setLobbyJoinable(_lobby_id, joinable)
	steam.setLobbyData(_lobby_id, LOBBY_LEVEL_KEY, str(level_name))


## Joinable public lobbies on our version, as rows for the server browser
func find_lobbies() -> Array[Dictionary]:
	steam.addRequestLobbyListStringFilter(LOBBY_VERSION_KEY, _get_version(), LOBBY_COMPARISON_EQUAL)
	steam.addRequestLobbyListDistanceFilter(LOBBY_DISTANCE_FILTER_WORLDWIDE)
	steam.requestLobbyList()
	var lobby_ids: Array = await Signal(steam, "lobby_match_list")

	var rows: Array[Dictionary] = []
	for lobby_id: int in lobby_ids:
		rows.append({
			"id": lobby_id,
			"host_name": steam.getLobbyData(lobby_id, LOBBY_HOST_NAME_KEY),
			"members": steam.getNumLobbyMembers(lobby_id),
			"max_members": steam.getLobbyMemberLimit(lobby_id),
			# Empty before the host's first gamemode: still in the lobby menu
			"level": steam.getLobbyData(lobby_id, LOBBY_LEVEL_KEY).to_int(),
		})
	return rows


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


## Emits avatar_loaded when Steam has it
func request_avatar(steam_id: int):
	# True: Steam doesn't know this non-friend yet; persona_state_change asks again once it does
	if steam.requestUserInformation(steam_id, false):
		_pending_avatar_ids[steam_id] = true
		return
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
	steam.connect("persona_state_change", _on_persona_state_change)

	# Cold launch from an invite: Steam appends `+connect_lobby <id>`
	var args := OS.get_cmdline_args()
	var idx := args.find("+connect_lobby")
	if idx != -1 and idx + 1 < args.size():
		_on_join_requested(args[idx + 1].to_int(), 0)


func _get_version() -> String:
	return ProjectSettings.get_setting("application/config/version")


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


## Also fires for friends' status changes, hence the pending set
func _on_persona_state_change(steam_id: int, _flags: int):
	if _pending_avatar_ids.erase(steam_id):
		steam.getPlayerAvatar(AVATAR_MEDIUM, steam_id)


func _on_avatar_loaded(steam_id: int, size: int, data: PackedByteArray):
	var image := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	avatar_loaded.emit(steam_id, ImageTexture.create_from_image(image))
