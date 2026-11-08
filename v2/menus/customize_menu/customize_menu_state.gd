@tool
## Customize from the main / play / lobby menus: the garage level behind a GarageUI.
class_name CustomizeMenuState extends MenuState

@export var save_manager: SaveManager
@export var level_manager: LevelManager
@export var audio_manager: AudioManager
@export var input_state_manager: InputStateManager
@export var tour_manager: TourManager

@onready var garage_ui: GarageUI = %GarageUI
@onready var _tour: Tour = %CustomizeTour
@onready var _profile_step: TourStep = %ProfileStep
@onready var _loadouts_step: TourStep = %LoadoutsStep
@onready var _add_step: TourStep = %AddStep
@onready var _recolor_step: TourStep = %RecolorStep
@onready var _set_active_step: TourStep = %SetActiveStep

var _garage_set: GarageSet


func Enter(state_context: StateContext):
	return_ctx = state_context
	return_state = state_context.return_state

	_garage_set = level_manager.spawn_garage_level().garage_set

	garage_ui.preview_changed.connect(_garage_set.show_preview)
	garage_ui.pose_requested.connect(_garage_set.cycle_pose)
	garage_ui.exit_requested.connect(_on_exit_requested)
	ui.show()
	garage_ui.open(save_manager, audio_manager, input_state_manager)
	_play_tour()


## Only commits: on a host launch, spawn_level() already freed the garage and is what called this.
func Exit(_state_context: StateContext):
	# Backing out mid-tour is only possible during an action step, and counts as a skip.
	if tour_manager.is_open():
		tour_manager.skip()
	ui.hide()
	garage_ui.commit()
	garage_ui.preview_changed.disconnect(_garage_set.show_preview)
	garage_ui.pose_requested.disconnect(_garage_set.cycle_pose)
	garage_ui.exit_requested.disconnect(_on_exit_requested)
	_garage_set = null


## The tour has the player add a loadout and recolor it, then explains the active marker.
func _play_tour():
	_profile_step.target = garage_ui.get_profile_tab()
	_loadouts_step.target = garage_ui.get_loadout_tabs()
	_add_step.target = garage_ui.get_add_tab()
	_recolor_step.target = garage_ui.get_panel()
	_set_active_step.target = garage_ui.get_loadout_tabs()
	# GarageUI edits this same PlayerDefinition in place.
	var player_def := save_manager.get_player_definition()
	var loadout_count := player_def.loadouts.size()
	# The new loadout starts as a copy of the active one.
	var source_colors := player_def.loadouts[player_def.active_loadout_index].bike.colors.duplicate()
	# At the cap, + is hidden and there's nothing to add.
	_add_step.done_when = func():
		return (
			player_def.loadouts.size() > loadout_count
			or loadout_count >= PlayerDefinition.MAX_LOADOUTS
		)
	_recolor_step.done_when = func(): return player_def.loadouts.back().bike.colors != source_colors
	tour_manager.play_once(_tour)


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
	if audio_manager == null:
		issues.append("audio_manager must not be empty")
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	if tour_manager == null:
		issues.append("tour_manager must not be empty")
	return issues
