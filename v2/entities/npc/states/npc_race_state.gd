@tool
## Racing behavior for NPCRiderEntity: ride the shared NPCRacingLine on this bot's own braking
## profile, offset sideways by a lateral that wanders over the lap. A bot knocked well off the
## line navmesh-paths back onto it. Crashes by the player's rules, dumbed down (see _detect_crash).
## NPCRaceManager toggles `npc.driving`, hands over the line once it's baked, and owns the
## crash/respawn timers.
##
## Anti-train: bots must never ride one line nose to tail. Each rolls its own style (corner
## carry, braking, reaction) and wander off its name, so their offsets drift apart rather than
## running parallel.
class_name NPCRaceState extends State

## Wedged and making no progress — NPCRaceManager wipes the bot out and puts it back on
## its last checkpoint. A graybox parked on the line or a barrier the navmesh missed can
## still pin a bot; traffic has had this since day one.
signal stuck
## Went down: hit a wall, rode into a racer (victim, else null), or got rammed. NPCRaceManager
## takes the victim down too, since it never sees the collision from its side.
signal crashed(victim: Node3D)

enum Mistake { NONE, LATE_BRAKE, RUN_WIDE }

@export var npc: NPCRiderEntity
## 0 = easiest, 1 = hardest, 0.5 = the base tuning. Scales speed / corner carry / braking /
## wander / mistakes. NPCRaceManager sets it at spawn; applied once on Enter.
@export_range(0.0, 1.0) var skill: float = 0.5
## Off = ride the line with wander only — flip off to isolate overtaking issues.
@export var enable_overtaking: bool = true
## Widest the wander strays from the line, as a fraction of the road room on that side.
@export var wander_fraction: float = 0.6
## Rough metres along the line per wander cycle; each bot rolls its own around this.
@export var wander_wavelength: float = 250.0
## Per-bot spread (± fraction) on corner carry, braking and steering reaction.
@export var style_spread: float = 0.1
## How fast (m/s) the lateral offset follows its target: the bot's steering reaction.
@export var offset_response: float = 2.0
## Most the bot may cut inside the line (m) chasing its steer point; bends shorten the lookahead.
@export var max_corner_cut: float = 0.5
## Further than this (m) from its spot on the line, the bot paths back instead of steering at it.
@export var rejoin_distance: float = 6.0
## How far ahead on the line (m) a rejoin aims, so the bot merges rather than turning square on.
@export var rejoin_lookahead: float = 25.0
## Report stuck after covering less than stuck_min_progress metres over stuck_window
## seconds. Generous on purpose — a slow crawl out of a hairpin must not read as wedged.
@export var stuck_window: float = 3.0
@export var stuck_min_progress: float = 2.0
## Forward scan for riders ahead: seconds of travel it reaches (never short of avoid_min_range),
## and its half width. A rider within avoid_lane_half_width of our offset is in our way.
@export var avoid_lookahead_time: float = 1.5
@export var avoid_min_range: float = 8.0
@export var avoid_scan_half_width: float = 6.0
@export var avoid_lane_half_width: float = 1.2
## A rider within this many metres fore or aft is alongside: our offset stops overtake_clearance
## short of its line instead of riding into it.
@export var alongside_length: float = 4.0
## Overtaking: how far beside the rider ahead to pass, and how long to commit to that side.
@export var overtake_clearance: float = 2.2
@export var overtake_commit_time: float = 2.5
## Average seconds between mistakes and how long one lasts: a late brake reads the speed
## late_brake_distance behind, running wide pushes out by run_wide_fraction of the outside room.
@export var mistake_interval: float = 30.0
@export var mistake_duration: float = 1.5
@export var late_brake_distance: float = 15.0
@export var run_wide_fraction: float = 0.4
## Chance a landing after a real jump (past air_trick_min_airtime, so crests never roll it) crashes
## the bot. Bots almost always land.
@export var bad_landing_chance: float = 0.02

