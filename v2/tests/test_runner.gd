extends Node
## Drives one peer through the real game. Peer 0 hosts and directs: it walks the timeline
## (Testing.md), orders every rider's DriveBot from their current task, and judges the invariants
## from snapshots every peer reports. Peer `peers` is the late joiner. Same node path on every
## peer, so the RPCs land.

const ErrorLogger := preload("res://tests/error_logger.gd")
const MenuFlows := preload("res://tests/menu_flows.gd")
const TaskSolvers := preload("res://tests/task_solvers.gd")
const Invariants := preload("res://tests/invariants.gd")
const Coverage := preload("res://tests/coverage.gd")
const ActivityPlayers := preload("res://tests/activity_players.gd")
const DriveBot := preload("res://tests/drive_bot.gd")

## Generous: a fresh build compiles shaders (WarmupMenuState) before the splash
const STEP_TIMEOUT_S := 120.0
const ACTIVITY_TIMEOUT_S := 60.0
const DISCONNECT_TIMEOUT_S := 10.0
const SAMPLE_INTERVAL_S := 0.5
const CONTROL_INTERVAL_S := 0.1
## Endless modes are cancelled through the pause menu once they've run this long
const ENDLESS_SOLVE_S := 20.0
const ENDLESS_KINDS: Array[int] = [
	GameModeType.Kind.TIME_ATTACK, GameModeType.Kind.LONG_JUMP, GameModeType.Kind.TRICK_BATTLE
]
const ENDLESS_CANCEL_S := 5.0
## Leaving free roam to coming back, results included. A kind missing here fails loudly
const EVENT_TIMEOUTS_S: Dictionary[int, float] = {
	GameModeType.Kind.RACE: 60.0,
	GameModeType.Kind.STUNT_RACE: 60.0,
	GameModeType.Kind.STUNT_CHALLENGE: 30.0,
	GameModeType.Kind.TIME_ATTACK: ENDLESS_SOLVE_S + ENDLESS_CANCEL_S,
	GameModeType.Kind.LONG_JUMP: ENDLESS_SOLVE_S + ENDLESS_CANCEL_S,
	GameModeType.Kind.TRICK_BATTLE: ENDLESS_SOLVE_S + ENDLESS_CANCEL_S,
}
## Agreement isn't judged this soon after a join, leave or gamemode change
const SETTLE_MS := 3000
const GYM_LEVEL := LevelManager.LevelName.TEST_LEVEL_01
const HOST_ADDR := "127.0.0.1"
## run.py launches the clients once READY_MARKER exists, the late joiner on LATE_JOIN_MARKER
const READY_MARKER := "peer0.ready"
const LATE_JOIN_MARKER := "late_join.go"
## run.py shows a hands-off banner while this exists
const MOUSE_MARKER := "mouse.busy"
## run.py drops this on Esc twice, Ctrl+C or its timeout: leave a last screenshot and result
const ABORT_MARKER := "abort"
const ABORT_POLL_S := 0.25
## Between the banner going up and the bot taking the mouse
const MOUSE_WARNING_S := 2.0
## The fresh test save's balance
const TEST_MONEY := 2500

@onready var _drive_bot: DriveBot = %DriveBot

var menu_manager: MenuManager
var connection_manager: ConnectionManager
var lobby_manager: LobbyManager
var gamemode_manager: GamemodeManager
var hud_manager: HUDManager
var input_state_manager: InputStateManager
var spawn_manager: SpawnManager
var save_manager: SaveManager

var _logger: ErrorLogger
var _peer: int
var _peers: int
## Off: no late joiner, so no late join or rejoin steps
var _late_join: bool
var _out_dir: String
## message -> times seen, so a failure on every sample reads as one line
var _violations: Dictionary[String, int] = {}
## Printed in the summary without failing the run
var _warnings: Array[String] = []
var _screenshot_count := 0

var _menus: MenuFlows
var _activities: ActivityPlayers

## Director only
var _solvers: TaskSolvers
var _invariants: Invariants
var _running := false
var _ready_peers: Array[int] = []
var _late_peer_id := 0
## Peers that late-joined a running event; they free-roam beside it until it ends
var _benched: Array[int] = []
var _settle_until_ms := 0
var _host_gamemode := ""
var _lobby_size := 0
## sample -> {peer_id: snapshot}
var _snapshots: Dictionary[int, Dictionary] = {}
var _next_sample := 0
## peer_id -> last order sent
var _orders: Dictionary[int, Dictionary] = {}
## peer_id -> order overriding the solvers while it runs a free-roam activity
var _activity_orders: Dictionary[int, Dictionary] = {}
var _activities_done: Array[int] = []
## Fuel-up warps the one OS cursor: peers queue for it
var _mouse_queue: Array[int] = []
var _mouse_holder := 0
var _mouse_warning := false

