class_name UtilsConstants extends Node

const PORT = 42068

const DISCORD_URL = "https://discord.gg/HCe4XcCFw3"
const STEAM_STORE_URL = "https://store.steampowered.com/app/5416370/Dank_Nooner/"
## export.sh swaps this into project.godot for demo builds
const STEAM_DEMO_APP_ID = 5431410
const STEAM_FULL_APP_ID = 5416370

## Godot Group names.
const GROUPS = {
	"Managers": "Managers",
	"Validate": "Validate",
	"InputStateManager": "InputStateManager",
	"EventCircles": "EventCircles",
	## Level clutter you can hide in the editor; LevelDefinition re-shows it at runtime.
	"EditorHideable": "EditorHideable",
	"FreeRoamActivities": "FreeRoamActivities",
	"GasStations": "GasStations",
	"Racers": "Racers",
	"LocalPlayer": "LocalPlayer",
	## Ambient free-roam traffic. A subset of Racers (they still queue behind each other
	## and crash into things), tagged so HUD/scoring can tell them from actual competitors.
	"Traffic": "Traffic",
}

## Navigation layers (bitmasks, not physics layers) of each level's NPCNavRegions.
const NAV_LAYER_ROAD: int = 1
const NAV_LAYER_GRASS: int = 2

## Seconds a crashed player stays down (ragdolled) before respawning.
const CRASH_RESPAWN_DELAY: float = 5.0

## Remappable actions, keyed by category localization key. A category is the context its actions
## are active in, so duplicate binds only conflict within one.
const CONTROL_CATEGORIES: Dictionary = {
	"CONTROLS_CATEGORY_RIDING":
	[
		"throttle_pct",
		"brake_front_pct",
		"brake_rear",
		"steer_left",
		"steer_right",
		"lean_forward",
		"lean_back",
		"clutch",
		"gear_up",
		"gear_down",
		"trick",
		"boost",
		"use_item",
		"horn",
		"respawn",
		"cam_left",
		"cam_right",
		"cam_up",
		"cam_down",
		"switch_cam",
		"reset_cam",
		"open_map",
		"pause",
	],
	"CONTROLS_CATEGORY_MINIGAME": ["fuel_fill"],
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

## UI palette, shared by code and theme: scripts/gen_neon_theme.py reads every `UI_*` Color
## here, so keep each on one line as `const UI_X: Color = Color(r, g, b)`.
## UI chrome, menus and HUD — the world's neon edge blue (neon_edges.gdshader edge_color).
const UI_BLUE: Color = Color(0.255, 0.686, 1.0)
## Combo tier 1, bonus tricks.
const UI_ICE: Color = Color(0.65, 0.9, 1.0)
## Banked but not yet spendable (a boost gauge under one segment).
const UI_BLUE_DIM: Color = Color(0.16, 0.34, 0.48)
## Empty bar segments.
const UI_TRACK: Color = Color(0.22, 0.26, 0.3)
## Rewards: XP, combo tier 2.
const UI_GOLD: Color = Color(1.0, 0.82, 0.25)
## Money — the aurora's green.
const UI_GREEN: Color = Color(0.2, 1.0, 0.55)
## Danger: bail, redline, combo tier 3.
const UI_RED: Color = Color(1.0, 0.24, 0.24)
## Panel fills, darkest first; UI_GLASS also outlines HUD text.
const UI_GLASS: Color = Color(0.02, 0.027, 0.06)
const UI_SKY: Color = Color(0.02, 0.04, 0.12)

## Set from MainGame.debug_demo_mode
static var debug_demo_mode := false


static func is_demo_build() -> bool:
	return (
		debug_demo_mode
		or ProjectSettings.get_setting("steam/initialization/app_data/app_id") == STEAM_DEMO_APP_ID
	)