@export_group("Tricks")
## Metres of line ahead the bot must be able to take flat out to wheelie or boost.
@export var straight_distance: float = 60.0
## Average seconds between wheelies while the line ahead is straight, and how long one lasts.
@export var wheelie_interval: float = 6.0
@export var wheelie_min_secs: float = 1.5
@export var wheelie_max_secs: float = 4.0
## Share of wheelies spent in a held wheelie trick (TrickController.BINDINGS' wheelie holds).
@export var mod_wheelie_chance: float = 0.25
## Shortest airtime worth a trick (predicted at takeoff) or a bad-landing roll (measured); road crests
## launch too.
@export var air_trick_min_airtime: float = 0.4
## Share of real jumps the bot tricks off, and the share of those that are flips when it has time.
@export var air_trick_chance: float = 0.8
@export var flip_chance: float = 0.3
## Chance landing out of an air trick bails: a crash that voids the combo.
@export var trick_bail_chance: float = 0.04

## Racer bodies carry this layer, and so do traffic ContactAreas (traffic has no body).
const CRASH_COLLISION_MASK: int = 2  # 1 << 1 (layer 2)
const SCAN_HEIGHT: float = 2.0
const MAX_SCAN_RESULTS: int = 32


## Set by NPCRaceManager once the bake lands; null until then and the bot holds on the grid.
var racing_line: NPCRacingLine:
	set(value):
		racing_line = value
		# Before Enter the style isn't rolled yet — Enter fits the line itself
		if racing_line != null and _style_rolled:
			_fit_to_line()

var _style_rolled: bool = false
## Per-bot style, rolled on Enter (see style_spread).
var _corner_carry: float = 1.0
var _brake_scale: float = 1.0
var _reaction: float = 1.0
var _wander_phase := PackedFloat32Array([0.0, 0.0])
var _wander_length := PackedFloat32Array([1.0, 1.0])
## This bot's target speed per line sample: the line's corner speeds through its own braking.
var _profile := PackedFloat32Array()
## Progress along the line (m) and current sideways offset from it (m, + = right).
var _s: float = 0.0
var _lateral: float = 0.0
## Navmesh path to the current steer goal: where it was asked from, its corners, its end.
var _path := PackedVector3Array()
## Last forward scan, reused until the next (see NPCRiderEntity.scan_interval_min): each rider
## ahead with its distance along our heading and its sideways offset from the line.
var _ahead_riders: Array[Node3D] = []
var _ahead_dist := PackedFloat32Array()
var _ahead_lateral := PackedFloat32Array()
var _scan_next_ms: int = 0
var _scan_box := BoxShape3D.new()
var _scan_query := PhysicsShapeQueryParameters3D.new()
var _overtake_lateral: float = 0.0
var _overtake_until_ms: int = 0
var _mistake: Mistake = Mistake.NONE
var _mistake_until_ms: int = 0
var _next_mistake_ms: int = 0
var _path_next_ms: int = 0
var _stuck_timer: float = 0.0
var _air_time: float = 0.0
## Left the ground moving up (a ramp lip), not off a bump or another bike.
var _launched: bool = false
## Vertical speed at takeoff, for the airtime prediction.
var _launch_vy: float = 0.0
## Started an air trick this jump, so the landing may bail.
var _air_tricked: bool = false
var _wheelie_left: float = 0.0
var _stuck_anchor: Vector3
var _dbg_drive := ""  # DEBUG: temp - last tick's steering, printed when stuck fires
var _dbg_log_drive := false  # DEBUG: temp - print the first drive tick after a reset


