@tool
## The event's RaceChallenges (definition.race_challenges): ticked from synced rider state, fed
## TrickManager's combo bank/void events, one leaderboard column each. Frozen at the finish line.
## Race bots take them too, off the same trick_controller / is_crashed a player exposes.
class_name ChallengesComponent extends RaceComponent

@export var trick_manager: TrickManager

var _challenges: Array[RaceChallenge] = []
var _finished: Dictionary[int, bool] = {}


func race_start() -> void:
	_challenges = race_mode.get_definition().race_challenges
	_finished.clear()
	var bonus := PackedInt32Array()
	var rider_ids := _riders().keys()
	for challenge in _challenges:
		challenge.reset(rider_ids)
		bonus.append_array(challenge.bonus_tricks())
	for rider_id in rider_ids:
		trick_manager.set_bonus_tricks(rider_id, bonus)
	trick_manager.combo_banked.connect(_on_combo_banked)
	trick_manager.combo_voided.connect(_on_combo_voided)


func race_end() -> void:
	# Bots despawned already (NPCRacersComponent ends first), taking their bonus tricks with them
	for peer_id in race_mode.lobby_manager.lobby_players:
		trick_manager.set_bonus_tricks(peer_id, PackedInt32Array())
	trick_manager.combo_banked.disconnect(_on_combo_banked)
	trick_manager.combo_voided.disconnect(_on_combo_voided)


func tick(delta: float) -> void:
	var riders := _riders()
	for rider_id in riders:
		# Finished riders don't tick — skip is intentional.
		if _finished.has(rider_id):
			continue
		for challenge in _challenges:
			challenge.tick(rider_id, riders[rider_id], delta)


func racer_finished(peer_id: int) -> void:
	_finished[peer_id] = true


func column_headers() -> PackedStringArray:
	var headers := PackedStringArray()
	for challenge in _titled():
		headers.append("%s %s" % [challenge.icon, tr(challenge.title_key)])
	return headers


func column_cells(peer_id: int) -> PackedStringArray:
	var cells := PackedStringArray()
	for challenge in _titled():
		cells.append(challenge.format_value(challenge.get_best(peer_id)))
	return cells


## Tricks the riding HUD explains while these challenges run.
func hint_tricks() -> PackedInt32Array:
	var tricks := PackedInt32Array()
	for challenge in _challenges:
		tricks.append_array(challenge.hint_tricks())
	return tricks


## Challenges with a leaderboard column.
func _titled() -> Array[RaceChallenge]:
	var out: Array[RaceChallenge] = []
	out.assign(_challenges.filter(func(c): return c.title_key != ""))
	return out


## rider id -> PlayerEntity or race bot, for every spawned racer.
func _riders() -> Dictionary[int, Node3D]:
	var riders: Dictionary[int, Node3D] = {}
	for peer_id in race_mode.lobby_manager.lobby_players:
		# Unspawned (late-join) players don't ride yet — skip is intentional.
		var player := race_mode.spawn_manager.get_player_by_peer_id(peer_id)
		if player != null:
			riders[peer_id] = player
	if race_mode.npc_racers != null:
		for npc in race_mode.npc_racers.get_npcs():
			riders[int(npc.name)] = npc
	return riders


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
