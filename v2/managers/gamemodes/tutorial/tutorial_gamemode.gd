@tool
class_name TutorialGameMode extends GameMode

@export var tutorial_hud: TutorialHUD
@export var input_state_manager: InputStateManager
@export var lobby_manager: LobbyManager

var _steps_lib: TutorialSteps
var _current_sequence: Array[TutorialSteps.Step] = []
var _current_index: int = 0
var _target_peer_id: int = -1
var _respawn_delay: float = 3.0


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return

	gamemode_manager.current_game_mode = GamemodeManager.TGameMode.TUTORIAL
	DebugUtils.DebugMsg("Tutorial Mode")

	if state_context is GamemodeStateContext:
		_target_peer_id = state_context.peer_id
	else:
		_target_peer_id = multiplayer.get_unique_id()

	gamemode_manager.player_crashed.connect(_on_player_crashed)
	gamemode_manager.player_disconnected.connect(_on_player_disconnected)
	gamemode_manager.player_latejoined.connect(_on_player_latejoined)

	_steps_lib = TutorialSteps.new()
	_current_sequence = TutorialSteps.THE_BASICS
	_current_index = 0

	spawn_manager.spawn_all_players()

	if multiplayer.is_server():
		_start_step(_current_index)


func Update(delta: float):
	if !multiplayer.is_server():
		return

	if _current_index >= _current_sequence.size():
		return

	var step_enum := _current_sequence[_current_index]
	var step_def := _steps_lib.defs[step_enum]

	# Player may not be spawned yet during late-join sync — skip is intentional
	var player := spawn_manager._get_player_by_peer_id(_target_peer_id)
	if player == null:
		return

	if step_def.check.call(player, delta):
		if step_def.on_exit.is_valid():
			step_def.on_exit.call()
		_current_index += 1
		if _current_index >= _current_sequence.size():
			tutorial_hud.rpc_show_complete.rpc()
			get_tree().create_timer(3.0).timeout.connect(
				func(): _return_to_free_roam(), CONNECT_ONE_SHOT
			)
		else:
			_start_step(_current_index)


func _start_step(index: int):
	var step_enum := _current_sequence[index]
	var step_def := _steps_lib.defs[step_enum]
	if step_def.on_enter.is_valid():
		step_def.on_enter.call()
	tutorial_hud.rpc_show_step.rpc(index, _current_sequence.size(), step_def.objective_text, step_def.hint_text)


func _return_to_free_roam():
	var ctx := GamemodeStateContext.new()
	ctx.peer_id = _target_peer_id
	gamemode_manager._rpc_transition_gamemode.rpc(GamemodeManager.TGameMode.FREE_FROAM as int, _target_peer_id)


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.player_crashed.disconnect(_on_player_crashed)
	gamemode_manager.player_disconnected.disconnect(_on_player_disconnected)
	gamemode_manager.player_latejoined.disconnect(_on_player_latejoined)

	tutorial_hud.rpc_hide.rpc()


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

	# If the tutorial player disconnected, return to free roam
	if peer_id == _target_peer_id and multiplayer.is_server():
		_return_to_free_roam()


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if tutorial_hud == null:
		issues.append("tutorial_hud must not be empty")
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	if lobby_manager == null:
		issues.append("lobby_manager must not be empty")

	return issues