func Enter(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	_roll_style()
	if racing_line != null:
		_fit_to_line()
	_scan_query.shape = _scan_box
	_scan_query.collide_with_areas = true
	_scan_query.collision_mask = CRASH_COLLISION_MASK
	_scan_query.exclude = [npc.get_rid(), npc.contact_area.get_rid()]
	_next_mistake_ms = Time.get_ticks_msec() + _mistake_gap_ms()
	_stuck_timer = 0.0
	_stuck_anchor = npc.global_position
	npc.hit_by_racer.connect(_on_hit_by_racer)


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	npc.hit_by_racer.disconnect(_on_hit_by_racer)


func Physics_Update(delta: float):
	if Engine.is_editor_hint():
		return

	var can_drive := _can_drive()
	if can_drive:
		var t := Time.get_ticks_usec()  # PROF: temp
		_drive(delta)
		DebugUtils.Prof("npc.race_drive", t)  # PROF: temp
	else:
		npc.coast_to_stop(delta)

	npc.apply_gravity_and_move(delta)

	# Only while it's actually trying to move — sitting on the grid or waiting out the
	# countdown is not being stuck, or crashing.
	if can_drive:
		_update_tricks(delta)
		_detect_landing(delta)
		_detect_crash()
		_check_stuck(delta)


func _can_drive() -> bool:
	return (
		npc.driving
		and racing_line != null
		and npc.npc_state != NPCRiderEntity.NPCState.CRASHED
		and npc.npc_state != NPCRiderEntity.NPCState.FINISHED
	)


## Re-find this bot on the line after a teleport (grid, crash respawn). It keeps the sideways offset
## it's standing at: zeroing it sent a whole grid at one point on the line, where they piled up.
func reset_line_progress() -> void:
	_s = racing_line.closest_offset(npc.global_position)
	var side := (npc.global_position - racing_line.point_at(_s)).dot(racing_line.right_at(_s))
	_lateral = clampf(side, -racing_line.half_width_at(_s, -1.0), racing_line.half_width_at(_s, 1.0))
	DebugUtils.DebugMsg(  # DEBUG: temp
		"[npc %s] RESET pos=%s s=%.1f side=%.2f lat=%.2f room L/R=%.1f/%.1f"  # DEBUG: temp
		% [npc.name, npc.global_position, _s, side, _lateral,  # DEBUG: temp
		racing_line.half_width_at(_s, -1.0), racing_line.half_width_at(_s, 1.0)]  # DEBUG: temp
	)  # DEBUG: temp
	_dbg_log_drive = true  # DEBUG: temp
	_path.clear()
	_air_time = 0.0
	_air_tricked = false
	_wheelie_left = 0.0
	_stuck_timer = 0.0
	_stuck_anchor = npc.global_position


## Seeded off the bot's name, salted so it doesn't repeat the entity's own hash(name) roll.
func _roll_style() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(npc.name) + "race_style")
	_corner_carry = rng.randf_range(1.0 - style_spread, 1.0 + style_spread)
	_brake_scale = rng.randf_range(1.0 - style_spread, 1.0 + style_spread)
	_reaction = rng.randf_range(1.0 - style_spread, 1.0 + style_spread)
	for i in 2:
		_wander_phase[i] = rng.randf() * TAU
	# Two waves of unrelated length, so the sum never settles into a visible period
	_wander_length[0] = wander_wavelength * rng.randf_range(0.7, 1.3)
	_wander_length[1] = wander_wavelength * rng.randf_range(0.3, 0.5)
	_apply_difficulty()
	_style_rolled = true


## Scale the base tuning and this bot's style by skill.
func _apply_difficulty() -> void:
	npc.move_speed *= _skill_scale(0.82, 1.12)
	npc.min_turn_speed *= _skill_scale(0.85, 1.15)
	_corner_carry *= _skill_scale(0.9, 1.08)
	_brake_scale *= _skill_scale(0.85, 1.1)
	wander_fraction *= _skill_scale(1.2, 0.5)
	mistake_interval *= _skill_scale(0.6, 2.0)
	bad_landing_chance *= _skill_scale(2.0, 0.5)
	trick_bail_chance *= _skill_scale(2.0, 0.5)


