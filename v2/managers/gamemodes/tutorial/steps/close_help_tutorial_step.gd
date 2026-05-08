@tool
## Opens the help menu on the active peer and waits until they close it.
##
## Self-contained: holds its own RPCs. Manager refs are pulled from `_gamemode`
## (TutorialGameMode) since cross-scene NodePath wiring isn't possible from a
## level-authored child.
class_name CloseHelpTutorialStep extends GameModeObjective


func on_enter(player: PlayerEntity, state: Dictionary) -> void:
	state["closed"] = false
	_rpc_show_help.rpc_id(int(player.name))


func check(_player: PlayerEntity, _delta: float, state: Dictionary) -> bool:
	return state.get("closed", false)


func get_objective_text() -> String:
	return "TUT_SHOW_HELP"


func get_hint_text() -> String:
	return "TUT_HINT_SHOW_HELP"


@rpc("call_local", "reliable")
func _rpc_show_help():
	var tut := _gamemode as TutorialGameMode
	var player := tut.spawn_manager._get_player_by_peer_id(multiplayer.get_unique_id())
	player.input_controller.input_disabled = true

	tut.input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME_PAUSED
	tut.menu_manager.enable_input_and_processing()
	tut.help_menu_state.ui.show()
	tut.help_menu_state._show_controls_for_current_device()

	tut.help_menu_state.close_help_btn.pressed.connect(_on_help_closed, CONNECT_ONE_SHOT)
	tut.input_state_manager.unpause_requested.connect(_on_help_closed, CONNECT_ONE_SHOT)


func _on_help_closed():
	var tut := _gamemode as TutorialGameMode
	if tut.help_menu_state.close_help_btn.pressed.is_connected(_on_help_closed):
		tut.help_menu_state.close_help_btn.pressed.disconnect(_on_help_closed)
	if tut.input_state_manager.unpause_requested.is_connected(_on_help_closed):
		tut.input_state_manager.unpause_requested.disconnect(_on_help_closed)

	tut.help_menu_state.ui.hide()
	tut.menu_manager.disable_input_and_processing()
	tut.input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME

	var player := tut.spawn_manager._get_player_by_peer_id(multiplayer.get_unique_id())
	player.input_controller.input_disabled = false

	_rpc_help_closed.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_help_closed():
	var peer_id := multiplayer.get_remote_sender_id()
	_gamemode.mark_objective_state(peer_id, "closed", true)
