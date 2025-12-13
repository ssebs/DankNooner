@tool
class_name Upgrades extends Control

@onready var quit_btn_upgrade_menu: Button = %QuitBtn2
@onready var retry_btn: Button = %RetryBtn
@onready var main_menu_btn: Button = %MainMenuBtn
@onready var upgrade_1_btn: Button = %Upgrade1Btn
@onready var upgrade_2_btn: Button = %Upgrade2Btn
@onready var upgrade_3_btn: Button = %Upgrade3Btn

@onready var max_bonus_time_label: Label = %MaxBonusTimeLabel
@onready var max_distance_label: Label = %MaxDistanceLabel
@onready var max_clean_runs_label: Label = %MaxCleanRunsLabel
@onready var money_label: Label = %MoneyLabel

@onready var fuel_upgrade_level: Label = %FuelUpgradeLevel
@onready var max_speed_upgrade_level: Label = %MaxSpeedUpgradeLevel
@onready var speed_boost_upgrade_level: Label = %SpeedBoostUpgradeLevel

@onready var camera: Camera3D = %Camera3D

var upgrade_button_metadata: Dictionary = {
    1: {
        "label": "Add a Speed Boost",
        'cost': 600,
        'func': on_upgrade_1_pressed
    },
    2: {
        "label": "Increase Top Speed",
        'cost': 1500,
        'func': on_upgrade_2_pressed
    },
    3: {
        "label": "Upgrade Max Fuel",
        'cost': 2000,
        'func': on_upgrade_3_pressed
    },
}
# TODO: multiply cost by upgrade level, see upgrade 3 btn onclick

func _ready():
    if !Engine.is_editor_hint() and SignalBus.ui == null:
        print("UI is null in upgrades.gd")
        
    my_show()

    set_max_distance_label_text(0)
    set_max_clean_runs_label_text(0)
    set_money_label_text(0)
    set_max_bonus_time_label_text(0)
    set_fuel_upgrade_label_text(UpgradeStatsRes.Level.LOW)
    set_max_speed_upgrade_label_text(UpgradeStatsRes.Level.LOW)
    set_speed_boost_upgrade_label_text(UpgradeStatsRes.Level.LOW)

    upgrade_1_btn.text = upgrade_button_metadata[1]["label"] + "\n$" + str(upgrade_button_metadata[1]['cost'])
    upgrade_1_btn.pressed.connect(upgrade_button_metadata[1]['func'])

    upgrade_2_btn.text = upgrade_button_metadata[2]["label"] + "\n$" + str(upgrade_button_metadata[2]['cost'])
    upgrade_2_btn.pressed.connect(upgrade_button_metadata[2]['func'])

    upgrade_3_btn.text = upgrade_button_metadata[3]["label"] + "\n$" + str(upgrade_button_metadata[3]["cost"])
    upgrade_3_btn.pressed.connect(upgrade_button_metadata[3]['func'])


func my_show():
    camera.make_current()
    self.visible = true

func my_hide():
    camera.clear_current()
    self.visible = false

#region upgrade btn
## speed boost count upgrade
func on_upgrade_1_pressed():
    if SignalBus.upgrade_stats.speed_boost_level < UpgradeStatsRes.Level.MAX:
        if SignalBus.upgrade_stats.money < upgrade_button_metadata[1]["cost"]:
            print("you're too poor")
            return
        SignalBus.upgrade_stats.money -= upgrade_button_metadata[1]["cost"]
        set_money_label_text(SignalBus.upgrade_stats.money)
        
        # += doesn't cast properly, according to the linter B)
        var new_val = SignalBus.upgrade_stats.speed_boost_level + 1
        SignalBus.upgrade_stats.speed_boost_level = new_val as UpgradeStatsRes.Level

        set_speed_boost_upgrade_label_text(SignalBus.upgrade_stats.speed_boost_level)
        
    if SignalBus.upgrade_stats.speed_boost_level >= UpgradeStatsRes.Level.MAX:
        upgrade_1_btn.disabled = true
    
## Max Speed Upgrade
func on_upgrade_2_pressed():
    if SignalBus.upgrade_stats.speed_level < UpgradeStatsRes.Level.MAX:
        if SignalBus.upgrade_stats.money < upgrade_button_metadata[2]["cost"]:
            print("you're too poor")
            return
        SignalBus.upgrade_stats.money -= upgrade_button_metadata[2]["cost"]
        set_money_label_text(SignalBus.upgrade_stats.money)

        var new_val = SignalBus.upgrade_stats.speed_level + 1
        SignalBus.upgrade_stats.speed_level = new_val as UpgradeStatsRes.Level

        set_max_speed_upgrade_label_text(SignalBus.upgrade_stats.speed_level)

    if SignalBus.upgrade_stats.speed_level >= UpgradeStatsRes.Level.MAX:
        upgrade_2_btn.disabled = true

## Max fuel upgrade
func on_upgrade_3_pressed():
    if SignalBus.upgrade_stats.fuel_level < UpgradeStatsRes.Level.MAX:
        var cost = (SignalBus.upgrade_stats.fuel_level + 1) * upgrade_button_metadata[3]["cost"]

        if SignalBus.upgrade_stats.money < cost:
            print("you're too poor")
            return
        SignalBus.upgrade_stats.money -= cost
        set_money_label_text(SignalBus.upgrade_stats.money)
                
        var new_val = SignalBus.upgrade_stats.fuel_level + 1
        SignalBus.upgrade_stats.fuel_level = new_val as UpgradeStatsRes.Level
        upgrade_3_btn.text = upgrade_button_metadata[3]["label"] + "\n$" + str(cost)
        print("cost:", cost)

        set_fuel_upgrade_label_text(SignalBus.upgrade_stats.fuel_level)

    if SignalBus.upgrade_stats.fuel_level >= UpgradeStatsRes.Level.MAX:
        upgrade_3_btn.disabled = true
#endregion


#region label setters
func set_max_bonus_time_label_text(time: float):
    max_bonus_time_label.text = "Most Dank Time: %.2fs" % time

func set_max_distance_label_text(distance: float):
    max_distance_label.text = "Max Distance: %.0fm" % distance

func set_max_clean_runs_label_text(clean_runs: int):
    max_clean_runs_label.text = "Clean Runs: %d" % clean_runs

func set_money_label_text(money: float):
    money_label.text = "Money: $%.2f" % money

func set_fuel_upgrade_label_text(level: UpgradeStatsRes.Level):
    fuel_upgrade_level.text = "Fuel Upgrade Level: %d" % level
func set_max_speed_upgrade_label_text(level: UpgradeStatsRes.Level):
    max_speed_upgrade_level.text = "Max Speed Upgrade Level: %d" % level
func set_speed_boost_upgrade_label_text(level: UpgradeStatsRes.Level):
    speed_boost_upgrade_level.text = "Speed Boost Upgrade Level: %d" % level

#endregion
