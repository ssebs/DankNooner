@tool
## Apply gearing-aware movement to parent CharacterBody3D
class_name MovementController extends Node

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var gearing_controller: GearingController
@export var crash_controller: CrashController
@export var rear_raycast: RayCast3D
@export var front_raycast: RayCast3D

@export var debug_verbose:bool=false

const CLUTCH_KICK_WINDOW: float = 0.2
const CLUTCH_POP_MIN_POWER_FRAC: float = 0.65  # fraction of bike's 1st-gear torque needed to clutch-pop — blocks high-gear pops
const POWER_WHEELIE_MIN_FORCE: float = 21.6  # power × bd.acceleration floor for power wheelies — auto-scales by bike strength
const FALL_GRAVITY: float = 40
const AIR_DRAG: float = 12.0  # speed loss while airborne. TODO - turn into a curve
const MIN_SPEED_FROM_AIR_DRAG:float = 5.0
# Unstable surface (collision layer 5) — gravel/sand/etc. Scaled by bike's unstable_surface_factor.
const UNSTABLE_LAYER_MASK: int = 16  # 1 << 4 (layer 5)
const UNSTABLE_DRAG_RATE: float = 0.6  # proportional drag (per sec) on unstable ground at factor=1 — caps top speed without stalling launches
const UNSTABLE_WHEELIE_SUPPRESSION: float = 0.4  # wheelie target scaled by (1 - factor * this)
const UNSTABLE_STEER_SUPPRESSION: float = 0.5  # turn_rate scaled by (1 - factor * this)
# Ramp / loop tuning
const SURFACE_BLEND_SPEED_MIN: float = 3.0  # up_direction alignment speed at rest
const SURFACE_BLEND_SPEED_MAX: float = 40.0  # alignment speed at full speed (must track loops)
const SURFACE_BLEND_SPEED_FALL: float = 0.25  # airborne alignment back to global UP
const ADHESION_ANGLE: float = 80.0  # degrees — adhesion speed check kicks in here
const RAMP_DOWNHILL_FACTOR: float = 1.25  # slope-gravity multiplier rolling downhill (adds speed)
const RAMP_UPHILL_FACTOR: float = 0.8  # slope-gravity multiplier climbing uphill (bleeds speed)
# Below this, the uphill bleed is suppressed — at idle RPM it exceeds engine drive and would pin
# the bike at a standstill, blocking pulling away from a stop. Downhill assist always applies.
const SLOPE_GRAVITY_MIN_SPEED: float = 5.0
const MIN_LOOP_SPEED: float = 20.0  # speed needed at fully inverted (180°)
# Trick tuning
const TRICK_DISABLE_ANGLE: float = 30.0  # (degrees)
const AIR_TRICK_ROTATION_SPEED: float = 4.0  # rad/s pitch control while airborne
const WHEELIE_AIR_GRACE: float = 1.0  # short hops (curbs) keep the wheelie pitch_angle
const LANDING_SNAP_ANGLE_DEG: float = 30.0  # forgiveness window — flips landing this close to upright snap to neutral
# Reverse — hold clutch + any brake to roll backwards from a stop
const REVERSE_MAX_SPEED: float = 2.0
const REVERSE_ACCEL: float = 8.0
const REVERSE_BRAKE_THRESHOLD: float = 0.3
var is_reversing: bool = false
# Drift / powerslide — see planning_docs/PLAN-DRIFT.md
const DRIFT_MIN_SPEED: float = 6.0  # below this it's a stationary burnout (slip stays ~0)
const DRIFT_BRAKE_HOLD: float = 0.4  # rear-brake input that sustains a brake slide
const DRIFT_STEER_ENTRY: float = 0.3  # steer needed to kick a brake slide loose
const DRIFT_BREAK_FORCE: float = POWER_WHEELIE_MIN_FORCE  # power×accel torque gate to break traction
const DRIFT_RECOVER_RATE: float = 2.0  # rad/s grip pulls the travel line back to heading
const DRIFT_RECOVER_SUPPRESS: float = 0.8  # how much drive (0..1) suppresses recovery (holds the slide)
const DRIFT_YAW_RATE: float = 1.6  # rad/s the heading carves per full steer while drifting
const DRIFT_SPEED_SCRUB: float = 0.6  # speed bleed per sec, proportional to |slip_angle|
const DRIFT_MAX_SLIP_ANGLE_DEG: float = 70.0  # clamp just past the 60° spinout so crash fires, no wrap
var speed: float = 0.0
var roll_angle: float = 0.0  # lean left/right
var pitch_angle: float = 0.0  # + = wheelie, - = stoppie
var slip_angle: float = 0.0  # signed radians: heading vs velocity direction. Synced via RollbackSynchronizer.
var is_drifting: bool = false  # re-derived each tick from synced inputs + slip_angle (not synced directly)

