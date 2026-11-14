@tool
## Profile: tabs on the left 3/4, the active save's ProfileCard and challenges on the right 1/4.
## Save Slots tab: the active save's username, then a card per save on disk (this build's only, see
## SaveManager.slot_path) and empty cards in the lowest free slots up to MIN_CARDS. From the pause
## menu (a PauseStateContext) it's rename-only: no empty cards, load or delete. Cards are rebuilt,
## previews included, on Enter, and so are the Career, Bike Challenges and challenge lists.
class_name SavesMenuState extends MenuState

@export var save_manager: SaveManager
@export var input_state_manager: InputStateManager

const MIN_CARDS := 3
const SAVE_CARD_SCENE := preload("res://menus/saves_menu/components/save_card.tscn")

# TODO: real bike challenges + mastery, Progression.md step 4. Bike type -> its list.
const _STUB_BIKE_CHALLENGES: Dictionary = {
	"Mini": {
		"mastery": 2,
		"challenges": [
			{"title": "Land 10 bunny hops", "progress": 10, "target": 10},
			{"title": "Hold a 5s wheelie", "progress": 10, "target": 10},
			{"title": "Grind 50m of rail", "progress": 12, "target": 50},
		],
	},
	"Naked": {
		"mastery": 1,
		"challenges": [
			{"title": "Hold a 3s stoppie", "progress": 10, "target": 10},
			{"title": "Win 5 stunt battles", "progress": 2, "target": 5},
			{"title": "1 minute of airtime", "progress": 18, "target": 60},
		],
	},
	"Sport": {
		"mastery": 0,
		"challenges": [
			{"title": "Hit 250 km/h", "progress": 0, "target": 1},
			{"title": "Win 5 stunt races", "progress": 1, "target": 5},
			{"title": "Hold a 10s wheelie", "progress": 4, "target": 10},
		],
	},
}
const _MAX_MASTERY := 10

@onready var _bg_tint: ColorRect = %BGTint
@onready var _tabs: PromptTabContainer = %Tabs
@onready var _username_edit: LineEdit = %UsernameEdit
@onready var _profile_card: ProfileCard = %ProfileCard
@onready var _cards: HBoxContainer = %Cards
@onready var _career_list: VBoxContainer = %CareerList
@onready var _bike_list: VBoxContainer = %BikeList
@onready var _challenge_list: VBoxContainer = %ChallengeList
@onready var _close_btn: Button = %CloseBtn
@onready var _confirm_box: Control = %ConfirmBox
@onready var _confirm_label: Label = %ConfirmLabel
@onready var _confirm_yes_btn: Button = %ConfirmYesBtn
@onready var _confirm_no_btn: Button = %ConfirmNoBtn

## slot -> its SaveCard
var _card_by_slot: Dictionary = {}
## Runs on the confirm box's yes (load or delete).
var _on_confirm: Callable
## Opened mid-game: swapping saves under a live session isn't allowed.
var _in_session: bool = false


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if save_manager == null:
		warnings.append("save_manager is not set")
	if input_state_manager == null:
		warnings.append("input_state_manager is not set")
	return warnings


func Enter(state_context: StateContext):
	return_state = state_context.return_state
	_in_session = state_context is PauseStateContext
	_bg_tint.visible = _in_session and state_context.show_bg_tint
	ui.show()
	_confirm_box.hide()
	_show_active()
	_username_edit.text_submitted.connect(_on_username_submitted)
	_username_edit.focus_exited.connect(_on_username_focus_exited)
	_close_btn.pressed.connect(_on_close_pressed)
	_confirm_yes_btn.pressed.connect(_on_confirm_yes)
	_confirm_no_btn.pressed.connect(_confirm_box.hide)
	input_state_manager.device_changed.connect(_tabs.show_prompts)
	_tabs.show_prompts(input_state_manager.is_gamepad)
	_build_cards()
	ProfileCard.build_rows(_career_list, ProfileCard.STUB_CAREER)
	ProfileCard.build_rows(_challenge_list, ProfileCard.STUB_CHALLENGES)
	_build_bike_lists()


func Exit(_state_context: StateContext):
	ui.hide()
	_username_edit.text_submitted.disconnect(_on_username_submitted)
	_username_edit.focus_exited.disconnect(_on_username_focus_exited)
	_close_btn.pressed.disconnect(_on_close_pressed)
	_confirm_yes_btn.pressed.disconnect(_on_confirm_yes)
	_confirm_no_btn.pressed.disconnect(_confirm_box.hide)
	input_state_manager.device_changed.disconnect(_tabs.show_prompts)
	for list: Node in [_cards, _career_list, _bike_list, _challenge_list]:
		for child in list.get_children():
			child.queue_free()
	_card_by_slot.clear()


