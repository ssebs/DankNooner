@tool
class_name FreeRoamGameMode extends GameModeType

@export var game_mode_event_confirm_hud: GameModeEventConfirmHUD
@export var level_manager: LevelManager

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
	gamemode_manager.current_game_mode = GameModeType.Kind.FREE_ROAM
	DebugUtils.DebugMsg("FreeRoam Mode")

	gamemode_manager.player_crashed.connect(_on_player_crashed)
	gamemode_manager.player_disconnected.connect(_on_player_disconnected)
	gamemode_manager.player_latejoined.connect(_on_player_latejoined)

	_signals_event_circles(true)

	# Hide + disable every event's objects (checkpoints, etc.) — they only show
	# while their own gamemode is running. Initial-load default and return path.
	for event_start_circle in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["EventCircles"]):
		(event_start_circle as EventStartCircle).disable_game_objects()

	# Only spawn if players aren't already in the level (e.g. coming from another gamemode)
	if spawn_manager._get_player_by_peer_id(multiplayer.get_unique_id()) == null:
		spawn_manager.spawn_all_players()

	if multiplayer.is_server():
		# Distribute every peer to a unique spot. With grid_markers, each peer gets
		# its own grid slot (and persistent respawn point). Without, fall back to
		# the legacy single-spawn behavior.
		# Must hit every peer, not just _ctx.peer_id — that's only the player who
		# triggered the transition (the server, for race end), leaving clients riding.
		var grid_markers: Array[Marker3D] = level_manager.current_level.grid_markers
		var slot: int = 0
		for peer_id in gamemode_manager.lobby_manager.lobby_players:
			if grid_markers.is_empty():
				spawn_manager.reset_respawn_point.rpc(peer_id)
				spawn_manager.respawn_player.rpc(peer_id)
			else:
				var idx: int = min(slot, grid_markers.size() - 1)
				var marker := grid_markers[idx]
				spawn_manager.respawn_player_at.rpc(
					peer_id, marker.global_position, marker.global_basis
				)
				slot += 1


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


func _on_event_circle_entered(peer_id: int, source_circle: EventStartCircle):
	var ev := source_circle.gamemode_event
	DebugUtils.DebugMsg("%d entered eventcircle: %s" % [peer_id, ev.name])

	_ctx.gamemode_event = ev
	_ctx.event_start_circle = source_circle

	game_mode_event_confirm_hud.on_player_entered_circle.rpc_id(1, peer_id, ev.name, ev.description)

	# connect hud signals
	if not game_mode_event_confirm_hud.hud_submitted.is_connected(
		_on_game_mode_event_confirm_hud_submitted
	):
		game_mode_event_confirm_hud.hud_submitted.connect(_on_game_mode_event_confirm_hud_submitted)

	# TODO - set player velocity to 0


func _on_event_circle_exited(peer_id: int, source_circle: EventStartCircle):
	DebugUtils.DebugMsg("%d exited eventcircle: %s" % [peer_id, source_circle.gamemode_event.name])

	if game_mode_event_confirm_hud.hud_submitted.is_connected(
		_on_game_mode_event_confirm_hud_submitted
	):
		game_mode_event_confirm_hud.hud_submitted.disconnect(
			_on_game_mode_event_confirm_hud_submitted
		)

	game_mode_event_confirm_hud.on_player_close_pressed.rpc_id(1, peer_id)


func _on_game_mode_event_confirm_hud_submitted(peer_id: int):
	DebugUtils.DebugMsg("Starting Event... %d" % peer_id)
	game_mode_event_confirm_hud.on_player_close_pressed.rpc_id(1, peer_id)
	gamemode_manager.change_gamemode.rpc_id(
		1, _ctx.gamemode_event.target_gamemode, peer_id, _ctx.event_start_circle.get_path()
	)


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
		func(): _respawn_at_crash_site(peer_id), CONNECT_ONE_SHOT
	)


## Free roam respawns you where you crashed (upright, same heading) rather than back at
## spawn. Doesn't touch the persistent respawn point, so the pause-menu respawn button
## still returns to the original spawn.
func _respawn_at_crash_site(peer_id: int):
	var player := spawn_manager._get_player_by_peer_id(peer_id)
	var upright := Basis(Vector3.UP, player.global_rotation.y)
	spawn_manager.respawn_player_in_place.rpc(peer_id, player.global_position, upright)


func _on_player_latejoined(peer_id: int):
	gamemode_manager.latespawn_player(peer_id)


func _on_player_disconnected(peer_id: int):
	if gamemode_manager.match_state == GamemodeManager.MatchState.IN_GAME:
		spawn_manager.rpc_despawn_player.rpc(peer_id)


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if game_mode_event_confirm_hud == null:
		issues.append("game_mode_event_confirm_hud must not be empty")
	if level_manager == null:
		issues.append("level_manager must not be empty")

	return issues