var air_pitch_total: float = 0.0  # cumulative pitch rotation while airborne (for flip counting)
var _air_time: float = 0.0  # time since takeoff (for wheelie grace window)
var _wheelie_grace_consumed: bool = false  # true once grace expired and pitch_angle was zeroed

# spawn protection - todo move?
var _default_spawn_timer: float = 1.0
var _spawn_timer: float = _default_spawn_timer

# Wheelie physics
var _prev_clutch_held: bool = false
var _clutch_kick_window: float = 0.0
var _balance_point_decay_mult: float = 0.85
var _was_on_floor: bool = false  # previous tick's floor state (for landing detection)
var _is_on_floor: bool = false  # cached once per tick to avoid redundant move_and_slide calls
var _floor_normal: Vector3 = Vector3.UP  # cached per tick — only valid when _is_on_floor
var _speed_pct: float = 0.0  # speed / max_speed, cached per tick
var _on_unstable_surface: bool = false  # touching layer 5 (unstable_collision), cached per tick


func _ready():
	if Engine.is_editor_hint():
		return

	player_entity.respawned.connect(_on_respawn)


func _on_respawn():
	_spawn_timer = _default_spawn_timer


## TODO - split this into multiple funcs for each thing that it does
func on_movement_rollback_tick(delta: float):
	if Engine.is_editor_hint():
		return
	if player_entity.is_crashed:
		return

	_was_on_floor = _is_on_floor
	_is_on_floor = is_on_floor_netfox()
	_on_unstable_surface = _detect_unstable_surface()
	if _is_on_floor:
		_floor_normal = _get_blended_surface_normal()
		# Landing — normalize pitch to effective angle from upright
		# e.g. 290° → -70° (70° from ground), full 360° → ~0°
		if not _was_on_floor:
			pitch_angle = fmod(pitch_angle, TAU)
			if pitch_angle > PI:
				pitch_angle -= TAU
			elif pitch_angle < -PI:
				pitch_angle += TAU
			# Landing forgiveness: if you (nearly) completed at least one full flip and touch
			# down close to upright, snap to neutral for a clean landing. Held wheelies/stoppies
			# off a jump (air_pitch_total below a full rotation) are left as-is so you can land
			# into them; over-rotations past the bike's max still crash via CrashController.
			var did_flip := air_pitch_total >= PI  # half-turn+ = a flip attempt, not a held wheelie
			if did_flip and absf(pitch_angle) <= deg_to_rad(LANDING_SNAP_ANGLE_DEG):
				pitch_angle = 0.0
			air_pitch_total = 0.0
			_air_time = 0.0
			_wheelie_grace_consumed = false
	else:
		# Takeoff — start grace window. Short hops (e.g. curbs) keep the wheelie;
		# once grace expires we zero pitch_angle so longer airtime lets air tricks
		# accumulate from level.
		if _was_on_floor:
			air_pitch_total = 0.0
			_air_time = 0.0
			_wheelie_grace_consumed = false
		_air_time += delta
		if not _wheelie_grace_consumed and _air_time >= WHEELIE_AIR_GRACE:
			# Clear a leftover ground-wheelie pitch after a long hop — but NEVER mid-flip.
			# air_pitch_total grows from air lean, so a meaningful value means the rider is
			# actively flipping; zeroing then whips the visual ("speeds up halfway") and discards
			# the rotation the landing-forgiveness snap relies on (causing late-flip land crashes).
			if air_pitch_total < deg_to_rad(LANDING_SNAP_ANGLE_DEG):
				pitch_angle = 0.0
				air_pitch_total = 0.0
			_wheelie_grace_consumed = true
	_speed_calc(delta)
	_speed_pct = clampf(speed / player_entity.bike_definition.max_speed, 0.0, 1.0)
	_update_surface_alignment(delta)
	_drift_calc(delta)
	_steer_calc(delta)
	_velocity_calc(delta)
	_pitch_angle_calc(delta)

	# Apply movement
	player_entity.velocity *= NetworkTime.physics_factor
	player_entity.move_and_slide()
	player_entity.velocity /= NetworkTime.physics_factor

	_handle_player_collision(delta)

	if debug_verbose:
		_debug_air_state()


