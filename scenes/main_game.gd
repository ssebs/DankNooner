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
var max_score: int = 0
var max_distance: float = 0.0
var max_clean_runs: int = 0

func _ready():
    game_state = GameState.MAIN_MENU
    ui.play_btn.pressed.connect(start_run)
    ui.quit_btn.pressed.connect(func():
        get_tree().quit(0)
    )
    ui.restart_btn.pressed.connect(on_restart_pressed)

## Spawn Motorcycle, add child, set cam, switch game state, conn finished_run signal
func start_run():
    if spawn_pos == null || SignalBus == null || SignalBus.notify_ui == null:
        return
    motorcycle = moto_scene.instantiate()
    motorcycle.global_position = spawn_pos.global_position
    add_child(motorcycle)
    motorcycle.camera.make_current()
    switch_game_state(GameState.PLAYING)
    motorcycle.finished_run.connect(on_run_finished)
    SignalBus.notify_ui.emit("Click & drag your mouse to pop a wheelie!", 2)

## Note: Motorcycle should queue_free() on it's own
func on_run_finished(has_crashed: bool, msg: String):
    switch_game_state(GameState.RUN_OVER)
    ui.restart_btn.visible = true
    
    # ui.notify_finished.connect(func():
    #     pass
    # )
    if !has_crashed:
        if SignalBus.score > max_score:
            max_score = SignalBus.score
        if SignalBus.distance > max_distance:
            max_distance = SignalBus.distance
    
    SignalBus.score = 0
    SignalBus.distance = 0.0
    SignalBus.throttle_input = 0.0
    SignalBus.angle_deg = 0.0
    ui.set_max_distance_label_text(max_distance)
    ui.set_max_score_label_text(max_score)
    ui.set_max_clean_runs_label_text(max_clean_runs)

    SignalBus.notify_ui.emit(msg, 5)

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
