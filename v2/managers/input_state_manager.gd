@tool
## Manages InputState (in menu or in game) + sends input signals
class_name InputStateManager extends BaseManager

signal input_state_changed(new_state: InputState)
signal pause_requested
signal unpause_requested
## A tap (release before the hold threshold) fired a quick in-place respawn. Lets the HUD flash
## its "Respawning..." text even for a tap too brief to observe via the hold timer.
signal respawn_quick_fired
## The loadout bar's highlighted slot moved, or -1 when the bar closed.
signal loadout_pick_changed(index: int)
## Last input flipped between gamepad and keyboard/mouse. For UI with no player to ask.
signal device_changed(is_gamepad: bool)

enum InputState {
	IN_MENU,
	IN_GAME,
	IN_GAME_PAUSED,
	IN_MAP,
	DISABLED,
	## Cursor-driven 3D minigame (fuel-up) — cursor shown, riding input ignored.
	IN_MINIGAME,
	## A TourManager overlay is open; it handles its own input.
	IN_TOUR,
}

@export var menu_manager: MenuManager
@export var save_manager: SaveManager
@export var spawn_manager: SpawnManager
@export var item_manager: ItemManager
@export var hud_manager: HUDManager
## Read for current_event: events only allow same-bike loadout swaps.
@export var gamemode_manager: GamemodeManager

# @export var debug_mobile := true
@export var debug_mobile := false

## Hold the respawn action at least this long for a full respawn; a shorter tap is an
## in-place quick respawn.
const RESPAWN_HOLD_THRESHOLD: float = 0.5

var current_input_state = InputState.IN_MENU:
	set(val):
		current_input_state = val
		showhide_mouse_cursor()
		input_state_changed.emit(val)

var is_mobile := false
## Same split as InputController._detect_gamepad_or_kbm, which only runs while riding.
var is_gamepad: bool = false

## Respawn tap/hold tracking for the local player. Full respawn fires once the hold crosses
## the threshold; a release before then is a tap → quick in-place respawn.
var _respawn_hold_time: float = 0.0
## This press already did its action (full respawn or set point), so its release is no tap.
var _respawn_press_spent: bool = false
## Last tap's release; a press within TrickController.DOUBLE_TAP_WINDOW of it sets the respawn point.
var _respawn_tapped_msec: int = -1
## Last trick-button release; a press within TrickController.DOUBLE_TAP_WINDOW of it uses the held item.
var _trick_released_msec: int = -1
## Last horn release; a honk within the same window discards the held item.
var _horn_released_msec: int = -1
## Loadout bar's highlighted slot while the loadouts action is held, else -1.
var _loadout_pick: int = -1


