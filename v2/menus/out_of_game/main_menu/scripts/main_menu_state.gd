class_name MainMenuState extends State

@export var menu_manager: MenuManager
@export var menu_scene: BaseMenu

var settings_btn: Button = null
var quit_btn: Button = null

func _ready():
    settings_btn = menu_scene.get_node("%SettingsBtn")
    quit_btn = menu_scene.get_node("%QuitBtn")

func Enter():
    menu_scene.show()
    settings_btn.pressed.connect(_on_settings_pressed)
    quit_btn.pressed.connect(_on_quit_pressed)

func Exit():
    menu_scene.hide()
    # HACK - I don't like these kinds of checks
    if settings_btn:
        settings_btn.pressed.disconnect(_on_settings_pressed)
    if quit_btn:
        quit_btn.pressed.disconnect(_on_quit_pressed)

func _on_settings_pressed():
    var new_state = state_machine_ref.get_state_by_name("SettingsMenuState")
    transitioned.emit(new_state)

func _on_quit_pressed():
    get_tree().quit(0)
