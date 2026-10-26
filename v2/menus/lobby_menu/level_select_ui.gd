@tool
class_name LevelSelectUI extends OptionButton

signal level_selected(level_id: int)


func _ready():
	item_selected.connect(_on_item_selected)


## Populate dropdown from level_manager
func populate(level_manager: LevelManager, default_id: int = 1):
	var items = level_manager.get_levels_as_option_items()

	clear()

	for level_name_str in items:
		var level_id: int = items[level_name_str]
		if level_id != LevelManager.LevelName.LEVEL_SELECT_LABEL and level_manager.is_locked_in_demo(level_id):
			add_item("%s %s" % [tr(level_name_str), tr("DEMO_LOCKED_LABEL")], level_id)
			set_item_disabled(item_count - 1, true)
			set_item_tooltip(item_count - 1, tr("DEMO_LOCKED_TOOLTIP"))
		else:
			add_item(level_name_str, level_id)

	set_item_disabled(0, true)  # Always set to LEVEL_SELECT_LABEL
	selected = default_id


## Get the currently selected level ID
func get_selected_level_id() -> int:
	return get_item_id(selected)


## Sync selection from server RPC
func set_selected_index(idx: int):
	selected = idx


func _on_item_selected(idx: int):
	if idx == 0:
		return
	level_selected.emit(get_item_id(idx))


func _get_configuration_warnings() -> PackedStringArray:
	return []
