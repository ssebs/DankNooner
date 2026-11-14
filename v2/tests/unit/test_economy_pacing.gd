extends GutTest
## Economy balance sim. Rider PROFILES play the demo's events through the game's own payout, combo
## and level code, then shop for bikes from a new save. test_print_balance_table prints the numbers
## to rebalance from; the rest assert the Pacing targets in planning_docs/Economy.md. Scoring
## tunables are read from main_game.tscn and event payouts from stunt_city.tscn, so scene
## overrides count.

const MAIN_GAME := preload("res://main_game.tscn")
const LEVEL := preload("res://levels/racetracks/stunt_city/stunt_city.tscn")
const DEFAULT_PLAYER := preload("res://resources/player/default_player_definition.tres")
const MODES_PATH := "ManagerManager/GamemodeManager/StateMachine/"
const T := TrickController.Trick
const BIKES := {
	"naked": "res://resources/bikes/skins/naked_default_skin_definition.tres",
	"sport": "res://resources/bikes/skins/sport_default_skin_definition.tres",
}

## The demo's events, in the order a grinder plays them (Economy.md: Demo scope).
const ROTATION: Array[String] = [
	"stunt_race", "track_race", "trick_battle", "stunt_race", "crash_launch"
]
## Each mode's kind, and minutes per event including ~10s riding to the next. Measured from the
## [economy] logs (RunnerGameMode) on 2026-11-13; track race wasn't played, so it's a guess.
const MODES := {
	"stunt_race": {"kind": GameModeType.Kind.STUNT_RACE, "minutes": 1.3},
	"track_race": {"kind": GameModeType.Kind.RACE, "minutes": 1.25},
	"trick_battle": {"kind": GameModeType.Kind.TRICK_BATTLE, "minutes": 1.25},
	"crash_launch": {"kind": GameModeType.Kind.CRASH_LAUNCH, "minutes": 0.75},
}
const TICK_HZ := 60.0
const MAX_EVENTS := 500

const BEGINNER_WHEELIE := [{"trick": T.WHEELIE_SITTING, "secs": 3.0, "mult": TrickController.WHEELIE_MIN_SCORE_MULT}]
const REGULAR_CHAIN := [
	{"trick": T.WHEELIE_SITTING, "secs": 4.0, "mult": 1.0},
	{"trick": T.STOPPIE, "secs": 1.5, "mult": 1.0},
]
const PRO_CHAIN := [
	{"trick": T.WHEELIE_SITTING, "secs": 6.0, "mult": TrickController.WHEELIE_BP_SCORE_MULT},
	{"trick": T.KICKFLIP},
	{"trick": T.WHEELIE_SITTING, "secs": 6.0, "mult": TrickController.WHEELIE_BP_SCORE_MULT},
	{"trick": T.STOPPIE, "secs": 4.0, "mult": 1.0},
]

## What a rider does in one event of each mode. A combo is a chain of steps: held tricks ("secs",
## "mult" = wheelie score mult) or one-time tricks. "place" is 0 = 1st, in every mode.
## "regular" is calibrated to real results screens (stunt race ~770, trick battle ~425, crash
## launch ~4,500). Edit these to rebalance.
const PROFILES := {
	"beginner": {
		"place": 2,
		"knockouts": 0,
		"race_combos": [BEGINNER_WHEELIE, BEGINNER_WHEELIE, BEGINNER_WHEELIE, [{"trick": T.BUNNY_HOP}]],
		"battle_combos": [
			BEGINNER_WHEELIE, BEGINNER_WHEELIE, BEGINNER_WHEELIE, BEGINNER_WHEELIE,
			[{"trick": T.BUNNY_HOP}], [{"trick": T.BUNNY_HOP}],
		],
		"launch_meters": [50.0, 60.0, 40.0],
	},
	"regular": {
		"place": 0,
		"knockouts": 0,
		"race_combos": [REGULAR_CHAIN, REGULAR_CHAIN, REGULAR_CHAIN, REGULAR_CHAIN, [{"trick": T.KICKFLIP}]],
		"battle_combos": [REGULAR_CHAIN, REGULAR_CHAIN, REGULAR_CHAIN, REGULAR_CHAIN],
		"launch_meters": [120.0, 110.0, 100.0],
	},
	"pro": {
		"place": 0,
		"knockouts": 3,
		"race_combos": [PRO_CHAIN, PRO_CHAIN, PRO_CHAIN],
		"battle_combos": [PRO_CHAIN, PRO_CHAIN, PRO_CHAIN],
		"launch_meters": [180.0, 170.0, 175.0],
	},
}

## GameModeType.Kind -> the level's first event definition of that kind.
var _event_defs: Dictionary[GameModeType.Kind, GameModeEventDefinition] = {}


