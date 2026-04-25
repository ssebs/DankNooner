@tool
class_name CustomizeMenuState extends MenuState

@export var menu_manager: MenuManager
@export var save_manager: SaveManager
@export var play_menu_state: MenuState

const BIKE_SKINS_DIR := "res://resources/bikes/skins/"
const CHARACTER_SKINS_DIR := "res://resources/player/skins/"
const COLOR_MODS_DIR := "res://resources/bikes/mods/color_mods/"

@onready var back_btn: Button = %BackBtn
@onready var save_btn: Button = %SaveBtn
@onready var username_entry: LineEdit = %UsernameEntry
@onready var bike_skin_btn: OptionButton = %BikeSkinBtn
@onready var character_skin_btn: OptionButton = %CharacterSkinBtn
@onready var color_mod_btn: OptionButton = %ColorModBtn

@onready var bg_tint: ColorRect = %BGTint

# skin_name -> res path
var bike_skins: Dictionary = {}
var character_skins: Dictionary = {}
# display_name -> res_path
var color_mods: Dictionary = {}


func Enter(state_context: StateContext):
	bg_tint.visible = false
	return_ctx = state_context
	return_state = state_context.return_state

	if state_context is PauseStateContext:
		bg_tint.visible = state_context.show_bg_tint
	# else:
	# 	return_state = menu_manager.prev_state

	ui.show()
	back_btn.pressed.connect(_on_back_pressed)
	save_btn.pressed.connect(_on_save_pressed)
	bike_skin_btn.item_selected.connect(_on_bike_skin_changed)

	_populate_skins()
	_load_current_selections()


func Exit(_state_context: StateContext):
	ui.hide()
	back_btn.pressed.disconnect(_on_back_pressed)
	save_btn.pressed.disconnect(_on_save_pressed)
	bike_skin_btn.item_selected.disconnect(_on_bike_skin_changed)


func _populate_skins():
	bike_skins = _scan_skin_dir(BIKE_SKINS_DIR)
	character_skins = _scan_skin_dir(CHARACTER_SKINS_DIR)
	color_mods = _scan_color_mods()

	bike_skin_btn.clear()
	for skin_name in bike_skins.keys():
		bike_skin_btn.add_item(skin_name)

	character_skin_btn.clear()
	for skin_name in character_skins.keys():
		character_skin_btn.add_item(skin_name)

	color_mod_btn.clear()
	color_mod_btn.add_item("None")
	for mod_name in color_mods.keys():
		color_mod_btn.add_item(mod_name)


func _scan_skin_dir(dir_path: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		DebugUtils.DebugErrMsg("Failed to open skin directory: %s" % dir_path)
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


func _scan_color_mods() -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(COLOR_MODS_DIR)
	if dir == null:
		DebugUtils.DebugErrMsg("Failed to open color_mods directory: %s" % COLOR_MODS_DIR)
		return result

	var is_exported := !OS.has_feature("editor")
	var extension := ".tres.remap" if is_exported else ".tres"

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(extension):
			var res_path := COLOR_MODS_DIR + file_name.replace(".remap", "")
			var display_name := (
				file_name.replace(extension, "").replace("_", " ").capitalize()
			)
			result[display_name] = res_path
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


func _refresh_color_mod_selection(skin_def: BikeSkinDefinition):
	color_mod_btn.select(0)  # default: None
	if skin_def == null:
		return
	for mod in skin_def.mods:
		if not mod is ColorMod:
			continue
		for i in color_mod_btn.item_count:
			var display_name := color_mod_btn.get_item_text(i)
			if color_mods.get(display_name, "") == mod.resource_path:
				color_mod_btn.select(i)
				return
		break


func _on_bike_skin_changed(_idx: int):
	var bike_name := bike_skin_btn.get_item_text(bike_skin_btn.selected)
	var skin_def := load(bike_skins[bike_name]) as BikeSkinDefinition
	var user_path := skin_def.get_user_save_path()
	if ResourceLoader.exists(user_path):
		skin_def = load(user_path)
	_refresh_color_mod_selection(skin_def)


func _load_current_selections():
	var player_def := save_manager.get_player_definition()
	username_entry.text = player_def.username

	# Match by skin_name (stable across res:// and user:// versions of the same skin)
	# rather than resource_path, which differs once a user:// override has been saved.
	_select_option_by_text(bike_skin_btn, player_def.bike_skin.skin_name)
	_select_option_by_text(character_skin_btn, player_def.character_skin.skin_name)
	_refresh_color_mod_selection(player_def.bike_skin)


func _select_option_by_text(btn: OptionButton, text: String):
	for i in btn.item_count:
		if btn.get_item_text(i) == text:
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

	_save_color_mod(player_def)

	save_manager.update_save("player_definition", player_def, true, true)

	UiToast.ShowToast(tr("SAVED_SETTINGS_LABEL"))


func _save_color_mod(player_def: PlayerDefinition):
	var skin_def: BikeSkinDefinition = player_def.bike_skin
	# Shallow duplicate: keeps mesh_res / curves / collision shapes as external refs.
	# Deep duplicate would strip resource paths and embed broken copies.
	var duped_def := skin_def.duplicate(false) as BikeSkinDefinition

	var mod_name := color_mod_btn.get_item_text(color_mod_btn.selected)
	if mod_name == "None":
		duped_def.mods = [] as Array[BikeMod]
	else:
		var mod := load(color_mods[mod_name]) as BikeMod
		duped_def.mods = [mod] as Array[BikeMod]

	var saved_path := duped_def.save_to_disk()
	if saved_path == "":
		return
	# duped_def now owns saved_path via take_over_path() inside save_to_disk().
	player_def.bike_skin = duped_def


func _on_back_pressed():
	transitioned.emit(return_state, return_ctx)


#override
func on_cancel_key_pressed():
	_on_back_pressed()
