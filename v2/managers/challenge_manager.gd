@tool
## Bike challenges (Progression.md#challenges), on each rider's own client: every
## StatsManager.stat_recorded sample advances the matching challenges in the active bike type's
## list, and a finished one pays through SaveManager.earn.
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


#region handlers
func _on_stat_recorded(key: String, value: float):
	var bike_type := save_manager.get_player_definition().bike_skin.bike_type
	for challenge in bike_type.challenges:
		if challenge.stat != key:
			continue
		if !challenge.modes.is_empty() and gamemode_manager.current_game_mode not in challenge.modes:
			continue
		var progress := save_manager.get_challenge_progress(challenge)
		# Finished challenges stop counting — skip is intentional
		if progress >= challenge.target:
			continue
		progress = challenge.apply(progress, value)
		save_manager.set_challenge_progress(challenge, progress)
		if progress >= challenge.target:
			_complete(challenge)
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
