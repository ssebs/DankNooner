@tool
## Fuel-up minigame HUD, in place of the riding HUD: the tank (the rider's boost meter, filling
## live) and the current step's prompt.
class_name FuelUpHUDState extends HUDState

@onready var _gauge: BoostGauge = %BoostGauge
@onready var _prompt: Label = %HUD_FuelUpPrompt

## Set by HUDManager.go_to_fuel_up_hud.
var minigame: FuelUpMinigame


func _ready() -> void:
	hide_ui()


func Enter(_state_context: StateContext):
	show_ui()


func Exit(_state_context: StateContext):
	hide_ui()


func Update(_delta: float):
	if Engine.is_editor_hint():
		return
	_gauge.current_val = minigame.fill * BoostController.BOOST_SEGMENTS
	_prompt.text = tr(minigame.get_prompt_key())