## One-line dump of every value relevant to air/landing: angles, speed, trick state, and the
## VISUAL pitch/height (visual_root) that produces the "land underground" dip. Toggle the
## MovementController's `debug_verbose` export to enable. trick state is last tick's (the
## TrickController runs after MovementController in _rollback_tick).
func _debug_air_state():
	var vr: Node3D = player_entity.visual_root
	DebugUtils.DebugMsg(
		(
			"[AIR] floor=%s pitch=%.1f air_pitch=%.1f roll=%.1f up=%.1f | vroot_x=%.1f vroot_y=%.3f"
			+ " | spd=%.1f vel=(%.1f,%.1f,%.1f) | trick=%s"
		)
		% [
			_is_on_floor,
			rad_to_deg(pitch_angle),
			rad_to_deg(air_pitch_total),
			rad_to_deg(roll_angle),
			rad_to_deg(player_entity.up_direction.angle_to(Vector3.UP)),
			rad_to_deg(vr.rotation.x),
			vr.position.y,
			speed,
			player_entity.velocity.x,
			player_entity.velocity.y,
			player_entity.velocity.z,
			TrickController.trick_to_str(player_entity.trick_controller.current_trick),
		],
		debug_verbose
	)


## True if any current slide collision is on layer 5 (unstable_collision).
## is_on_floor_netfox() runs move_and_slide just before this, so the collision list is fresh.
func _detect_unstable_surface() -> bool:
	for i in player_entity.get_slide_collision_count():
		var collider = player_entity.get_slide_collision(i).get_collider()
		if collider is CollisionObject3D and collider.collision_layer & UNSTABLE_LAYER_MASK:
			return true
	return false


## Effective unstable factor (0..1) — bike's resistance applied. 0 when not on unstable
## ground OR when the bike fully ignores unstable surfaces (dirtbike).
func get_unstable_factor() -> float:
	if not _on_unstable_surface:
		return 0.0
	return player_entity.bike_definition.unstable_surface_factor


## Blend normals from front + rear raycasts for smoother ramp transitions.
## Falls back to CharacterBody3D floor normal if neither raycast hits.
func _get_blended_surface_normal() -> Vector3:
	var front_hit = front_raycast.is_colliding()
	var rear_hit = rear_raycast.is_colliding()

	if front_hit and rear_hit:
		return (
			front_raycast
			. get_collision_normal()
			. lerp(rear_raycast.get_collision_normal(), 0.5)
			. normalized()
		)
	if front_hit:
		return front_raycast.get_collision_normal()
	if rear_hit:
		return rear_raycast.get_collision_normal()

	return player_entity.get_floor_normal()


## Align bike's up_direction to surface normal for ramp/loop riding
func _update_surface_alignment(delta: float):
	var pe = player_entity

	if _is_on_floor:
		var surface_angle = _floor_normal.angle_to(Vector3.UP)
		if surface_angle > deg_to_rad(5.0):
			DebugUtils.DebugMsg(
				(
					"Surface: angle=%.1f° normal=%s F=%s R=%s"
					% [
						rad_to_deg(surface_angle),
						_floor_normal.snapped(Vector3.ONE * 0.01),
						front_raycast.is_colliding(),
						rear_raycast.is_colliding()
					]
				),
				OS.has_feature("debug") and debug_verbose
			)

		# Adhesion check — need enough speed to ride steep/inverted surfaces
		if surface_angle > deg_to_rad(ADHESION_ANGLE):
			var steepness = clampf(
				(surface_angle - deg_to_rad(ADHESION_ANGLE)) / deg_to_rad(180.0 - ADHESION_ANGLE),
				0.0,
				1.0
			)
			var required_speed = MIN_LOOP_SPEED * steepness
			if speed < required_speed:
				# Too slow — peel off the surface
				pe.up_direction = pe.up_direction.slerp(Vector3.UP, 2.0 * delta).normalized()
				DebugUtils.DebugMsg("peel off: speed=%.1f required=%.1f" % [speed, required_speed])
				return

		# Blend up_direction toward surface normal — faster at speed (must track loops)
		# Skip slerp when vectors are nearly identical (avoids non-normalized axis error)
		if pe.up_direction.dot(_floor_normal) < 0.9999:
			var blend_speed = lerpf(SURFACE_BLEND_SPEED_MIN, SURFACE_BLEND_SPEED_MAX, _speed_pct)
			var t = clampf(blend_speed * delta, 0.0, 1.0)
			pe.up_direction = pe.up_direction.slerp(_floor_normal, t).normalized()
	else:
		_detach_from_surface(delta)


## Blend up_direction back to global up (airborne or detaching).
## More inverted = slower correction — rider falls on their head off a loop.
func _detach_from_surface(delta: float):
	var inversion = player_entity.up_direction.angle_to(Vector3.UP) / PI  # 0=upright, 1=inverted
	# Upright: corrects quickly. Fully inverted: nearly frozen so they fall on their head.
	var correction_speed = lerpf(
		SURFACE_BLEND_SPEED_FALL, SURFACE_BLEND_SPEED_FALL * 0.05, inversion
	)
	player_entity.up_direction = (
		player_entity.up_direction.slerp(Vector3.UP, correction_speed * delta).normalized()
	)


