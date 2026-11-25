@tool
## Bonus ramps: one Ramp in the level at a time asks for a trick ("BACKFLIP HERE 10x" over it, gold,
## and a marker on the compass strip). Taking off from its lip and landing that trick clean banks
## the trick's score x score_mult. Ramp and trick rotate every rotate_secs. Players only (bots
## can't aim for a ramp). Only Ramp.trick_spot ramps get picked (not the Ramp item).
class_name BonusRampComponent extends RaceComponent

@export var trick_manager: TrickManager
@export var trick_pool: Array[TrickController.Trick] = [
	TrickController.Trick.BACKFLIP,
	TrickController.Trick.FRONTFLIP,
	TrickController.Trick.KICKFLIP,
	TrickController.Trick.HEELFLIP,
	TrickController.Trick.SUPERMAN,
	TrickController.Trick.SPREAD_EAGLE,
]
@export var rotate_secs: float = 30.0
@export var score_mult: int = 10
## Leaving the ground within this many metres of the bonus ramp's lip counts as taking it.
@export var takeoff_radius: float = 10.0

## Server: the level's ramps at the race start, and the bonus one's index (-1 = none).
var _ramps: Array[Node] = []
var _ramp_index: int = -1
var _trick: TrickController.Trick = TrickController.Trick.NONE
var _rotate_left: float = 0.0
## Server: peer_id -> this jump's {"airborne", "from_ramp", "did_trick"}.
var _jumps: Dictionary[int, Dictionary] = {}
## Every peer: the ramp showing the bonus label.
var _shown: Ramp = null


func race_runner_start() -> void:
	_ramps.assign(_level().find_children("*", "Ramp", true, false).filter(func(r): return r.trick_spot))
	_ramp_index = -1
	_rotate_left = 0.0
	_jumps.clear()


func tick(delta: float) -> void:
	if _ramps.is_empty():
		return
	_rotate_left -= delta
	if _rotate_left <= 0.0:
		_rotate_left = rotate_secs
		_rotate()
	var ramp: Ramp = _ramps[_ramp_index]
	for peer_id in race_mode.lobby_manager.lobby_players:
		var player := race_mode.spawn_manager.get_player_by_peer_id(peer_id)
		# Late joiner not spawned yet — skip is intentional
		if player != null:
			_track_jump(peer_id, player, ramp)


func race_end() -> void:
	_ramps.clear()
	_ramp_index = -1
	_rpc_set_bonus.rpc(NodePath(), TrickController.Trick.NONE)


func _rotate() -> void:
	var next := randi() % _ramps.size()
	if _ramps.size() > 1 and next == _ramp_index:
		next = (next + 1) % _ramps.size()
	_ramp_index = next
	_trick = trick_pool.pick_random()
	_rpc_set_bonus.rpc(_level().get_path_to(_ramps[_ramp_index]), _trick)


## A jump counts from the bonus ramp if it left the ground near the lip; it pays on a clean landing
## if the bonus trick showed at any point in the air.
func _track_jump(peer_id: int, player: PlayerEntity, ramp: Ramp) -> void:
	var jump: Dictionary = _jumps.get_or_add(peer_id, {"airborne": false})
	if !player.movement_controller.is_on_floor and !player.is_crashed:
		if !jump["airborne"]:
			jump["airborne"] = true
			jump["from_ramp"] = player.global_position.distance_to(ramp.lip_position()) < takeoff_radius
			jump["did_trick"] = false
		if player.trick_controller.current_trick == _trick:
			jump["did_trick"] = true
		return
	if jump["airborne"] and jump["from_ramp"] and jump["did_trick"] and !player.is_crashed:
		var base: float = ComboRules.ONE_TIME_TRICK_SCORE.get(_trick, ComboRules.HELD_TRICK_SCORE.get(_trick, 1.0))
		var points := base * trick_manager.points_per_second * score_mult
		trick_manager.add_points(peer_id, points)
		race_mode.riding_hud_state.push_callout(
			peer_id, tr("CALLOUT_BONUS_RAMP").format({"points": int(points)})
		)
	jump["airborne"] = false


func _level() -> Node:
	return race_mode.gamemode_manager.level_manager.current_level


## Every peer: move the bonus label + compass marker. Empty path clears them.
@rpc("call_local", "reliable")
func _rpc_set_bonus(ramp_path: NodePath, trick: int) -> void:
	if is_instance_valid(_shown):
		_shown.spot_label.set_bonus("")
	_shown = null
	var minimap := race_mode.riding_hud_state.minimap
	minimap.has_bonus_ramp = !ramp_path.is_empty()
	if ramp_path.is_empty():
		return
	_shown = _level().get_node(ramp_path)
	var trick_name := tr("TRICK_NAME_" + TrickController.trick_to_str(trick)).to_upper()
	_shown.spot_label.set_bonus(
		tr("BONUS_RAMP_LABEL").format({"trick": trick_name, "mult": score_mult})
	)
	minimap.bonus_ramp_pos = _shown.lip_position()


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if trick_manager == null:
		issues.append("trick_manager must not be empty")
	return issues
