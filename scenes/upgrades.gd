class_name Upgrades extends Node

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
# TODO: multiply cost by upgrade level

func _ready():
    if SignalBus.ui == null:
        print("UI is null in upgrades.gd")
        
    SignalBus.ui.upgrade_1_btn.text = upgrade_button_metadata[1]["label"] + "\n$" + str(upgrade_button_metadata[1]['cost'])
    SignalBus.ui.upgrade_1_btn.pressed.connect(upgrade_button_metadata[1]['func'])

    SignalBus.ui.upgrade_2_btn.text = upgrade_button_metadata[2]["label"] + "\n$" + str(upgrade_button_metadata[2]['cost'])
    SignalBus.ui.upgrade_2_btn.pressed.connect(upgrade_button_metadata[2]['func'])

    SignalBus.ui.upgrade_3_btn.text = upgrade_button_metadata[3]["label"] + "\n$" + str(upgrade_button_metadata[3]["cost"])
    SignalBus.ui.upgrade_3_btn.pressed.connect(upgrade_button_metadata[3]['func'])




#region upgrade btn
## speed boost count upgrade
func on_upgrade_1_pressed():
    if SignalBus.upgrade_stats.speed_boost_level < UpgradeStatsRes.Level.MAX:
        if SignalBus.upgrade_stats.money < upgrade_button_metadata[1]["cost"]:
            print("you're too poor")
            return
        SignalBus.upgrade_stats.money -= upgrade_button_metadata[1]["cost"]
        SignalBus.ui.set_money_label_text(SignalBus.upgrade_stats.money)
        
        # += doesn't cast properly, according to the linter B)
        var new_val = SignalBus.upgrade_stats.speed_boost_level + 1
        SignalBus.upgrade_stats.speed_boost_level = new_val as UpgradeStatsRes.Level

        SignalBus.ui.set_speed_boost_upgrade_label_text(SignalBus.upgrade_stats.speed_boost_level)
        
    if SignalBus.upgrade_stats.speed_boost_level >= UpgradeStatsRes.Level.MAX:
        SignalBus.ui.upgrade_1_btn.disabled = true
    
## Max Speed Upgrade
func on_upgrade_2_pressed():
    if SignalBus.upgrade_stats.speed_level < UpgradeStatsRes.Level.MAX:
        if SignalBus.upgrade_stats.money < upgrade_button_metadata[2]["cost"]:
            print("you're too poor")
            return
        SignalBus.upgrade_stats.money -= upgrade_button_metadata[2]["cost"]
        SignalBus.ui.set_money_label_text(SignalBus.upgrade_stats.money)

        var new_val = SignalBus.upgrade_stats.speed_level + 1
        SignalBus.upgrade_stats.speed_level = new_val as UpgradeStatsRes.Level

        SignalBus.ui.set_max_speed_upgrade_label_text(SignalBus.upgrade_stats.speed_level)

    if SignalBus.upgrade_stats.speed_level >= UpgradeStatsRes.Level.MAX:
        SignalBus.ui.upgrade_2_btn.disabled = true

## Max fuel upgrade
func on_upgrade_3_pressed():
    if SignalBus.upgrade_stats.fuel_level < UpgradeStatsRes.Level.MAX:
        var cost = (SignalBus.upgrade_stats.fuel_level + 1) * upgrade_button_metadata[3]["cost"]

        if SignalBus.upgrade_stats.money < cost:
            print("you're too poor")
            return
        SignalBus.upgrade_stats.money -= cost
        SignalBus.ui.set_money_label_text(SignalBus.upgrade_stats.money)
                
        var new_val = SignalBus.upgrade_stats.fuel_level + 1
        SignalBus.upgrade_stats.fuel_level = new_val as UpgradeStatsRes.Level
        SignalBus.ui.upgrade_3_btn.text = upgrade_button_metadata[3]["label"] + "\n$" + str(cost)
        print("cost:", cost)

        SignalBus.ui.set_fuel_upgrade_label_text(SignalBus.upgrade_stats.fuel_level)

    if SignalBus.upgrade_stats.fuel_level >= UpgradeStatsRes.Level.MAX:
        SignalBus.ui.upgrade_3_btn.disabled = true
#endregion
