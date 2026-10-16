extends RefCounted
## Snapshots (every peer) and the invariants the director judges them by. Steps only put the game
## into a situation; these decide whether it's right.

## HUD states a rider may be in while riding; activity HUDs only while running one
const RIDING_HUDS: Array[String] = ["RidingHUDState", "GamemodeEventHUDState", "ResultsHUDState"]
const ACTIVITY_HUDS: Array[String] = ["FuelUpHUDState", "GarageHUDState"]
## Below this speed (m/s) a rider counts as stationary
const STILL_SPEED := 0.5
## A countdown's lock lands a moment after the task starts
const COUNTDOWN_SETTLE_MS := 500
## Throttle held this long after a countdown must have the rider moving
const AFTER_COUNTDOWN_MS := 2000
## Throttle held, not locked or crashed, and stationary this long = stuck
const STUCK_MS := 4000
## No closer to the waypoint for this long = stuck on geometry
const NO_PROGRESS_MS := 12000
const PROGRESS_STEP := 1.0

## The TestRunner. Untyped: it preloads this script, and a cyclic preload won't resolve.
var _runner: Node
## Per peer: {task, task_since_ms, countdown_end_ms, still_since_ms, target, best_dist, best_ms}
var _track: Dictionary[int, Dictionary] = {}


func _init(runner: Node) -> void:
	_runner = runner


## This peer's view. `busy` = running a free-roam activity.
static func snapshot(runner: Node, busy: bool) -> Dictionary:
	var players := []
	for racer in runner.get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Racers"]):
		if racer is PlayerEntity:
			players.append(int(str(racer.name)))
	players.sort()
	var hud := runner.hud_manager.state_machine.current_state as HUDState
	var gamemode: State = runner.gamemode_manager.state_machine.current_state
	var snap := {
		"players": players,
		"gamemode": str(gamemode.name) if gamemode != null else "",
		"hud": str(hud.name),
		"hud_visible": hud.ui.is_visible_in_tree(),
		"menu_open": runner.input_state_manager.is_menu_open(),
		"busy": busy,
	}
	# Mid-rejoin or mid-load there's no rider — the snapshot just says so
	var player := runner.get_tree().get_first_node_in_group(UtilsConstants.GROUPS["LocalPlayer"])
	if player != null:
		snap.merge({
			"pos": player.global_position,
			"speed": player.movement_controller.speed,
			"locked": player.movement_locked,
			"crashed": player.is_crashed,
			"throttle": Input.get_action_strength(&"throttle_pct"),
		})
	return snap


## Judges one sample. `expected` = peer ids that should have reported; `player_count` = riders
## everyone should see (the host's lobby); `benched` = peers that late-joined a running event and
## free-roam beside it; `settled` = false right after a join, leave or gamemode change.
func judge(
	snapshots: Dictionary, expected: Array, player_count: int, benched: Array, settled: bool
) -> void:
	var host: Dictionary = snapshots[1]
	for peer_id in expected:
		if !snapshots.has(peer_id):
			_runner.violate("peer %d didn't report a snapshot" % peer_id)
			continue
		var snap: Dictionary = snapshots[peer_id]
		if settled:
			_judge_agreement(peer_id, snap, host, player_count, peer_id in benched)
		_judge_hud(peer_id, snap)
		if snap.has("pos"):
			_judge_movement(peer_id, snap)


## Director-side task + order bookkeeping the movement invariants need, per control tick.
func track_task(peer_id: int, task: GameModeTask, target: Variant) -> void:
	var now := Time.get_ticks_msec()
	var track: Dictionary = _track.get_or_add(peer_id, {})
	var was_countdown: bool = track.get("task") is CountdownTask
	if track.get("task") != task:
		track["task"] = task
		track["task_since_ms"] = now
		if was_countdown:
			track["countdown_end_ms"] = now
	if track.get("target") != target:
		track["target"] = target
		track["best_dist"] = INF
		track["best_ms"] = now


func forget(peer_id: int) -> void:
	_track.erase(peer_id)


func _judge_agreement(
	peer_id: int, snap: Dictionary, host: Dictionary, expected_count: int, is_benched: bool
) -> void:
	if snap["players"].size() != expected_count:
		_runner.violate("peer %d sees %d players, expected %d" % [
			peer_id, snap["players"].size(), expected_count
		])
	if snap["players"] != host["players"]:
		_runner.violate("peer %d sees players %s, host sees %s" % [
			peer_id, snap["players"], host["players"]
		])
	var expected_mode: String = "FreeRoamGameMode" if is_benched else host["gamemode"]
	if snap["gamemode"] != expected_mode:
		_runner.violate("peer %d is in %s, expected %s" % [peer_id, snap["gamemode"], expected_mode])


func _judge_hud(peer_id: int, snap: Dictionary) -> void:
	# The pause menu hides the HUD on purpose
	if snap["menu_open"]:
		return
	var allowed := RIDING_HUDS + ACTIVITY_HUDS if snap["busy"] else RIDING_HUDS
	if snap["hud"] not in allowed or not snap["hud_visible"]:
		_runner.violate("peer %d HUD is %s (visible: %s), expected a visible one of %s" % [
			peer_id, snap["hud"], snap["hud_visible"], allowed
		])


func _judge_movement(peer_id: int, snap: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	var track: Dictionary = _track.get_or_add(peer_id, {})
	var still: bool = snap["speed"] < STILL_SPEED
	var throttle_held: bool = snap["throttle"] > 0.5

	if track.get("task") is CountdownTask and now - track["task_since_ms"] > COUNTDOWN_SETTLE_MS:
		if !snap["locked"] or !still:
			_runner.violate(
				"peer %d not locked and still during a countdown (locked: %s)" % [peer_id, snap["locked"]]
			)

	var countdown_end: int = track.get("countdown_end_ms", 0)
	if countdown_end > 0 and now - countdown_end > AFTER_COUNTDOWN_MS:
		track.erase("countdown_end_ms")
		if throttle_held and (snap["locked"] or still):
			_runner.violate("peer %d stuck at the start after the countdown (locked: %s)" % [
				peer_id, snap["locked"]
			])

	var stuck: bool = (
		throttle_held and still and !snap["locked"] and !snap["crashed"]
		and !snap["menu_open"] and !snap["busy"]
	)
	if !stuck:
		track.erase("still_since_ms")
	elif now - track.get_or_add("still_since_ms", now) > STUCK_MS:
		track.erase("still_since_ms")
		_runner.on_stuck(peer_id, "not moving with the throttle held", "at %s" % snap["pos"])

	if track.get("target") == null or snap["crashed"] or snap["locked"]:
		return
	var dist: float = (track["target"] as Vector3).distance_to(snap["pos"])
	if dist < track["best_dist"] - PROGRESS_STEP:
		track["best_dist"] = dist
		track["best_ms"] = now
	elif now - track["best_ms"] > NO_PROGRESS_MS:
		track["best_ms"] = now
		track["best_dist"] = INF
		var detail := "toward %s from %s" % [track["target"], snap["pos"]]
		_runner.on_stuck(peer_id, "no progress toward its waypoint", detail)