## easy at skill 0, 1.0 (the base tuning) at 0.5, hard at 1.
func _skill_scale(easy: float, hard: float) -> float:
	if skill < 0.5:
		return lerpf(easy, 1.0, skill * 2.0)
	return lerpf(1.0, hard, skill * 2.0 - 1.0)


func _fit_to_line() -> void:
	_profile = racing_line.braking_profile(npc.braking * _brake_scale, _corner_carry)
	if racing_line.closed:
		# A whole number of cycles per lap, so the offset doesn't jump at the start/finish
		var lap := racing_line.get_length()
		for i in 2:
			_wander_length[i] = lap / maxf(1.0, roundf(lap / _wander_length[i]))
	reset_line_progress()


func _drive(delta: float) -> void:
	var pos := npc.global_position
	var now := Time.get_ticks_msec()
	_s = racing_line.track_offset(pos, _s, npc.max_steer_lookahead * 2.0)
	_scan_ahead(pos, now)
	_update_mistake(now)
	var speed_cap := _avoid(now)

	var steer_s := _s + _steer_lookahead()
	var lateral_target := _clear_of_alongside(_lateral_target(steer_s, now))
	_lateral = move_toward(_lateral, lateral_target, offset_response * _reaction * delta)
	var spot := racing_line.point_at(_s) + racing_line.right_at(_s) * _lateral
	var goal: Vector3
	var off_line := Vector2(spot.x - pos.x, spot.z - pos.z).length()
	var rejoining := off_line > rejoin_distance
	if rejoining:
		goal = racing_line.point_at(_s + rejoin_lookahead)
	else:
		goal = _steer_point(steer_s)
	var target := _path_target(pos, goal)

	var speed_s := _s - late_brake_distance if _mistake == Mistake.LATE_BRAKE else _s
	var line_speed := maxf(npc.min_turn_speed, racing_line.profile_speed(_profile, speed_s))
	var target_speed := minf(speed_cap, minf(npc.cruise_speed(), line_speed))
	npc.steer_toward(target, target_speed, delta)
	_dbg_drive = (  # DEBUG: temp
		"floor=%s wall=%s s=%.1f line_pt=%s off_line=%.1f lat=%.2f rejoin=%s target=%s speed=%.1f/%.1f path=%s"  # DEBUG: temp
		% [npc.is_on_floor(), npc.is_on_wall(), _s, racing_line.point_at(_s), off_line, _lateral,  # DEBUG: temp
		rejoining, target,  # DEBUG: temp
		npc.current_speed, target_speed, _path.slice(0, 4)]  # DEBUG: temp
	)  # DEBUG: temp
	if _dbg_log_drive:  # DEBUG: temp
		_dbg_log_drive = false  # DEBUG: temp
		DebugUtils.DebugMsg("[npc %s] FIRST DRIVE goal=%s %s" % [npc.name, goal, _dbg_drive])  # DEBUG: temp


## Our offset's point on the line at s, walked back toward the line until it's on the nav map.
## Snapping it straight to the closest point puts it on the near rim of a small hole (a pole),
## aiming the bot head-on at it. Whole nav map, so dodges may still cross grass, never a wall.
func _steer_point(s: float) -> Vector3:
	var map := npc.get_world_3d().navigation_map
	var line_point := racing_line.point_at(s)
	var right := racing_line.right_at(s)
	var lateral := _lateral
	var ahead := line_point + right * lateral
	var on_map := NavigationServer3D.map_get_closest_point(map, ahead)
	while (
		_flat(on_map - ahead).length() > NPCRacingLine.ROOM_STEP * 0.5
		and absf(lateral) > NPCRacingLine.ROOM_STEP
	):
		lateral = move_toward(lateral, 0.0, NPCRacingLine.ROOM_STEP)
		ahead = line_point + right * lateral
		on_map = NavigationServer3D.map_get_closest_point(map, ahead)
	return on_map


