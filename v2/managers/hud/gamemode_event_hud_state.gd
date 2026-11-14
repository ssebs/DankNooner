@tool
class_name GamemodeEventHUDState extends HUDState

signal hud_closed(peer_id: int)
## event_index indexes the entered circle's get_events().
signal hud_submitted(peer_id: int, event_index: int)

@export var hud_manager: HUDManager
@export var input_state_manager: InputStateManager
@export var save_manager: SaveManager
@export var spawn_manager: SpawnManager

@onready var submit_btn: Button = %SubmitBtn
@onready var close_btn: Button = %CloseBtn

@onready var gm_name: Label = %GamemodeName
@onready var gm_desc: Label = %GamemodeDesc
## Picks between the circle's events; hidden when it has only one.
@onready var event_picker: OptionButton = %EventPicker

var _names: PackedStringArray = []
var _descriptions: PackedStringArray = []
var _pb_keys: PackedStringArray = []


func _ready():
	hide_ui()
	event_picker.item_selected.connect(_show_event)


@rpc("any_peer", "call_local", "reliable")
func on_player_entered_circle(
	peer_id: int,
	event_names: PackedStringArray,
	event_descriptions: PackedStringArray,
	pb_keys: PackedStringArray,
	per_rider: bool
):
	if !multiplayer.is_server():
		return

	# Lobby-wide events are the host's call; per-rider ones (gas station fuel-up) are anyone's.
	if peer_id != 1 and !per_rider:
		return

	CountdownTask.freeze(spawn_manager.get_player_by_peer_id(peer_id))
	set_gamemode_hud_and_show_ui.rpc_id(
		peer_id, event_names, event_descriptions, pb_keys, per_rider
	)


@rpc("call_local", "reliable")
func set_gamemode_hud_and_show_ui(
	event_names: PackedStringArray,
	event_descriptions: PackedStringArray,
	pb_keys: PackedStringArray,
	per_rider: bool
):
	submit_btn.text = "ACTIVITY_START_LABEL" if per_rider else "START_LABEL"
	_names = event_names
	_descriptions = event_descriptions
	_pb_keys = pb_keys
	event_picker.clear()
	for event_name in event_names:
		event_picker.add_item(tr(event_name))
	event_picker.visible = event_names.size() > 1
	event_picker.select(0)
	_show_event(0)
	input_state_manager.current_input_state = InputStateManager.InputState.IN_EVENT_PICKER
	show_ui()


func _show_event(index: int):
	gm_name.text = tr(_names[index])
	gm_desc.text = tr(_descriptions[index])
	if _pb_keys[index] != "":
		gm_desc.text += "\n\n" + TimeAttackComponent.personal_best_text(save_manager, _pb_keys[index])


@rpc("any_peer", "call_local", "reliable")
func on_player_close_pressed(peer_id: int):
	if !multiplayer.is_server():
		return

	CountdownTask.unfreeze(spawn_manager.get_player_by_peer_id(peer_id))
	hide_ui_for_peer.rpc_id(peer_id)
	hud_closed.emit(peer_id)


@rpc("call_local", "reliable")
func hide_ui_for_peer():
	# Before the state change, which _on_input_state_changed would otherwise undo.
	hide_ui()
	input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME


func show_ui():
	ui.show()
	if !submit_btn.pressed.is_connected(_on_submit_pressed):
		submit_btn.pressed.connect(_on_submit_pressed)
	if !close_btn.pressed.is_connected(_on_close_pressed):
		close_btn.pressed.connect(_on_close_pressed)
	if !input_state_manager.input_state_changed.is_connected(_on_input_state_changed):
		input_state_manager.input_state_changed.connect(_on_input_state_changed)
	submit_btn.call_deferred("grab_focus")


func hide_ui():
	ui.hide()
	if submit_btn.pressed.has_connections():
		submit_btn.pressed.disconnect(_on_submit_pressed)
	if close_btn.pressed.has_connections():
		close_btn.pressed.disconnect(_on_close_pressed)
	if input_state_manager.input_state_changed.is_connected(_on_input_state_changed):
		input_state_manager.input_state_changed.disconnect(_on_input_state_changed)


func _unhandled_input(event: InputEvent):
	if (
		input_state_manager.current_input_state != InputStateManager.InputState.IN_EVENT_PICKER
		or Console.is_visible()
	):
		return
	# Esc is both; pause wins so keyboard can still reach the pause menu.
	if event.is_action_pressed("pause"):
		input_state_manager.pause_requested.emit()
	elif event.is_action_pressed("ui_cancel"):
		_on_close_pressed()


## Unpause always lands on IN_GAME — hand input back to the picker while it's still up.
func _on_input_state_changed(new_state: InputStateManager.InputState):
	if new_state == InputStateManager.InputState.IN_GAME:
		input_state_manager.current_input_state = InputStateManager.InputState.IN_EVENT_PICKER
		submit_btn.grab_focus()


func _on_submit_pressed():
	hud_submitted.emit(multiplayer.multiplayer_peer.get_unique_id(), event_picker.selected)


func _on_close_pressed():
	on_player_close_pressed.rpc_id(1, multiplayer.multiplayer_peer.get_unique_id())


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	if save_manager == null:
		issues.append("save_manager must not be empty")
	if spawn_manager == null:
		issues.append("spawn_manager must not be empty")
	return issues
