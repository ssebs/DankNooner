@tool
## Race body task — per-peer lap + checkpoint tracking for street race.
##
## Watches multiple CheckPointMarkers directly via their `entered` signal
## instead of using the runner's single-`trigger` system.
##
## Per-lap sequence: start_checkpoint -> lap_checkpoints[0..N] -> end_checkpoint.
## When end_checkpoint == start_checkpoint, crossing it ends one lap and (if
## more remain) immediately starts the next.
##
## On every recognized checkpoint crossing, the player's persistent respawn
## transform is updated to that marker (same mechanism as TeleportTask), so
## crashes return to the last checkpoint passed.
class_name RaceTask extends GameModeTask

enum WaitFor { START, LAP_CP, END }

@export var start_checkpoint: CheckPointMarker
@export var lap_checkpoints: Array[CheckPointMarker] = []
@export var end_checkpoint: CheckPointMarker
@export var total_laps: int = 3
@export var objective_key: String = "RACE_OBJECTIVE"

## Per-racer progress (humans AND NPCs — RaceTask is the single scoring source
## of truth, keyed by racer id; NPC ids are negative). RaceTask owns this
## directly — the runner's per-peer scratchpad isn't reachable from signal
## callbacks.
##   racer_id -> { "laps_done": int, "next_lap_idx": int, "waiting_for": WaitFor,
##                 "start_ms": int, ["completion_time_ms": int],
##                 ["respawn_ckpt": CheckPointMarker  (NPC rows only)] }
var _peer_progress: Dictionary[int, Dictionary] = {}
var _signals_wired: bool = false
## False until the race body actually starts (first human on_enter) — NPCs are
## registered earlier, at gamemode Enter, and must hold at the grid until then.
var _race_active: bool = false


func _init():
	eval_when = EvalWhen.ALWAYS


func on_enter(player: PlayerEntity, _state: Dictionary) -> void:
	if !_signals_wired:
		_wire_checkpoint_signals()
		_signals_wired = true
	if !_race_active:
		_race_active = true
		# NPCs were registered back at gamemode Enter (before grid/countdown) —
		# start their clocks together with the humans'. Human rows surviving
		# from a previous run are stale — drop them (this run's peers get fresh
		# rows below).
		for id in _peer_progress.keys():
			if id < 0:
				_peer_progress[id]["start_ms"] = Time.get_ticks_msec()
			else:
				_peer_progress.erase(id)
	var peer_id := int(player.name)
	_peer_progress[peer_id] = {
		"laps_done": 0,
		"next_lap_idx": 0,
		"waiting_for": WaitFor.START,
		"start_ms": Time.get_ticks_msec(),
	}
	# Runner pushes rpc_show_step right after on_enter — defer the hide so it
	# runs after that, otherwise the step label re-shows.
	var hud := _runner.task_hud
	(func(): hud.rpc_hide_step_label.rpc_id(peer_id)).call_deferred()


