## Upgrades + Stats
class_name UpgradeStatsRes extends Resource

# TODO: implement save and load
enum Level {LOW = 1, MEDIUM, HIGH}

# Upgrades
@export var fuel_level: Level = Level.LOW
@export var speed_level: Level = Level.LOW
@export var speed_boost_level: Level = Level.LOW
# @export var armor_level: Level = Level.LOW
# @export var unlocked_tricks: Dictionary = {
#     "BACKFLIP": false,
#     "FRONTFLIP": false,
#     "BUNNY_HOP": false,
#     "NOLLIE_LAZERFLIP": false,
# }

# Stats
@export var max_distance: float = 0.0
@export var max_bonus_time: float = 0.0 # aka dank time
@export var max_clean_runs: int = 0
@export var runs_played: int = 0
@export var money: float = 0.0

# Settings
@export var volume: float = 0.2:
    set(val):
        volume = val
        volume_updated.emit(val)
signal volume_updated(volume: float)