## Every peer
var _busy := false
var _has_mouse := false
## The activity this peer last finished; its picker is ignored until the director sends another
var _spent_activity := ""


func run(logger: ErrorLogger, args: Dictionary) -> void:
	_logger = logger
	_peer = args["peer"]
	_peers = args["peers"]
	_late_join = args["late_join"]
	_out_dir = args["out"]
	menu_manager = _find_manager(MenuManager)
	connection_manager = _find_manager(ConnectionManager)
	lobby_manager = _find_manager(LobbyManager)
	gamemode_manager = _find_manager(GamemodeManager)
	hud_manager = _find_manager(HUDManager)
	input_state_manager = _find_manager(InputStateManager)
	spawn_manager = _find_manager(SpawnManager)
	save_manager = _find_manager(SaveManager)
	_menus = MenuFlows.new(self)
	_activities = ActivityPlayers.new(self)
	_drive_bot.violate = violate
	_watch_activities()
	_watch_abort()

	if not await _menus.reach_play_menu():
		_quit()
		return
	var player_def := save_manager.get_player_definition()
	player_def.money = TEST_MONEY
	save_manager.update_save("player_definition", player_def, true, true)
	if _is_director():
		await _direct()
		await _end_run_as_director()
	elif not await _join():
		_quit()
	# A driver that got in idles on the director's orders until it ends the run


#region shared helpers (also used by the helper scripts)
## Polls `condition` every frame. On timeout records a violation and returns false.
func wait_until(condition: Callable, what: String, timeout_s := STEP_TIMEOUT_S) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			violate("timed out waiting for %s" % what)
			return false
		await get_tree().process_frame
	return true


func violate(message: String) -> void:
	DebugUtils.DebugMsg("[test] VIOLATION: %s" % message)
	_violations[message] = _violations.get(message, 0) + 1


## Director: a rider stopped making progress. Screenshot, respawn, carry on. `why` is the
## violation (kept short so repeats count up); `detail` only goes to the log.
func on_stuck(peer_id: int, why: String, detail: String) -> void:
	violate("peer %d stuck: %s" % [peer_id, why])
	DebugUtils.DebugMsg("[test] stuck detail: %s" % detail)
	_screenshot_all.rpc("stuck_peer%d" % peer_id)
	spawn_manager.respawn_player.rpc(peer_id)


#endregion


#region director
func _direct() -> void:
	_solvers = TaskSolvers.new(self)
	_invariants = Invariants.new(self)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not await _menus.host():
		return
	FileAccess.open(_out_dir.path_join(READY_MARKER), FileAccess.WRITE).store_string("")

	var lobby_full := func(): return lobby_manager.lobby_players.size() == _peers
	if not await wait_until(lobby_full, "%d players in the lobby" % _peers):
		return
	_menus.pick_level(GYM_LEVEL)
	if not _menus.start_game() or not await _wait_in_game():
		return
	_ready_peers.append(multiplayer.get_unique_id())
	if not await wait_until(func(): return _ready_peers.size() == _peers, "every peer in free roam"):
		return

	_running = true
	_sample_loop()
	_control_loop()
	var coverage := Coverage.check(get_tree())
	for gap: String in coverage["gaps"]:
		violate(gap)
	for message: String in coverage["untested"]:
		_warnings.append("untested: %s" % message)
	await _free_roam_phase()
	await _events_phase()


## Fuel-up then garage for every starting rider; the late joiner joins during the first one.
func _free_roam_phase() -> void:
	if _late_join:
		FileAccess.open(_out_dir.path_join(LATE_JOIN_MARKER), FileAccess.WRITE).store_string("")
	var pump: FuelUpMinigame = null
	var garage: GarageActivity = null
	for activity in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["FreeRoamActivities"]):
		if activity is FuelUpMinigame and pump == null:
			pump = activity
		elif activity is GarageActivity and garage == null:
			garage = activity
	# Coverage already reported a missing activity
	for activity: FreeRoamActivity in [pump, garage]:
		if activity == null:
			continue
		for peer_id in _ready_peers.duplicate():
			await _run_activity(peer_id, activity)
	if _late_join:
		await wait_until(func(): return _late_peer_id != 0, "the late joiner in free roam")


