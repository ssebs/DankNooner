@tool
## Career stats (see Progression.md#stats-and-achievements), saved through SaveManager.add_stat /
## max_stat, lifetime and per bike type. Every sample is also emitted for ChallengeManager.
##
## Trick holds come from the server's TrickManager.combo_banked (no resim double counts, and a crash
## voids them), sent to each rider for their own save; so are event results. Distance, top speed,
## airtime and crashes are read from the local rider on its own client.
class_name StatsManager extends BaseManager

## Local: one sample recorded on this client's save (see ChallengeDefinition.stat for the keys).
signal stat_recorded(key: String, value: float)

@export var save_manager: SaveManager
@export var spawn_manager: SpawnManager
@export var trick_manager: TrickManager
@export var gamemode_manager: GamemodeManager

## The local rider.
var _player: PlayerEntity = null
## Seconds the local rider has been airborne this jump.
var _air_t: float = 0.0


func _ready():
	if Engine.is_editor_hint():
		return

	spawn_manager.player_spawned.connect(_on_player_spawned)
	trick_manager.combo_banked.connect(_on_combo_banked)
	gamemode_manager.event_placed.connect(_on_event_placed)


func _process(delta: float):
	if Engine.is_editor_hint():
		return
	# No local rider in menus or after a despawn — skip is intentional
	if !is_instance_valid(_player) or _player.is_crashed:
		return
	var movement := _player.movement_controller
	var speed := absf(movement.speed)
	_add("distance", speed * delta)
	save_manager.max_stat("top_speed", speed)
	stat_recorded.emit("top_speed", speed)
	if !movement.is_on_floor:
		_air_t += delta
	elif _air_t > 0.0:
		_add_runs("airtime", [_air_t])
		_air_t = 0.0


func _add(key: String, amount: float):
	save_manager.add_stat(key, amount)
	stat_recorded.emit(key, amount)


## Seconds of each run (a trick hold, a jump): saved as key_count, key_secs and key_best_secs.
func _add_runs(key: String, runs: Array):
	save_manager.add_stat(key + "_count", runs.size())
	save_manager.max_stat(key + "_best_secs", runs.max())
	for run: float in runs:
		save_manager.add_stat(key + "_secs", run)
		stat_recorded.emit(key, run)


## Server -> one rider: add a banked combo's holds (TrickManager.combo_banked) to their own save.
@rpc("call_local", "reliable")
func rpc_bank_holds(holds: Dictionary):
	for trick in holds:
		_add_runs(TrickController.trick_to_str(trick), holds[trick])
	save_manager.save_save()


## Server -> one rider: they finished an event of `kind`.
@rpc("call_local", "reliable")
func rpc_event_result(kind: GameModeType.Kind, won: bool):
	var mode: String = GameModeType.Kind.keys()[kind]
	_add(mode + "_played", 1)
	if won:
		_add(mode + "_wins", 1)
	save_manager.save_save()


#region handlers
func _on_player_spawned(player: PlayerEntity):
	if !player.is_local_client:
		return
	_player = player
	_air_t = 0.0
	player.crashed.connect(_on_crashed)


func _on_crashed(_peer_id: int):
	_air_t = 0.0
	_add("crashes", 1)
	save_manager.save_save()


## Server only (combo_banked is). Bots keep no stats.
func _on_combo_banked(
	peer_id: int, _points: float, _duration: float, _multiplier: int, holds: Dictionary
):
	if peer_id < 0:
		return
	rpc_bank_holds.rpc_id(peer_id, holds)


## Server only. NPC rows never reach it (_pay_out skips them).
func _on_event_placed(peer_id: int, won: bool):
	rpc_event_result.rpc_id(peer_id, gamemode_manager.current_game_mode, won)
#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if save_manager == null:
		issues.append("save_manager must not be empty")
	if spawn_manager == null:
		issues.append("spawn_manager must not be empty")
	if trick_manager == null:
		issues.append("trick_manager must not be empty")
	if gamemode_manager == null:
		issues.append("gamemode_manager must not be empty")

	return issues
