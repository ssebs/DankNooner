@tool
class_name LobbyMenuState extends MenuState

# SEE planning_docs\diagrams\play-menu-ui.excalidraw

@export var menu_manager: MenuManager
@export var play_menu_state: MenuState

@export var player_list_item_scene: PackedScene = preload(
	"res://menus/out_of_game/lobby_menu/player_list_item.tscn"
)

@onready var singleplayer_ui: Control = %SingleplayerUI
@onready var multiplayer_ui: Control = %MultiplayerUI

@onready var back_btn: Button = %BackBtn
@onready var level_select_btn: OptionButton = %LevelSelectBtn
@onready var level_preview_tex: TextureRect = %LevelPreview
@onready var start_btn: Button = %StartBtn

@onready var ip_label: Label = %IPLabel
# @onready var ip_copy_btn: Button = %IPCopyBtn
# @onready var invite_btn: Button = %InviteBtn
@onready var player_list: VBoxContainer = %PlayersList

var ctx: LobbyStateContext


func Enter(state_context: StateContext):
    if state_context is not LobbyStateContext:
        printerr("Must pass LobbyStateContext type when transitioning to LobbyMenuState")
        return

    ctx = state_context
    ui.show()
    back_btn.pressed.connect(_on_back_pressed)
    start_btn.pressed.connect(_on_start_pressed)

    set_panel_rename_me()


func Exit(_state_context: StateContext):
    ui.hide()
    ctx = null
    back_btn.pressed.disconnect(_on_back_pressed)
    start_btn.pressed.disconnect(_on_start_pressed)


func set_panel_rename_me():
    match ctx.mode:
        LobbyStateContext.Mode.FREEROAM:
            multiplayer_ui.hide()
            singleplayer_ui.show()
        _:
            singleplayer_ui.hide()
            multiplayer_ui.show()


#region button handlers
func _on_start_pressed():
    var level_manager = menu_manager.manager_manager.level_manager
    level_manager.spawn_level(level_manager.LevelName.TEST_LEVEL_01)
    menu_manager.hide_all_menus()


func _on_back_pressed():
    transitioned.emit(play_menu_state, null)
#endregion
