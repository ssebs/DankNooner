## The active save: the rider in a circle, level and money, then the save name small. On the main
## menu clicking it opens the Saves menu; the garage shows it display-only in place of a money label.
class_name CurrentSaveCard extends PanelContainer

signal pressed

## Off: no hover, hand cursor or pressed.
@export var clickable: bool = true

const HOVER_MODULATE := Color(1.25, 1.25, 1.25)

## A MoneyLabel, so a host can flash / pop it (the garage's purchases).
@onready var money_label: MoneyLabel = %MoneyLabel
@onready var _portrait: SavePreview = %Portrait
@onready var _level_label: Label = %LevelLabel
@onready var _name_label: Label = %NameLabel


func _ready():
	if !clickable:
		mouse_default_cursor_shape = CURSOR_ARROW
		return
	mouse_entered.connect(func(): modulate = HOVER_MODULATE)
	mouse_exited.connect(func(): modulate = Color.WHITE)


## The portrait, text and their containers pass clicks up to here.
func _gui_input(event: InputEvent):
	if (
		clickable
		and event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and !event.pressed
	):
		pressed.emit()


func show_save(slot: int, save_dict: Dictionary, player_def: PlayerDefinition) -> void:
	_level_label.text = SaveCard.level_text(player_def)
	money_label.text = MoneyLabel.format(player_def.money)
	_name_label.text = SaveCard.display_name(slot, save_dict)
	_portrait.show_player(player_def)
