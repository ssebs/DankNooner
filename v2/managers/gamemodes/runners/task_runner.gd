@tool
## Base for composite runners (Sequential, Concurrent).
##
## Holds the deps shared by every runner so leaf tasks can address them via
## `runner.spawn_manager` / `runner.riding_hud` / `runner.audio_manager` / `runner.route`
## regardless of which runner type owns them.
##
## Owns the per-peer bookkeeping (states, task list, completion). Subclasses call super()
## from start/update/stop and implement _update_player to drive their walk.
class_name TaskRunner extends GameModeTask

## Notifies the host gamemode that a crashed peer should be respawned (gamemode
## owns the actual delay timer). Respawn target is read from the player's own
## persistent `rb_respawn_transform`, set by TeleportTask via SpawnManager, unless
## `in_place` (see GameModeTask.respawn_in_place).
signal respawn_requested(peer_id: int, in_place: bool)

## Set by the host gamemode (or a parent runner, for nested cases) before
## `start()`. Not @exported because the runner lives in a level scene while the
## managers live in main_game.tscn — cross-scene NodePaths would be fragile.
var spawn_manager: SpawnManager
## Step text goes to its event pane.
var riding_hud: RidingHUDState
## "2 / 5" on the event pane — tutorials yes, races no (see RunnerGameMode.shows_step_count).
var show_step_count: bool = true
var audio_manager: AudioManager
## The event's EventRoute (grid, checkpoints) — null for events without one.
var route: EventRoute

var player_states: Dictionary[int, PlayerTaskState] = {}
var tasks: Array[GameModeTask] = []
var _running: bool = false

#region Composite API


## Subclasses call super() first, then begin their walk.
func start(peer_ids: Array) -> void:
	tasks = []
	for c in get_children():
		if c is GameModeTask:
			tasks.append(c)
			c.runner = self
	player_states.clear()
	var now := Time.get_ticks_msec() as float
	for peer_id in peer_ids:
		var state := PlayerTaskState.create()
		state.started = true
		state.start_time = now
		player_states[peer_id] = state
	_running = true


func update(delta: float) -> void:
	if !_running or !multiplayer.is_server():
		return
	for peer_id in player_states:
		var state := player_states[peer_id]
		if state.completed or !state.started:
			continue
		# Player may not be spawned yet during late-join sync — skip is intentional
		var player := spawn_manager.get_player_by_peer_id(peer_id)
		if player == null:
			continue
		# Pause progress while crashed/respawning. trick_controller freezes current_trick
		# during a crash, so without this guard a wheelie/stoppie timer would keep ticking
		# through the respawn delay.
		if player.is_crashed:
			continue
		_update_player(peer_id, state, player, delta)


func stop() -> void:
	_running = false
	for task in tasks:
		task.runner = null
	player_states.clear()
	tasks = []


func notify_disconnected(peer_id: int) -> void:
	player_states.erase(peer_id)


#endregion

#region Per-peer walk


## Advance one live, uncrashed peer's walk. Subclasses implement.
func _update_player(
	_peer_id: int, _state: PlayerTaskState, _player: PlayerEntity, _delta: float
) -> void:
	pass


func _complete_player(peer_id: int, state: PlayerTaskState) -> void:
	state.completed = true
	state.completion_time_ms = Time.get_ticks_msec() - state.start_time
	riding_hud.push_event_status(peer_id, "TUT_WAITING_FOR_OTHERS")
	player_completed.emit(peer_id)
	if _all_peers_complete():
		all_completed.emit()


func _all_peers_complete() -> bool:
	for peer_id in player_states:
		if !player_states[peer_id].completed:
			return false
	return player_states.size() > 0


#endregion


## Wire `runner` on every child task and propagate deps + recurse into nested
## runners. Runs on every peer (host gamemode calls this in Enter()) so RPCs
## targeting clients can resolve `runner.audio_manager` etc — the per-peer
## `start()` only runs on the server and can't do this for clients.
func wire_task_refs() -> void:
	for c in get_children():
		if c is GameModeTask:
			c.runner = self
		if c is TaskRunner:
			c.spawn_manager = spawn_manager
			c.riding_hud = riding_hud
			c.show_step_count = show_step_count
			c.audio_manager = audio_manager
			c.route = route
			c.wire_task_refs()