## The speed-based lookahead, shortened through bends: chasing a point L ahead on curvature k
## cuts inside the line by about L²·k/2, so L is capped to keep that under max_corner_cut.
func _steer_lookahead() -> float:
	var lookahead := npc.steer_lookahead()
	var k := maxf(racing_line.peak_curvature(_s, lookahead), NPCRacingLine.MIN_CURVATURE)
	return maxf(minf(lookahead, sqrt(2.0 * max_corner_cut / k)), npc.min_steer_lookahead)


## Where the lateral offset is heading at line offset s (m, + = right): a committed overtake,
## else the wander, pushed to the outside of the corner while running wide.
func _lateral_target(s: float, now: int) -> float:
	if now < _overtake_until_ms:
		return _overtake_lateral
	var lateral := _wander(s)
	if _mistake == Mistake.RUN_WIDE:
		# Left turns curve positive, so their outside is the right (+)
		var outside := signf(racing_line.curvature_at(s))
		lateral += outside * run_wide_fraction * racing_line.half_width_at(s, outside)
	return lateral


## Two summed sines, as a share of the road room on whichever side they lean.
func _wander(s: float) -> float:
	var wave := (
		0.6 * sin(TAU * s / _wander_length[0] + _wander_phase[0])
		+ 0.4 * sin(TAU * s / _wander_length[1] + _wander_phase[1])
	)
	return wave * wander_fraction * racing_line.half_width_at(s, wave)


## One box along our heading, from alongside_length behind to the avoid reach ahead, hitting racer
## bodies and traffic ContactAreas alike. Throttled: a shape query per bot per tick is what the scan
## cadence exists to avoid.
func _scan_ahead(pos: Vector3, now: int) -> void:
	if now < _scan_next_ms:
		return
	_scan_next_ms = now + npc.next_scan_delay_ms()
	var forward := -npc.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var reach := maxf(avoid_min_range, npc.current_speed * avoid_lookahead_time)
	_scan_box.size = Vector3(avoid_scan_half_width * 2.0, SCAN_HEIGHT, reach + alongside_length)
	var mid := forward * (reach - alongside_length) * 0.5
	_scan_query.transform = Transform3D(
		Basis.looking_at(forward), pos + mid + Vector3.UP * SCAN_HEIGHT * 0.5
	)
	_ahead_riders.clear()
	_ahead_dist.clear()
	_ahead_lateral.clear()
	for hit in npc.get_world_3d().direct_space_state.intersect_shape(_scan_query, MAX_SCAN_RESULTS):
		var rider := _rider_of(hit["collider"])
		# Walls are the navmesh's job, a rider's body and ContactArea both hit, and a wreck is
		# nothing to brake for — skip is intentional
		if rider == null or _ahead_riders.has(rider) or rider.is_crashed:
			continue
		var dist := (rider.global_position - pos).dot(forward)
		var rider_s := _s + dist
		_ahead_riders.append(rider)
		_ahead_dist.append(dist)
		_ahead_lateral.append(
			(rider.global_position - racing_line.point_at(rider_s)).dot(racing_line.right_at(rider_s))
		)


## The racer a scan hit belongs to: the body itself, or the rider owning a ContactArea. Null for
## anything else.
func _rider_of(collider: Node) -> Node3D:
	var racers: String = UtilsConstants.GROUPS["Racers"]
	if collider.is_in_group(racers):
		return collider
	var parent := collider.get_parent()
	return parent if parent.is_in_group(racers) else null


## Commit to passing the rider in our way when a side is open, and return the speed cap it puts
## on us: its speed while we're still behind it, INF once the way is clear or we're going round.
func _avoid(now: int) -> float:
	var i := _blocker_index()
	if i < 0:
		return INF
	if enable_overtaking and now >= _overtake_until_ms:
		var side := _open_side(i)
		if side != 0.0:
			_overtake_lateral = _ahead_lateral[i] + side * overtake_clearance
			_overtake_until_ms = now + int(overtake_commit_time * 1000.0)
	# Pulling out past it at speed, unless it's about to be hit before we're across
	if now < _overtake_until_ms and _ahead_dist[i] > avoid_min_range:
		return INF
	return npc.horizontal_speed(_ahead_riders[i])