## Calculate speed from input / power output
func _speed_calc(delta: float):
	var bd = player_entity.bike_definition

	# Airborne
	if not _is_on_floor:
		is_reversing = false
		return

	# Reverse — hold clutch + brake from a near-stop. Bypasses normal accel/brake/slope.
	var brake_total = input_controller.nfx_front_brake + input_controller.nfx_rear_brake
	var reverse_input = input_controller.nfx_clutch_held and brake_total > REVERSE_BRAKE_THRESHOLD
	if reverse_input and (is_reversing or speed <= 0.5):
		is_reversing = true
		speed = move_toward(speed, -REVERSE_MAX_SPEED, REVERSE_ACCEL * delta)
		return
	elif is_reversing:
		# Inputs released — decay back to 0, then resume normal logic next tick.
		speed = move_toward(speed, 0.0, REVERSE_ACCEL * delta)
		if speed >= 0.0:
			is_reversing = false
			speed = 0.0
		return

	# Acceleration (uses gearing power output)
	# Hard braking (> 0.5) cuts throttle so the brake can always bring you to a
	# stop. Light braking keeps throttle for trail-braking.
	var power = gearing_controller.get_power_output()
	var gear_max_speed = gearing_controller.get_gear_max_speed()
	if power > 0 and speed < gear_max_speed and brake_total <= 0.5:
		speed += bd.acceleration * power * delta
		speed = minf(speed, gear_max_speed)
	# Engine braking — applies when not on throttle, stronger at higher RPM
	elif power <= 0 and speed > 0.5:
		var rpm_factor = gearing_controller.get_rpm_ratio()
		speed = move_toward(speed, 0, bd.engine_brake_strength * rpm_factor * delta)

	# Braking
	var total_brake = input_controller.nfx_front_brake + input_controller.nfx_rear_brake
	if total_brake > 0:
		speed = move_toward(speed, 0, bd.brake_strength * total_brake * delta)

	# Slope gravity — projects gravity along the surface. Downhill (positive) adds speed,
	# uphill (negative) bleeds it. The uphill bleed is suppressed below SLOPE_GRAVITY_MIN_SPEED
	# so it can't out-pull engine drive at idle RPM and pin the bike at a standstill; the
	# downhill assist always applies so you gain speed rolling down a grade.
	if _is_on_floor and player_entity.velocity.length_squared() > 0.01:
		var gravity_on_surface = Vector3.DOWN - _floor_normal * Vector3.DOWN.dot(_floor_normal)
		var vel_dir = player_entity.velocity.normalized()
		var slope_dot = gravity_on_surface.dot(vel_dir)  # >0 downhill, <0 uphill
		var factor = RAMP_DOWNHILL_FACTOR if slope_dot > 0.0 else RAMP_UPHILL_FACTOR
		var slope_accel = FALL_GRAVITY * slope_dot * factor
		if slope_accel < 0.0 and speed < SLOPE_GRAVITY_MIN_SPEED:
			slope_accel = 0.0
		speed += slope_accel * delta
		speed = maxf(speed, 0.0)

	# Unstable surface drag — proportional to speed so low-speed launches still work.
	# Equilibrium with throttle settles around a fraction of normal top speed.
	var unstable_factor = get_unstable_factor()
	if unstable_factor > 0 and speed > 0:
		speed -= speed * UNSTABLE_DRAG_RATE * unstable_factor * delta

	speed = minf(speed, bd.max_speed)


## Calculate roll_angle & set player_entity.rotation
func _steer_calc(delta: float):
	var bd = player_entity.bike_definition

	var amount_normalized_rename_me:=1.0
	if player_entity.trick_controller.current_trick == TrickController.Trick.TWO_LEFT_FEET:
		amount_normalized_rename_me = 0.5
	elif speed < 1 and not is_reversing:
		amount_normalized_rename_me = 0.2

	# ONCE STOPPED, LERP BACK TO DEFAULT POSE

	# Curve-based speed factor for steering and lean. Reverse bypasses the curves —
	# they're tuned for forward speed and bottom out near 0, so we'd lose all authority.
	var lean_factor = 1.0 if is_reversing else bd.lean_curve.sample(_speed_pct)
	var steer_input = -input_controller.nfx_steer if is_reversing else input_controller.nfx_steer
	var target_lean = steer_input * bd.max_lean_angle_rad * lean_factor
	roll_angle = lerpf(roll_angle, target_lean, bd.lean_speed * delta)*amount_normalized_rename_me

	# Steering — bell curve: low at standstill, peaks mid-low speed, tapers at top speed.
	# Uses abs(speed) so reverse rolling still turns the body.
	if absf(speed) > 0.5 and not is_drifting:
		var steer_factor = 1.0 if is_reversing else (bd.steer_curve.sample(_speed_pct) if bd.steer_curve else 1.0)
		var turn_rate = bd.turn_speed * steer_factor * (1.0 - get_unstable_factor() * UNSTABLE_STEER_SUPPRESSION)
		DebugUtils.DebugMsg(
			(
				"Steer: spd=%.1f spd%%=%.0f%% curve=%.2f rate=%.2f"
				% [speed, _speed_pct * 100, steer_factor, turn_rate]
			),
			OS.has_feature("debug") and debug_verbose
		)
		player_entity.rotate_y(-roll_angle * turn_rate * delta)

	
	# Align bike basis so local Y points along up_direction (ramp riding)
	var target_up = player_entity.up_direction
	var current_forward = -player_entity.global_transform.basis.z
	var right = current_forward.cross(target_up)
	if right.length_squared() > 0.001:
		right = right.normalized()
		var adjusted_forward = target_up.cross(right).normalized()
		player_entity.global_transform.basis = Basis(right, target_up, -adjusted_forward)


