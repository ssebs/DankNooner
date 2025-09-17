class_name UpgradeStatsRes extends Resource

enum Level {LOW, MEDIUM, HIGH}

@export var fuel_level: Level = Level.LOW
@export var speed_level: Level = Level.LOW
@export var armor_level: Level = Level.LOW
@export var unlocked_tricks: Dictionary = {
    "BACKFLIP": false,
    "FRONTFLIP": false,
    "BUNNY_HOP": false,
    "NOLLIE_LAZERFLIP": false,
}

@export var max_distance: float = 0.0
@export var max_bonus_time: float = 0.0
@export var max_clean_runs: int = 0
