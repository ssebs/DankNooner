## One challenge in the profile card's drop panel: its name over a thin progress line and count,
## then its payout when it has one.
class_name ChallengeRow extends VBoxContainer

const DONE_MODULATE := Color(1, 1, 1, 0.5)

@onready var _title: Label = %Title
@onready var _bar: ProgressBar = %Bar
@onready var _count: Label = %Count
@onready var _payout: HBoxContainer = %Payout
@onready var _payout_money: Label = %PayoutMoney
@onready var _payout_xp: Label = %PayoutXP


func _ready() -> void:
	_payout_money.add_theme_color_override("font_color", MoneyLabel.COLOR)
	_payout_xp.add_theme_color_override("font_color", UtilsConstants.UI_GOLD)


## money / xp: what finishing it pays; 0 and 0 hides the line (career stats).
func show_challenge(title: String, progress: float, target: float, money := 0, xp := 0) -> void:
	_title.text = title
	_bar.max_value = target
	_bar.value = progress
	_count.text = "%d/%d" % [int(progress), int(target)]
	_payout.visible = money > 0 or xp > 0
	_payout_money.text = MoneyLabel.format(money)
	_payout_xp.text = "%s %s" % [MoneyLabel.group_digits(xp), tr("LB_XP")]
	modulate = DONE_MODULATE if progress >= target else Color.WHITE
