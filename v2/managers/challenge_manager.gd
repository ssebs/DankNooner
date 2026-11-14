@tool
## Bike challenges and dailies (Progression.md#challenges), on each rider's own client: every
## StatsManager.stat_recorded sample advances the matching challenges in the active bike type's
## list and today's dailies (any bike), and a finished one pays through SaveManager.earn.
class_name ChallengeManager extends BaseManager

@export var save_manager: SaveManager
@export var stats_manager: StatsManager
@export var gamemode_manager: GamemodeManager
@export var riding_hud_state: RidingHUDState
@export var audio_manager: AudioManager


func _ready():
	if Engine.is_editor_hint():
		return

	stats_manager.stat_recorded.connect(_on_stat_recorded)


func _complete(challenge: ChallengeDefinition):
	save_manager.earn(challenge.money, challenge.xp)
	riding_hud_state.pop_earned(challenge.money, challenge.xp)
	riding_hud_state.pop_challenge_done(
		tr("CHALLENGE_COMPLETE").format({"title": challenge.title()})
	)
	audio_manager.play_sfx(AudioManager.Sfx.CONFETTI_HORN)
	if challenge.reward_mod != null:
		_unlock_mod(challenge.reward_mod)


## Callout + thumbnail on the rider's bike; unread in the garage until its row is focused.
func _unlock_mod(mod: BikeMod):
	var unread := save_manager.unread_mods()
	if mod.resource_path not in unread:
		unread.append(mod.resource_path)
	save_manager.save_save()
	var bike: BikeSkinDefinition = save_manager.get_player_definition().bike_skin.duplicate()
	var mods: Array[BikeMod] = [mod]
	bike.mods = mods
	riding_hud_state.pop_unlocked(
		tr("SKIN_UNLOCKED").format({"skin": GarageUI.skin_label(GarageUI.mod_file_name(mod))}), bike
	)


#region handlers
func _on_stat_recorded(key: String, value: float):
	# Riding past midnight rolls the dailies over
	save_manager.refresh_dailies()
	var save := save_manager.current_save
	var bike_type := save_manager.get_player_definition().bike_skin.bike_type
	var bike_progress := SaveManager.bike_challenge_progress(save)
	if _advance(bike_type.challenges, bike_progress, key, value):
		_announce_unlocks(bike_type)
	_advance(SaveManager.daily_challenges(save), SaveManager.daily_progress(save), key, value)


## progress: resource path -> progress, written in place (saved with the next write). True if one
## finished.
func _advance(
	challenges: Array[ChallengeDefinition], progress: Dictionary, key: String, value: float
) -> bool:
	var finished := false
	for challenge in challenges:
		if challenge.stat != key:
			continue
		if !challenge.modes.is_empty() and gamemode_manager.current_game_mode not in challenge.modes:
			continue
		var before: float = progress.get(challenge.resource_path, 0.0)
		# Finished challenges stop counting — skip is intentional
		if before >= challenge.target:
			continue
		var after := challenge.apply(before, value)
		progress[challenge.resource_path] = after
		if after >= challenge.target:
			_complete(challenge)
			finished = true
	return finished


## A callout per skin of bike_type whose unlock_mastery the type just reached, and its mastery mod
## once the list is done.
func _announce_unlocks(bike_type: BikeTypeDefinition):
	var mastery := save_manager.mastery(bike_type)
	for path: String in SkinScanner.scan_skin_dir(GarageUI.BIKE_SKINS_DIR).values():
		var skin: BikeSkinDefinition = load(path)
		if skin.bike_type == bike_type and skin.unlock_mastery == mastery:
			riding_hud_state.pop_challenge_done(
				tr("SKIN_UNLOCKED").format({"skin": GarageUI.skin_label(skin.skin_name)})
			)
	if mastery == bike_type.challenges.size() and bike_type.mastery_mod != null:
		_unlock_mod(bike_type.mastery_mod)
#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if save_manager == null:
		issues.append("save_manager must not be empty")
	if stats_manager == null:
		issues.append("stats_manager must not be empty")
	if gamemode_manager == null:
		issues.append("gamemode_manager must not be empty")
	if riding_hud_state == null:
		issues.append("riding_hud_state must not be empty")
	if audio_manager == null:
		issues.append("audio_manager must not be empty")

	return issues
