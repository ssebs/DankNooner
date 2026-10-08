class_name UtilsConstants extends Node

const PORT = 42068

## Godot Group names.
const GROUPS = {
	"Managers": "Managers",
	"Validate": "Validate",
	"InputStateManager": "InputStateManager",
	"EventCircles": "EventCircles",
	"FreeRoamActivities": "FreeRoamActivities",
	"Racers": "Racers",
	"LocalPlayer": "LocalPlayer",
	## Ambient free-roam traffic. A subset of Racers (they still queue behind each other
	## and crash into things), tagged so HUD/scoring can tell them from actual competitors.
	"Traffic": "Traffic",
}

## Event payouts: event base × place multiplier + score × rate (see Progression.md).
## Multipliers from 1st; everyone below them gets PAYOUT_PLACE_FLOOR.
const PAYOUT_PLACE_MULTS: Array[float] = [1.0, 0.7, 0.5]
const PAYOUT_PLACE_FLOOR: float = 0.3
const PAYOUT_SCORE_MONEY_RATE: float = 0.01
const PAYOUT_SCORE_XP_RATE: float = 0.02
## Time attack: every lap pays this fraction of the event base; a new PB adds the full base.
const PAYOUT_LAP_FRACTION: float = 0.1
## Level = 1 + sqrt(xp / XP_PER_LEVEL), so each level takes longer than the last.
const XP_PER_LEVEL: int = 100

## Swatches in the garage's ColorPicker: the deleted character variants' colors + the bike color mods'.
const SKIN_COLOR_PRESETS: Array[Color] = [
	Color(1, 0, 0, 1),
	Color(0, 0, 1, 1),
	Color(1, 0.41, 0.41, 1),
	Color(0.45, 0.5875, 1, 1),
	Color(0.125, 0.125, 0.125, 1),
	Color(0.17254902, 0.17254902, 0.17254902, 1),
	Color(0.921875, 0.921875, 0.921875, 1),
	Color(0.185, 0.5087501, 0.74, 1),
	Color(0.25490198, 0.6862745, 1, 1),
	Color(0.054901965, 0.7607843, 0.69460785, 1),
	Color(0.53624463, 0.15046692, 0.67578125, 1),
	Color(0.8046875, 0.38034058, 0.69860077, 1),
	Color(0.9254902, 0.44705883, 0.8862745, 1),
	Color(0.92578125, 0.4484253, 0.8847585, 1),
	Color(0.78515625, 0.021469116, 0.021469116, 1),
	Color(0.9140625, 0.101872444, 0.017852783, 1),
]
