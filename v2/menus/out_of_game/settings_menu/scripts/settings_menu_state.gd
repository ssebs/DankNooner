class_name SettingsMenuState extends State

@export var menu_scene: BaseMenu

var back_btn: Button = null

func _ready():
    # HACK - I don't like getting the node this way
    back_btn = menu_scene.get_node("%BackBtn")

func Enter():
    back_btn.pressed.connect(_on_back_pressed)

func Exit():
    if back_btn:
        back_btn.pressed.disconnect(_on_back_pressed)

func _on_back_pressed():
    var new_state = state_machine_ref.get_state_by_name("MainMenuState")
    transitioned.emit(new_state)