func _run_activity(peer_id: int, activity: FreeRoamActivity) -> void:
	var circle: Node3D = activity.get_node("%PlayerStartCircle")
	_activities_done.erase(peer_id)
	_activity_orders[peer_id] = {"mode": "idle", "activity": activity.event_name}
	# Riding onto the circle opens the picker; the rider's own peer submits it
	spawn_manager.respawn_player_in_place.rpc(peer_id, circle.global_position, _upright(circle))
	var done := func(): return peer_id in _activities_done
	var finished := await wait_until(done, "peer %d to finish %s" % [peer_id, activity.name], ACTIVITY_TIMEOUT_S)
	_activity_orders.erase(peer_id)
	if !finished:
		await _recover("activity_%s" % activity.name)


## Every event in the gym, in tree order.
func _events_phase() -> void:
	var rejoined := false
	for circle: EventStartCircle in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["EventCircles"]):
		for index in circle.get_events().size():
			if not await _run_event(circle, index, rejoined):
				return
			rejoined = rejoined or _was_race(circle.get_events()[index])


## Returns false when recovery failed and the run should stop.
func _run_event(circle: EventStartCircle, index: int, rejoined: bool) -> bool:
	var event := circle.get_events()[index]
	var label := "%s/%s" % [circle.name, event.name]
	var kind := event.definition.target_gamemode
	if kind not in EVENT_TIMEOUTS_S:
		violate("no timeout for %s events (%s)" % [GameModeType.Kind.find_key(kind), label])
		return true
	var budget_s := EVENT_TIMEOUTS_S[kind]
	if event.definition.fuel_up_first:
		# Pumps take the one mouse in turn, after the hands-off warning
		budget_s += ActivityPlayers.PUMP_TIMEOUT_S * _ready_peers.size() + MOUSE_WARNING_S
	DebugUtils.DebugMsg("[test] event %s" % label)
	spawn_manager.respawn_player_in_place.rpc(1, circle.global_position, _upright(circle))
	# Opens on the circle's first event; the last activity's picker may still be up
	var first_event := circle.get_events()[0].definition.name
	var picker_open := func(): return _menus.is_picker_open_for(first_event)
	if not await wait_until(picker_open, "the event picker at %s" % circle.name):
		return await _recover(label)
	_menus.submit_picker(index)
	if not await wait_until(_is_out_of_free_roam, "%s to start" % label):
		return await _recover(label)

	var started_ms := Time.get_ticks_msec()
	var cancelled := false
	var rejoin_due := _late_join and _was_race(event) and !rejoined
	while _is_out_of_free_roam():
		var elapsed_s := (Time.get_ticks_msec() - started_ms) / 1000.0
		if elapsed_s > budget_s:
			violate("%s didn't finish within %ds" % [label, budget_s])
			return await _recover(label)
		if _menus.are_results_open():
			_menus.skip_results()
		elif kind in ENDLESS_KINDS and elapsed_s > ENDLESS_SOLVE_S and !cancelled:
			cancelled = await _menus.cancel_event()
		var late_joiner_in := _late_peer_id in _ready_peers
		if rejoin_due and late_joiner_in and TaskSolvers.current_task(event, 1) is RaceTask:
			rejoin_due = false
			_rejoin.rpc_id(_late_peer_id)
		await get_tree().create_timer(CONTROL_INTERVAL_S).timeout
	if _late_join:
		await wait_until(func(): return _late_peer_id in _ready_peers, "the late joiner back in")
	return true


## Screenshots every peer, then cancels back to free roam. False if even that fails.
func _recover(label: String) -> bool:
	_screenshot_all.rpc("recover_%s" % label)
	if _is_out_of_free_roam():
		await _menus.cancel_event()
	return await wait_until(func(): return !_is_out_of_free_roam(), "recovery to free roam", 15.0)


func _sample_loop() -> void:
	while _running:
		var sample := _next_sample
		_next_sample += 1
		_snapshots[sample] = {multiplayer.get_unique_id(): Invariants.snapshot(self, _busy)}
		_take_snapshot.rpc(sample)
		await get_tree().create_timer(SAMPLE_INTERVAL_S).timeout
		var gamemode := str(gamemode_manager.state_machine.current_state.name)
		var lobby_size := lobby_manager.lobby_players.size()
		if gamemode != _host_gamemode or lobby_size != _lobby_size:
			_host_gamemode = gamemode
			_lobby_size = lobby_size
			_settle()
		if gamemode_manager.state_machine.current_state == gamemode_manager.free_roam_mode:
			_benched.clear()
		var settled := Time.get_ticks_msec() > _settle_until_ms
		_invariants.judge(_snapshots[sample], _ready_peers.duplicate(), lobby_size, _benched, settled)
		_snapshots.erase(sample)


