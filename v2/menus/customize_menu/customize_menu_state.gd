@tool
class_name CustomizeMenuState extends MenuState

@export var menu_manager: MenuManager
@export var save_manager: SaveManager
@export var play_menu_state: MenuState
@export var loadout_card_scene: PackedScene = preload(
	"res://menus/customize_menu/components/loadout_card.tscn"
)
@export var new_loadout_card_scene: PackedScene = preload(
	"res://menus/customize_menu/components/new_loadout_card.tscn"
)

const BIKE_SKINS_DIR := "res://resources/bikes/skins/"
const CHARACTER_SKINS_DIR := "res://resources/player/skins/"
const COLOR_MODS_DIR := "res://resources/bikes/mods/color_mods/"

@onready var back_btn: Button = %BackBtn
@onready var username_entry: LineEdit = %UsernameEntry
@onready var character_skin_btn: OptionButton = %CharacterSkinBtn

@onready var loadout_grid: GridContainer = %LoadoutGrid
@onready var name_entry: LineEdit = %NameEntry
@onready var base_bike_btn: OptionButton = %BaseBikeBtn
@onready var color_mod_btn: OptionButton = %ColorModBtn
@onready var save_btn: Button = %SaveBtn
@onready var delete_btn: Button = %DeleteBtn
@onready var set_active_btn: Button = %SetActiveBtn

@onready var bg_tint: ColorRect = %BGTint

# skin_name -> res path
var bike_skins: Dictionary = {}
var character_skins: Dictionary = {}
# display_name -> res_path
var color_mods: Dictionary = {}

var selected_index: int = 0


func Enter(state_context: StateContext):
	bg_tint.visible = false
	return_ctx = state_context
	return_state = state_context.return_state

	if state_context is PauseStateContext:
		bg_tint.visible = state_context.show_bg_tint

	ui.show()
	back_btn.pressed.connect(_on_back_pressed)
	save_btn.pressed.connect(_on_save_pressed)
	delete_btn.pressed.connect(_on_delete_pressed)
	set_active_btn.pressed.connect(_on_set_active_pressed)
	base_bike_btn.item_selected.connect(_on_base_bike_changed)
	username_entry.text_changed.connect(_on_username_changed)
	character_skin_btn.item_selected.connect(_on_character_skin_changed)

	_populate_option_lists()
	_load_username_and_character()
	selected_index = save_manager.get_player_definition().active_loadout_index
	_rebuild_grid()
	_load_selected_into_editor()


func Exit(_state_context: StateContext):
	ui.hide()
	back_btn.pressed.disconnect(_on_back_pressed)
	save_btn.pressed.disconnect(_on_save_pressed)
	delete_btn.pressed.disconnect(_on_delete_pressed)
	set_active_btn.pressed.disconnect(_on_set_active_pressed)
	base_bike_btn.item_selected.disconnect(_on_base_bike_changed)
	username_entry.text_changed.disconnect(_on_username_changed)
	character_skin_btn.item_selected.disconnect(_on_character_skin_changed)


#region populate / scan
func _populate_option_lists() -> void:
	bike_skins = _scan_skin_dir(BIKE_SKINS_DIR)
	character_skins = _scan_skin_dir(CHARACTER_SKINS_DIR)
	color_mods = _scan_color_mods()

	base_bike_btn.clear()
	for skin_name in bike_skins.keys():
		base_bike_btn.add_item(skin_name)

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
			var display_name := file_name.replace(extension, "").replace("_", " ").capitalize()
			result[display_name] = res_path
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


#endregion


#region top-level (username + character)
func _load_username_and_character() -> void:
	var player_def := save_manager.get_player_definition()
	username_entry.text = player_def.username
	_select_option_by_text(character_skin_btn, player_def.character_skin.skin_name)


func _on_username_changed(_new: String) -> void:
	var player_def := save_manager.get_player_definition()
	player_def.username = username_entry.text
	save_manager.update_save("player_definition", player_def, true, true)


func _on_character_skin_changed(idx: int) -> void:
	if idx < 0:
		return
	var player_def := save_manager.get_player_definition()
	var char_name := character_skin_btn.get_item_text(idx)
	player_def.character_skin = load(character_skins[char_name])
	save_manager.update_save("player_definition", player_def, true, true)


#endregion


#region loadout grid
func _rebuild_grid() -> void:
	for child in loadout_grid.get_children():
		child.queue_free()

	var player_def := save_manager.get_player_definition()
	for i in player_def.loadouts.size():
		var card: LoadoutCard = loadout_card_scene.instantiate()
		loadout_grid.add_child(card)
		(
			card
			. populate(
				player_def.loadouts[i],
				i,
				i == player_def.active_loadout_index,
				i == selected_index,
			)
		)
		card.selected.connect(_on_card_selected)
		card.set_active_requested.connect(_on_card_set_active_requested)

	var at_cap := player_def.loadouts.size() >= PlayerDefinition.MAX_LOADOUTS
	var new_card: NewLoadoutCard = new_loadout_card_scene.instantiate()
	if at_cap:
		new_card.disable_btn()
	loadout_grid.add_child(new_card)
	new_card.new_pressed.connect(_on_new_loadout_pressed)


