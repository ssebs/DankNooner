@tool
## Server-authoritative trick scoring.
##
## The per-tick half of the system (combo timer, multiplier, boost fill) lives in
## TrickController's rollback tick — those are netfox state properties, and
## RollbackSynchronizer re-applies every state property from history each tick, so a manager
## writing them in _process() gets silently overwritten before anything accumulates.
##
## This manager watches those synced values and banks a SCORE when a combo ends, which keeps
## scoring out of the rollback path entirely (no resimulation double-counting) and keeps the
## rules in one gamemode-agnostic place. Gamemodes read get_score(peer_id) and clear with
## reset_peer(peer_id). Bonus tricks (set_bonus_tricks) score 2x, already in get_score.
class_name TrickManager extends BaseManager

## Emitted (server) when a combo ends cleanly and its score is banked.
signal combo_banked(peer_id: int, points: float, duration: float, multiplier: int)
## Emitted (server) when a crash voids an in-progress combo — nothing was banked.
signal combo_voided(peer_id: int, lost_duration: float, lost_points: float)

@export var spawn_manager: SpawnManager
@export var gamemode_manager: GamemodeManager
@export var riding_hud_state: RidingHUDState

@export_group("Scoring")
## Points per unit of TrickController.combo_score (a 1.0 held trick earns this per second), before
## the multiplier.
@export var points_per_second: float = 10.0

## peer_id -> {"points", "prev_time", "prev_score", "bonus_score", "peak_mult"}
var _peer_states: Dictionary[int, Dictionary] = {}
## peer_id -> tricks whose combo_score counts twice. Apart from _peer_states so reset_peer (every
## spawn) keeps it.
var _bonus_tricks: Dictionary[int, PackedInt32Array] = {}


func _ready():
	if Engine.is_editor_hint():
		return

	spawn_manager.player_spawned.connect(_on_player_spawned)
	gamemode_manager.player_disconnected.connect(_on_player_disconnected)
	gamemode_manager.match_ended.connect(_on_match_ended)


func _process(_delta: float):
	if Engine.is_editor_hint():
		return
	if multiplayer.multiplayer_peer == null or !multiplayer.is_server():
		return

	for peer_id in _peer_states:
		# Player despawns (level swap / disconnect) before its row is cleared — skip until
		# _on_player_disconnected catches up.
		var player := spawn_manager.get_player_by_peer_id(peer_id)
		if player == null:
			continue
		_track_combo(peer_id, player)


## Watch a peer's synced combo state; bank the run the frame it drops back to zero.
##
## Crashing voids the run outright — no partial credit. Checked before the combo_time test
## because a crash freezes combo_time (the rollback tick bails on is_crashed) and only zeroes
## it at the respawn; without this the run would bank on the way down like a clean finish.
func _track_combo(peer_id: int, player: PlayerEntity):
	var st := _peer_states[peer_id]

	if player.is_crashed:
		if st["prev_time"] > 0.0:
			combo_voided.emit(peer_id, st["prev_time"], get_open_combo_points(peer_id))
			st["prev_time"] = 0.0
			st["prev_score"] = 0.0
			st["bonus_score"] = 0.0
			st["peak_mult"] = 1
		return

	var tc := player.trick_controller
	var elapsed: float = tc.combo_time

	if elapsed > 0.0:
		st["peak_mult"] = maxi(st["peak_mult"], tc.combo_multiplier)
		st["prev_time"] = elapsed
		# This frame's combo_score growth belongs to the trick held now; a bonus trick's counts again.
		if tc.current_trick in _bonus_tricks.get(peer_id, PackedInt32Array()):
			st["bonus_score"] += tc.combo_score - st["prev_score"]
		st["prev_score"] = tc.combo_score
		return

	if st["prev_time"] <= 0.0:
		return

	var duration: float = st["prev_time"]
	var multiplier: int = st["peak_mult"]
	var bonus: bool = st["bonus_score"] > 0.0
	var points: float = get_open_combo_points(peer_id)
	st["points"] += points
	st["prev_time"] = 0.0
	st["prev_score"] = 0.0
	st["bonus_score"] = 0.0
	st["peak_mult"] = 1
	combo_banked.emit(peer_id, points, duration, multiplier)
	riding_hud_state.push_score_popup(peer_id, int(points), multiplier, bonus)


#region public api
## Total points this peer has banked since their last reset_peer().
func get_score(peer_id: int) -> float:
	return _peer_states[peer_id]["points"]


## What the combo in progress would bank if it ended now (0 when none is open).
func get_open_combo_points(peer_id: int) -> float:
	var st := _peer_states[peer_id]
	return (st["prev_score"] + st["bonus_score"]) * points_per_second * st["peak_mult"]


## True while a combo is running or ended but not yet banked.
func is_combo_open(peer_id: int) -> bool:
	return _peer_states[peer_id]["prev_time"] > 0.0


## Wipe a peer's banked score. Gamemodes call this when a run starts.
func reset_peer(peer_id: int):
	_peer_states[peer_id] = {
		"points": 0.0,
		"prev_time": 0.0,
		"prev_score": 0.0,
		"bonus_score": 0.0,
		"peak_mult": 1,
	}


## Tricks that score 2x for this peer (SuggestedTricksChallenge). Empty to clear.
func set_bonus_tricks(peer_id: int, tricks: PackedInt32Array):
	_bonus_tricks[peer_id] = tricks
#endregion


#region handlers
func _on_player_spawned(player: PlayerEntity):
	if !multiplayer.is_server():
		return
	reset_peer(int(str(player.name)))


func _on_player_disconnected(peer_id: int):
	_peer_states.erase(peer_id)
	_bonus_tricks.erase(peer_id)


## Match teardown — drop every peer's scoring row so it can't outlive the match into a menu
## level (whose current_level has no player_spawn_pos), which would crash the _process scan.
func _on_match_ended():
	_peer_states.clear()
	_bonus_tricks.clear()
#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if spawn_manager == null:
		issues.append("spawn_manager must not be empty")
	if gamemode_manager == null:
		issues.append("gamemode_manager must not be empty")
	if riding_hud_state == null:
		issues.append("riding_hud_state must not be empty")

	return issues