## Calculate player_entity.velocity & set slope angle
func _velocity_calc(delta: float):
	# Apply velocity following slope
	var forward = -player_entity.global_transform.basis.z
	# Drift: velocity travels along heading rotated by slip_angle (tail out). slip_angle==0
	# (normal riding) leaves this identical to forward.
	var travel_dir = forward
	if is_drifting:
		# Rotate about global Y to match the heading carve (rotate_y) so slip stays
		# consistent on ramps; .slide(_floor_normal) below reprojects onto the surface.
		travel_dir = forward.rotated(Vector3.UP, slip_angle)
	if _is_on_floor:
		player_entity.velocity = travel_dir.slide(_floor_normal).normalized() * speed
	else:
		# Airborne: keep the launch momentum instead of rebuilding velocity from the (slerping)
		# bike basis — the synced velocity already carries the takeoff trajectory, so the basis
		# can't deflect it. Bleed only the horizontal component with drag, floored at
		# MIN_SPEED_FROM_AIR_DRAG so huge jumps keep steering authority. velocity.y is left to
		# gravity below for a real parabola.
		var horizontal := Vector3(player_entity.velocity.x, 0.0, player_entity.velocity.z)
		var h_speed := horizontal.length()
		if h_speed > 0.0001:
			var floor_speed := minf(h_speed, MIN_SPEED_FROM_AIR_DRAG)
			var new_h := maxf(h_speed - AIR_DRAG * delta, floor_speed)
			horizontal = horizontal / h_speed * new_h
			player_entity.velocity.x = horizontal.x
			player_entity.velocity.z = horizontal.z
			speed = new_h  # keep speed in sync for landing, wheel spin, steering

	# Gravity — integrated onto velocity.y so airborne flight arcs like a real parabola
	# instead of dropping at a constant rate.
	if !_is_on_floor:
		player_entity.velocity.y -= FALL_GRAVITY * delta


