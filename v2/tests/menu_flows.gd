extends RefCounted
## The real UI paths a player clicks through: play menu, lobby, event picker, pause menu, results.
## Buttons are pressed by emitting their `pressed` signal; text fields by setting text and
## emitting `text_changed`, as typing does.

## The TestRunner. Untyped: it preloads this script, and a cyclic preload won't resolve.
var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


## Waits out warmup + splash, then presses Play
func reach_play_menu() -> bool:
	if not await _runner.wait_until(func(): return _menu_is(MainMenuState), "the main menu"):
		return false
	(_menu() as MainMenuState).play_btn.pressed.emit()
	return await _runner.wait_until(func(): return _menu_is(PlayMenuState), "the play menu")


## Hosts over IP/port from the play menu. True once the server listens.
func host() -> bool:
	var play := _menu() as PlayMenuState
	# Steam, when logged in, comes first in the list
	play.host_mode_opt.select(
		play.host_mode_opt.get_item_index(ConnectionManager.ConnectionMode.IP_PORT)
	)
	play.host_btn.pressed.emit()
	var listening := func(): return _runner.connection_manager.conn_addr != ""
	return await _runner.wait_until(listening, "the host to listen")


## Types `addr` into the play menu's code entry and joins.
func join(addr: String) -> bool:
	var play := _menu() as PlayMenuState
	play.code_entry.text = addr
	play.code_entry.text_changed.emit(addr)
	if play.join_btn.disabled:
		_runner.violate("join button disabled for %s" % addr)
		return false
	if _runner.connection_manager.connection_mode != ConnectionManager.ConnectionMode.IP_PORT:
		_runner.violate("%s didn't auto-select IP_PORT" % addr)
		return false
	play.join_btn.pressed.emit()
	return true


## Picks `level` in the lobby's level dropdown, as a click does.
func pick_level(level: LevelManager.LevelName) -> void:
	var dropdown := (_menu() as LobbyMenuState).level_select_panel.level_select_btn
	var index := dropdown.get_item_index(level)
	dropdown.select(index)
	dropdown.item_selected.emit(index)


func start_game() -> bool:
	var start_btn := (_menu() as LobbyMenuState).level_select_panel.start_btn
	if start_btn.disabled:
		_runner.violate("lobby start button is disabled")
		return false
	start_btn.pressed.emit()
	return true


## Submits event `index` in this peer's open event picker.
func submit_picker(index: int) -> void:
	var picker := _picker()
	if picker.event_picker.visible:
		picker.event_picker.select(index)
		picker.event_picker.item_selected.emit(index)
	picker.submit_btn.pressed.emit()


## The picker shows over the riding HUD without becoming the HUD state
func is_picker_open() -> bool:
	return _picker().ui.visible


## Pause menu → Cancel Event.
func cancel_event() -> bool:
	if not await _pause():
		return false
	var pause := _menu() as PauseMenuState
	if not pause.cancel_event_btn.visible:
		_runner.violate("Cancel Event isn't offered in %s" % _gamemode_name())
		pause.resume_btn.pressed.emit()
		return false
	pause.cancel_event_btn.pressed.emit()
	return true


## Pause menu → Main Menu, which disconnects.
func leave_to_main_menu() -> bool:
	if not await _pause():
		return false
	(_menu() as PauseMenuState).main_menu_btn.pressed.emit()
	return await _runner.wait_until(func(): return _menu_is(MainMenuState), "the main menu")


## Host only: skips the results countdown, or ends a finished run, back to free roam.
func skip_results() -> void:
	var results: ResultsHUDState = _runner.gamemode_manager.get_current_gamemode().results_hud
	if results.skip_btn.visible:
		results.skip_btn.pressed.emit()
	elif results.end_event_btn.visible:
		results.end_event_btn.pressed.emit()


func are_results_open() -> bool:
	var mode: GameModeType = _runner.gamemode_manager.get_current_gamemode()
	return mode is RunnerGameMode and (mode as RunnerGameMode).results_hud.ui.visible


func _pause() -> bool:
	var pause := InputEventAction.new()
	pause.action = &"pause"
	pause.pressed = true
	Input.parse_input_event(pause)
	return await _runner.wait_until(func(): return _menu_is(PauseMenuState), "the pause menu")


func _picker() -> GamemodeEventHUDState:
	return (_runner.gamemode_manager.free_roam_mode as FreeRoamGameMode).game_mode_event_hud_state


func _gamemode_name() -> String:
	return str(_runner.gamemode_manager.state_machine.current_state.name)


func _menu() -> MenuState:
	return _runner.menu_manager.state_machine.current_state as MenuState


func _menu_is(type: Script) -> bool:
	return is_instance_of(_runner.menu_manager.state_machine.current_state, type)
