@tool
class_name GamemodeEventHUDState extends HUDState

signal hud_closed(peer_id: int)
## event_index indexes the entered circle's get_events().
signal hud_submitted(peer_id: int, event_index: int)

@export var hud_manager: HUDManager
@export var input_state_manager: InputStateManager

@onready var submit_btn: Button = %SubmitBtn
@onready var close_btn: Button = %CloseBtn

@onready var gm_name: Label = %GamemodeName
@onready var gm_desc: Label = %GamemodeDesc
## Picks between the circle's events; hidden when it has only one.
@onready var event_picker: OptionButton = %EventPicker

var _names: PackedStringArray = []
var _descriptions: PackedStringArray = []


func _ready():
	hide_ui()
	event_picker.item_selected.connect(_show_event)


@rpc("any_peer", "call_local", "reliable")
func on_player_entered_circle(
	peer_id: int, event_names: PackedStringArray, event_descriptions: PackedStringArray
):
	if !multiplayer.is_server():
		return

	# Only show event popup to the host
	if peer_id != 1:
		return

	set_gamemode_hud_and_show_ui.rpc_id(peer_id, event_names, event_descriptions)


@rpc("call_local", "reliable")
func set_gamemode_hud_and_show_ui(
	event_names: PackedStringArray, event_descriptions: PackedStringArray
):
	_names = event_names
	_descriptions = event_descriptions
	event_picker.clear()
	for event_name in event_names:
		event_picker.add_item(tr(event_name))
	event_picker.visible = event_names.size() > 1
	event_picker.select(0)
	_show_event(0)
	input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME_PAUSED
	show_ui()


func _show_event(index: int):
	gm_name.text = tr(_names[index])
	gm_desc.text = tr(_descriptions[index])


@rpc("any_peer", "call_local", "reliable")
func on_player_close_pressed(peer_id: int):
	if !multiplayer.is_server():
		return

	hide_ui_for_peer.rpc_id(peer_id)
	hud_closed.emit(peer_id)


@rpc("call_local", "reliable")
func hide_ui_for_peer():
	input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME
	hide_ui()


func show_ui():
	ui.show()
	if !submit_btn.pressed.is_connected(_on_submit_pressed):
		submit_btn.pressed.connect(_on_submit_pressed)
	if !close_btn.pressed.is_connected(_on_close_pressed):
		close_btn.pressed.connect(_on_close_pressed)
	if event_picker.visible:
		event_picker.call_deferred("grab_focus")
	else:
		submit_btn.call_deferred("grab_focus")


func hide_ui():
	ui.hide()
	if submit_btn.pressed.has_connections():
		submit_btn.pressed.disconnect(_on_submit_pressed)
	if close_btn.pressed.has_connections():
		close_btn.pressed.disconnect(_on_close_pressed)


func _on_submit_pressed():
	hud_submitted.emit(multiplayer.multiplayer_peer.get_unique_id(), event_picker.selected)


func _on_close_pressed():
	on_player_close_pressed.rpc_id(1, multiplayer.multiplayer_peer.get_unique_id())


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	return issues