## Orchestrates pitch_angle: clutch detection → wheelie target → stoppie → apply
func _pitch_angle_calc(delta: float):
	_update_clutch_dump_detection()

	# Airborne trick control — lean to flip, no decay (weightless)
	if not _is_on_floor:
		if input_controller.nfx_lean != 0:
			# Lean back (negative) = backflip (positive pitch), lean forward = frontflip
			var rotation_delta = input_controller.nfx_lean * AIR_TRICK_ROTATION_SPEED * delta
			pitch_angle -= rotation_delta
			air_pitch_total += abs(rotation_delta)
		return
		

	var bd = player_entity.bike_definition
	var in_wheelie = pitch_angle > deg_to_rad(TrickController.WHEELIE_PITCH_THRESHOLD_DEG)
	var in_stoppie = pitch_angle < deg_to_rad(TrickController.STOPPIE_PITCH_THRESHOLD_DEG)
	var bp_low = deg_to_rad(bd.wheelie_balance_point_deg - bd.wheelie_balance_point_width_deg)
	var bp_high = deg_to_rad(bd.wheelie_balance_point_deg + bd.wheelie_balance_point_width_deg)
	var in_balance_point = pitch_angle >= bp_low and pitch_angle <= bp_high
	var above_balance_point = pitch_angle > bp_high

	# Disable tricks on steep surfaces — decay pitch back to neutral
	var surface_angle = player_entity.up_direction.angle_to(Vector3.UP)
	if surface_angle > deg_to_rad(TRICK_DISABLE_ANGLE):
		if pitch_angle != 0:
			pitch_angle = move_toward(pitch_angle, 0, bd.return_speed * delta)
		return

	# --- Wheelie ---
	var wheelie_target = 0.0
	if _can_initiate_wheelie(in_wheelie) and not in_stoppie:
		wheelie_target = _calc_normal_wheelie_target(bd)
		# Above balance point is unstable — overrides normal target with drift-to-crash.
		# In-BP keeps the normal target; dampened rotation/decay in _apply_wheelie_pitch gives the BP feel.
		if above_balance_point:
			wheelie_target = _calc_above_balance_point_target(bd, bp_low, bp_high)

	DebugUtils.DebugMsg(
		(
			"pitch_angle: %.2f | wheelie_target: %.2f | balance_point: %.2f | \
	max_wheelie: %.2f | in_bp: %s"
			% [
				rad_to_deg(pitch_angle),
				rad_to_deg(wheelie_target),
				bd.wheelie_balance_point_deg,
				bd.max_wheelie_angle_deg,
				in_balance_point
			]
		),
		OS.has_feature("debug")and debug_verbose
	)

	# Lean forward recovery — pull the front wheel down
	if input_controller.nfx_lean > 0 and in_wheelie:
		pitch_angle = move_toward(
			pitch_angle, 0, bd.return_speed * input_controller.nfx_lean * 2.0 * delta
		)

	# Speed-dependent wheelie gravity — less speed = front wheel drops
	# Only applies when rider isn't actively pulling back or flooring throttle
	if in_wheelie and input_controller.nfx_lean >= 0 and input_controller.nfx_throttle < 0.5:
		var speed_ratio = clampf(speed / (bd.max_speed * 0.5), 0.0, 1.0)
		var wheelie_gravity = bd.return_speed * (1.0 - speed_ratio)
		# Balance point stabilizes the wheelie — gravity is dampened here too
		if in_balance_point:
			wheelie_gravity *= _balance_point_decay_mult * 2.0
		pitch_angle = move_toward(pitch_angle, 0, wheelie_gravity / 2 * delta)

	# Rev limiter drop — banging the limiter during a wheelie kills the power
	# Rider needs to shift up or back off throttle to maintain the wheelie
	if in_wheelie and gearing_controller.is_rev_limited:
		var drop_speed = bd.return_speed * 5.0
		pitch_angle = move_toward(pitch_angle, 0, drop_speed * delta)
		speed = move_toward(speed, speed * 0.95, bd.max_speed * 0.1 * delta)

	_apply_wheelie_pitch(bd, wheelie_target, in_balance_point, delta)

	# --- Stoppie ---
	if not in_wheelie:
		_stoppie_calc(bd, in_stoppie, delta)

	# TODO: easy mode clamp


## Apply wheelie pitch toward target, or decay back to 0
func _apply_wheelie_pitch(
	bd: BikeSkinDefinition, wheelie_target: float, in_balance_point: bool, delta: float
):
	if wheelie_target > 0:
		var spd = (
			bd.rotation_speed * _balance_point_decay_mult if in_balance_point else bd.rotation_speed
		)
		# Clutch dump torque boost — massive at low speed, fades with speed
		if _clutch_kick_window > 0:
			var speed_falloff = 1.0 - clampf(speed / (bd.max_speed * 0.3), 0.0, 1.0)
			spd += bd.rotation_speed * 2.0 * speed_falloff
		pitch_angle = move_toward(pitch_angle, wheelie_target, spd * delta)
	elif pitch_angle > 0:
		var decay_speed = (
			bd.return_speed * _balance_point_decay_mult if in_balance_point else bd.return_speed
		)
		pitch_angle = move_toward(pitch_angle, 0, decay_speed * delta)


## Stoppie physics: brake hard + lean forward to lift the rear wheel
func _stoppie_calc(bd: BikeSkinDefinition, in_stoppie: bool, delta: float):
	var total_brake = input_controller.nfx_front_brake + input_controller.nfx_rear_brake
	var max_stoppie_rad = deg_to_rad(bd.max_stoppie_angle_deg)

	# Dynamic brake threshold: need more brake to start, less to sustain at deeper angles
	var stoppie_ratio = clampf(abs(pitch_angle) / max_stoppie_rad, 0.0, 1.0)
	var required_brake = lerpf(0.5, 0.15, stoppie_ratio)

	var can_stoppie = (
		total_brake > required_brake
		and input_controller.nfx_lean > 0.3
		and speed > 3.0
		and abs(roll_angle) < deg_to_rad(10)
	)

	if can_stoppie or in_stoppie:
		# Target deepens with brake + lean — speed just needs a minimum
		var speed_factor = clampf(speed / (bd.max_speed * 0.25), 0.0, 1.0)
		var brake_pct = clampf(total_brake * 1.5, 0.0, 1.0)
		# Target can exceed max — crash controller will trigger if you go over
		var stoppie_target = -max_stoppie_rad * (0.5 + brake_pct * 0.7) * speed_factor

		# Lean back recovery — push the rear wheel down
		if input_controller.nfx_lean < 0 and in_stoppie:
			pitch_angle = move_toward(
				pitch_angle, 0, bd.return_speed * abs(input_controller.nfx_lean) * 2.0 * delta
			)

		if can_stoppie:
			pitch_angle = move_toward(pitch_angle, stoppie_target, bd.rotation_speed * 1.5 * delta)
		elif in_stoppie:
			# Brake dropped below threshold — decay back to 0
			pitch_angle = move_toward(pitch_angle, 0, bd.return_speed * delta)
	elif pitch_angle < 0:
		# Residual negative pitch below the in_stoppie threshold — without this,
		# pitch gets stranded a few degrees negative and the rear wheel hangs.
		pitch_angle = move_toward(pitch_angle, 0, bd.return_speed * delta)


