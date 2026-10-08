@tool
## Race body task — per-peer lap + checkpoint tracking for every RaceGameMode type.
##
## Watches multiple CheckPointMarkers directly via their `entered` signal
## instead of using the runner's single-`trigger` system.
##
## The route is the EventRoute's CheckPointMarkers, in tree order. A first marker named
## `…StartStop1` is both start and finish (a lap circuit: StartStop1 -> 2 -> 3 … -> StartStop1);
## otherwise it's point-to-point (first = start, last = finish).
##
## On every recognized checkpoint crossing, the player's persistent respawn
## transform is updated to that marker (same mechanism as TeleportTask), so
## crashes return to the last checkpoint passed.
class_name RaceTask extends GameModeTask

## A racer (human or NPC) crossed the finish of a lap; lap_ms is that lap's split.
signal lap_completed(racer_id: int, lap_ms: int)

enum WaitFor {START, LAP_CP, END}

@export var total_laps: int = 3
## Time attack: never completes (total_laps ignored). Circuits lap forever; a point-to-point run
## parks the rider at the finish until restart_run(). The host ends it via Cancel Event.
@export var endless: bool = false
@export var objective_key: String = "RACE_OBJECTIVE"
## Wrong-way warning fires once a racer is this many meters past their closest approach to the
## next gate and still moving away from it (e.g. missed a turn).
@export var wrong_way_margin: float = 40.0

const WRONG_WAY_MIN_SPEED: float = 5.0
## Going the wrong way this long respawns the racer at their last checkpoint.
const WRONG_WAY_RESPAWN_MS: int = 3000
## Time attack restart: frozen on the grid this long (matches COUNTDOWN_3SEC).
const RESTART_COUNTDOWN_MS: int = 3000
## Gates shown before the start crossing: the start and the one after (routes have at least 2).
const START_CHECKPOINTS: PackedInt32Array = [0, 1]

## Derived from the route by _collect_checkpoints().
var start_checkpoint: CheckPointMarker
var lap_checkpoints: Array[CheckPointMarker] = []
var end_checkpoint: CheckPointMarker

## Per-racer progress (humans AND NPCs — RaceTask is the single scoring source
## of truth, keyed by racer id; NPC ids are negative). RaceTask owns this
## directly — the runner's per-peer scratchpad isn't reachable from signal
## callbacks.
##   racer_id -> { "laps_done": int, "next_lap_idx": int, "waiting_for": WaitFor,
##                 "start_ms": int, "lap_start_ms": int, ["completion_time_ms": int],
##                 ["respawn_ckpt": CheckPointMarker  (NPC rows only)] }
var peer_progress: Dictionary[int, Dictionary] = {}
var _signals_wired: bool = false
## False until the race body actually starts (first human on_enter) — NPCs are
## registered earlier, at gamemode Enter, and must hold at the grid until then.
var _race_active: bool = false


func _init():
	eval_when = EvalWhen.ALWAYS


func on_enter(player: PlayerEntity, _state: Dictionary) -> void:
	if !_signals_wired:
		_collect_checkpoints()
		_wire_checkpoint_signals()
		_signals_wired = true
	if !_race_active:
		_race_active = true
		# NPCs were registered back at gamemode Enter (before grid/countdown) —
		# start their clocks together with the humans'. Human rows surviving
		# from a previous run are stale — drop them (this run's peers get fresh
		# rows below).
		for id in peer_progress.keys():
			if id < 0:
				peer_progress[id]["start_ms"] = Time.get_ticks_msec()
				peer_progress[id]["lap_start_ms"] = Time.get_ticks_msec()
			else:
				peer_progress.erase(id)
	var peer_id := int(player.name)
	# Stable per-racer respawn lane, in entry order (0,1,2…) — picks a distinct
	# slot from each checkpoint's RespawnPoints so crashed racers don't stack.
	var respawn_slot := 0
	for id in peer_progress:
		if id >= 0:
			respawn_slot += 1
	peer_progress[peer_id] = {
		"laps_done": 0,
		"next_lap_idx": 0,
		"waiting_for": WaitFor.START,
		"start_ms": Time.get_ticks_msec(),
		"lap_start_ms": Time.get_ticks_msec(),
		## Endless point-to-point: finished a run, waiting on restart_run().
		"run_done": false,
		## Ticks when a restart_run() countdown ends, 0 when none is running.
		"countdown_end_ms": 0,
		"respawn_slot": respawn_slot,
		"best_dist": INF,
		## Ticks when the racer started going the wrong way, 0 while on course.
		"wrong_way_since_ms": 0,
	}
	_rpc_reset_checkpoints.rpc_id(peer_id)


