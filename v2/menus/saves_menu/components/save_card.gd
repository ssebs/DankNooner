## One Saves menu slot: a still of the save's active loadout, its name, level, money and version,
## or a big `+` when the slot is empty. An older save_version is grayed out and can only be deleted.
class_name SaveCard extends PanelContainer

signal new_pressed
signal load_pressed
signal delete_pressed
signal name_submitted(slot_name: String)

const OLD_VERSION_MODULATE := Color(1, 1, 1, 0.4)

@onready var _new_btn: Button = %NewBtn
@onready var _filled: Control = %Filled
@onready var _preview: SavePreview = %Preview
@onready var _active_label: Label = %ActiveLabel
@onready var _name_edit: LineEdit = %NameEdit
@onready var _stats: Control = %Stats
@onready var _level_label: Label = %LevelLabel
@onready var _money_label: Label = %MoneyLabel
@onready var _version_label: Label = %VersionLabel
@onready var _delete_btn: Button = %DeleteBtn

## The panel takes the theme's Button normal / hover / pressed style, like a button.
var _style_state: String = ""
var _held: bool = false
## Empty (its `+` starts a save), or a current-version save that isn't the active one.
var _loadable: bool = false
var _is_current_version: bool = false


## "Save N" when the save has no name. Static (TranslationServer, not tr) for the main menu.
static func display_name(slot: int, save_dict: Dictionary) -> String:
	var slot_name: String = save_dict.get("name", "")
	if slot_name != "":
		return slot_name
	return TranslationServer.translate("SAVE_SLOT_DEFAULT_NAME").format({"slot": slot})


static func level_text(player_def: PlayerDefinition) -> String:
	return TranslationServer.translate("SAVE_SLOT_LEVEL").format({"level": player_def.level()})


func _ready():
	_restyle()
	_new_btn.pressed.connect(new_pressed.emit)
	_delete_btn.pressed.connect(delete_pressed.emit)
	_name_edit.text_submitted.connect(name_submitted.emit)
	_name_edit.focus_exited.connect(_on_name_focus_exited)


## _input, not mouse_entered / _gui_input: the card's own buttons and name field (the empty
## card's `+` covers all of it) take the mouse first.
func _input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_held = event.pressed and _is_hovered()
		_restyle()
	elif event is InputEventMouseMotion:
		_restyle()


## Clicks the card's Delete and name field keep; the preview, labels and containers pass up.
func _gui_input(event: InputEvent):
	if (
		_loadable
		and event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and !event.pressed
	):
		load_pressed.emit()


func _is_hovered() -> bool:
	return get_global_rect().has_point(get_global_mouse_position())


func _restyle():
	var hovered := _loadable and _is_hovered()
	var state := "pressed" if _held and hovered else ("hover" if hovered else "normal")
	if state != _style_state:
		_style_state = state
		add_theme_stylebox_override("panel", get_theme_stylebox(state, "Button"))


## `save_dict` is the raw save (SaveManager.read_slot), {} for an empty slot.
func show_save(slot: int, save_dict: Dictionary, is_current_version: bool) -> void:
	_new_btn.visible = save_dict.is_empty()
	_filled.visible = !save_dict.is_empty()
	_is_current_version = is_current_version
	if save_dict.is_empty():
		return

	_name_edit.placeholder_text = tr("SAVE_SLOT_DEFAULT_NAME").format({"slot": slot})
	_name_edit.text = save_dict.get("name", "")
	_version_label.text = tr("SAVE_SLOT_VERSION").format({"version": int(save_dict.get("version", 0))})
	_filled.modulate = Color.WHITE if is_current_version else OLD_VERSION_MODULATE
	_name_edit.editable = is_current_version
	_stats.visible = is_current_version
	_preview.visible = is_current_version
	# An older save's player_definition may not parse.
	if !is_current_version:
		return

	var player_def := PlayerDefinition.new()
	player_def.from_dict(save_dict["player_definition"])
	_level_label.text = level_text(player_def)
	_money_label.text = MoneyLabel.format(player_def.money)
	_preview.show_player(player_def)


## An older save's name is read-only, so leaving its field mustn't rewrite the file.
func _on_name_focus_exited():
	if _name_edit.editable:
		name_submitted.emit(_name_edit.text)


## Shows the "(active)" subtitle; no redraw. Call after show_save. `locked`: no load or delete.
func set_active(is_active: bool, locked: bool = false) -> void:
	# Faded, not hidden, so every card's preview sits at the same height.
	_active_label.modulate.a = 1.0 if is_active else 0.0
	_delete_btn.visible = !locked
	_loadable = !locked and (_new_btn.visible or (_is_current_version and !is_active))
	mouse_default_cursor_shape = CURSOR_POINTING_HAND if _loadable else CURSOR_ARROW
	_restyle()