## The duck-typed combo + boost state ComboRules ticks (TrickController / NPCTrickController).
class ComboState:
	var combo_time := 0.0
	var combo_grace := 0.0
	var combo_score := 0.0
	var combo_multiplier := 1
	var combo_boost_earned := 0.0
	var boost_amount := 0.0
	var boost_burn_target := -1.0
	var boost_burn_rate := 0.0


func before_all():
	var state := LEVEL.get_state()
	for node in state.get_node_count():
		for prop in state.get_node_property_count(node):
			var def = state.get_node_property_value(node, prop)
			if state.get_node_property_name(node, prop) == &"definition" and def is GameModeEventDefinition:
				if !_event_defs.has(def.target_gamemode):
					_event_defs[def.target_gamemode] = def


#region tests


func test_print_balance_table():
	var lines := PackedStringArray(["", "Level 1 payouts: $ / XP [score] $ per minute"])
	for profile_name in PROFILES:
		var cells := PackedStringArray()
		for mode in ["stunt_race", "trick_battle", "crash_launch", "track_race"]:
			var pay := _event_payout(PROFILES[profile_name], mode, 1)
			var score := _score(PROFILES[profile_name], mode)
			cells.append("%s $%d/%d [%d] $%d/min" % [mode, pay.x, pay.y, score, _per_minute(pay.x, mode)])
		lines.append("  %-8s %s" % [profile_name, " | ".join(cells)])
	lines.append("Minutes (events) until bought, from a new save:")
	for profile_name in PROFILES:
		var via_naked := _simulate(PROFILES[profile_name], ["naked", "sport"])
		var direct := _simulate(PROFILES[profile_name], ["sport"])
		lines.append(
			(
				"  %-8s naked %s, sport via naked %s, sport direct %s, level %d after 30 min"
				% [
					profile_name,
					_bought_text(via_naked.get("naked")),
					_bought_text(via_naked.get("sport")),
					_bought_text(direct.get("sport")),
					_level_after_minutes(PROFILES[profile_name], 30.0),
				]
			)
		)
	gut.p("\n".join(lines))
	pass_test("table printed")


func test_starting_money_buys_no_gated_bike():
	for bike in BIKES:
		assert_lt(DEFAULT_PLAYER.money, float(_bike(bike).price), bike)


func test_stunt_race_pays_most_and_crash_launch_least_per_minute():
	for profile_name in PROFILES:
		var profile: Dictionary = PROFILES[profile_name].duplicate()
		profile["place"] = 0
		var stunt_race := _per_minute(_event_payout(profile, "stunt_race", 1).x, "stunt_race")
		var trick_battle := _per_minute(_event_payout(profile, "trick_battle", 1).x, "trick_battle")
		var crash_launch := _per_minute(_event_payout(profile, "crash_launch", 1).x, "crash_launch")
		assert_gt(stunt_race, trick_battle, profile_name)
		assert_gt(trick_battle, crash_launch, profile_name)


func test_modes_pay_about_the_same_per_minute_for_a_regular():
	var stunt_race := _per_minute(_event_payout(PROFILES["regular"], "stunt_race", 1).x, "stunt_race")
	for mode in ["trick_battle", "crash_launch", "track_race"]:
		assert_gt(_per_minute(_event_payout(PROFILES["regular"], mode, 1).x, mode), stunt_race * 0.6, mode)


func test_naked_is_a_short_save_up():
	assert_lt(_simulate(PROFILES["regular"], ["naked"])["naked"].y, 12.0)


func test_grinder_gets_sport_in_about_30_minutes():
	assert_between(_simulate(PROFILES["regular"], ["naked", "sport"])["sport"].y, 20.0, 40.0)


func test_levels_never_slow_to_a_crawl():
	var events_at_level := {}
	var rider := PlayerDefinition.new()
	for event in MAX_EVENTS:
		var level := rider.level()
		events_at_level[level] = events_at_level.get(level, 0) + 1
		rider.xp += _event_payout(PROFILES["regular"], ROTATION[event % ROTATION.size()], level).y
	for level in range(1, rider.level()):
		assert_lt(events_at_level[level], 10, "level %d" % level)


#endregion

#region sim


## Money (x) and XP (y) one event pays at `level`, through the game's payout code.
func _event_payout(profile: Dictionary, mode: String, level: int) -> Vector2i:
	var score := _score(profile, mode)
	if mode == "crash_launch":
		score *= CrashLaunchGameMode.PAYOUT_SCORE_SCALE
	var is_score_mode := mode != "track_race"
	var place: int = profile["place"]
	var money_rate := UtilsConstants.PAYOUT_SCORE_MONEY_RATE
	var xp_rate := UtilsConstants.PAYOUT_SCORE_XP_RATE
	var def := _event_defs[MODES[mode]["kind"]]
	var money := RunnerGameMode.place_payout(def.payout_money, money_rate, place, score, is_score_mode)
	var xp := RunnerGameMode.place_payout(def.payout_xp, xp_rate, place, score, is_score_mode)
	return Vector2i(RunnerGameMode.level_payout(money, level), RunnerGameMode.level_payout(xp, level))


