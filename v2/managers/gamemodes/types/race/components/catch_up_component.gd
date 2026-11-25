@tool
## Catch-up through tricks: a racer behind the leader fills boost faster from tricks, more the
## further back (ComboRules.catch_up_mult). Never free speed. Crashing while behind also respawns
## with a segment (PlayerEntity._apply_respawn_state). Players only; bots race as tuned.
class_name CatchUpComponent extends RaceComponent

## Seconds between standing checks — places change slowly.
const REFRESH_SECS: float = 0.5

var _refresh_accum: float = 0.0


func tick(delta: float) -> void:
	_refresh_accum -= delta
	if _refresh_accum > 0.0:
		return
	_refresh_accum = REFRESH_SECS
	var race_task := race_mode.race_task
	for peer_id in race_mode.lobby_manager.lobby_players:
		var player := race_mode.spawn_manager.get_player_by_peer_id(peer_id)
		# Late joiner not spawned, or not racing (spectating, already finished) — skip is intentional
		if player == null:
			continue
		var racing := race_task.has_racer(peer_id) and race_task.get_completion_time_ms(peer_id) < 0.0
		var behind := race_task.get_race_position(peer_id) - 1 if racing else 0
		player.catch_up_target = ComboRules.catch_up_mult(behind)


func race_end() -> void:
	for peer_id in race_mode.lobby_manager.lobby_players:
		# Despawned with a disconnect — skip is intentional
		var player := race_mode.spawn_manager.get_player_by_peer_id(peer_id)
		if player != null:
			player.catch_up_target = 1.0
