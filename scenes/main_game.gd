class_name MainGame extends Node

@export var moto_scene: PackedScene = preload("res://scenes/motorcycle.tscn")

@onready var spawn_pos: Marker3D = $SpawnPos
@onready var ui: UI = $UI
@onready var menu_screen_items: Node3D = %MenuStuff

enum GameState {MAIN_MENU, PAUSE_MENU, PLAYING, RUN_OVER}

var game_state: GameState
var motorcycle: Motorcycle

func _ready():
    switch_game_state(GameState.MAIN_MENU)

    # Main menu handlers
    ui.play_btn.pressed.connect(start_run)
    ui.quit_btn_main_menu.pressed.connect(func():
        get_tree().quit(0)
    )

    # Upgrade menu handlers
    ui.quit_btn_upgrade_menu.pressed.connect(func():
        get_tree().quit(0)
    )
    ui.retry_btn.pressed.connect(start_run)
    ui.main_menu_btn.pressed.connect(goto_main_menu)
    ui.upgrade_1_btn.pressed.connect(on_upgrade_1_pressed)
    ui.upgrade_2_btn.pressed.connect(on_upgrade_2_pressed)
    ui.upgrade_3_btn.pressed.connect(on_upgrade_3_pressed)

#region gameplay
func on_upgrade_1_pressed():
    print("Boost count upgrade")
    if SignalBus.upgrade_stats.speed_boost_level < UpgradeStatsRes.Level.HIGH:
        # += doesn't cast properly, according to the linter B)
        var new_val = SignalBus.upgrade_stats.speed_boost_level + 1
        SignalBus.upgrade_stats.speed_boost_level = new_val as UpgradeStatsRes.Level

        ui.set_speed_boost_upgrade_label_text(SignalBus.upgrade_stats.speed_boost_level)
        
    if SignalBus.upgrade_stats.speed_boost_level >= UpgradeStatsRes.Level.HIGH:
        ui.upgrade_1_btn.disabled = true
    
func on_upgrade_2_pressed():
    print("Max Speed Upgrade")
    
func on_upgrade_3_pressed():
    print("Max Gas Upgrade")

## Spawn Motorcycle, add child, set cam, switch game state, conn finished_run signal
func start_run():
    if Engine.is_editor_hint():
        return
    motorcycle = moto_scene.instantiate()
    motorcycle.position = spawn_pos.position
    add_child(motorcycle)
    motorcycle.camera.make_current()
    motorcycle.finished_run.connect(on_run_finished)
    switch_game_state(GameState.PLAYING)
    SignalBus.notify_ui.emit("Click & drag your mouse to pop a wheelie!\nOr use WASD...", 2)

## Note: Motorcycle should queue_free() on it's own
func on_run_finished(has_crashed: bool, msg: String):
    SignalBus.notify_ui.emit(msg, 5) # TODO: move out of GamePanel so it doesn't hide
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
    
    reset_stats()

func reset_stats():
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
    ui.set_boosts_remaining_label_text(SignalBus.upgrade_stats.speed_boost_level as int)

#endregion

#region level select
# TODO: move pause/esc/press logic here
func goto_main_menu():
    switch_game_state(GameState.MAIN_MENU)

func switch_game_state(state: GameState):
    game_state = state
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
#endregion
