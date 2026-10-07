@tool
## Pre-race fuel-up: every rider is parked at their own pump in the event circle's gas_station
## and frozen, while their client pays the pump's price and plays its FuelUpMinigame locally
## (outside the rollback sim); a rider who can't pay sits it out. Each finish sets that rider's
## boost to their fill (spilling caps it), and banks a clean-fill bonus for
## FuelUpBonusComponent; once every rider has reported, the event hands off to its definition's
## target_gamemode.
class_name FuelUpGameMode extends GameModeType

@export var input_state_manager: InputStateManager
@export var hud_manager: HUDManager
@export var save_manager: SaveManager

## Riders start at most this many segments below full, so a full tank still has to play.
const FULL_TANK_DRAIN_SEGMENTS: float = 2.0
## Bonus for a spill-free fill-up, scaling down to 0 at SPILL_FOR_NO_BONUS (in tanks).
const MAX_BONUS: float = 200.0
const SPILL_FOR_NO_BONUS: float = 0.25

var _event: GameModeEvent
## This client's pump; null once it's done.
var _minigame: FuelUpMinigame
## Server only — peers still fueling.
var _pending: Array[int] = []
## Server only — peer_id -> clean-fill bonus. Kept past Exit for the race it hands off to.
var _bonus: Dictionary[int, float] = {}


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

	var pump := pumps[peer_ids.find(multiplayer.get_unique_id())]
	if save_manager.spend(pump.price):
		_minigame = pump
		_minigame.finished.connect(_on_minigame_finished, CONNECT_ONE_SHOT)
		_minigame.begin(
			spawn_manager.get_player_by_peer_id(multiplayer.get_unique_id()),
			input_state_manager,
			gamemode_manager.audio_manager,
			hud_manager
		)
		_minigame.fill = minf(
			_minigame.fill, 1.0 - FULL_TANK_DRAIN_SEGMENTS / BoostController.BOOST_SEGMENTS
		)
	else:
		# Can't pay: sit it out at the pump. Deferred so the host's own skip lands after the
		# server half below has filled _pending.
		hud_manager.riding_hud_state.flash_money()
		(func(): _rpc_fuel_up_skipped.rpc_id(1)).call_deferred()

	if multiplayer.is_server():
		_bonus.clear()
		_pending.assign(peer_ids)
		for i in peer_ids.size():
			var spot := pumps[i].bike_spot
			spawn_manager.respawn_player_in_place.rpc(
				peer_ids[i], spot.global_position, spot.global_basis
			)
			CountdownTask.freeze(spawn_manager.get_player_by_peer_id(peer_ids[i]))


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
			var player := spawn_manager.get_player_by_peer_id(peer_id)
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
	var fill := _minigame.fill
	var spilled := _minigame.spilled
	_minigame = null
	_rpc_fuel_up_done.rpc_id(1, fill, spilled)

#region Server


func get_bonus(peer_id: int) -> float:
	return _bonus.get(peer_id, 0.0)



## Only a tank filled to its unspilled space earns the bonus, so stopping early can't bank one.
@rpc("any_peer", "call_local", "reliable")
func _rpc_fuel_up_done(fill: float, spilled: float):
	if !multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	spawn_manager.set_boost_player.rpc(
		peer_id, clampf(fill, 0.0, 1.0) * BoostController.BOOST_SEGMENTS
	)
	if fill >= 1.0 - spilled:
		_bonus[peer_id] = MAX_BONUS * maxf(0.0, 1.0 - spilled / SPILL_FOR_NO_BONUS)
	_mark_done(peer_id)


## Couldn't pay — keeps their boost, no bonus.
@rpc("any_peer", "call_local", "reliable")
func _rpc_fuel_up_skipped():
	if !multiplayer.is_server():
		return
	_mark_done(multiplayer.get_remote_sender_id())


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
	if save_manager == null:
		issues.append("save_manager must not be empty")
	return issues
