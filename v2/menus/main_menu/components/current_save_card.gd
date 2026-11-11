## The main menu's active save: the rider in a circle, level and money, then the save name small.
class_name CurrentSaveCard extends PanelContainer

@onready var _portrait: SavePreview = %Portrait
@onready var _stats_label: Label = %StatsLabel
@onready var _name_label: Label = %NameLabel


func show_save(slot: int, save_dict: Dictionary, player_def: PlayerDefinition) -> void:
	_stats_label.text = SaveCard.stats_text(player_def)
	_name_label.text = SaveCard.display_name(slot, save_dict)
	_portrait.show_player(player_def)
