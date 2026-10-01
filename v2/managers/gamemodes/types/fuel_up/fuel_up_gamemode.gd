@tool
## Pre-race fuel-up: every rider is parked at their own pump in the event circle's gas_station
## and frozen, while their client plays that pump's FuelUpMinigame locally (outside the rollback
## sim). Each finish fills that rider's boost; once every rider has reported, the event hands off
## to its definition's target_gamemode.
class_name FuelUpGameMode extends GameModeType

@export var input_state_manager: InputStateManager
@export var hud_manager: HUDManager

var _event: GameModeEvent
## This client's pump; null once it's done.
var _minigame: FuelUpMinigame
## Server only — peers still fueling.
var _pending: Array[int] = []


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GameModeType.Kind.FUEL_UP
	DebugUtils.DebugMsg("FuelUp Mode")
	_event = (state_context as GamemodeStateContext).event

	gamemode_manager.player_disconnected.connect(_on_player_disconnected)
	gamemode_manager.player_latejoined.connect(_on_player_latejoined)

	var station := _event.get_circle().gas_station
	# Extra pumps only exist for fuel-up (e.g. the station's HIDE_CTRL).
	_set_station_objects_active(station, true)
	var pumps: Array[FuelUpMinigame] = []
	pumps.assign(station.find_children("*", "FuelUpMinigame", true, false))
	# Sorted so every peer derives the same pump per rider without an RPC.
	var peer_ids := gamemode_manager.lobby_manager.lobby_players.keys()
	peer_ids.sort()

	_minigame = pumps[peer_ids.find(multiplayer.get_unique_id())]
	_minigame.finished.connect(_on_minigame_finished, CONNECT_ONE_SHOT)
	_minigame.begin(
		spawn_manager._get_player_by_peer_id(multiplayer.get_unique_id()),
		input_state_manager,
		gamemode_manager.audio_manager,
		hud_manager
	)

	if multiplayer.is_server():
		_pending.assign(peer_ids)
		for i in peer_ids.size():
			var spot := pumps[i].bike_spot
			spawn_manager.respawn_player_in_place.rpc(
				peer_ids[i], spot.global_position, spot.global_basis
			)
			CountdownTask.freeze(spawn_manager._get_player_by_peer_id(peer_ids[i]))


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.player_disconnected.disconnect(_on_player_disconnected)
	gamemode_manager.player_latejoined.disconnect(_on_player_latejoined)

	# Exited early (host cancelled) — before the teleport landed, or mid-minigame.
	if _minigame != null:
		_minigame.finished.disconnect(_on_minigame_finished)
		_minigame.end()

	if multiplayer.is_server():
		# The race's own grid + countdown re-freeze riders as needed.
		for peer_id in gamemode_manager.lobby_manager.lobby_players:
			# Player may not be spawned yet (late-join) — skip is intentional.
			var player := spawn_manager._get_player_by_peer_id(peer_id)
			if player != null:
				CountdownTask.unfreeze(player)
	_set_station_objects_active(_event.get_circle().gas_station, false)
	_pending.clear()
	_minigame = null
	_event = null


func _set_station_objects_active(station: Node3D, active: bool):
	for obj: GameModeObject in station.find_children("*", "GameModeObject", true, false):
		obj.is_active = active


## Local — the pump already handed the rider back.
func _on_minigame_finished():
	_minigame = null
	_rpc_fuel_up_done.rpc_id(1)

#region Server


@rpc("any_peer", "call_local", "reliable")
func _rpc_fuel_up_done():
	if !multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	spawn_manager.max_boost_player.rpc(peer_id)
	_mark_done(peer_id)


func _mark_done(peer_id: int):
	_pending.erase(peer_id)
	if _pending.is_empty():
		gamemode_manager.change_gamemode(
			_event.definition.target_gamemode, multiplayer.get_unique_id(), _event.get_path()
		)


func _on_player_latejoined(peer_id: int):
	gamemode_manager.latespawn_player(peer_id)


func _on_player_disconnected(peer_id: int):
	if gamemode_manager.match_state == GamemodeManager.MatchState.IN_GAME:
		spawn_manager.rpc_despawn_player.rpc(peer_id)
	_mark_done(peer_id)


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	if hud_manager == null:
		issues.append("hud_manager must not be empty")
	return issues
