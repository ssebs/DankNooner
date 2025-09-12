class_name MainGame extends Node

@export var moto_scene: PackedScene = preload("res://scenes/motorcycle.tscn")

@onready var spawn_pos: Marker3D = $SpawnPos
@onready var ui: UI = $UI
@onready var menu_stuff = %MenuStuff

enum GameState {MAIN_MENU, PAUSE_MENU, PLAYING}
var game_state: GameState:
    set(val):
        game_state = val
        switch_game_state(val)

func _ready():
    game_state = GameState.MAIN_MENU
    ui.play_btn.pressed.connect(on_play_pressed)
    ui.quit_btn.pressed.connect(func():
        get_tree().quit(0)
    )


func on_play_pressed():
    var motorcycle: Motorcycle = moto_scene.instantiate()
    motorcycle.global_position = spawn_pos.global_position
    add_child(motorcycle)
    motorcycle.camera.make_current()
    switch_game_state(GameState.PLAYING)

# TODO: move pause/esc/press logic here

func switch_game_state(state: GameState):
    ui.switch_panels(state)
    match state:
        GameState.MAIN_MENU:
            menu_stuff.visible = true
        GameState.PLAYING:
            menu_stuff.visible = false
        GameState.PAUSE_MENU:
            menu_stuff.visible = false