## Nearest scanned rider in our way (within avoid_lane_half_width of our offset) and slower than
## us, or -1.
func _blocker_index() -> int:
	var best := -1
	for i in _ahead_riders.size():
		# Scans are cached, so a rider may have despawned since — skip is intentional
		if !is_instance_valid(_ahead_riders[i]) or _ahead_dist[i] <= 0.0:
			continue
		if absf(_ahead_lateral[i] - _lateral) > avoid_lane_half_width:
			continue
		if npc.horizontal_speed(_ahead_riders[i]) >= npc.current_speed - 1.0:
			continue
		if best < 0 or _ahead_dist[i] < _ahead_dist[best]:
			best = i
	return best


## -1 (left) or +1 (right) beside blocker i that no other scanned rider holds, preferring the
## side with more road room past it — 0 when both are taken. Ties go the way the wander leans.
## Counting the others is what fans a pack stacked behind one rider out to both sides.
func _open_side(blocker: int) -> float:
	var lean := 1.0 if _wander(_s) >= 0.0 else -1.0
	var blocker_s := _s + _ahead_dist[blocker]
	var best := 0.0
	var best_room := -INF
	for side: float in [lean, -lean]:
		var lateral := _ahead_lateral[blocker] + side * overtake_clearance
		if _lane_taken(lateral, blocker):
			continue
		var room := racing_line.half_width_at(blocker_s, side) - side * _ahead_lateral[blocker]
		if room > best_room:
			best_room = room
			best = side
	return best


## target, held overtake_clearance short of any rider alongside. Wander and overtakes would otherwise
## steer bots side by side (a grid row) straight into each other.
func _clear_of_alongside(target: float) -> float:
	for i in _ahead_riders.size():
		if !is_instance_valid(_ahead_riders[i]) or absf(_ahead_dist[i]) > alongside_length:
			continue
		if _ahead_lateral[i] >= _lateral:
			target = minf(target, _ahead_lateral[i] - overtake_clearance)
		else:
			target = maxf(target, _ahead_lateral[i] + overtake_clearance)
	return target


func _lane_taken(lateral: float, skip: int) -> bool:
	for i in _ahead_riders.size():
		if i != skip and is_instance_valid(_ahead_riders[i]):
			if absf(_ahead_lateral[i] - lateral) < avoid_lane_half_width:
				return true
	return false


## Ends the current mistake when it runs out, and rolls the next one when due.
func _update_mistake(now: int) -> void:
	if _mistake != Mistake.NONE and now >= _mistake_until_ms:
		_mistake = Mistake.NONE
	if now < _next_mistake_ms:
		return
	_next_mistake_ms = now + _mistake_gap_ms()
	_mistake = [Mistake.LATE_BRAKE, Mistake.RUN_WIDE].pick_random()
	_mistake_until_ms = now + int(mistake_duration * 1000.0)


func _mistake_gap_ms() -> int:
	return int(mistake_interval * randf_range(0.5, 1.5) * 1000.0)