func _ready():
	add_to_group(UtilsConstants.GROUPS["InputStateManager"], true)
	if !Engine.is_editor_hint():
		# Device detection keeps tour icons live while a tutorial tour pauses the game (IN_TOUR is inert).
		process_mode = Node.PROCESS_MODE_ALWAYS

	if (
		(OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"))
		or debug_mobile
	):
		is_mobile = true


func _input(event: InputEvent):
	var gamepad := is_gamepad
	if event is InputEventKey or event is InputEventMouse:
		gamepad = false
	elif ControlBindings.is_gamepad(event):
		gamepad = true
	if gamepad != is_gamepad:
		is_gamepad = gamepad
		device_changed.emit(gamepad)
	# Web browsers require mouse capture to happen inside an input event callback
	if event is InputEventMouseButton and event.pressed:
		showhide_mouse_cursor()


## Respawn tap vs hold vs double tap. Polled here rather than in _unhandled_input because the hold
## needs per-frame timing: crossing the threshold fires a full respawn immediately, and releasing
## before it fires a quick in-place respawn. A second tap saves that spot as the respawn point.
func _process(delta: float):
	if current_input_state != InputState.IN_GAME:
		_respawn_hold_time = 0.0
		_respawn_press_spent = false
		_close_loadout_bar()
		return
	_poll_loadout_bar()
	if (
		Input.is_action_just_pressed("respawn")
		and Time.get_ticks_msec() - _respawn_tapped_msec <= TrickController.DOUBLE_TAP_WINDOW * 1000.0
	):
		_respawn_press_spent = true
		spawn_manager.request_set_respawn_point.rpc_id(1)
	if Input.is_action_pressed("respawn") and not _respawn_press_spent:
		_respawn_hold_time += delta
		if _respawn_hold_time >= RESPAWN_HOLD_THRESHOLD:
			_respawn_press_spent = true
			spawn_manager.request_respawn.rpc_id(1)
	if Input.is_action_just_released("respawn"):
		if not _respawn_press_spent:
			spawn_manager.request_respawn_in_place.rpc_id(1)
			respawn_quick_fired.emit()
			_respawn_tapped_msec = Time.get_ticks_msec()
		_respawn_hold_time = 0.0
		_respawn_press_spent = false


## Seconds the respawn action has been held (0 when not held). Polled by RidingHUDState to
## drive the hold-progress bar toward RESPAWN_HOLD_THRESHOLD.
func get_respawn_hold_time() -> float:
	return _respawn_hold_time


## Hold loadouts to open the bar, cam up/down (or scroll wheel, in _unhandled_input) to pick, release to swap.
func _poll_loadout_bar():
	if Input.is_action_just_pressed("loadouts"):
		_loadout_pick = save_manager.get_player_definition().active_loadout_index
		loadout_pick_changed.emit(_loadout_pick)
	if _loadout_pick < 0:
		return
	if Input.is_action_just_released("loadouts"):
		_switch_loadout(_loadout_pick)
		_close_loadout_bar()
		return
	_step_loadout_pick(int(Input.is_action_just_pressed("cam_down")) - int(Input.is_action_just_pressed("cam_up")))


## Move the bar's highlight by step (-1 up, 1 down), stopping at the ends.
func _step_loadout_pick(step: int):
	var last := save_manager.get_player_definition().loadouts.size() - 1
	if step != 0 and clampi(_loadout_pick + step, 0, last) != _loadout_pick:
		_loadout_pick += step
		loadout_pick_changed.emit(_loadout_pick)


func _close_loadout_bar():
	if _loadout_pick >= 0:
		_loadout_pick = -1
		loadout_pick_changed.emit(-1)


## The loadout bar owns the camera stick while it's open.
func is_loadout_bar_open() -> bool:
	return _loadout_pick >= 0


## Events only swap skins: the loadout must share the base bike you're riding.
func can_swap_loadout(idx: int) -> bool:
	if gamemode_manager.current_event == null:
		return true
	var bike := save_manager.get_player_definition().loadouts[idx].bike
	return bike.get_base_path() == hud_manager.local_player.bike_definition.get_base_path()


#region InputState (in game vs in menu)
func _unhandled_input(event: InputEvent):
	match current_input_state:
		InputStateManager.InputState.DISABLED, InputStateManager.InputState.IN_TOUR:
			return
		InputStateManager.InputState.IN_GAME:
			if is_loadout_bar_open() and event is InputEventMouseButton and event.pressed:
				if event.button_index == MOUSE_BUTTON_WHEEL_UP:
					_step_loadout_pick(-1)
				elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					_step_loadout_pick(1)
			if event.is_action_pressed("pause"):
				pause_requested.emit()
			elif event.is_action_pressed("open_map"):
				# Live overlay, coordinates no other manager — so unlike pause this state owns
				# its own toggle. The HUD expands the minimap off the input_state_changed signal.
				current_input_state = InputState.IN_MAP
			elif event.is_action_released("trick"):
				_trick_released_msec = Time.get_ticks_msec()
			elif event.is_action_pressed("trick"):
				_try_use_item()
			elif event.is_action_pressed("use_item"):
				item_manager.request_use_item.rpc_id(1)
			elif event.is_action_released("horn"):
				_horn_released_msec = Time.get_ticks_msec()
			elif event.is_action_pressed("horn"):
				_try_drop_item()
		InputStateManager.InputState.IN_GAME_PAUSED:
			var menu_state := menu_manager.state_machine.current_state as MenuState
			if event.is_action_pressed("pause"):
				unpause_requested.emit()
			# Results/event HUDs share this state with no menu up — don't drive the stale menu.
			elif menu_state.ui.visible:
				if event.is_action_pressed("ui_cancel"):
					menu_state.on_cancel_key_pressed()
				elif _tab_dir(event) != 0:
					menu_state.on_tab_key_pressed(_tab_dir(event))
		InputStateManager.InputState.IN_MAP:
			if event.is_action_pressed("open_map") or event.is_action_pressed("ui_cancel"):
				current_input_state = InputState.IN_GAME
		InputStateManager.InputState.IN_MINIGAME:
			var hud_state := hud_manager.state_machine.current_state as HUDState
			# Esc is both; pause wins so keyboard can always reach Cancel Event.
			if event.is_action_pressed("pause"):
				pause_requested.emit()
			elif event.is_action_pressed("ui_cancel"):
				hud_state.on_cancel_key_pressed()
			elif _tab_dir(event) != 0:
				hud_state.on_tab_key_pressed(_tab_dir(event))
		InputStateManager.InputState.IN_MENU:
			var current_state = menu_manager.state_machine.current_state as MenuState
			if event.is_action_pressed("ui_cancel"):
				if current_state:
					current_state.on_cancel_key_pressed()
			elif _tab_dir(event) != 0:
				if current_state:
					current_state.on_tab_key_pressed(_tab_dir(event))


## -1 / 1 for ui_tab_prev / ui_tab_next presses, else 0.
func _tab_dir(event: InputEvent) -> int:
	if event.is_action_pressed("ui_tab_prev"):
		return -1
	if event.is_action_pressed("ui_tab_next"):
		return 1
	return 0


## Double-tap the trick button to use the held item — timed like the trick stick's double tap.
func _try_use_item():
	if Time.get_ticks_msec() - _trick_released_msec <= TrickController.DOUBLE_TAP_WINDOW * 1000.0:
		item_manager.request_use_item.rpc_id(1)


## Double-tap the horn to discard the held item.
func _try_drop_item():
	if Time.get_ticks_msec() - _horn_released_msec <= TrickController.DOUBLE_TAP_WINDOW * 1000.0:
		item_manager.request_drop_item.rpc_id(1)


## Make loadout idx active. Reuses the customize menu's active-loadout path, which syncs the
## swap to every peer via SpawnManager.update_skins.
func _switch_loadout(idx: int):
	var player_def := save_manager.get_player_definition()
	# Already active, or locked by the event — nothing to do.
	if idx == player_def.active_loadout_index or !can_swap_loadout(idx):
		return
	player_def.active_loadout_index = idx
	save_manager.update_save("player_definition", player_def, true, true)


## Pause or a menu opened from it is on screen. Event prompts and results are HUD, not menus.
func is_menu_open() -> bool:
	var menu := menu_manager.state_machine.current_state as MenuState
	return menu != null and menu.ui.visible


## Shows or hides mouse cursor depending on current_input_state
func showhide_mouse_cursor():
	match current_input_state:
		InputStateManager.InputState.IN_MENU, InputStateManager.InputState.IN_GAME_PAUSED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		InputStateManager.InputState.IN_MAP, InputStateManager.InputState.IN_MINIGAME, InputStateManager.InputState.IN_TOUR:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		InputStateManager.InputState.IN_GAME, InputStateManager.InputState.DISABLED:
			if !is_mobile:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

#endregion
