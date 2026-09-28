@tool
## The event's RaceChallenges (definition.race_challenges): ticked from synced player state, fed
## TrickManager's combo bank/void events, one leaderboard column each. Frozen at the finish line.
class_name ChallengesComponent extends RaceComponent

@export var trick_manager: TrickManager

var _challenges: Array[RaceChallenge] = []
var _finished: Dictionary[int, bool] = {}


func race_start() -> void:
	_challenges = race_mode.get_definition().race_challenges
	_finished.clear()
	for challenge in _challenges:
		challenge.reset(race_mode.lobby_manager.lobby_players.keys())
	trick_manager.combo_banked.connect(_on_combo_banked)
	trick_manager.combo_voided.connect(_on_combo_voided)


func race_end() -> void:
	trick_manager.combo_banked.disconnect(_on_combo_banked)
	trick_manager.combo_voided.disconnect(_on_combo_voided)


func tick(delta: float) -> void:
	for peer_id in race_mode.lobby_manager.lobby_players:
		# Unspawned (late-join) and finished riders don't tick — skip is intentional.
		var player := race_mode.spawn_manager._get_player_by_peer_id(peer_id)
		if player == null or _finished.has(peer_id):
			continue
		for challenge in _challenges:
			challenge.tick(peer_id, player, delta)


func racer_finished(peer_id: int) -> void:
	_finished[peer_id] = true


func column_headers() -> PackedStringArray:
	var headers := PackedStringArray()
	for challenge in _challenges:
		headers.append("%s %s" % [challenge.icon, tr(challenge.title_key)])
	return headers


func column_cells(peer_id: int) -> PackedStringArray:
	var cells := PackedStringArray()
	for challenge in _challenges:
		cells.append(challenge.format_value(challenge.get_best(peer_id)))
	return cells


## Tricks the riding HUD explains while these challenges run.
func hint_tricks() -> PackedInt32Array:
	var tricks := PackedInt32Array()
	for challenge in _challenges:
		tricks.append_array(challenge.hint_tricks())
	return tricks


func _on_combo_banked(peer_id: int, points: float, _duration: float, _multiplier: int):
	if _finished.has(peer_id):
		return
	for challenge in _challenges:
		challenge.on_combo_banked(peer_id, points)


func _on_combo_voided(peer_id: int, _lost_duration: float, _lost_points: float):
	if _finished.has(peer_id):
		return
	for challenge in _challenges:
		challenge.on_combo_voided(peer_id)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if trick_manager == null:
		issues.append("trick_manager must not be empty")
	return issues
