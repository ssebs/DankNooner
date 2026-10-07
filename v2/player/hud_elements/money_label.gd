@tool
## A "$1,234" money readout. flash() blinks it red (can't afford); pop_spent() also drops a red
## "-$N" off it, in TrickPopups' pop style.
class_name MoneyLabel extends Label

const COLOR := Color(0.3, 1.0, 0.35)
## Straight down — money leaving, vs TrickPopups' up-and-out.
const SPENT_DRIFT := Vector2(0.0, 110.0)
const FLASH_COUNT: int = 3
const FLASH_HALF_SECS: float = 0.08

var _flash_tween: Tween


func _ready():
	add_theme_color_override("font_color", COLOR)


## 15000 -> "$15,000"
static func format(amount: float) -> String:
	var digits := str(int(amount))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(-3)
	return "$" + digits + grouped


func flash() -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	_flash_tween = create_tween().set_loops(FLASH_COUNT)
	_flash_tween.tween_property(
		self, "theme_override_colors/font_color", TrickPopups.OOF_COLOR, FLASH_HALF_SECS
	)
	_flash_tween.tween_property(self, "theme_override_colors/font_color", COLOR, FLASH_HALF_SECS)


func pop_spent(amount: int) -> void:
	TrickPopups.spawn_pop(self, "-" + format(amount), TrickPopups.OOF_COLOR, size / 2.0, SPENT_DRIFT)
	flash()