func _on_card_selected(idx: int) -> void:
	selected_index = idx
	_load_selected_into_editor()
	_rebuild_grid()


func _on_card_set_active_requested(idx: int) -> void:
	selected_index = idx
	_on_set_active_pressed()


#endregion


#region edit panel
func _load_selected_into_editor() -> void:
	var player_def := save_manager.get_player_definition()
	if (
		player_def.loadouts.is_empty()
		or selected_index < 0
		or selected_index >= player_def.loadouts.size()
	):
		return
	var def := player_def.loadouts[selected_index]
	name_entry.text = def.skin_name
	_select_option_by_text(base_bike_btn, _base_bike_name_for(def))
	_refresh_color_mod_selection(def)

	delete_btn.disabled = player_def.loadouts.size() <= 1
	set_active_btn.disabled = (selected_index == player_def.active_loadout_index)


func _base_bike_name_for(def: BikeSkinDefinition) -> String:
	# Match by base_res_path so customized loadouts still resolve back to their base bike name.
	for skin_name in bike_skins.keys():
		if bike_skins[skin_name] == def.base_res_path:
			return skin_name
	return def.skin_name


func _refresh_color_mod_selection(skin_def: BikeSkinDefinition) -> void:
	color_mod_btn.select(0)
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


func _on_base_bike_changed(_idx: int) -> void:
	# Live-preview color mod options based on whatever the user picked.
	pass


func _on_save_pressed() -> void:
	var player_def := save_manager.get_player_definition()
	if player_def.loadouts.is_empty():
		return

	var base_idx := base_bike_btn.selected
	if base_idx < 0:
		return
	var base_name := base_bike_btn.get_item_text(base_idx)
	var base_def := load(bike_skins[base_name]) as BikeSkinDefinition

	var duped: BikeSkinDefinition = base_def.duplicate(false) as BikeSkinDefinition
	duped.base_res_path = bike_skins[base_name]
	duped.skin_name = name_entry.text if name_entry.text.strip_edges() != "" else base_def.skin_name

	var mod_name := color_mod_btn.get_item_text(color_mod_btn.selected)
	if mod_name == "None":
		duped.mods = [] as Array[BikeMod]
	else:
		var mod := load(color_mods[mod_name]) as BikeMod
		duped.mods = [mod] as Array[BikeMod]

	# Persist to user://skins/ so to_dict/from_dict roundtrips have a cached copy.
	duped.save_to_disk()

	player_def.loadouts[selected_index] = duped
	save_manager.update_save("player_definition", player_def, true, true)

	UiToast.ShowToast(tr("SAVED_SETTINGS_LABEL"))
	_rebuild_grid()


func _on_delete_pressed() -> void:
	var player_def := save_manager.get_player_definition()
	if player_def.loadouts.size() <= 1:
		return

	player_def.loadouts.remove_at(selected_index)
	if player_def.active_loadout_index >= player_def.loadouts.size():
		player_def.active_loadout_index = 0
	selected_index = clampi(selected_index, 0, player_def.loadouts.size() - 1)
	save_manager.update_save("player_definition", player_def, true, true)
	_rebuild_grid()
	_load_selected_into_editor()


func _on_set_active_pressed() -> void:
	var player_def := save_manager.get_player_definition()
	player_def.active_loadout_index = selected_index
	save_manager.update_save("player_definition", player_def, true, true)
	_rebuild_grid()
	_load_selected_into_editor()


func _on_new_loadout_pressed() -> void:
	var player_def := save_manager.get_player_definition()
	if player_def.loadouts.size() >= PlayerDefinition.MAX_LOADOUTS:
		return
	if bike_skins.is_empty():
		return

	var first_base_path: String = bike_skins.values()[0]
	var new_def := BikeSkinDefinition.new()
	(
		new_def
		. from_dict(
			{
				"base_res_path": first_base_path,
				"skin_name": "Loadout %d" % (player_def.loadouts.size() + 1),
			}
		)
	)
	player_def.loadouts.append(new_def)
	selected_index = player_def.loadouts.size() - 1
	save_manager.update_save("player_definition", player_def, true, true)
	_rebuild_grid()
	_load_selected_into_editor()


#endregion


func _select_option_by_text(btn: OptionButton, text: String) -> void:
	for i in btn.item_count:
		if btn.get_item_text(i) == text:
			btn.select(i)
			return


func _on_back_pressed() -> void:
	transitioned.emit(return_state, return_ctx)


#override
func on_cancel_key_pressed() -> void:
	_on_back_pressed()
