@tool
## Pauses the player and shows a numeric countdown on the HUD for `seconds`.
## Mirrors the start-of-tutorial countdown — disables input + clears throttle/brake/steer
## so the player can't drift through it. Auto-advances when the timer hits 0.
class_name CountdownTask extends GameModeTask

@export var seconds: float = 3.0
@export var show_hud: bool = true


func on_enter(player: PlayerEntity, state: Dictionary) -> void:
	state["t"] = seconds
	state["last_shown"] = -1  # forces first check() tick to RPC the initial number
	# Player may not be spawned yet during late-join sync — input toggle skipped intentionally
	if player == null:
		return
	player.input_controller.input_disabled = true
	player.input_controller.nfx_throttle = 0.0
	player.input_controller.nfx_front_brake = 0.0
	player.input_controller.nfx_rear_brake = 0.0
	player.input_controller.nfx_steer = 0.0
	player.input_controller.nfx_lean = 0.0


func check(player: PlayerEntity, delta: float, state: Dictionary) -> bool:
	state["t"] = state.get("t", 0.0) - delta
	var t: float = state["t"]
	var curr := ceili(t)
	var last: int = state.get("last_shown", -1)
	if curr != last and curr > 0:
		state["last_shown"] = curr
		if show_hud:
			_rpc_show_countdown.rpc_id(int(player.name), curr)
	return t <= 0.0


func on_exit(player: PlayerEntity, _state: Dictionary) -> void:
	player.input_controller.input_disabled = false


@rpc("call_local", "reliable")
func _rpc_show_countdown(num: int):
	var tut := _gamemode as TutorialGameMode
	tut.tutorial_hud.rpc_show_countdown(num)
