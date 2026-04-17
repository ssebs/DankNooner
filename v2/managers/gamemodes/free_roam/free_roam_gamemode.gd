@tool
class_name FreeRoamGameMode extends GameMode

@export var game_mode_event_confirm_hud: GameModeEventConfirmHUD

var _respawn_delay: float = 3.0

var _ctx: GamemodeStateContext


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	if state_context is GamemodeStateContext:
		_ctx = state_context
	else:
		_ctx = GamemodeStateContext.new()
		_ctx.peer_id = multiplayer.get_unique_id()
	gamemode_manager.current_game_mode = GamemodeManager.TGameMode.FREE_FROAM
	DebugUtils.DebugMsg("FreeRoam Mode")

	gamemode_manager.player_crashed.connect(_on_player_crashed)
	gamemode_manager.player_disconnected.connect(_on_player_disconnected)
	gamemode_manager.player_latejoined.connect(_on_player_latejoined)

	_signals_event_circles(true)

	# Only spawn if players aren't already in the level (e.g. coming from another gamemode)
	if spawn_manager._get_player_by_peer_id(multiplayer.get_unique_id()) == null:
		spawn_manager.spawn_all_players()

	if multiplayer.is_server():
		# Coming from another gamemode — respawn the target peer
		spawn_manager.respawn_player.rpc(_ctx.peer_id)


## param is whether to connect() or disconnect()
func _signals_event_circles(should_connect: bool):
	for event_start_circle in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["EventCircles"]):
		event_start_circle = event_start_circle as EventStartCircle
		if should_connect:
			event_start_circle.entered_event_circle.connect(_on_event_circle_entered)
			event_start_circle.exited_event_circle.connect(_on_event_circle_exited)
		else:
			event_start_circle.entered_event_circle.disconnect(_on_event_circle_entered)
			event_start_circle.exited_event_circle.disconnect(_on_event_circle_exited)


func _on_event_circle_entered(peer_id: int, gamemode_event: GameModeEvent):
	DebugUtils.DebugMsg("%d entered eventcircle: %s" % [peer_id, gamemode_event.name])

	_ctx.gamemode_event = gamemode_event

	game_mode_event_confirm_hud.on_player_entered_circle.rpc_id(
		1, peer_id, gamemode_event.name, gamemode_event.description
	)

	# connect hud signals
	if not game_mode_event_confirm_hud.hud_submitted.is_connected(
		_on_game_mode_event_confirm_hud_submitted
	):
		game_mode_event_confirm_hud.hud_submitted.connect(_on_game_mode_event_confirm_hud_submitted)

	# TODO - set player velocity to 0


func _on_event_circle_exited(peer_id: int, gamemode_event: GameModeEvent):
	DebugUtils.DebugMsg("%d exited eventcircle: %s" % [peer_id, gamemode_event.name])

	if game_mode_event_confirm_hud.hud_submitted.is_connected(
		_on_game_mode_event_confirm_hud_submitted
	):
		game_mode_event_confirm_hud.hud_submitted.disconnect(_on_game_mode_event_confirm_hud_submitted)

	game_mode_event_confirm_hud.on_player_close_pressed.rpc_id(1, peer_id)


func _on_game_mode_event_confirm_hud_submitted(peer_id: int):
	DebugUtils.DebugMsg("Starting Event... %d" % peer_id)
	game_mode_event_confirm_hud.on_player_close_pressed.rpc_id(1, peer_id)
	gamemode_manager.change_gamemode.rpc_id(1, _ctx.gamemode_event.target_gamemode, peer_id)


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.player_crashed.disconnect(_on_player_crashed)
	gamemode_manager.player_disconnected.disconnect(_on_player_disconnected)
	gamemode_manager.player_latejoined.disconnect(_on_player_latejoined)

	_signals_event_circles(false)


func _on_player_crashed(peer_id: int):
	if !multiplayer.is_server():
		return

	get_tree().create_timer(_respawn_delay).timeout.connect(
		func(): spawn_manager.respawn_player.rpc(peer_id), CONNECT_ONE_SHOT
	)


func _on_player_latejoined(peer_id: int):
	gamemode_manager.latespawn_player(peer_id)


func _on_player_disconnected(peer_id: int):
	if gamemode_manager.match_state == GamemodeManager.MatchState.IN_GAME:
		spawn_manager.rpc_despawn_player.rpc(peer_id)


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if game_mode_event_confirm_hud == null:
		issues.append("game_mode_event_confirm_hud must not be empty")

	return issues
