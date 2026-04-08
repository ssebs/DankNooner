@tool
class_name FreeRoamGameMode extends GameMode

@export var game_mode_event_confirm_hud: GameModeEventConfirmHUD

var _respawn_delay: float = 3.0


func Enter(_state_context: StateContext):
	if Engine.is_editor_hint():
		return

	gamemode_manager.current_game_mode = GamemodeManager.TGameMode.FREE_FROAM
	DebugUtils.DebugMsg("FreeRoam Mode")

	gamemode_manager.player_crashed.connect(_on_player_crashed)
	gamemode_manager.player_disconnected.connect(_on_player_disconnected)
	gamemode_manager.player_latejoined.connect(_on_player_latejoined)

	_signals_event_circles(true)

	spawn_manager.spawn_all_players()


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
	# TODO - show UI


func _on_event_circle_exited(peer_id: int, gamemode_event: GameModeEvent):
	DebugUtils.DebugMsg("%d exited eventcircle: %s" % [peer_id, gamemode_event.name])
	# TODO - hide UI


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
