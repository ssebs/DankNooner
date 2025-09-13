class_name MainGame extends Node

@export var moto_scene: PackedScene = preload("res://scenes/motorcycle.tscn")

@onready var spawn_pos: Marker3D = $SpawnPos
@onready var ui: UI = $UI
@onready var menu_stuff = %MenuStuff

enum GameState {MAIN_MENU, PAUSE_MENU, PLAYING, RUN_OVER}

var game_state: GameState:
    set(val):
        game_state = val
        switch_game_state(val)
var motorcycle: Motorcycle
# var high_score: 

func _ready():
    game_state = GameState.MAIN_MENU
    ui.play_btn.pressed.connect(start_run)
    ui.quit_btn.pressed.connect(func():
        get_tree().quit(0)
    )
    ui.restart_btn.pressed.connect(on_restart_pressed)

## Spawn Motorcycle, add child, set cam, switch game state, conn finished_run signal
func start_run():
    motorcycle = moto_scene.instantiate()
    motorcycle.global_position = spawn_pos.global_position
    add_child(motorcycle)
    motorcycle.camera.make_current()
    switch_game_state(GameState.PLAYING)
    motorcycle.finished_run.connect(on_run_finished)
    SignalBus.notify_ui.emit("Click & drag your mouse to pop a wheelie!", 2)

## Note: Motorcycle should queue_free() on it's own
func on_run_finished(has_crashed: bool):
    switch_game_state(GameState.RUN_OVER)
    ui.restart_btn.visible = true
    
    # ui.notify_finished.connect(func():
    #     pass
    # )

    if has_crashed:
        # disable_input = true
        SignalBus.notify_ui.emit("You crashed!")
    else:
        # disable_input = true
        SignalBus.notify_ui.emit("Run finished!")

func on_restart_pressed():
    ui.restart_btn.visible = false
    # reset score
    start_run()


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
        GameState.RUN_OVER:
            menu_stuff.visible = true
