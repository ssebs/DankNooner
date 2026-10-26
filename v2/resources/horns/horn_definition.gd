@tool
## A loadout's horn: which AudioManager sound plays while the horn button is held.
class_name HornDefinition extends Resource

## Garage label, and what SkinScanner keys it by.
@export var skin_name: String = "replace_me"
@export var sfx: AudioManager.Sfx = AudioManager.Sfx.CAR_HORN
## Garage cost; 0 = owned by default.
@export var price: int = 1000
## Unavailable in the Steam demo build
@export var demo_locked: bool = false

const SKINS_DIR := "res://resources/horns/skins/"
const DEFAULT_PATH := SKINS_DIR + "car_horn.tres"
