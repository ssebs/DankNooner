extends GutTest
## Event payout formula: RunnerGameMode.place_payout / level_payout. Shape only — the numbers are
## tuned in test_economy_pacing.gd. See planning_docs/Economy.md.

const BASE := 200
const RATE := 0.1


func test_places_pay_less_down_the_podium():
	var first := RunnerGameMode.place_payout(BASE, RATE, 0, 0.0, false)
	var second := RunnerGameMode.place_payout(BASE, RATE, 1, 0.0, false)
	var third := RunnerGameMode.place_payout(BASE, RATE, 2, 0.0, false)
	assert_eq(first, BASE)
	assert_gt(first, second)
	assert_gt(second, third)


func test_everyone_below_the_podium_gets_the_floor():
	var podium := UtilsConstants.PAYOUT_PLACE_MULTS.size()
	var floor_pay := int(BASE * UtilsConstants.PAYOUT_PLACE_FLOOR)
	for place in range(podium, podium + 5):
		assert_eq(RunnerGameMode.place_payout(BASE, RATE, place, 0.0, false), floor_pay)


func test_zero_score_gets_the_floor_in_score_modes():
	var floor_pay := int(BASE * UtilsConstants.PAYOUT_PLACE_FLOOR)
	assert_eq(RunnerGameMode.place_payout(BASE, RATE, 0, 0.0, true), floor_pay)


func test_score_adds_on_top_at_its_rate():
	var low := RunnerGameMode.place_payout(BASE, RATE, 0, 1000.0, true)
	var high := RunnerGameMode.place_payout(BASE, RATE, 0, 2000.0, true)
	assert_eq(high - low, int(1000.0 * RATE))


func test_level_one_is_unscaled():
	assert_eq(RunnerGameMode.level_payout(BASE, 1), BASE)


func test_each_level_pays_more():
	for level in range(1, 30):
		assert_gt(RunnerGameMode.level_payout(BASE, level + 1), RunnerGameMode.level_payout(BASE, level))


func test_crash_launch_score_is_scaled_down():
	assert_lt(CrashLaunchGameMode.PAYOUT_SCORE_SCALE, 1.0)