## Every rider's order from its current task (or its activity), sent when it changes.
func _control_loop() -> void:
	while _running:
		var event := gamemode_manager.current_event
		var in_runner_mode := gamemode_manager.get_current_gamemode() is RunnerGameMode
		for peer_id in _ready_peers:
			var order: Dictionary = DriveBot.IDLE
			var task: GameModeTask = null
			if _activity_orders.has(peer_id):
				order = _activity_orders[peer_id]
			elif event != null and in_runner_mode and peer_id not in _benched:
				order = _solvers.order_for(event, peer_id)
				task = TaskSolvers.current_task(event, peer_id)
			_invariants.track_task(peer_id, task, order.get("target"))
			if _orders.get(peer_id) != order:
				_orders[peer_id] = order
				if peer_id == multiplayer.get_unique_id():
					_drive_bot.set_order(order)
				else:
					_set_order.rpc_id(peer_id, order)
		await get_tree().create_timer(CONTROL_INTERVAL_S).timeout


## Drivers quit first: a host leaving first would drop them into the disconnect flow
func _end_run_as_director() -> void:
	_running = false
	_end_run.rpc()
	var drivers_gone := func(): return multiplayer.get_peers().is_empty()
	await wait_until(drivers_gone, "drivers to disconnect", DISCONNECT_TIMEOUT_S)
	_quit()


func _on_peer_disconnected(peer_id: int) -> void:
	_ready_peers.erase(peer_id)
	_orders.erase(peer_id)
	_invariants.forget(peer_id)
	_mouse_queue.erase(peer_id)
	if _mouse_holder == peer_id:
		_mouse_holder = 0
		_grant_next_mouse()
	_settle()


func _settle() -> void:
	_settle_until_ms = Time.get_ticks_msec() + SETTLE_MS


func _is_out_of_free_roam() -> bool:
	return gamemode_manager.state_machine.current_state != gamemode_manager.free_roam_mode


## `node`'s heading without its tilt or scale, for a rider teleported onto it
static func _upright(node: Node3D) -> Basis:
	return Basis(Vector3.UP, node.global_rotation.y)


static func _was_race(event: GameModeEvent) -> bool:
	return event.definition.target_gamemode == GameModeType.Kind.RACE


func _grant_next_mouse() -> void:
	if _mouse_holder != 0 or _mouse_warning:
		return
	var marker := _out_dir.path_join(MOUSE_MARKER)
	if _mouse_queue.is_empty():
		if FileAccess.file_exists(marker):
			DirAccess.remove_absolute(marker)
		return
	# Back-to-back pumps keep the banner up; only a fresh one warns the human first
	if !FileAccess.file_exists(marker):
		FileAccess.open(marker, FileAccess.WRITE).store_string("")
		_mouse_warning = true
		await get_tree().create_timer(MOUSE_WARNING_S).timeout
		_mouse_warning = false
		if _mouse_queue.is_empty():  # its peer left during the warning
			_grant_next_mouse()
			return
	_mouse_holder = _mouse_queue.pop_front()
	_grant_mouse.rpc_id(_mouse_holder)


#endregion


#region drivers
## Joins via the play menu. False if it never got into the game.
func _join() -> bool:
	if not _menus.join(HOST_ADDR) or not await _wait_in_game():
		return false
	request_mark_ready.rpc_id(1, _peer == _peers)
	return true


## Plays any activity whose HUD comes up, and submits the picker the director sent this rider to.
func _watch_activities() -> void:
	while true:
		await get_tree().process_frame
		var activity: String = _drive_bot.order.get("activity", "")
		if activity == "":
			_spent_activity = ""
		if _busy:
			continue
		var hud_state := hud_manager.state_machine.current_state
		if activity != "" and activity != _spent_activity and _menus.is_picker_open_for(activity):
			_menus.submit_picker(0)
		elif hud_state == hud_manager.fuel_up_hud_state:
			_busy = true
			request_mouse.rpc_id(1)
			var ok := await wait_until(func(): return _has_mouse, "the mouse", ACTIVITY_TIMEOUT_S * 3)
			ok = ok and await _activities.play_fuel_up(hud_manager.fuel_up_hud_state.minigame)
			_has_mouse = false
			request_release_mouse.rpc_id(1)
			_finish_activity(ok)
		elif hud_state == hud_manager.garage_hud_state:
			_busy = true
			_finish_activity(await _activities.play_garage())


