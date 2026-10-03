@tool
## Timed trick battle: after the grid + countdown runner, riders trick anywhere for
## `duration_secs`. Every banked combo counts, plus the one still open at the buzzer; the highest
## total wins.
class_name TrickBattleGameMode extends TimedScoreGameMode


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GameModeType.Kind.TRICK_BATTLE
	DebugUtils.DebugMsg("Trick Battle Mode")

	super(state_context)


#override
## Points banked before the battle (free roam) don't count.
func _start_next_runner():
	super()
	if _is_last_runner():
		for peer_id in lobby_manager.lobby_players:
			trick_manager.reset_peer(peer_id)


#override
func _score(peer_id: int) -> float:
	return trick_manager.get_score(peer_id) + trick_manager.get_open_combo_points(peer_id)


#override
func _results_title_key() -> String:
	return "TRICK_BATTLE_COMPLETE"


#override
func _push_leaderboard():
	var rows: Array = []
	for peer_id in _ranked_peer_ids():
		var cells := PackedStringArray(
			[lobby_manager.lobby_players[peer_id].username, "%d" % _score(peer_id)]
		)
		rows.append({"peer_id": peer_id, "cells": cells})
	var headers := PackedStringArray(["", "🏆 %s" % tr("LB_SCORE")])
	riding_hud_state.push_leaderboard(headers, rows, PackedInt32Array())