## Detect clutch dump (held → released while on throttle) and manage kick window
func _update_clutch_dump_detection():
	var clutch_held = input_controller.nfx_clutch_held

	if _prev_clutch_held and not clutch_held and input_controller.nfx_throttle > 0.5:
		_clutch_kick_window = CLUTCH_KICK_WINDOW

	if _clutch_kick_window > 0:
		_clutch_kick_window -= NetworkTime.ticktime

	_prev_clutch_held = clutch_held


## Check if a wheelie can start or is already in progress
func _can_initiate_wheelie(in_wheelie: bool) -> bool:
	var bd = player_entity.bike_definition

	if in_wheelie:
		return true

	# Can't START while turning
	if abs(roll_angle) >= deg_to_rad(10):
		return false

	# Clutch dump pop — needs raw torque (low gear). Gates on potential power
	# (ignoring engagement, since clutch_value is still ~1.0 at the dump instant).
	var clutch_pop = _clutch_kick_window > 0 and input_controller.nfx_throttle > 0.5
	if clutch_pop:
		var max_torque_mult = bd.gear_ratios[0] / bd.gear_ratios[bd.num_gears - 1]
		return gearing_controller.get_potential_power_output() > max_torque_mult * CLUTCH_POP_MIN_POWER_FRAC

	# Power wheelie — needs forward motion + lean back + throttle + delivered force.
	# Gate uses power × bd.acceleration (bike's actual wheel force), so weaker bikes
	# (lower acceleration) auto-fail without needing a per-bike flag.
	if speed <= 1:
		return false
	var force = gearing_controller.get_power_output() * bd.acceleration
	return (
		input_controller.nfx_lean < -0.3
		and input_controller.nfx_throttle > 0.7
		and force > POWER_WHEELIE_MIN_FORCE
	)


## Drift entry. Mirror of the wheelie clutch/power gates but gated on lean FORWARD
## (lean back = wheelie, lean forward = drift), plus a rear-brake-slide entry.
func _can_initiate_drift() -> bool:
	if is_drifting:
		return true
	if not _is_on_floor or speed < DRIFT_MIN_SPEED:
		return false

	# Brake-slide entry — steer + hold rear brake breaks the rear loose. Accessible, safe to release.
	if (
		input_controller.nfx_rear_brake > DRIFT_BRAKE_HOLD
		and absf(input_controller.nfx_steer) > DRIFT_STEER_ENTRY
	):
		return true

	# Power entry — needs lean forward (distinguishes from wheelie's lean back).
	if input_controller.nfx_lean <= 0.3:
		return false
	var bd = player_entity.bike_definition

	# Clutch-dump pop (lean-forward variant) — same low-gear torque gate the wheelie pop uses.
	var clutch_pop = _clutch_kick_window > 0 and input_controller.nfx_throttle > 0.5
	if clutch_pop:
		var max_torque_mult = bd.gear_ratios[0] / bd.gear_ratios[bd.num_gears - 1]
		return (
			gearing_controller.get_potential_power_output()
			> max_torque_mult * CLUTCH_POP_MIN_POWER_FRAC
		)

	# Power slide — floored throttle + enough delivered force to break traction.
	var force = gearing_controller.get_power_output() * bd.acceleration
	return input_controller.nfx_throttle > 0.7 and force > DRIFT_BREAK_FORCE