func check(player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	var peer_id := int(player.name)
	var p := _peer_progress[peer_id]
	if p["laps_done"] >= total_laps:
		return true
	_push_lap_hud(peer_id, p)
	return false


func on_exit(_player: PlayerEntity, _state: Dictionary) -> void:
	# Keep the finished row — results read completion_time_ms from here after
	# the runner stops (single scoring source for humans + NPCs). Stale rows
	# are purged at the next race start in on_enter.
	pass


func get_objective_text() -> String:
	return tr(objective_key)


func get_hint_text() -> String:
	# Empty — dynamic lap/timer text is pushed each frame via rpc_update_progress.
	return ""


#region NPC racers (server-side, driven by StreetRaceGameMode / NPCRaceManager)


## Adds an NPC row so checkpoint crossings score it like any peer. Called at
## gamemode Enter — before the race body starts — so this also resets
## _race_active, holding NPCs at the grid until the first human on_enter.
func register_npc(npc_id: int) -> void:
	_race_active = false
	_peer_progress[npc_id] = {
		"laps_done": 0,
		"next_lap_idx": 0,
		"waiting_for": WaitFor.START,
		"start_ms": Time.get_ticks_msec(),
	}


func unregister_npc(npc_id: int) -> void:
	_peer_progress.erase(npc_id)


## The checkpoint an NPC should navigate toward. Null while the race body
## hasn't started (grid/countdown) or once the NPC has finished — the caller
## holds position. One event, two jobs: the same crossing that scores the lap
## also retargets navigation.
func get_target_checkpoint(npc_id: int) -> CheckPointMarker:
	if !_race_active:
		return null
	var p := _peer_progress[npc_id]
	if p["laps_done"] >= total_laps:
		return null
	return _expected_checkpoint(p)


## Last checkpoint the NPC passed — its crash respawn point. Null until the
## first crossing; caller falls back to the spawn grid slot.
func get_npc_respawn_checkpoint(npc_id: int) -> CheckPointMarker:
	return _peer_progress[npc_id].get("respawn_ckpt")


#endregion


#region Checkpoint signal wiring


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
	if !_peer_progress.has(peer_id):
		return
	var p := _peer_progress[peer_id]
	# Finished racers keep their row for results — don't let victory laps
	# advance the state or overwrite the recorded time.
	if p.has("completion_time_ms"):
		return
	var expected := _expected_checkpoint(p)
	if ckpt != expected:
		DebugUtils.DebugMsg(
			"RaceTask: peer %d hit %s out of order (expected %s)"
			% [peer_id, ckpt.name, expected.name if expected else "null"]
		)
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
		_runner.spawn_manager.set_respawn_point.rpc(
			peer_id, ckpt.global_position, ckpt.global_basis
		)

	match p["waiting_for"]:
		WaitFor.START:
			_after_start_or_lap_advance(p)
		WaitFor.LAP_CP:
			p["next_lap_idx"] += 1
			_after_start_or_lap_advance(p)
		WaitFor.END:
			p["laps_done"] += 1
			p["next_lap_idx"] = 0
			if p["laps_done"] >= total_laps:
				# Racer done (check() returns true next frame for humans).
				# RaceTask is the scoring source of truth for every racer —
				# record the time here for humans and NPCs alike.
				p["completion_time_ms"] = Time.get_ticks_msec() - p["start_ms"]
			elif end_checkpoint == start_checkpoint:
				# Same marker doubles as the next lap's start crossing — go straight to lap CPs.
				p["waiting_for"] = WaitFor.LAP_CP if !lap_checkpoints.is_empty() else WaitFor.END
			else:
				p["waiting_for"] = WaitFor.START


func _after_start_or_lap_advance(p: Dictionary) -> void:
	if p["next_lap_idx"] < lap_checkpoints.size():
		p["waiting_for"] = WaitFor.LAP_CP
	else:
		p["waiting_for"] = WaitFor.END


func _push_lap_hud(peer_id: int, p: Dictionary) -> void:
	var current_lap: int = min(p["laps_done"] + 1, total_laps)
	var elapsed_ms: int = Time.get_ticks_msec() - p["start_ms"]
	var minutes := elapsed_ms / 60000
	var secs := (elapsed_ms % 60000) / 1000.0
	var time_str := "%d:%05.2f" % [minutes, secs]
	var text := tr("RACE_LAP").format(
		{"current": current_lap, "total": total_laps, "time": time_str}
	)
	_runner.task_hud.rpc_update_progress.rpc_id(peer_id, text)


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if start_checkpoint == null:
		issues.append("start_checkpoint must be set")
	if end_checkpoint == null:
		issues.append("end_checkpoint must be set")
	if lap_checkpoints.is_empty():
		issues.append("lap_checkpoints should not be empty")
	if total_laps <= 0:
		issues.append("total_laps must be > 0")
	return issues
