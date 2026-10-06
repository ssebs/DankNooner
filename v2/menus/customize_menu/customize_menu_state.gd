@tool
## Customize from the main / play / lobby menus: the garage level behind a GarageUI.
class_name CustomizeMenuState extends MenuState

@export var save_manager: SaveManager
@export var level_manager: LevelManager

@onready var garage_ui: GarageUI = %GarageUI

var _garage_set: GarageSet


func Enter(state_context: StateContext):
	return_ctx = state_context
	return_state = state_context.return_state

	level_manager.spawn_level(LevelManager.LevelName.GARAGE_LEVEL, InputStateManager.InputState.IN_MENU)
	var bay: GarageActivity = level_manager.current_level.find_children("*", "GarageActivity", true, false)[0]
	bay.camera.make_current()
	_garage_set = bay.garage_set

	garage_ui.preview_changed.connect(_garage_set.show_preview)
	garage_ui.pose_requested.connect(_garage_set.cycle_pose)
	garage_ui.exit_requested.connect(_on_exit_requested)
	ui.show()
	garage_ui.open(save_manager)


## Only commits: on a host launch, spawn_level() already freed the garage and is what called this.
func Exit(_state_context: StateContext):
	ui.hide()
	garage_ui.commit()
	garage_ui.preview_changed.disconnect(_garage_set.show_preview)
	garage_ui.pose_requested.disconnect(_garage_set.cycle_pose)
	garage_ui.exit_requested.disconnect(_on_exit_requested)
	_garage_set = null


func _on_exit_requested():
	level_manager.spawn_menu_level()
	transitioned.emit(return_state, return_ctx)


#override
func on_cancel_key_pressed():
	garage_ui.go_back()


#override
func on_tab_key_pressed(dir: int):
	garage_ui.cycle_tab(dir)


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if save_manager == null:
		issues.append("save_manager must not be empty")
	if level_manager == null:
		issues.append("level_manager must not be empty")
	return issues
