@tool
class_name TutorialGameMode extends RunnerGameMode

@export var menu_manager: MenuManager
@export var tour_manager: TourManager
## The event's PickupSpawners grant items through it, and DropItemTask listens to it.
@export var item_manager: ItemManager
## Where the player lands once the tutorial ends.
@export var play_menu_state: MenuState

func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GameModeType.Kind.TUTORIAL
	DebugUtils.DebugMsg("Tutorial Mode")

	super(state_context)

	if multiplayer.is_server():
		# Resume at the first unfinished mission; a replay after finishing starts at mission 1.
		var missions_done := save_manager.get_tutorial_missions_done()
		_active_runner_index = missions_done - 1 if missions_done < _runners.size() else -1
		item_manager.clear_items()
		for spawner in _event.get_pickup_spawners():
			spawner.activate(item_manager)
		# Initial teleport is handled by a leading TeleportTask in each runner.
		_start_next_runner()


func Exit(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	for spawner in _event.get_pickup_spawners():
		spawner.deactivate()
	super(state_context)


#region Setup


## Tutorial-specific tasks need the tour manager on top of the runner deps.
func _inject_runner_deps():
	super()
	for runner in _runners:
		_inject_task_deps(runner)


func _inject_task_deps(runner: TaskRunner):
	for child in runner.get_children():
		if child is ShowTourTask:
			child.tour_manager = tour_manager
		elif child is DropItemTask:
			child.item_manager = item_manager
		elif child is TaskRunner:
			_inject_task_deps(child)


#endregion


#override
func can_cancel_event() -> bool:
	return false


#override
## Each mission is a milestone: progress saves only when one completes.
func _on_runner_all_completed():
	save_manager.set_tutorial_missions_done(_active_runner_index + 1)
	super()


#override
func _on_last_runner_completed(runner: TaskRunner):
	save_manager.mark_tutorial_complete()
	_show_results(_completion_results(runner, "TUT_COMPLETE"))


#override
## The tutorial ends the session instead of returning to free roam.
func _return_to_free_roam():
	(menu_manager.pause_menu_state as PauseMenuState).leave_session(play_menu_state)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if tour_manager == null:
		issues.append("tour_manager must not be empty")
	if item_manager == null:
		issues.append("item_manager must not be empty")
	if play_menu_state == null:
		issues.append("play_menu_state must not be empty")
	return issues
