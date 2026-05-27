@tool
class_name LevelSelectPanel extends VBoxContainer

signal level_selected(level_id: int)
signal start_pressed

@onready var level_select_btn: LevelSelectUI = %LevelSelectBtn
@onready var level_preview_img: TextureRect = %LevelPreview
@onready var start_btn: Button = %StartBtn

var _level_manager: LevelManager


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	level_select_btn.level_selected.connect(_on_level_selected)
	start_btn.pressed.connect(_on_start_pressed)


func populate(level_manager: LevelManager, default_level_id: int = 1) -> void:
	_level_manager = level_manager
	level_select_btn.populate(level_manager, default_level_id)
	# level_select_btn.populate sets `selected` as if it were an index; resolve it
	# to the actual index whose item-id matches default_level_id.
	for i in level_select_btn.item_count:
		if level_select_btn.get_item_id(i) == default_level_id:
			level_select_btn.selected = i
			break
	refresh_preview()


func get_selected_level_id() -> int:
	return level_select_btn.get_selected_level_id()


func get_selected_index() -> int:
	return level_select_btn.selected


## Sync selection from RPC (idx is the OptionButton index, not the level id)
func set_selected_index(idx: int) -> void:
	level_select_btn.set_selected_index(idx)
	refresh_preview()


## Disables both the dropdown and the start button (used for clients in lobby)
func set_controls_disabled(disabled: bool) -> void:
	level_select_btn.disabled = disabled
	start_btn.disabled = disabled


## Disables only the start button (server toggles this based on selection state)
func set_start_disabled(disabled: bool) -> void:
	start_btn.disabled = disabled


func grab_start_focus() -> void:
	start_btn.call_deferred("grab_focus")


func refresh_preview() -> void:
	var preview_texture: Texture = _level_manager.level_img_map.get(
		level_select_btn.get_selected_level_id()
	)
	if preview_texture:
		level_preview_img.texture = preview_texture
	else:
		level_preview_img.texture = load("res://resources/img/test_level_select_img.png")


func _on_level_selected(level_id: int) -> void:
	refresh_preview()
	level_selected.emit(level_id)


func _on_start_pressed() -> void:
	start_pressed.emit()
