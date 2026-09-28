@tool
class_name TutorialGameMode extends RunnerGameMode

@export var menu_manager: MenuManager
@export var help_menu_state: HelpMenuState

func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GameModeType.Kind.TUTORIAL
	DebugUtils.DebugMsg("Tutorial Mode")

	super(state_context)

	if multiplayer.is_server():
		# Initial teleport is handled by a leading TeleportTask in each runner.
		_start_next_runner()


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


#override
func _on_last_runner_completed(runner: TaskRunner):
	_show_results(_completion_results(runner, "TUT_COMPLETE"))


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if help_menu_state == null:
		issues.append("help_menu_state must not be empty")
	return issues
