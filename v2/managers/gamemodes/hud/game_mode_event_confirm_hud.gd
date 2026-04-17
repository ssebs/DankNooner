@tool
class_name GameModeEventConfirmHUD extends Control

signal hud_closed(peer_id: int)
signal hud_submitted(peer_id: int)

@export var input_state_manager: InputStateManager

@onready var submit_btn: Button = %SubmitBtn
@onready var close_btn: Button = %CloseBtn

@onready var gm_name: Label = %GamemodeName
@onready var gm_desc: Label = %GamemodeDesc


func _ready():
	hide_ui()


@rpc("any_peer", "call_local", "reliable")
func on_player_entered_circle(peer_id: int, gamemode_name: String, gamemode_description: String):
	if !multiplayer.is_server():
		return

	set_gamemode_hud_and_show_ui.rpc_id(peer_id, gamemode_name, gamemode_description)


@rpc("call_local", "reliable")
func set_gamemode_hud_and_show_ui(gamemode_name: String, gamemode_description: String):
	gm_name.text = tr(gamemode_name)
	gm_desc.text = tr(gamemode_description)
	input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME_PAUSED
	show_ui()


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
	self.show()
	if !submit_btn.pressed.is_connected(_on_submit_pressed):
		submit_btn.pressed.connect(_on_submit_pressed)
	if !close_btn.pressed.is_connected(_on_close_pressed):
		close_btn.pressed.connect(_on_close_pressed)


func hide_ui():
	self.hide()
	if submit_btn.pressed.has_connections():
		submit_btn.pressed.disconnect(_on_submit_pressed)
	if close_btn.pressed.has_connections():
		close_btn.pressed.disconnect(_on_close_pressed)


func _on_submit_pressed():
	hud_submitted.emit(multiplayer.multiplayer_peer.get_unique_id())


func _on_close_pressed():
	on_player_close_pressed.rpc_id(1, multiplayer.multiplayer_peer.get_unique_id())


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	return issues