## The mode's results-screen score, from its scoring nodes in main_game.tscn.
func _score(profile: Dictionary, mode: String) -> float:
	var place: int = profile["place"]
	match mode:
		"stunt_race":
			var finish_points: PackedInt32Array = _tunable(MODES_PATH + "StuntRaceGameMode/FinishBonus", "placement_points")
			var knockout_points: int = _tunable(MODES_PATH + "StuntRaceGameMode/KnockoutScoring", "points_per_knockout")
			return (
				(finish_points[place] if place < finish_points.size() else 0)
				+ profile["knockouts"] * knockout_points
				+ _combos_points(profile["race_combos"])
			)
		"trick_battle":
			return _combos_points(profile["battle_combos"])
		"crash_launch":
			var heat_points: PackedInt32Array = _tunable(MODES_PATH + "CrashLaunchGameMode", "placement_points")
			var points_per_meter: float = _tunable(MODES_PATH + "CrashLaunchGameMode", "points_per_meter")
			var total := 0.0
			for meters in profile["launch_meters"]:
				total += meters * points_per_meter
				total += heat_points[place] if place < heat_points.size() else 0
			return total + (_tunable(MODES_PATH + "CrashLaunchGameMode", "longest_launch_bonus") if place == 0 else 0)
		"track_race":
			return 0.0
	assert(false, "unknown mode %s" % mode)
	return 0.0


## Points the combos bank, each run through ComboRules at TICK_HZ and banked like TrickManager:
## combo_score × points_per_second × the combo's peak multiplier.
func _combos_points(combos: Array) -> float:
	var points_per_second: float = _tunable("ManagerManager/TrickManager", "points_per_second")
	var total := 0.0
	for combo in combos:
		var state := ComboState.new()
		var peak := 1
		for step in combo:
			if !step.has("secs"):
				ComboRules.start_trick(state, state, step["trick"], true)
				continue
			for tick in int(step["secs"] * TICK_HZ):
				ComboRules.accrue(state, state, step["trick"], step["mult"], 1.0 / TICK_HZ)
				peak = maxi(peak, state.combo_multiplier)
		total += state.combo_score * points_per_second * peak
	return total


## Plays ROTATION from a new save, buying each bike in `shopping` in order as soon as it's unlocked
## and affordable. Returns bike -> Vector2(events, minutes) when bought; missing if never.
func _simulate(profile: Dictionary, shopping: Array) -> Dictionary:
	var rider := PlayerDefinition.new()
	rider.money = DEFAULT_PLAYER.money
	var bought := {}
	var minutes := 0.0
	for event in MAX_EVENTS:
		var mode := ROTATION[event % ROTATION.size()]
		var pay := _event_payout(profile, mode, rider.level())
		rider.money += pay.x
		rider.xp += pay.y
		minutes += MODES[mode]["minutes"]
		while bought.size() < shopping.size():
			var bike := _bike(shopping[bought.size()])
			if rider.level() < bike.unlock_level or rider.money < bike.price:
				break
			rider.money -= bike.price
			bought[shopping[bought.size()]] = Vector2(event + 1, minutes)
		if bought.size() == shopping.size():
			break
	return bought


func _level_after_minutes(profile: Dictionary, minutes: float) -> int:
	var rider := PlayerDefinition.new()
	var event := 0
	while minutes > 0.0:
		var mode := ROTATION[event % ROTATION.size()]
		rider.xp += _event_payout(profile, mode, rider.level()).y
		minutes -= MODES[mode]["minutes"]
		event += 1
	return rider.level()


func _per_minute(amount: int, mode: String) -> float:
	return amount / MODES[mode]["minutes"]


## `bought` is a _simulate entry, null if never bought.
func _bought_text(bought) -> String:
	return "never" if bought == null else "%.0f min (%d)" % [bought.y, bought.x]


## An export as main_game.tscn sets it on the node at `path`, else its script default. Read from
## the scene file, not an instance — instancing the whole game leaks nodes.
func _tunable(path: String, property: String) -> Variant:
	var state := MAIN_GAME.get_state()
	for node in state.get_node_count():
		if str(state.get_node_path(node)) != "./" + path:
			continue
		var script: Script
		for prop in state.get_node_property_count(node):
			var prop_name := state.get_node_property_name(node, prop)
			if prop_name == property:
				return state.get_node_property_value(node, prop)
			if prop_name == &"script":
				script = state.get_node_property_value(node, prop)
		return script.get_property_default_value(property)
	assert(false, "no node %s in main_game.tscn" % path)
	return null


func _bike(bike: String) -> BikeSkinDefinition:
	return load(BIKES[bike])

#endregion
