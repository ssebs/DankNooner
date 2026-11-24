@tool
## Pre-race fuel-up: parks the rider at their own pump in the event circle's gas_station, frozen,
## while their client plays its FuelUpMinigame locally (outside the rollback sim), paying by the
## second. Ending it sets their boost to the fill and moves them on, without waiting for the others.
##
## Place first in the DriveToStartRunner, so each rider heads to the start as soon as they're done.
## Needs gas_station set on the parent EventStartCircle, with a pump per rider.
class_name FuelUpTask extends GameModeTask

## Client deps for the pump. They live in main_game.tscn, so RaceGameMode injects them.
var input_state_manager: InputStateManager
var hud_manager: HUDManager
var save_manager: SaveManager
var tour_manager: TourManager

## This client's pump; null once it's done.
var _minigame: FuelUpMinigame
## Shown station, kept so reset() can hide it once the runner has let go of this task.
var _station: Node3D


func on_enter(player: PlayerEntity, state: Dictionary) -> void:
	state["done"] = false
	var peer_id := int(player.name)
	# Each rider gets the pump at their place in the runner's peer order.
	var pump_idx := runner.player_states.keys().find(peer_id)
	_rpc_set_station_active.rpc(true)
	# Before the teleport: the pump starts its session on the rider's respawn.
	_rpc_begin.rpc_id(peer_id, pump_idx)
	var spot := _get_pumps()[pump_idx].bike_spot
	runner.spawn_manager.respawn_player_in_place.rpc(
		peer_id, spot.global_position, spot.global_basis
	)
	CountdownTask.freeze(player)


func check(_player: PlayerEntity, _delta: float, state: Dictionary) -> bool:
	return state.get("done", false)


func on_exit(player: PlayerEntity, _state: Dictionary) -> void:
	CountdownTask.unfreeze(player)
	for peer_id in runner.player_states:
		if peer_id != int(player.name) and runner.get_current_task(peer_id) == self:
			return
	_rpc_set_station_active.rpc(false)


## Every peer, when the event ends: drops a pump still running (host cancelled mid-fill).
func reset():
	if _minigame != null:
		_minigame.finished.disconnect(_on_minigame_finished)
		_minigame.end()
		_minigame = null
	if _station != null:
		_set_station_active(false)


func _get_pumps() -> Array[FuelUpMinigame]:
	var pumps: Array[FuelUpMinigame] = []
	pumps.assign(runner.event.get_circle().gas_station.find_children("*", "FuelUpMinigame", true, false))
	return pumps


## Extra pumps only exist for fuel-up (e.g. the station's HIDE_CTRL).
@rpc("call_local", "reliable")
func _rpc_set_station_active(active: bool):
	_station = runner.event.get_circle().gas_station
	_set_station_active(active)


func _set_station_active(active: bool):
	for obj: GameModeObject in _station.find_children("*", "GameModeObject", true, false):
		obj.is_active = active
	if !active:
		_station = null


@rpc("call_local", "reliable")
func _rpc_begin(pump_idx: int):
	_minigame = _get_pumps()[pump_idx]
	_minigame.finished.connect(_on_minigame_finished, CONNECT_ONE_SHOT)
	_minigame.begin(
		runner.spawn_manager.get_player_by_peer_id(multiplayer.get_unique_id()),
		input_state_manager,
		runner.audio_manager,
		hud_manager,
		save_manager,
		tour_manager
	)


## Local — the pump already handed the rider back.
func _on_minigame_finished():
	var fill := _minigame.fill
	_minigame = null
	_rpc_fuel_up_done.rpc_id(1, fill)


@rpc("any_peer", "call_local", "reliable")
func _rpc_fuel_up_done(fill: float):
	if !multiplayer.is_server():
		return
	# The event may have ended while this was in flight — skip is intentional.
	if runner == null:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	runner.spawn_manager.set_boost_player.rpc(
		peer_id, clampf(fill, 0.0, 1.0) * BoostController.BOOST_SEGMENTS
	)
	runner.mark_state(peer_id, "done", true)
