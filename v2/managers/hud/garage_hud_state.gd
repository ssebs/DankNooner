@tool
## Free-roam garage HUD, in place of the riding HUD: a GarageUI previewing on the activity's
## GarageSet. Leaving it commits the edits, which syncs the live bike through the lobby.
class_name GarageHUDState extends HUDState

@export var save_manager: SaveManager

@onready var _garage_ui: GarageUI = %GarageUI

## Set by HUDManager.go_to_garage_hud.
var activity: GarageActivity


func _ready() -> void:
	hide_ui()


func Enter(_state_context: StateContext):
	_garage_ui.preview_changed.connect(activity.garage_set.show_preview)
	_garage_ui.exit_requested.connect(_on_exit_requested)
	show_ui()
	_garage_ui.open(save_manager)


func Exit(_state_context: StateContext):
	hide_ui()
	_garage_ui.commit()
	_garage_ui.preview_changed.disconnect(activity.garage_set.show_preview)
	_garage_ui.exit_requested.disconnect(_on_exit_requested)
	activity.garage_set.hide_preview()


func _on_exit_requested():
	activity.end()
	activity.finished.emit()


#override
func on_cancel_key_pressed():
	_garage_ui.go_back()


#override
func on_tab_key_pressed(dir: int):
	_garage_ui.cycle_tab(dir)


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if save_manager == null:
		issues.append("save_manager must not be empty")
	return issues
