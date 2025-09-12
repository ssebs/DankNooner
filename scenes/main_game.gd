class_name MainGame extends Node

@export var moto_scene: PackedScene = preload("res://scenes/motorcycle.tscn")

@onready var spawn_pos: Marker3D = $SpawnPos
@onready var ui: UI = $UI

enum GameState {MAIN_MENU, PAUSE_MENU, PLAYING}
var game_state: GameState = GameState.MAIN_MENU:
    set(val):
        game_state = val
        switch_game_state(val)

func _ready():
    pass
    # ui.onplay => play_game
    play_game()

func play_game():
    var motorcycle: Motorcycle = moto_scene.instantiate()
    motorcycle.global_position = spawn_pos.global_position
    add_child(motorcycle)

func switch_game_state(state: GameState):
    ui.switch_panels(state)
    match state:
        GameState.MAIN_MENU:
            pass
        GameState.PLAYING:
            pass
