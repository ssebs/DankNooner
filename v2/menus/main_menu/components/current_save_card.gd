## The main menu's active save: the rider in a circle, level and money, then the save name small.
## Clicking it opens the Saves menu.
class_name CurrentSaveCard extends PanelContainer

signal pressed

const HOVER_MODULATE := Color(1.25, 1.25, 1.25)

@onready var _portrait: SavePreview = %Portrait
@onready var _stats_label: Label = %StatsLabel
@onready var _name_label: Label = %NameLabel


func _ready():
	mouse_entered.connect(func(): modulate = HOVER_MODULATE)
	mouse_exited.connect(func(): modulate = Color.WHITE)


## The portrait, text and their containers pass clicks up to here.
func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and !event.pressed:
		pressed.emit()


func show_save(slot: int, save_dict: Dictionary, player_def: PlayerDefinition) -> void:
	_stats_label.text = SaveCard.stats_text(player_def)
	_name_label.text = SaveCard.display_name(slot, save_dict)
	_portrait.show_player(player_def)
