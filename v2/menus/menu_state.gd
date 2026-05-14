@tool
## All Menu objects should inherit from this
## Be sure to set return_state on Enter()!
class_name MenuState extends State

@onready var ui: Control = %UI

var return_state: MenuState  # Use in Enter(), see @settings_menu_state.gd
var return_ctx: StateContext  # Use in Enter(), see @customize_menu_state.gd


func _ready():
	add_to_group(UtilsConstants.GROUPS["Validate"])
	if Engine.is_editor_hint():
		return
	_wire_button_click_sounds()


func _wire_button_click_sounds():
	var audio_manager: AudioManager
	for mgr in get_tree().get_nodes_in_group("Managers"):
		if mgr is AudioManager:
			audio_manager = mgr
			break
	if audio_manager == null:
		return
	for btn in find_children("*", "Button", true, false):
		(btn as Button).pressed.connect(audio_manager.play_menu_click)


func hide_ui():
	ui.hide()


func show_ui():
	ui.show()


## Override this, used to press back btn / close menu / etc when ESC is pressed
## Called from menu_manager when ui_cancel is pressed
func on_cancel_key_pressed():
	pass


func get_first_button_for_focus() -> Button:
	var buttons = find_children("*", "Button", true, true)
	if len(buttons) == 0:
		return null
	return buttons[0]
