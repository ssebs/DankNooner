@tool
## Banked trick score from TrickManager, frozen at the finish line.
class_name StyleScoringComponent extends RaceComponent

@export var trick_manager: TrickManager

## peer_id -> score when they finished, open combo included — tricks after the line don't count.
var _finish_scores: Dictionary[int, float] = {}


func race_start() -> void:
	_finish_scores.clear()
	for peer_id in race_mode.lobby_manager.lobby_players:
		trick_manager.reset_peer(peer_id)


func racer_finished(peer_id: int) -> void:
	_finish_scores[peer_id] = (
		trick_manager.get_score(peer_id) + trick_manager.get_open_combo_points(peer_id)
	)


func score(peer_id: int) -> float:
	if _finish_scores.has(peer_id):
		return _finish_scores[peer_id]
	return trick_manager.get_score(peer_id)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if trick_manager == null:
		issues.append("trick_manager must not be empty")
	return issues
