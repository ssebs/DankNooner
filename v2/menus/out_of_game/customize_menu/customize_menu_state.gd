@tool
class_name CustomizeMenuState extends MenuState

@export var menu_manager: MenuManager
@export var save_manager: SaveManager
@export var play_menu_state: MenuState

const BIKE_SKINS_DIR := "res://resources/entities/bikes/skins/"
const CHARACTER_SKINS_DIR := "res://resources/entities/player/skins/"

@onready var back_btn: Button = %BackBtn
@onready var save_btn: Button = %SaveBtn
@onready var username_entry: LineEdit = %UsernameEntry
@onready var bike_skin_btn: OptionButton = %BikeSkinBtn
@onready var character_skin_btn: OptionButton = %CharacterSkinBtn

@onready var bg_tint: ColorRect = %BGTint

# skin_name -> res path
var bike_skins: Dictionary = {}
var character_skins: Dictionary = {}

var return_state: MenuState  # TODO - add to MenuState


func Enter(state_context: StateContext):
	if state_context is PauseStateContext:
		return_state = state_context.return_state
		bg_tint.visible = state_context.show_bg_tint
	else:
		return_state = menu_manager.prev_state
		bg_tint.visible = false

	ui.show()
	back_btn.pressed.connect(_on_back_pressed)
	save_btn.pressed.connect(_on_save_pressed)

	_populate_skins()
	_load_current_selections()


func Exit(_state_context: StateContext):
	ui.hide()
	back_btn.pressed.disconnect(_on_back_pressed)
	save_btn.pressed.disconnect(_on_save_pressed)


func _populate_skins():
	bike_skins = _scan_skin_dir(BIKE_SKINS_DIR)
	character_skins = _scan_skin_dir(CHARACTER_SKINS_DIR)

	bike_skin_btn.clear()
	for skin_name in bike_skins.keys():
		bike_skin_btn.add_item(skin_name)

	character_skin_btn.clear()
	for skin_name in character_skins.keys():
		character_skin_btn.add_item(skin_name)


func _scan_skin_dir(dir_path: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		printerr("Failed to open skin directory: %s" % dir_path)
		return result

	var is_exported := !OS.has_feature("editor")
	var extension := ".tres.remap" if is_exported else ".tres"

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(extension):
			var res_path := dir_path + file_name.replace(".remap", "")
			var res := ResourceLoader.load(res_path)
			if res and "skin_name" in res:
				result[res.skin_name] = res_path
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


func _load_current_selections():
	var player_def := save_manager.get_player_definition()
	username_entry.text = player_def.username

	var saved_bike := player_def.bike_skin.resource_path if player_def.bike_skin else ""
	var saved_character := (
		player_def.character_skin.resource_path if player_def.character_skin else ""
	)

	_select_option_by_value(bike_skin_btn, bike_skins, saved_bike)
	_select_option_by_value(character_skin_btn, character_skins, saved_character)


func _select_option_by_value(btn: OptionButton, skins: Dictionary, saved_path: String):
	if saved_path == "":
		return
	for i in btn.item_count:
		var p := btn.get_item_text(i)
		if skins.get(p, "") == saved_path:
			btn.select(i)
			return


func _on_save_pressed():
	var player_def := save_manager.get_player_definition()
	player_def.username = username_entry.text

	var bike_idx := bike_skin_btn.selected
	var char_idx := character_skin_btn.selected

	if bike_idx >= 0:
		var bike_name := bike_skin_btn.get_item_text(bike_idx)
		player_def.bike_skin = load(bike_skins[bike_name])

	if char_idx >= 0:
		var char_name := character_skin_btn.get_item_text(char_idx)
		player_def.character_skin = load(character_skins[char_name])

	save_manager.update_save("player_definition", player_def, true, true)

	# TODO - if we're in a lobby/server, update metadata so the skin can be changed in game

	UiToast.ShowToast(tr("SAVED_SETTINGS_LABEL"))


func _on_back_pressed():
	transitioned.emit(return_state, null)


#override
func on_cancel_key_pressed():
	_on_back_pressed()