## Steer at goal, or at the next navmesh corner on the way when a wall is in between: a straight
## shot at a point ahead cuts through any wall the line wraps round. Also how a bot knocked off the
## line paths back. Road and grass both, the grass region's travel cost keeps it on the road.
func _path_target(pos: Vector3, goal: Vector3) -> Vector3:
	var now := Time.get_ticks_msec()
	if now >= _path_next_ms:
		_path_next_ms = now + npc.next_scan_delay_ms()
		_path = NavigationServer3D.map_get_path(
			npc.get_world_3d().navigation_map,
			pos,
			goal,
			true,
			UtilsConstants.NAV_LAYER_ROAD | UtilsConstants.NAV_LAYER_GRASS
		)
	# Drop corners we've crossed the perpendicular of, so a stale path never steers the bike back.
	# A hairpin's corner stays ahead until we're actually round it.
	while _path.size() > 2 and _flat(pos - _path[1]).dot(_flat(_path[1] - _path[0])) >= 0.0:
		_path.remove_at(0)
	# The end is goal as it was at the last refresh; goal itself has moved on since
	return _path[1] if _path.size() > 2 else goal


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## A launch may start an air trick. Touching down after one is almost always fine: a
## bad_landing_chance roll crashes it, plus trick_bail_chance out of an air trick.
func _detect_landing(delta: float) -> void:
	if !npc.is_on_floor():
		if _air_time == 0.0:
			_launched = npc.pre_slide_velocity.y > 0.0
			_launch_vy = npc.pre_slide_velocity.y
		# The player's gate: a crest or bump isn't a jump until it's been airborne this long
		var min_air := TrickController.AIR_TRICK_MIN_AIRTIME
		if _launched and _air_time < min_air and _air_time + delta >= min_air:
			_try_air_trick()
		_air_time += delta
		return
	var jumped := _launched and _air_time >= air_trick_min_airtime
	if _air_time > 0.2:  # DEBUG: temp
		DebugUtils.DebugMsg("[npc %s] landed air=%.2f launched=%s" % [npc.name, _air_time, _launched])  # DEBUG: temp
	_air_time = 0.0
	var bail_chance := bad_landing_chance
	if _air_tricked:
		_air_tricked = false
		bail_chance += trick_bail_chance
		npc.trick_controller.end_trick()
	if jumped and randf() < bail_chance:
		DebugUtils.DebugMsg("[npc %s] CRASH bad landing" % npc.name)  # DEBUG: temp
		crashed.emit(null)


## Airtime predicted from the launch as a flat-ground jump. The trick fills what's left of it with time
## to spare, and a flip only goes when it fits.
func _try_air_trick() -> void:
	var tc := npc.trick_controller
	var airtime := 2.0 * _launch_vy / NPCRiderEntity.GRAVITY
	if (
		tc.current_trick != TrickController.Trick.NONE
		or airtime < air_trick_min_airtime
		or randf() >= air_trick_chance
	):
		return
	var hold := 0.7 * (airtime - _air_time)
	_air_tricked = true
	if hold >= NPCTrickController.FLIP_SECS and randf() < flip_chance:
		var flip: TrickController.Trick = [
			TrickController.Trick.BACKFLIP, TrickController.Trick.FRONTFLIP
		].pick_random()
		tc.start_trick(flip, NPCTrickController.FLIP_SECS, true)
	else:
		tc.start_trick(TrickController.AIR_TRICKS.pick_random(), hold, true)


## Tick the combo and run wheelies: one now and then down a straight, set down for a corner, a jump,
## or when it runs out. Air tricks start once a launch is a real jump (_detect_landing).
func _update_tricks(delta: float) -> void:
	var tc := npc.trick_controller
	tc.tick(delta)
	if npc.npc_state == NPCRiderEntity.NPCState.WHEELIE:
		_wheelie_left -= delta
		if _wheelie_left <= 0.0 or !npc.is_on_floor() or !is_straight_ahead():
			npc.stop_wheelie()
			tc.end_trick()
		return
	if (
		tc.current_trick != TrickController.Trick.NONE
		or !npc.is_on_floor()
		or randf() >= delta / wheelie_interval
		or !is_straight_ahead()
	):
		return
	_wheelie_left = randf_range(wheelie_min_secs, wheelie_max_secs)
	npc.wheelie()
	var trick := TrickController.Trick.WHEELIE_SITTING
	if randf() < mod_wheelie_chance:
		var holds: Array = TrickController.BINDINGS[TrickController.TrickState.WHEELIE][
			TrickController.Gesture.HOLD
		]
		trick = holds.filter(func(t): return t != TrickController.Trick.NONE).pick_random()
	tc.start_trick(trick, _wheelie_left, false)


