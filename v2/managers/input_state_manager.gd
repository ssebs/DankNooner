@tool
## Manages InputState (in menu or in game) + sends input signals
class_name InputStateManager extends BaseManager

signal input_state_changed(new_state: InputState)
signal pause_requested
signal unpause_requested

enum InputState {
	IN_MENU,
	IN_GAME,
	IN_GAME_PAUSED,
	IN_MAP,
	DISABLED,
}

@export var menu_manager: MenuManager
@export var save_manager: SaveManager
@export var spawn_manager: SpawnManager

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

## Respawn tap/hold tracking for the local player. Full respawn fires once the hold crosses
## the threshold; a release before then is a tap → quick in-place respawn.
var _respawn_hold_time: float = 0.0
var _respawn_full_fired: bool = false


func _ready():
	add_to_group(UtilsConstants.GROUPS["InputStateManager"], true)

	if (
		(OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"))
		or debug_mobile
	):
		is_mobile = true


func _input(event: InputEvent):
	# Web browsers require mouse capture to happen inside an input event callback
	if event is InputEventMouseButton and event.pressed:
		showhide_mouse_cursor()


## Respawn tap vs hold. Polled here rather than in _unhandled_input because the hold needs
## per-frame timing: crossing the threshold fires a full respawn immediately, and releasing
## before it fires a quick in-place respawn.
func _process(delta: float):
	if current_input_state != InputState.IN_GAME:
		_respawn_hold_time = 0.0
		_respawn_full_fired = false
		return
	if Input.is_action_pressed("respawn"):
		_respawn_hold_time += delta
		if _respawn_hold_time >= RESPAWN_HOLD_THRESHOLD and not _respawn_full_fired:
			_respawn_full_fired = true
			spawn_manager.request_respawn.rpc_id(1)
	if Input.is_action_just_released("respawn"):
		if not _respawn_full_fired:
			spawn_manager.request_respawn_in_place.rpc_id(1)
		_respawn_hold_time = 0.0
		_respawn_full_fired = false


#region InputState (in game vs in menu)
func _unhandled_input(event: InputEvent):
	match current_input_state:
		InputStateManager.InputState.DISABLED:
			return
		InputStateManager.InputState.IN_GAME:
			if event.is_action_pressed("pause"):
				pause_requested.emit()
			elif event.is_action_pressed("open_map"):
				# Live overlay, coordinates no other manager — so unlike pause this state owns
				# its own toggle. The HUD expands the minimap off the input_state_changed signal.
				current_input_state = InputState.IN_MAP
			elif event is InputEventKey and event.pressed and not event.echo:
				_try_switch_bike_slot(event.physical_keycode)
		InputStateManager.InputState.IN_GAME_PAUSED:
			if event.is_action_pressed("pause"):
				unpause_requested.emit()
		InputStateManager.InputState.IN_MAP:
			if event.is_action_pressed("open_map") or event.is_action_pressed("ui_cancel"):
				current_input_state = InputState.IN_GAME
		InputStateManager.InputState.IN_MENU:
			if event.is_action_pressed("ui_cancel"):
				var current_state = menu_manager.state_machine.current_state as MenuState
				if current_state:
					current_state.on_cancel_key_pressed()


## Switch the local player's active bike to the loadout for a number-row key
## (1 → slot 0, 2 → slot 1, …). Reuses the customize menu's active-loadout path, which
## syncs the swap to every peer via SpawnManager.update_skins.
func _try_switch_bike_slot(physical_keycode: int):
	if physical_keycode < KEY_1 or physical_keycode > KEY_8:
		return
	var idx := physical_keycode - KEY_1
	var player_def := save_manager.get_player_definition()
	# Slot past your last bike, or already active — nothing to do (e.g. "2" with one bike).
	if idx >= player_def.loadouts.size() or idx == player_def.active_loadout_index:
		return
	player_def.active_loadout_index = idx
	save_manager.update_save("player_definition", player_def, true, true)


## Shows or hides mouse cursor depending on current_input_state
func showhide_mouse_cursor():
	match current_input_state:
		InputStateManager.InputState.IN_MENU, InputStateManager.InputState.IN_GAME_PAUSED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		InputStateManager.InputState.IN_MAP:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		InputStateManager.InputState.IN_GAME, InputStateManager.InputState.DISABLED:
			if !is_mobile:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

#endregion