## Maintain is_drifting and integrate slip_angle. Runs before _velocity_calc so
## velocity picks up the slip this tick. No-op (and slip decays to 0) when not drifting.
func _drift_calc(delta: float):
	# --- entry / exit ---
	if player_entity.is_crashed or not _is_on_floor:
		is_drifting = false
		slip_angle = move_toward(slip_angle, 0.0, DRIFT_RECOVER_RATE * delta)
		return

	if not is_drifting:
		is_drifting = _can_initiate_drift()

	if not is_drifting:
		# Not drifting — make sure any residual slip unwinds.
		slip_angle = move_toward(slip_angle, 0.0, DRIFT_RECOVER_RATE * delta)
		return

	# Sustain check — drift ends once nothing is feeding it and the slide has closed.
	var brake_sustain = input_controller.nfx_rear_brake > DRIFT_BRAKE_HOLD
	var power_sustain = input_controller.nfx_throttle > 0.5 and input_controller.nfx_lean > 0.0
	if not brake_sustain and not power_sustain and absf(slip_angle) < deg_to_rad(2.0):
		is_drifting = false
		slip_angle = 0.0
		return

	var steer = input_controller.nfx_steer
	# Drive = how hard the slide is fed (throttle for power drift, rear brake for brake slide).
	var drive = clampf(maxf(input_controller.nfx_throttle, input_controller.nfx_rear_brake), 0.0, 1.0)

	# Carve the heading from steer. Momentum keeps the travel line put as the bike
	# rotates, so adding the same delta to slip_angle (heading-vs-travel) makes the
	# travel direction (forward.rotated(UP, slip_angle) in _velocity_calc) hold its
	# world heading instead of being dragged with the nose. Steering builds the
	# slide; countersteer unwinds it. This is the momentum-based (Forza-style) feel.
	var carve = steer * DRIFT_YAW_RATE * delta
	player_entity.rotate_y(-carve)
	slip_angle += carve

	# Grip pulls the travel line back toward the heading. Throttle/brake holds the
	# slide (suppresses recovery); lifting lets grip catch up and the drift unwinds.
	var recover = DRIFT_RECOVER_RATE * (1.0 - drive * DRIFT_RECOVER_SUPPRESS)
	slip_angle = move_toward(slip_angle, 0.0, recover * delta)

	# Clamp just past the spinout angle so CrashController fires before it can wrap.
	slip_angle = clampf(
		slip_angle, -deg_to_rad(DRIFT_MAX_SLIP_ANGLE_DEG), deg_to_rad(DRIFT_MAX_SLIP_ANGLE_DEG)
	)

	# Speed scrub — sliding sideways bleeds speed.
	speed -= speed * DRIFT_SPEED_SCRUB * absf(slip_angle) * delta

	DebugUtils.DebugMsg(
		"drift: slip=%.1f° drive=%.2f steer=%.2f" % [rad_to_deg(slip_angle), drive, steer],
		OS.has_feature("debug") and debug_verbose
	)


## Calculate wheelie target. Lean-back is the only driver — throttle alone
## must not pin a target, or the bike sticks at a static equilibrium angle.
func _calc_normal_wheelie_target(bd: BikeSkinDefinition) -> float:
	if input_controller.nfx_lean >= 0:
		return 0.0
	var max_wheelie_rad = deg_to_rad(bd.max_wheelie_angle_deg)
	# Unstable surfaces shrink the achievable target so reaching the balance point takes more input.
	var unstable_scale = 1.0 - get_unstable_factor() * UNSTABLE_WHEELIE_SUPPRESSION
	return max_wheelie_rad * abs(input_controller.nfx_lean) * 0.75 * unstable_scale


## Above balance point — unstable. Drifts toward crash unless rider leans forward.
func _calc_above_balance_point_target(
	bd: BikeSkinDefinition,
	bp_low: float,
	bp_high: float,
) -> float:
	var max_wheelie_rad = deg_to_rad(bd.max_wheelie_angle_deg)
	var balance_center = (bp_low + bp_high) / 2.0
	var drift_target = max_wheelie_rad + deg_to_rad(1)
	if input_controller.nfx_lean > 0:
		return balance_center
	# Lean back or no input — drifts toward crash
	return drift_target


## Stops players from spawning in eachother during _spawn_timer
func _handle_player_collision(delta: float):
	if _spawn_timer <= 0:
		return

	_spawn_timer -= delta

	var collision = player_entity.get_last_slide_collision()
	if collision == null:
		return

	var collider = collision.get_collider()
	if collider is PlayerEntity:
		var random_angle = randf() * TAU
		var offset = Vector3(cos(random_angle), 0.5, sin(random_angle))
		player_entity.global_position += offset


## Netfox's version of is_on_floor()
func is_on_floor_netfox() -> bool:
	var old_velocity = player_entity.velocity
	player_entity.velocity = Vector3.ZERO
	player_entity.move_and_slide()
	player_entity.velocity = old_velocity

	return player_entity.is_on_floor()


## Called from player_entity.gd's do_respawn
func do_reset():
	speed = 0.0
	roll_angle = 0.0
	pitch_angle = 0.0
	slip_angle = 0.0
	is_drifting = false
	is_reversing = false
	_was_on_floor = false
	_prev_clutch_held = false
	_clutch_kick_window = 0.0
	air_pitch_total = 0.0
	_air_time = 0.0
	_wheelie_grace_consumed = false
	player_entity.up_direction = Vector3.UP


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	if gearing_controller == null:
		issues.append("gearing_controller must not be empty")
	if crash_controller == null:
		issues.append("crash_controller must not be empty")
	if rear_raycast == null:
		issues.append("rear_raycast must not be empty")
	if front_raycast == null:
		issues.append("front_raycast must not be empty")
	return issues
