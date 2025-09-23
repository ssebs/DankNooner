class_name MainGame extends Node

@export var moto_scene: PackedScene = preload("res://scenes/motorcycle.tscn")

@onready var spawn_pos: Marker3D = $SpawnPos
@onready var ui: UI = $UI
@onready var menu_screen_items: Node3D = %MenuStuff

enum GameState {MAIN_MENU, PAUSE_MENU, PLAYING, RUN_OVER}

var game_state: GameState:
    set(val):
        game_state = val
        switch_game_state(val)
var motorcycle: Motorcycle

func _ready():
    game_state = GameState.MAIN_MENU
    # Main menu handlers
    ui.play_btn.pressed.connect(start_run)
    ui.quit_btn_main_menu.pressed.connect(func():
        get_tree().quit(0)
    )

    # Upgrade menu handlers
    ui.quit_btn_upgrade_menu.pressed.connect(func():
        get_tree().quit(0)
    )
    ui.retry_btn.pressed.connect(on_retry_pressed)
    ui.main_menu_btn.pressed.connect(goto_main_menu)
    ui.upgrade_1_btn.pressed.connect(func():
        on_upgrade_pressed(1)
        # do something with upgrade_stats
    )
    ui.upgrade_2_btn.pressed.connect(func():
        on_upgrade_pressed(2)
    )
    ui.upgrade_3_btn.pressed.connect(func():
        on_upgrade_pressed(3)
    )

## Spawn Motorcycle, add child, set cam, switch game state, conn finished_run signal
func start_run():
    if spawn_pos == null || Engine.is_editor_hint():
        return
    motorcycle = moto_scene.instantiate()
    motorcycle.position = spawn_pos.position
    add_child(motorcycle)
    motorcycle.camera.make_current()
    switch_game_state(GameState.PLAYING)
    motorcycle.finished_run.connect(on_run_finished)
    SignalBus.notify_ui.emit("Click & drag your mouse to pop a wheelie!", 2)

## Note: Motorcycle should queue_free() on it's own
func on_run_finished(has_crashed: bool, msg: String):
    SignalBus.notify_ui.emit(msg, 5)
    switch_game_state(GameState.RUN_OVER)

    # set stats
    if !has_crashed:
        SignalBus.upgrade_stats.max_clean_runs += 1
        if SignalBus.distance > SignalBus.upgrade_stats.max_distance:
            SignalBus.upgrade_stats.max_distance = SignalBus.distance
        if SignalBus.bonus_time > SignalBus.upgrade_stats.max_bonus_time:
            SignalBus.upgrade_stats.max_bonus_time = SignalBus.bonus_time
    else:
        SignalBus.upgrade_stats.max_clean_runs = 0
    
    SignalBus.money += (SignalBus.distance * (1 + SignalBus.upgrade_stats.max_clean_runs)) + (SignalBus.bonus_time)
    SignalBus.distance = 0.0
    SignalBus.throttle_input = 0.0
    SignalBus.angle_deg = 0.0
    SignalBus.bonus_time = 0.0
    SignalBus.fuel = 10 + SignalBus.upgrade_stats.fuel_level
    ui.fuel_progress.max_value = SignalBus.fuel

    ui.set_max_distance_label_text(SignalBus.upgrade_stats.max_distance)
    ui.set_max_clean_runs_label_text(SignalBus.upgrade_stats.max_clean_runs)
    ui.set_money_label_text(SignalBus.money)
    ui.set_max_bonus_time_label_text(SignalBus.upgrade_stats.max_bonus_time)

func on_upgrade_pressed(num: int):
    print("upgrade " + str(num) + " pressed")

func on_retry_pressed():
    # resets score/stats
    start_run()

func goto_main_menu():
    switch_game_state(GameState.MAIN_MENU)


# TODO: move pause/esc/press logic here

func switch_game_state(state: GameState):
    ui.switch_panels(state)
    match state:
        GameState.MAIN_MENU:
            menu_screen_items.visible = true
        GameState.PLAYING:
            menu_screen_items.visible = false
        GameState.PAUSE_MENU:
            menu_screen_items.visible = false
        GameState.RUN_OVER:
            menu_screen_items.visible = true
