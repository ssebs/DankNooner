@tool
class_name CustomizeMenuState extends MenuState

@export var menu_manager: MenuManager
@export var settings_manager: SettingsManager
@export var play_menu_state: MenuState

const BIKE_SKINS_DIR := "res://resources/entities/bikes/skins/"
const CHARACTER_SKINS_DIR := "res://resources/entities/player/skins/"

@onready var back_btn: Button = %BackBtn
@onready var save_btn: Button = %SaveBtn
@onready var bike_skin_btn: OptionButton = %BikeSkinBtn
@onready var character_skin_btn: OptionButton = %CharacterSkinBtn

# skin_name -> res path
var bike_skins: Dictionary = {}
var character_skins: Dictionary = {}


func Enter(_state_context: StateContext):
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
	var saved_bike := settings_manager.current_settings.get("bike_skin", "") as String
	var saved_character := settings_manager.current_settings.get("character_skin", "") as String

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
	var bike_idx := bike_skin_btn.selected
	var char_idx := character_skin_btn.selected

	if bike_idx >= 0:
		var bike_name := bike_skin_btn.get_item_text(bike_idx)
		settings_manager.update_setting("bike_skin", bike_skins[bike_name], false)

	if char_idx >= 0:
		var char_name := character_skin_btn.get_item_text(char_idx)
		settings_manager.update_setting("character_skin", character_skins[char_name], false)

	settings_manager.save_settings()
	UiToast.ShowToast(tr("SAVED_SETTINGS_LABEL"))


func _on_back_pressed():
	transitioned.emit(menu_manager.prev_state, null)


#override
func on_cancel_key_pressed():
	_on_back_pressed()
