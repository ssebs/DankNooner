extends GutTest
## Bike challenge and reward data rules (planning_docs/Progression.md#bike-challenges-and-mastery).
## Checks the shape of the lists, not their content, so tuning targets or swapping rewards passes.
## bike_types and daily_pool are read from main_game.tscn's SaveManager, like the game does.

const MAIN_GAME := preload("res://main_game.tscn")
const SAVE_MANAGER_PATH := "./ManagerManager/SaveManager"
const MODS_DIR := "res://resources/bikes/mods/"
const BIKE_SKINS_DIR := "res://resources/bikes/skins/"
const EN := preload("res://localization/localization.en.translation")


func test_every_bike_type_has_the_same_number_of_challenges():
	var types := _bike_types()
	for bike_type in types:
		assert_eq(bike_type.challenges.size(), types[0].challenges.size(), tr(bike_type.name_key))


## The last challenge's card shows the type's mastery mod instead (saves_menu_state.gd).
func test_every_challenge_but_the_last_rewards_a_texture():
	for bike_type in _bike_types():
		var last := bike_type.challenges.size() - 1
		for i in bike_type.challenges.size():
			var challenge := bike_type.challenges[i]
			if i == last:
				assert_null(challenge.reward_mod, challenge.resource_path)
			else:
				assert_is(challenge.reward_mod, TextureMod, challenge.resource_path)
		assert_is(bike_type.mastery_mod, AttachmentMod, tr(bike_type.name_key))


func test_no_reward_is_given_twice():
	var seen := {}
	for mod in _rewards():
		assert_false(seen.has(mod.resource_path), "%s is rewarded twice" % mod.resource_path)
		seen[mod.resource_path] = true


## Nothing is free: a texture on disk that no challenge unlocks can never be bought.
func test_every_texture_is_a_reward():
	var rewarded := _rewards().map(func(mod: BikeMod): return mod.resource_path)
	for file in DirAccess.get_files_at(MODS_DIR):
		if !file.ends_with("_mod.tres"):
			continue
		var mod: BikeMod = load(MODS_DIR + file)
		if mod is TextureMod:
			assert_has(rewarded, mod.resource_path, "%s is not any challenge's reward" % file)


## SaveManager.mod_rewards only goes one level deep.
func test_variants_have_no_variants_of_their_own():
	for bike_type in _bike_types():
		for challenge in bike_type.challenges:
			if challenge.reward_mod == null:
				continue
			for variant in challenge.reward_mod.variants:
				assert_eq(variant.variants.size(), 0, variant.resource_path)


func test_every_challenge_title_is_localized():
	var challenges: Array[ChallengeDefinition] = _daily_pool()
	for bike_type in _bike_types():
		challenges.append_array(bike_type.challenges)
	for challenge in challenges:
		assert_ne(EN.get_message(challenge.title_key), &"", challenge.resource_path)


func test_mastery_gates_fit_their_list():
	var sizes := {}
	for bike_type in _bike_types():
		sizes[bike_type] = bike_type.challenges.size()
	for file in DirAccess.get_files_at(BIKE_SKINS_DIR):
		if !file.ends_with(".tres"):
			continue
		var skin: BikeSkinDefinition = load(BIKE_SKINS_DIR + file)
		assert_lte(skin.unlock_mastery, sizes[skin.bike_type], file)


func test_last_challenge_opens_once_the_rest_are_done():
	var bike_type: BikeTypeDefinition = _bike_types()[0]
	var last: ChallengeDefinition = bike_type.challenges.back()
	var progress := {}
	var save_dict := {"progression": {"challenges": progress}}
	assert_false(last in SaveManager.open_challenges(bike_type, save_dict))
	for challenge in bike_type.challenges.slice(0, -1):
		progress[challenge.resource_path] = challenge.target
	assert_true(last in SaveManager.open_challenges(bike_type, save_dict))


func test_count_goal_only_counts_samples_at_its_min():
	var challenge := ChallengeDefinition.new()
	challenge.goal = ChallengeDefinition.Goal.COUNT
	challenge.min_value = 3.0
	assert_eq(challenge.apply(0.0, 2.9), 0.0)
	assert_eq(challenge.apply(0.0, 3.0), 1.0)


func test_total_goal_sums_samples():
	var challenge := ChallengeDefinition.new()
	challenge.goal = ChallengeDefinition.Goal.TOTAL
	assert_eq(challenge.apply(1.5, 2.0), 3.5)


func test_best_goal_keeps_the_largest_sample():
	var challenge := ChallengeDefinition.new()
	challenge.goal = ChallengeDefinition.Goal.BEST
	assert_eq(challenge.apply(5.0, 2.0), 5.0)
	assert_eq(challenge.apply(5.0, 7.0), 7.0)


#region helpers
## Every mod a challenge unlocks, variants included (SaveManager.mod_rewards without the save).
func _rewards() -> Array[BikeMod]:
	var mods: Array[BikeMod] = []
	for bike_type in _bike_types():
		for challenge in bike_type.challenges:
			if challenge.reward_mod != null:
				mods.append(challenge.reward_mod)
				mods.append_array(challenge.reward_mod.variants)
	return mods


func _bike_types() -> Array[BikeTypeDefinition]:
	return _save_manager_export(&"bike_types")


func _daily_pool() -> Array[ChallengeDefinition]:
	return _save_manager_export(&"daily_pool").duplicate()


## Read from the scene file, not an instance — instancing the whole game leaks nodes.
func _save_manager_export(property: StringName) -> Variant:
	var state := MAIN_GAME.get_state()
	for node in state.get_node_count():
		if str(state.get_node_path(node)) != SAVE_MANAGER_PATH:
			continue
		for prop in state.get_node_property_count(node):
			if state.get_node_property_name(node, prop) == property:
				return state.get_node_property_value(node, prop)
	assert(false, "SaveManager sets no %s in main_game.tscn" % property)
	return null

#endregion