## A mastery header per bike type over its challenges.
func _build_bike_lists():
	for bike_type: String in _STUB_BIKE_CHALLENGES:
		var bike: Dictionary = _STUB_BIKE_CHALLENGES[bike_type]
		var header := Label.new()
		header.theme_type_variation = &"Heading2Label"
		header.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		header.text = "%s  %d/%d" % [bike_type, bike["mastery"], _MAX_MASTERY]
		_bike_list.add_child(header)
		var challenges: Array[Dictionary] = []
		challenges.assign(bike["challenges"])
		ProfileCard.build_rows(_bike_list, challenges)


func _build_cards():
	var saved := save_manager.saved_slots()
	var slots := saved.duplicate()
	var free_slot := 1
	while !_in_session and slots.size() < MIN_CARDS:
		if free_slot not in saved:
			slots.append(free_slot)
		free_slot += 1
	slots.sort()

	for slot in slots:
		var card: SaveCard = SAVE_CARD_SCENE.instantiate()
		_cards.add_child(card)
		_card_by_slot[slot] = card
		_wire_button_click_sounds(card)
		card.new_pressed.connect(_load_slot.bind(slot))
		card.load_pressed.connect(_on_load_pressed.bind(slot))
		card.delete_pressed.connect(_on_delete_pressed.bind(slot))
		card.name_submitted.connect(_on_slot_name_submitted.bind(slot))
		_show_card(slot)
	_mark_active()


## Redraws the card's preview, so only for a slot whose save changed.
func _show_card(slot: int):
	var save_dict := save_manager.read_slot(slot)
	_card_by_slot[slot].show_save(slot, save_dict, save_manager.is_current_version(save_dict))


func _mark_active():
	for slot in _card_by_slot:
		_card_by_slot[slot].set_active(slot == save_manager.save_slot, _in_session)


## Loading an empty slot starts a new save there.
func _load_slot(slot: int):
	var was_empty := save_manager.read_slot(slot).is_empty()
	save_manager.switch_slot(slot)
	if was_empty:
		_show_card(slot)
	_mark_active()
	_show_active()


## Deleting the active save may start a new one in its slot (SaveManager.delete_slot).
func _delete_slot(slot: int):
	save_manager.delete_slot(slot)
	_show_card(slot)
	_mark_active()
	_show_active()


## The username field and profile card follow the active save.
func _show_active():
	_username_edit.text = save_manager.get_player_definition().username
	_profile_card.show_save(
		save_manager.save_slot, save_manager.current_save, save_manager.get_player_definition()
	)


func _on_slot_name_submitted(slot_name: String, slot: int):
	save_manager.rename_slot(slot, slot_name)
	if slot == save_manager.save_slot:
		_show_active()


func _on_load_pressed(slot: int):
	_confirm(tr("SAVE_LOAD_CONFIRM") % _slot_name(slot), "LOAD_LABEL", _load_slot.bind(slot))


func _on_delete_pressed(slot: int):
	_confirm(tr("GARAGE_DELETE_CONFIRM") % _slot_name(slot), "DELETE_LABEL", _delete_slot.bind(slot))


func _slot_name(slot: int) -> String:
	return SaveCard.display_name(slot, save_manager.read_slot(slot))


func _confirm(question: String, yes_label: String, on_yes: Callable):
	_confirm_label.text = question
	_confirm_yes_btn.text = yes_label
	_on_confirm = on_yes
	_confirm_box.show()


func _on_confirm_yes():
	_confirm_box.hide()
	_on_confirm.call()


func _on_username_submitted(username: String):
	var player_def := save_manager.get_player_definition()
	player_def.username = username
	save_manager.update_save("player_definition", player_def, true, true)


func _on_username_focus_exited():
	_on_username_submitted(_username_edit.text)


func _on_close_pressed():
	transitioned.emit(return_state, StateContext.NewWithReturn(self))


#override
func on_cancel_key_pressed():
	if _confirm_box.visible:
		_confirm_box.hide()
		return
	_on_close_pressed()


#override
func on_tab_key_pressed(dir: int):
	_tabs.current_tab = wrapi(_tabs.current_tab + dir, 0, _tabs.get_tab_count())
