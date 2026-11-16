@tool
## Customize from the main / play / lobby menus: the garage level behind a GarageUI.
class_name CustomizeMenuState extends MenuState

@export var save_manager: SaveManager
@export var level_manager: LevelManager
@export var audio_manager: AudioManager
@export var input_state_manager: InputStateManager
@export var tour_manager: TourManager
@export var saves_menu_state: MenuState

@onready var garage_ui: GarageUI = %GarageUI

var _garage_set: GarageSet


func Enter(state_context: StateContext):
	# Back from Saves keeps the original back target.
	if state_context.return_state != saves_menu_state:
		return_ctx = state_context
		return_state = state_context.return_state

	_garage_set = level_manager.spawn_garage_level().garage_set

	garage_ui.preview_changed.connect(_garage_set.show_preview)
	garage_ui.pose_requested.connect(_garage_set.cycle_pose)
	garage_ui.exit_requested.connect(_on_exit_requested)
	garage_ui.save_card.pressed.connect(_on_save_card_pressed)
	ui.show()
	garage_ui.open(save_manager, audio_manager, input_state_manager, tour_manager)


## Only commits: on a host launch, spawn_level() already freed the garage and is what called this.
func Exit(_state_context: StateContext):
	# Before hiding: a mid-tour skip refocuses a garage row, which hiding then releases.
	garage_ui.commit()
	ui.hide()
	garage_ui.preview_changed.disconnect(_garage_set.show_preview)
	garage_ui.pose_requested.disconnect(_garage_set.cycle_pose)
	garage_ui.exit_requested.disconnect(_on_exit_requested)
	garage_ui.save_card.pressed.disconnect(_on_save_card_pressed)
	_garage_set = null


func _on_exit_requested():
	level_manager.spawn_menu_level()
	transitioned.emit(return_state, return_ctx)


## From the lobby it's in session, so Saves locks switching saves.
func _on_save_card_pressed():
	audio_manager.play_menu_click()
	level_manager.spawn_menu_level()
	var ctx: StateContext = (
		PauseStateContext.NewFromPause(self)
		if return_ctx is LobbyStateContext
		else StateContext.NewWithReturn(self)
	)
	transitioned.emit(saves_menu_state, ctx)


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
	if audio_manager == null:
		issues.append("audio_manager must not be empty")
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	if tour_manager == null:
		issues.append("tour_manager must not be empty")
	if saves_menu_state == null:
		issues.append("saves_menu_state must not be empty")
	return issues
