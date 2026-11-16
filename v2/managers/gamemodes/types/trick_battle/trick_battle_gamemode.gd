@tool
## Timed trick battle: after the grid + countdown runner, riders trick anywhere for
## `duration_secs`. Every banked combo counts, plus the one still open at the buzzer; the highest
## total wins. With the event's enable_npcs, bots fill the free grid slots and lap its hidden
## bot_route, ranked like any rider.
class_name TrickBattleGameMode extends TimedScoreGameMode

## The event's PickupSpawners grant / hold items through it.
@export var item_manager: ItemManager
@export var npc_race_manager: NPCRaceManager


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GameModeType.Kind.TRICK_BATTLE
	DebugUtils.DebugMsg("Trick Battle Mode")

	super(state_context)
	if multiplayer.is_server():
		_spawn_npcs()


func Exit(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	_deactivate_pickups()
	if multiplayer.is_server():
		_despawn_npcs()
	super(state_context)


#override
func allows_set_respawn_point() -> bool:
	return true


#override
## Points and items held before the battle (free roam) don't count.
func _start_next_runner():
	super()
	if _is_last_runner():
		for peer_id in lobby_manager.lobby_players:
			trick_manager.reset_peer(peer_id)
		item_manager.clear_items()
		for spawner in _event.get_pickup_spawners():
			spawner.activate(item_manager)
		npc_race_manager.free_ride = true


#override
## Bots go back to the grid with fresh scores, like the humans.
func _restart():
	_deactivate_pickups()
	_despawn_npcs()
	_spawn_npcs()
	super()


func _deactivate_pickups():
	for spawner in _event.get_pickup_spawners():
		spawner.deactivate()


## Server. Bots take the grid slots behind the humans.
func _spawn_npcs():
	if !_event.definition.enable_npcs:
		return
	var grid_markers := _event.get_spawn_markers()
	for slot in range(lobby_manager.lobby_players.size(), grid_markers.size()):
		var marker := grid_markers[slot]
		npc_race_manager.spawn_npc(marker.global_position, marker.global_basis)
	npc_race_manager.bake_racing_line(_event)


func _despawn_npcs():
	npc_race_manager.free_ride = false
	npc_race_manager.despawn_all_npcs()


#override
func _on_player_latejoined(peer_id: int):
	super(peer_id)
	npc_race_manager.sync_npcs_to_peer(peer_id)


#override
func _rider_ids() -> Array:
	var ids := super()
	ids.append_array(npc_race_manager.get_npc_ids())
	return ids


#override
func _username(peer_id: int) -> String:
	# Bot ids are negative
	if peer_id < 0:
		return npc_race_manager.get_npc(peer_id).username
	return super(peer_id)


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
		var cells := PackedStringArray([_username(peer_id), "%d" % _score(peer_id)])
		rows.append({"peer_id": peer_id, "cells": cells})
	var headers := PackedStringArray(["", "🏆 %s" % tr("LB_SCORE")])
	riding_hud_state.push_leaderboard(headers, rows, PackedInt32Array())


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if item_manager == null:
		issues.append("item_manager must not be empty")
	if npc_race_manager == null:
		issues.append("npc_race_manager must not be empty")
	return issues
