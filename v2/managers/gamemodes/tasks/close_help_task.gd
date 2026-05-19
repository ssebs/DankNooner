@tool
## Opens the help menu on the active peer and waits until they close it.
##
## Holds its own RPCs. Tutorial-specific deps (input/menu/help) live in
## main_game.tscn while this task lives in a level scene — TutorialGameMode
## injects them after instancing rather than via cross-scene @export NodePaths.
## spawn_manager comes from the runner.
class_name CloseHelpTask extends GameModeTask

var input_state_manager: InputStateManager
var menu_manager: MenuManager
var help_menu_state: HelpMenuState


func on_enter(player: PlayerEntity, state: Dictionary) -> void:
	state["closed"] = false
	_rpc_show_help.rpc_id(int(player.name))


func check(_player: PlayerEntity, _delta: float, state: Dictionary) -> bool:
	return state.get("closed", false)


func get_objective_text() -> String:
	return tr("TUT_SHOW_HELP")


func get_hint_text() -> String:
	return tr("TUT_HINT_SHOW_HELP")


@rpc("call_local", "reliable")
func _rpc_show_help():
	var player := _runner.spawn_manager._get_player_by_peer_id(multiplayer.get_unique_id())
	player.input_controller.input_disabled = true

	input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME_PAUSED
	menu_manager.enable_input_and_processing()
	help_menu_state.ui.show()
	help_menu_state._show_controls_for_current_device()

	help_menu_state.close_help_btn.pressed.connect(_on_help_closed, CONNECT_ONE_SHOT)
	input_state_manager.unpause_requested.connect(_on_help_closed, CONNECT_ONE_SHOT)


func _on_help_closed():
	if help_menu_state.close_help_btn.pressed.is_connected(_on_help_closed):
		help_menu_state.close_help_btn.pressed.disconnect(_on_help_closed)
	if input_state_manager.unpause_requested.is_connected(_on_help_closed):
		input_state_manager.unpause_requested.disconnect(_on_help_closed)

	help_menu_state.ui.hide()
	menu_manager.disable_input_and_processing()
	input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME

	var player := _runner.spawn_manager._get_player_by_peer_id(multiplayer.get_unique_id())
	player.input_controller.input_disabled = false

	_rpc_help_closed.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_help_closed():
	var peer_id := multiplayer.get_remote_sender_id()
	_runner.mark_state(peer_id, "closed", true)


