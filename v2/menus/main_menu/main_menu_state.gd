@tool
class_name MainMenuState extends MenuState

@export var menu_manager: MenuManager
@export var level_manager: LevelManager
@export var audio_manager: AudioManager
@export var save_manager: SaveManager
@export var steam_manager: SteamManager
@export var settings_menu_state: MenuState
@export var play_menu_state: MenuState
@export var customize_menu_state: MenuState
@export var tricks_menu_state: MenuState
@export var credits_menu_state: MenuState

@onready var settings_btn: Button = %SettingsBtn
@onready var play_btn: Button = %PlayBtn
@onready var customize_btn: Button = %CustomizeBtn
@onready var quit_btn: Button = %QuitBtn
@onready var tricks_btn: Button = %TricksBtn
@onready var credits_btn: Button = %CreditsBtn
@onready var discord_btn: Button = %DiscordBtn
@onready var wishlist_btn: Button = %WishlistBtn
@onready var version_label: Label = %VersionLabel
@onready var greeting_label: Label = %GreetingLabel
@onready var steam_status_label: Label = %SteamStatusLabel


func _ready():
	super._ready()
	var version: String = ProjectSettings.get_setting("application/config/version")
	if UtilsConstants.is_demo_build():
		version += " (demo)"
	version_label.text = version
	var digits := RegEx.create_from_string("[^0-9]").sub(version, "", true)
	if "69" in digits:
		version_label.mouse_filter = Control.MOUSE_FILTER_STOP
		version_label.mouse_entered.connect(func(): version_label.text = version + "…nice.")
		version_label.mouse_exited.connect(func(): version_label.text = version)

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
	tricks_btn.pressed.connect(_on_tricks_btn_pressed)
	credits_btn.pressed.connect(_on_credits_btn_pressed)
	discord_btn.pressed.connect(_on_discord_btn_pressed)
	wishlist_btn.pressed.connect(_on_wishlist_btn_pressed)
	steam_manager.invite_received.connect(_on_invite_received)

	var username := save_manager.get_player_definition().username
	greeting_label.text = tr("MAIN_MENU_GREETING").format({"name": username})
	steam_status_label.visible = steam_manager.is_logged_in()
	if !steam_manager.pending_game_id.is_empty():
		_on_invite_received.call_deferred()
	elif DebugUtils.auto_host or DebugUtils.auto_join:
		_on_play_btn_pressed.call_deferred()

	if level_manager.current_level_name != LevelManager.LevelName.MAIN_MENU_LEVEL:
		level_manager.spawn_main_menu_level()
		if audio_manager:
			audio_manager.play_minimize()


func Exit(_state_context: StateContext):
	ui.hide()
	# The rider scene is main-menu only; menus opened from here sit on the gray bg
	level_manager.spawn_menu_level()

	play_btn.pressed.disconnect(_on_play_btn_pressed)
	settings_btn.pressed.disconnect(_on_settings_btn_pressed)
	quit_btn.pressed.disconnect(_on_quit_btn_pressed)
	customize_btn.pressed.disconnect(_on_customize_btn_pressed)
	tricks_btn.pressed.disconnect(_on_tricks_btn_pressed)
	credits_btn.pressed.disconnect(_on_credits_btn_pressed)
	discord_btn.pressed.disconnect(_on_discord_btn_pressed)
	wishlist_btn.pressed.disconnect(_on_wishlist_btn_pressed)
	steam_manager.invite_received.disconnect(_on_invite_received)


#region button handlers
func _on_tricks_btn_pressed():
	transitioned.emit(tricks_menu_state, StateContext.NewWithReturn(self))


func _on_credits_btn_pressed():
	transitioned.emit(credits_menu_state, StateContext.NewWithReturn(self))


func _on_discord_btn_pressed():
	OS.shell_open(UtilsConstants.DISCORD_URL)


func _on_wishlist_btn_pressed():
	OS.shell_open(UtilsConstants.STEAM_STORE_URL)


func _on_customize_btn_pressed():
	transitioned.emit(customize_menu_state, StateContext.NewWithReturn(self))


func _on_play_btn_pressed():
	transitioned.emit(play_menu_state, StateContext.NewWithReturn(self))


func _on_settings_btn_pressed():
	transitioned.emit(settings_menu_state, StateContext.NewWithReturn(self))


func _on_quit_btn_pressed():
	get_tree().quit(0)
#endregion


## Play menu joins the pending invite on Enter
func _on_invite_received():
	transitioned.emit(play_menu_state, StateContext.NewWithReturn(self))
