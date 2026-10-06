## One line in GarageUI's list: `*` + label on the left, price / OWNED / value on the right.
class_name GarageRow extends Button

const OWNED_COLOR := Color(0.35, 1, 0.45)
const UNAFFORDABLE_COLOR := Color(1, 0.3, 0.3)

@onready var _marker: Label = %Marker
@onready var _label: Label = %Label
@onready var _right: Label = %Right
@onready var _swatch: ColorRect = %Swatch


# The anchored labels don't size the button, so match a theme button with one line of text.
func _notification(what: int):
	if what == NOTIFICATION_THEME_CHANGED:
		var font_height := get_theme_font("font").get_height(get_theme_font_size("font_size"))
		custom_minimum_size.y = get_theme_stylebox("normal").get_minimum_size().y + font_height


## Call after add_child.
func setup(label: String, right: String, is_current: bool):
	_marker.visible = is_current
	_label.text = label
	_right.text = right


## OWNED_COLOR / UNAFFORDABLE_COLOR on the price.
func set_right_color(color: Color):
	_right.add_theme_color_override("font_color", color)


func set_swatch(color: Color):
	_swatch.color = color
	_swatch.show()