## True when nothing on the line in the next straight_distance metres makes this bot brake below its
## current speed. Not cruise speed: that's the bike's top speed, which the line's corner speeds almost
## never allow. Gates wheelies, and NPCRaceManager's boosts.
func is_straight_ahead() -> bool:
	var s := _s
	while s <= _s + straight_distance:
		if racing_line.profile_speed(_profile, s) < npc.current_speed:
			return false
		s += racing_line.sample_spacing
	return true


## CrashController's rules, dumbed down: a killbox, or a head-on hit on layer 2. Walls take our own
## speed, like the player. Racers take the speed into the contact instead (relative velocity along
## its normal): a pack riding side by side or swerving past each other only bumps, a real ram
## crashes. Under the player's ram-wobble speed it's a harmless bump.
func _detect_crash() -> void:
	for i in npc.get_slide_collision_count():
		var collision := npc.get_slide_collision(i)
		var collider := collision.get_collider()
		if collider is Killbox:
			DebugUtils.DebugMsg("[npc %s] CRASH killbox %s" % [npc.name, collider.get_path()])  # DEBUG: temp
			crashed.emit(null)
			return
		if !CrashController.is_crash_obstacle(collider):
			continue
		var angle := CrashController.impact_angle_deg(collision, npc.pre_slide_velocity)
		if angle >= CrashController.CRASH_MAX_ANGLE_DEG:
			continue
		if collider.is_in_group(UtilsConstants.GROUPS["Racers"]):
			var relative: Vector3 = npc.pre_slide_velocity - collider.velocity
			var into := -collision.get_normal().slide(Vector3.UP).normalized()
			var closing := relative.slide(Vector3.UP).dot(into)
			if closing >= CrashController.WOBBLE_RAM_MAX_SPEED:
				DebugUtils.DebugMsg(  # DEBUG: temp
					"[npc %s] CRASH ram %s angle=%.0f closing=%.1f"  # DEBUG: temp
					% [npc.name, collider.name, angle, closing]  # DEBUG: temp
				)  # DEBUG: temp
				crashed.emit(collider)
				return
		elif npc.current_speed >= CrashController.CRASH_MIN_SPEED:
			DebugUtils.DebugMsg(  # DEBUG: temp
				"[npc %s] CRASH wall %s angle=%.0f speed=%.1f"  # DEBUG: temp
				% [npc.name, collider.get_path(), angle, npc.current_speed]  # DEBUG: temp
			)  # DEBUG: temp
			crashed.emit(null)
			return


## Rammed by a racer that detected the hit from its side (CrashController, another bot, traffic).
func _on_hit_by_racer(_hitter: Node3D) -> void:
	# On the grid, already down, or done racing — skip is intentional
	if _can_drive():
		DebugUtils.DebugMsg("[npc %s] CRASH rammed by %s" % [npc.name, _hitter.name if _hitter else "?"])  # DEBUG: temp
		crashed.emit(null)


## Leaning on something the navmesh can't see. Sampled over a window rather than
## per tick so a genuinely slow section never trips it.
func _check_stuck(delta: float) -> void:
	_stuck_timer += delta
	if _stuck_timer < stuck_window:
		return
	var progress := npc.global_position.distance_to(_stuck_anchor)
	_stuck_timer = 0.0
	_stuck_anchor = npc.global_position
	if progress < stuck_min_progress:
		DebugUtils.DebugMsg(  # DEBUG: temp
			"[npc %s] STUCK pos=%s moved=%.1f %s" % [npc.name, npc.global_position, progress, _dbg_drive]  # DEBUG: temp
		)  # DEBUG: temp
		stuck.emit()


func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	if npc == null:
		issues.append("npc must not be empty")
	return issues