func check(player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	var peer_id := int(player.name)
	var p := peer_progress[peer_id]
	if !endless and p["laps_done"] >= total_laps:
		return true
	if p["countdown_end_ms"] > 0:
		_tick_restart_countdown(player, peer_id, p)
		return false
	if p["run_done"]:
		return false
	_push_lap_hud(peer_id, p)
	_check_wrong_way(player, peer_id, p)
	return false


func on_exit(player: PlayerEntity, _state: Dictionary) -> void:
	# Keep the finished row — results read completion_time_ms from here after
	# the runner stops (single scoring source for humans + NPCs). Stale rows
	# are purged at the next race start in on_enter.
	var peer_id := int(player.name)
	if peer_progress[peer_id]["wrong_way_since_ms"] > 0:
		runner.riding_hud.clear_event_warning(peer_id)


func get_objective_text() -> String:
	return tr(objective_key)


func get_hint_text() -> String:
	# Empty — dynamic lap/timer text is pushed each frame via riding_hud.push_event_progress.
	return ""


## Recorded finish time for any racer (humans and NPCs), -1.0 while unfinished.
## Public so the race gamemodes stop reaching into peer_progress.
func get_completion_time_ms(racer_id: int) -> float:
	return peer_progress[racer_id].get("completion_time_ms", -1.0)


func has_racer(racer_id: int) -> bool:
	return peer_progress.has(racer_id)


func is_point_to_point() -> bool:
	return end_checkpoint != start_checkpoint


## Running clock of the racer's current lap, -1 while parked after an endless point-to-point run
## or counting down a restart.
func get_lap_elapsed_ms(racer_id: int) -> int:
	var p := peer_progress[racer_id]
	if p.get("run_done", false) or p.get("countdown_end_ms", 0) > 0:
		return -1
	return Time.get_ticks_msec() - p["lap_start_ms"]


## Time attack (hold-R respawn, point-to-point "run again"): back to the rider's grid slot,
## frozen through a 3-2-1, then lap 1 on a fresh clock.
func restart_run(peer_id: int) -> void:
	var p := peer_progress[peer_id]
	p["run_done"] = false
	p["laps_done"] = 0
	p["next_lap_idx"] = 0
	p["waiting_for"] = WaitFor.START
	p["best_dist"] = INF
	p["wrong_way_since_ms"] = 0
	p["countdown_end_ms"] = Time.get_ticks_msec() + RESTART_COUNTDOWN_MS
	var markers := runner.route.get_grid_markers()
	var marker := markers[mini(p["respawn_slot"], markers.size() - 1)]
	runner.spawn_manager.respawn_player_at.rpc(peer_id, marker.global_position, marker.global_basis)
	CountdownTask.freeze(runner.spawn_manager.get_player_by_peer_id(peer_id))
	runner.riding_hud.clear_event_warning(peer_id)
	_rpc_reset_checkpoints.rpc_id(peer_id)
	_rpc_play_countdown_sfx.rpc_id(peer_id)


#region NPC racers (server-side, driven by the race gamemodes / NPCRaceManager)


## Adds an NPC row so checkpoint crossings score it like any peer. Called at
## gamemode Enter — before the race body starts — so this also resets
## _race_active, holding NPCs at the grid until the first human on_enter.
func register_npc(npc_id: int) -> void:
	_race_active = false
	peer_progress[npc_id] = {
		"laps_done": 0,
		"next_lap_idx": 0,
		"waiting_for": WaitFor.START,
		"start_ms": Time.get_ticks_msec(),
		"lap_start_ms": Time.get_ticks_msec(),
	}


func unregister_npc(npc_id: int) -> void:
	peer_progress.erase(npc_id)


## The checkpoint an NPC should navigate toward. Null while the race body
## hasn't started (grid/countdown) or once the NPC has finished — the caller
## holds position. One event, two jobs: the same crossing that scores the lap
## also retargets navigation.
func get_target_checkpoint(npc_id: int) -> CheckPointMarker:
	if !_race_active:
		return null
	var p := peer_progress[npc_id]
	if p["laps_done"] >= total_laps:
		return null
	return _expected_checkpoint(p)


## Last checkpoint the NPC passed — its crash respawn point. Null until the
## first crossing; caller falls back to the spawn grid slot.
func get_npc_respawn_checkpoint(npc_id: int) -> CheckPointMarker:
	return peer_progress[npc_id].get("respawn_ckpt")


#endregion


#region Checkpoint signal wiring


func _collect_checkpoints() -> void:
	var checkpoints := runner.route.get_checkpoints()
	start_checkpoint = checkpoints[0]
	if "StartStop" in start_checkpoint.name:
		end_checkpoint = start_checkpoint
		lap_checkpoints = checkpoints.slice(1)
	else:
		end_checkpoint = checkpoints[checkpoints.size() - 1]
		lap_checkpoints = checkpoints.slice(1, checkpoints.size() - 1)


func _wire_checkpoint_signals() -> void:
	var seen := {}
	for ckpt in _all_checkpoints():
		if ckpt == null or seen.has(ckpt):
			continue
		seen[ckpt] = true
		ckpt.entered.connect(_on_checkpoint_entered.bind(ckpt))


func _all_checkpoints() -> Array[CheckPointMarker]:
	var arr: Array[CheckPointMarker] = [start_checkpoint]
	for cp in lap_checkpoints:
		arr.append(cp)
	if end_checkpoint != start_checkpoint:
		arr.append(end_checkpoint)
	return arr


func _on_checkpoint_entered(racer: Node3D, ckpt: CheckPointMarker) -> void:
	var peer_id := int(racer.name)
	# Racer may not be racing (spectator, late-joiner, or already completed) — skip is intentional
	if !peer_progress.has(peer_id):
		return
	var p := peer_progress[peer_id]
	# Finished racers keep their row for results — don't let victory laps
	# advance the state or overwrite the recorded time.
	if p.has("completion_time_ms") or p.get("run_done", false):
		return
	var expected := _expected_checkpoint(p)
	if ckpt != expected:
		DebugUtils.DebugMsg(
			"RaceTask: peer %d hit %s out of order (expected %s)"
			% [peer_id, ckpt.name, expected.name if expected else "null"]
		)
		# Only a gate ahead of the expected one means one was skipped — re-crossing a
		# passed gate (e.g. after a respawn) isn't a miss.
		if peer_id >= 0 and _route_ordinal(ckpt, p) > _expected_ordinal(p):
			runner.riding_hud.push_event_warning(peer_id, "RACE_MISSED_CHECKPOINT")
		return
	_advance(peer_id, p, ckpt)


func _expected_checkpoint(p: Dictionary) -> CheckPointMarker:
	match p["waiting_for"]:
		WaitFor.START:
			return start_checkpoint
		WaitFor.LAP_CP:
			return lap_checkpoints[p["next_lap_idx"]]
		WaitFor.END:
			return end_checkpoint
	return null


func _advance(peer_id: int, p: Dictionary, ckpt: CheckPointMarker) -> void:
	if peer_id < 0:
		# NPC — no PlayerEntity rb_* respawn mechanism; NPCRaceManager reads
		# this back via get_npc_respawn_checkpoint for crash recovery.
		p["respawn_ckpt"] = ckpt
	else:
		# Update persistent respawn only — don't teleport the racing player.
		# Pick this racer's lane so crashed racers spread across the checkpoint
		# instead of stacking on its origin.
		var slots := ckpt.get_respawn_points()
		var slot := slots[p["respawn_slot"] % slots.size()]
		runner.spawn_manager.set_respawn_point.rpc(
			peer_id, slot.global_position, slot.global_basis
		)
		p["best_dist"] = INF

	match p["waiting_for"]:
		WaitFor.START:
			_after_start_or_lap_advance(p)
		WaitFor.LAP_CP:
			p["next_lap_idx"] += 1
			_after_start_or_lap_advance(p)
		WaitFor.END:
			p["laps_done"] += 1
			p["next_lap_idx"] = 0
			var now := Time.get_ticks_msec()
			var lap_ms: int = now - p["lap_start_ms"]
			p["lap_start_ms"] = now
			if endless and is_point_to_point():
				p["run_done"] = true
			elif !endless and p["laps_done"] >= total_laps:
				# Racer done (check() returns true next frame for humans).
				# RaceTask is the scoring source of truth for every racer —
				# record the time here for humans and NPCs alike.
				p["completion_time_ms"] = Time.get_ticks_msec() - p["start_ms"]
			elif end_checkpoint == start_checkpoint:
				# Same marker doubles as the next lap's start crossing — go straight to lap CPs.
				p["waiting_for"] = WaitFor.LAP_CP if !lap_checkpoints.is_empty() else WaitFor.END
			else:
				p["waiting_for"] = WaitFor.START
			# After the row update so listeners see run_done.
			lap_completed.emit(peer_id, lap_ms)

	if peer_id >= 0:
		# After the row update so the upcoming gates are known.
		var ckpt_idx := runner.route.get_checkpoints().find(ckpt)
		_rpc_checkpoint_passed.rpc_id(peer_id, ckpt_idx, _upcoming_checkpoint_idxs(p))


## Route indices of the racer's next gate and the one after; none once finished or parked.
func _upcoming_checkpoint_idxs(p: Dictionary) -> PackedInt32Array:
	if p.has("completion_time_ms") or p["run_done"]:
		return PackedInt32Array()
	var checkpoints := runner.route.get_checkpoints()
	var next_idx := checkpoints.find(_expected_checkpoint(p))
	var final_gate: bool = (
		p["waiting_for"] == WaitFor.END
		and (is_point_to_point() or (!endless and p["laps_done"] + 1 >= total_laps))
	)
	if final_gate:
		return PackedInt32Array([next_idx])
	# Circuits wrap back to StartStop1.
	return PackedInt32Array([next_idx, (next_idx + 1) % checkpoints.size()])


## Position of the racer's next gate along the whole race (laps included) — only grows.
func _expected_ordinal(p: Dictionary) -> int:
	var lap_ordinal: int = p["laps_done"] * (lap_checkpoints.size() + 2)
	match p["waiting_for"]:
		WaitFor.START:
			return lap_ordinal
		WaitFor.LAP_CP:
			return lap_ordinal + 1 + p["next_lap_idx"]
	return lap_ordinal + 1 + lap_checkpoints.size()


## Where `ckpt` sits in the racer's current lap, on the same scale as _expected_ordinal.
func _route_ordinal(ckpt: CheckPointMarker, p: Dictionary) -> int:
	var lap_ordinal: int = p["laps_done"] * (lap_checkpoints.size() + 2)
	if lap_checkpoints.has(ckpt):
		return lap_ordinal + 1 + lap_checkpoints.find(ckpt)
	if ckpt == end_checkpoint and p["waiting_for"] != WaitFor.START:
		return lap_ordinal + 1 + lap_checkpoints.size()
	return lap_ordinal


func _check_wrong_way(player: PlayerEntity, peer_id: int, p: Dictionary) -> void:
	var to_gate := _expected_checkpoint(p).global_position - player.global_position
	var dist := to_gate.length()
	p["best_dist"] = minf(p["best_dist"], dist)
	var heading_away := (
		player.velocity.length() > WRONG_WAY_MIN_SPEED and player.velocity.dot(to_gate) < 0.0
	)
	var wrong_way: bool = heading_away and dist - p["best_dist"] >= wrong_way_margin
	var was_wrong_way: bool = p["wrong_way_since_ms"] > 0
	if wrong_way == was_wrong_way:
		if wrong_way and Time.get_ticks_msec() - p["wrong_way_since_ms"] >= WRONG_WAY_RESPAWN_MS:
			runner.spawn_manager.respawn_player.rpc(peer_id)
			# Measure from the respawn gate, not the wrong-way spot.
			p["best_dist"] = INF
			p["wrong_way_since_ms"] = 0
			runner.riding_hud.clear_event_warning(peer_id)
		return
	if wrong_way:
		p["wrong_way_since_ms"] = Time.get_ticks_msec()
		runner.riding_hud.push_event_warning(peer_id, "RACE_WRONG_WAY", true)
	else:
		p["wrong_way_since_ms"] = 0
		runner.riding_hud.clear_event_warning(peer_id)


## Ranking key for one racer — higher is further ahead. Finished racers rank by time,
## the rest by route progress, then distance to their next gate.
func get_progress_key(racer_id: int, racer_pos: Vector3) -> float:
	var p := peer_progress[racer_id]
	if p.has("completion_time_ms"):
		return 1e12 - p["completion_time_ms"]
	var dist := racer_pos.distance_to(_expected_checkpoint(p).global_position)
	return _expected_ordinal(p) * 1e6 - dist


## 1-based race position among all live racers, humans and NPCs.
func get_race_position(racer_id: int) -> int:
	var keys := _live_progress_keys()
	var pos := 1
	for id in keys:
		if keys[id] > keys[racer_id]:
			pos += 1
	return pos


## racer_id -> get_progress_key for every racer in the scene.
func _live_progress_keys() -> Dictionary[int, float]:
	var keys: Dictionary[int, float] = {}
	for racer in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Racers"]):
		var id := int(racer.name)
		# Traffic and disconnected/stale rows aren't competitors — skip is intentional.
		if racer.is_in_group(UtilsConstants.GROUPS["Traffic"]) or !peer_progress.has(id):
			continue
		keys[id] = get_progress_key(id, (racer as Node3D).global_position)
	return keys


## "P2/6".
func _position_text(peer_id: int) -> String:
	var total := _live_progress_keys().size()
	return tr("RACE_POSITION").format({"pos": get_race_position(peer_id), "total": total})


func _after_start_or_lap_advance(p: Dictionary) -> void:
	if p["next_lap_idx"] < lap_checkpoints.size():
		p["waiting_for"] = WaitFor.LAP_CP
	else:
		p["waiting_for"] = WaitFor.END


## Point-to-point (one lap) shows just the running clock; endless shows the current lap, no place.
func _push_lap_hud(peer_id: int, p: Dictionary) -> void:
	if endless:
		var lap_text := format_time_ms(get_lap_elapsed_ms(peer_id))
		if !is_point_to_point():
			lap_text = tr("RACE_LAP_ENDLESS").format({"current": p["laps_done"] + 1, "time": lap_text})
		runner.riding_hud.push_event_progress(peer_id, lap_text)
		return
	var current_lap: int = min(p["laps_done"] + 1, total_laps)
	var text := format_time_ms(Time.get_ticks_msec() - p["start_ms"])
	if total_laps > 1:
		text = tr("RACE_LAP").format({"current": current_lap, "total": total_laps, "time": text})
	runner.riding_hud.push_event_progress(peer_id, "%s  -  %s" % [_position_text(peer_id), text])


## "m:ss.cc".
static func format_time_ms(ms: int) -> String:
	return "%d:%05.2f" % [ms / 60000, (ms % 60000) / 1000.0]


func _tick_restart_countdown(player: PlayerEntity, peer_id: int, p: Dictionary) -> void:
	var remaining_ms: int = p["countdown_end_ms"] - Time.get_ticks_msec()
	if remaining_ms > 0:
		runner.riding_hud.push_event_progress(peer_id, str(ceili(remaining_ms / 1000.0)))
		return
	p["countdown_end_ms"] = 0
	p["lap_start_ms"] = Time.get_ticks_msec()
	CountdownTask.unfreeze(player)


@rpc("call_local", "reliable")
func _rpc_play_countdown_sfx() -> void:
	runner.audio_manager.play_sfx(AudioManager.Sfx.COUNTDOWN_3SEC)


## Local-only feedback: visibility is per-client, other racers' gates are untouched.
@rpc("call_local", "reliable")
func _rpc_checkpoint_passed(ckpt_idx: int, upcoming: PackedInt32Array) -> void:
	runner.audio_manager.play_mouse_click()
	runner.route.show_only_checkpoints(upcoming, ckpt_idx)


@rpc("call_local", "reliable")
func _rpc_reset_checkpoints() -> void:
	runner.route.show_only_checkpoints(START_CHECKPOINTS)


#endregion


## Route checks live on GameModeEvent / EventRoute — they see both the task and the route.
func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if !endless and total_laps <= 0:
		issues.append("total_laps must be > 0")
	return issues
