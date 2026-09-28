@tool
class_name TutorialGameMode extends RunnerGameMode

@export var results_hud: ResultsHUDState
@export var input_state_manager: InputStateManager
@export var menu_manager: MenuManager
@export var help_menu_state: HelpMenuState

var _results_countdown: float = -1.0
var _results_countdown_total: float = 10.0

func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GameModeType.Kind.TUTORIAL
	DebugUtils.DebugMsg("Tutorial Mode")

	super(state_context)
	results_hud.skip_pressed.connect(_on_results_skip_pressed)

	if multiplayer.is_server():
		# Initial teleport is handled by a leading TeleportTask in each runner.
		_start_next_runner()


func Update(delta: float):
	if !multiplayer.is_server():
		return
	if _update_results_countdown(delta):
		return
	super(delta)


func Exit(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	results_hud.skip_pressed.disconnect(_on_results_skip_pressed)
	# results_hud sets IN_GAME_PAUSED when it shows; restore IN_GAME on the way out so
	# the cursor doesn't stay visible after skip→free-roam.
	if results_hud.ui.visible:
		input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME
	results_hud.hide_ui()
	super(state_context)


#region Setup


## Tutorial-specific tasks need menu/input managers on top of the runner deps.
func _inject_runner_deps():
	super()
	for runner in _runners:
		_inject_task_deps(runner)


func _inject_task_deps(runner: TaskRunner):
	for child in runner.get_children():
		if child is CloseHelpTask:
			child.input_state_manager = input_state_manager
			child.menu_manager = menu_manager
			child.help_menu_state = help_menu_state
		elif child is TaskRunner:
			_inject_task_deps(child)


#endregion

#region Results


func _update_results_countdown(delta: float) -> bool:
	if _results_countdown <= 0.0:
		return false
	_results_countdown -= delta
	if _results_countdown <= 0.0:
		_results_countdown = -1.0
		_return_to_free_roam()
	return true


#override
func _on_last_runner_completed(runner: TaskRunner):
	var rows: Array[Dictionary] = []
	for peer_id in runner._player_states:
		var state = runner._player_states[peer_id] as PlayerTaskState
		var username: String = lobby_manager.lobby_players[peer_id].username
		var time_sec: float = state.completion_time_ms / 1000.0
		(
			rows
			.append(
				{
					"Username": username,
					"Time": "%.1fs" % time_sec,
					"_sort_key": state.completion_time_ms,
				}
			)
		)
	rows.sort_custom(func(a, b): return a["_sort_key"] < b["_sort_key"])

	var data := ResultsData.create(tr("TUT_COMPLETE"), ["Username", "Time"], rows, ["", "⏱"])
	_results_countdown = _results_countdown_total
	tutorial_hud.rpc_hide.rpc()
	results_hud.rpc_show_results.rpc(data.to_dict(), _results_countdown_total)


func _on_results_skip_pressed():
	if !multiplayer.is_server():
		return
	_results_countdown = -1.0
	_return_to_free_roam()


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if results_hud == null:
		issues.append("results_hud must not be empty")
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if help_menu_state == null:
		issues.append("help_menu_state must not be empty")
	return issues
