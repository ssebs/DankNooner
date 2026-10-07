@tool
## Fuel-up minigame HUD, in place of the riding HUD: the tank (the rider's boost meter, filling
## live) and the current step's prompt.
class_name FuelUpHUDState extends HUDState

@export var save_manager: SaveManager

@onready var _money: MoneyLabel = %HUD_Money
@onready var _gauge: BoostGauge = %BoostGauge
@onready var _prompt: Label = %HUD_FuelUpPrompt

## Set by HUDManager.go_to_fuel_up_hud.
var minigame: FuelUpMinigame


func _ready() -> void:
	hide_ui()


func Enter(_state_context: StateContext):
	show_ui()
	_money.text = MoneyLabel.format(save_manager.get_player_definition().money)
	# A session only starts once its price was paid. Deferred so the label has resized to the
	# new amount, since the pop centers on it.
	_money.pop_spent.call_deferred(minigame.price)


func Exit(_state_context: StateContext):
	hide_ui()


func Update(_delta: float):
	if Engine.is_editor_hint():
		return
	_money.text = MoneyLabel.format(save_manager.get_player_definition().money)
	_gauge.current_val = minigame.fill * BoostController.BOOST_SEGMENTS
	_gauge.spilled_val = minigame.spilled * BoostController.BOOST_SEGMENTS
	_prompt.text = tr(minigame.get_prompt_key())


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if save_manager == null:
		issues.append("save_manager must not be empty")
	return issues
