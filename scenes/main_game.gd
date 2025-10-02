class_name MainGame extends Node

@export var moto_scene: PackedScene = preload("res://scenes/motorcycle.tscn")

@onready var spawn_pos: Marker3D = $SpawnPos
@onready var ui: UI = $UI
@onready var menu_screen_items: Node3D = %MenuStuff

enum GameState {MAIN_MENU, PAUSE_MENU, PLAYING, RUN_OVER}

var game_state: GameState
var motorcycle: Motorcycle

# TODO: multiply cost by upgrade level
var upgrade_button_metadata: Dictionary = {
    1: {
        "label": "+1 Speed Boost\n$600",
        'cost': 600,
        'func': on_upgrade_1_pressed
    },
    2: {
        "label": "+50 Max Speed\n$1500",
        'cost': 1500,
        'func': on_upgrade_2_pressed
    },
    3: {
        "label": "Upgrade Max Fuel",
        'cost': 2000,
        'func': on_upgrade_3_pressed
    },
}

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

    ui.upgrade_1_btn.pressed.connect(upgrade_button_metadata[1]['func'])
    ui.upgrade_2_btn.pressed.connect(upgrade_button_metadata[2]['func'])
    ui.upgrade_3_btn.pressed.connect(upgrade_button_metadata[3]['func'])
    ui.upgrade_1_btn.text = upgrade_button_metadata[1]["label"]
    ui.upgrade_2_btn.text = upgrade_button_metadata[2]["label"]
    # TODO: this for the other 2
    ui.upgrade_3_btn.text = upgrade_button_metadata[3]["label"] + "\n$" + str(upgrade_button_metadata[3]["cost"])


#region upgrade btn
## speed boost count upgrade
func on_upgrade_1_pressed():
    if SignalBus.upgrade_stats.speed_boost_level < UpgradeStatsRes.Level.MAX:
        if SignalBus.upgrade_stats.money < upgrade_button_metadata[1]["cost"]:
            print("you're too poor")
            return
        SignalBus.upgrade_stats.money -= upgrade_button_metadata[1]["cost"]
        ui.set_money_label_text(SignalBus.upgrade_stats.money)
        
        # += doesn't cast properly, according to the linter B)
        var new_val = SignalBus.upgrade_stats.speed_boost_level + 1
        SignalBus.upgrade_stats.speed_boost_level = new_val as UpgradeStatsRes.Level

        ui.set_speed_boost_upgrade_label_text(SignalBus.upgrade_stats.speed_boost_level)
        
    if SignalBus.upgrade_stats.speed_boost_level >= UpgradeStatsRes.Level.MAX:
        ui.upgrade_1_btn.disabled = true
    
## Max Speed Upgrade
func on_upgrade_2_pressed():
    if SignalBus.upgrade_stats.speed_level < UpgradeStatsRes.Level.MAX:
        if SignalBus.upgrade_stats.money < upgrade_button_metadata[2]["cost"]:
            print("you're too poor")
            return
        SignalBus.upgrade_stats.money -= upgrade_button_metadata[2]["cost"]

        var new_val = SignalBus.upgrade_stats.speed_level + 1
        SignalBus.upgrade_stats.speed_level = new_val as UpgradeStatsRes.Level

        ui.set_max_speed_upgrade_label_text(SignalBus.upgrade_stats.speed_level)

    if SignalBus.upgrade_stats.speed_level >= UpgradeStatsRes.Level.MAX:
        ui.upgrade_2_btn.disabled = true

## Max fuel upgrade
func on_upgrade_3_pressed():
    if SignalBus.upgrade_stats.fuel_level < UpgradeStatsRes.Level.MAX:
        var cost = (SignalBus.upgrade_stats.fuel_level + 1) * upgrade_button_metadata[3]["cost"]

        if SignalBus.upgrade_stats.money < cost:
            print("you're too poor")
            return
        SignalBus.upgrade_stats.money -= cost
                
        var new_val = SignalBus.upgrade_stats.fuel_level + 1
        SignalBus.upgrade_stats.fuel_level = new_val as UpgradeStatsRes.Level
        ui.upgrade_3_btn.text = upgrade_button_metadata[3]["label"] + "\n$" + str(cost)
        print("cost:", cost)

        ui.set_fuel_upgrade_label_text(SignalBus.upgrade_stats.fuel_level)

    if SignalBus.upgrade_stats.fuel_level >= UpgradeStatsRes.Level.MAX:
        ui.upgrade_3_btn.disabled = true
#endregion

#region gameplay
## Spawn Motorcycle, add child, set cam, switch game state, conn finished_run signal
func start_run():
    if Engine.is_editor_hint():
        return
    motorcycle = moto_scene.instantiate()
    motorcycle.position = spawn_pos.position
    add_child(motorcycle)
    motorcycle.camera.make_current()
    motorcycle.run_finished.connect(on_run_finished)
    switch_game_state(GameState.PLAYING)

    if SignalBus.upgrade_stats.runs_played == 0:
        SignalBus.ui.play_tutorial_anim()

## Note: Motorcycle should queue_free() on it's own
func on_run_finished(msg: String, has_crashed: bool, distance: float, bonus_time: float):
    SignalBus.notify_ui.emit(msg, 5) # TODO: move out of GamePanel so it doesn't hide
    switch_game_state(GameState.RUN_OVER)

    if SignalBus.ui.tutorial_anim_player.is_playing():
        SignalBus.ui.tutorial_anim_player.stop()

    # set stats
    if !has_crashed:
        SignalBus.upgrade_stats.max_clean_runs += 1
        if distance > SignalBus.upgrade_stats.max_distance:
            SignalBus.upgrade_stats.max_distance = distance
        if bonus_time > SignalBus.upgrade_stats.max_bonus_time:
            SignalBus.upgrade_stats.max_bonus_time = bonus_time
    else:
        SignalBus.upgrade_stats.max_clean_runs = 0
    
    SignalBus.upgrade_stats.money += (distance * (1 + SignalBus.upgrade_stats.max_clean_runs)) + (bonus_time)
    SignalBus.upgrade_stats.runs_played += 1

    reset_stats()

func reset_stats():
    ui.set_max_distance_label_text(SignalBus.upgrade_stats.max_distance)
    ui.set_max_clean_runs_label_text(SignalBus.upgrade_stats.max_clean_runs)
    ui.set_money_label_text(SignalBus.upgrade_stats.money)
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
