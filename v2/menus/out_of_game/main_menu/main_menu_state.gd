@tool
class_name MainMenuState extends MenuState

@export var menu_manager: MenuManager
@export var level_manager: LevelManager
@export var settings_menu_state: MenuState
@export var play_menu_state: MenuState
@export var customize_menu_state: MenuState
@export var help_menu_state: MenuState

@onready var settings_btn: Button = %SettingsBtn
@onready var play_btn: Button = %PlayBtn
@onready var customize_btn: Button = %CustomizeBtn
@onready var quit_btn: Button = %QuitBtn
@onready var help_btn: Button = %HelpBtn
@onready var version_label: Label = %VersionLabel


func _ready():
	version_label.text = ProjectSettings.get_setting("application/config/version")

	if OS.has_feature("web"):
		quit_btn.text = "WEB_QUIT_LABEL"
		quit_btn.disabled = true
	else:
		quit_btn.text = "QUIT_LABEL"


func Enter(_state_context: StateContext):
	ui.show()
	play_btn.pressed.connect(_on_play_btn_pressed)
	settings_btn.pressed.connect(_on_settings_btn_pressed)
	quit_btn.pressed.connect(_on_quit_btn_pressed)
	customize_btn.pressed.connect(_on_customize_btn_pressed)
	help_btn.pressed.connect(_on_help_btn_pressed)

	if level_manager.current_level_name != LevelManager.LevelName.BG_GRAY_LEVEL:
		level_manager.spawn_menu_level()


func Exit(_state_context: StateContext):
	ui.hide()

	play_btn.pressed.disconnect(_on_play_btn_pressed)
	settings_btn.pressed.disconnect(_on_settings_btn_pressed)
	quit_btn.pressed.disconnect(_on_quit_btn_pressed)
	customize_btn.pressed.disconnect(_on_customize_btn_pressed)
	help_btn.pressed.disconnect(_on_help_btn_pressed)


#region button handlers
func _on_help_btn_pressed():
	transitioned.emit(help_menu_state, StateContext.NewWithReturn(self))


func _on_customize_btn_pressed():
	transitioned.emit(customize_menu_state, StateContext.NewWithReturn(self))


func _on_play_btn_pressed():
	transitioned.emit(play_menu_state, StateContext.NewWithReturn(self))


func _on_settings_btn_pressed():
	transitioned.emit(settings_menu_state, StateContext.NewWithReturn(self))


func _on_quit_btn_pressed():
	get_tree().quit(0)
#endregion