func _finish_activity(ok: bool) -> void:
	_busy = false
	_spent_activity = _drive_bot.order.get("activity", "")
	request_activity_done.rpc_id(1, ok)


#endregion


## Every peer polls run.py's marker itself, so an abort doesn't depend on the network
func _watch_abort() -> void:
	var marker := _out_dir.path_join(ABORT_MARKER)
	while !FileAccess.file_exists(marker):
		await get_tree().create_timer(ABORT_POLL_S).timeout
	DebugUtils.DebugMsg("[test] aborted by run.py")
	_screenshot("abort")
	_quit()


## Free roam with the riding HUD up (it enters on the rider's first respawn, after spawn)
func _wait_in_game() -> bool:
	var in_game := func():
		return (
			gamemode_manager.state_machine.current_state == gamemode_manager.free_roam_mode
			and hud_manager.state_machine.current_state == hud_manager.riding_hud_state
		)
	return await wait_until(in_game, "free roam with the riding HUD")


#region RPCs
@rpc("any_peer", "call_remote", "reliable")
func request_mark_ready(is_late_joiner: bool) -> void:
	if !multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	_ready_peers.append(peer_id)
	if is_late_joiner:
		_late_peer_id = peer_id
	if !gamemode_manager.get_current_gamemode().is_late_joinable() and _is_out_of_free_roam():
		_benched.append(peer_id)
	_settle()


@rpc("any_peer", "call_remote", "reliable")
func request_report_snapshot(sample: int, snapshot: Dictionary) -> void:
	if !multiplayer.is_server():
		return
	# Arrived after the sample was judged — dropping it is intentional
	if !_snapshots.has(sample):
		return
	_snapshots[sample][multiplayer.get_remote_sender_id()] = snapshot


@rpc("any_peer", "call_local", "reliable")
func request_activity_done(ok: bool) -> void:
	if !multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender > 1 else 1
	_activities_done.append(peer_id)
	if !ok:
		violate("peer %d failed its activity" % peer_id)


@rpc("any_peer", "call_local", "reliable")
func request_mouse() -> void:
	if !multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_mouse_queue.append(sender if sender > 1 else 1)
	_grant_next_mouse()


@rpc("any_peer", "call_local", "reliable")
func request_release_mouse() -> void:
	if !multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if (sender if sender > 1 else 1) == _mouse_holder:
		_mouse_holder = 0
		_grant_next_mouse()


@rpc("call_local", "reliable")
func _grant_mouse() -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	_has_mouse = true


@rpc("call_remote", "reliable")
func _set_order(order: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	_drive_bot.set_order(order)


@rpc("call_remote", "reliable")
func _take_snapshot(sample: int) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	request_report_snapshot.rpc_id(1, sample, Invariants.snapshot(self, _busy))


@rpc("call_local", "reliable")
func _screenshot_all(label: String) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	_screenshot(label)


## Director → the late joiner: leave mid-race through the pause menu, then join again.
@rpc("call_remote", "reliable")
func _rejoin() -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	if not await _menus.leave_to_main_menu():
		_quit()
		return
	(menu_manager.state_machine.current_state as MainMenuState).play_btn.pressed.emit()
	var at_play := func(): return menu_manager.state_machine.current_state is PlayMenuState
	if not await wait_until(at_play, "the play menu") or not await _join():
		_quit()


@rpc("call_remote", "reliable")
func _end_run() -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	_quit()


#endregion


func _is_director() -> bool:
	return _peer == 0


func _find_manager(type: Script) -> Node:
	for mgr in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Managers"]):
		if is_instance_of(mgr, type):
			return mgr
	return null


func _screenshot(label: String) -> void:
	_screenshot_count += 1
	var file := "peer%d_%02d_%s.png" % [_peer, _screenshot_count, label.validate_filename()]
	get_viewport().get_texture().get_image().save_png(_out_dir.path_join(file))


func _quit() -> void:
	DictJSONSaverLoader.save_json_to_file(
		_out_dir.path_join("peer%d.result.json" % _peer),
		{
			"role": "director" if _is_director() else ("late joiner" if _peer == _peers else "driver"),
			"errors": _logger.get_errors(),
			"error_count": _logger.get_error_count(),
			"violations": _violations,
			"warnings": _warnings,
		}
	)
	get_tree().quit(1 if _violations or _logger.get_error_count() else 0)
