@tool
## Apply gearing-aware movement to parent CharacterBody3D
class_name MovementController extends Node

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var gearing_controller: GearingController
@export var crash_controller: CrashController
@export var wobble_controller: WobbleController
@export var rear_raycast: RayCast3D
@export var front_raycast: RayCast3D

@export var debug_verbose: bool = false

## Radians of wheelie target per unit of wheel force (get_power_output × acceleration). The single
## knob that calibrates how hard bikes loft: a strong/peaky power band drives the target past the
## balance point (loops), a weaker one tops out below it. See _calc_normal_wheelie_target.
const WHEELIE_FORCE_TO_ANGLE: float = 0.045
## How much lean adds to (back) / subtracts from (forward) the wheelie target, as a fraction of
## max_wheelie. The joystick's extra authority on a bike that already has the power to loft — it can't
## conjure a wheelie on a bike too weak to clear the start gate.
const WHEELIE_LEAN_INFLUENCE: float = 0.25
## Scales the wheelie climb rate (bd.rotation_speed) so the front comes up less abruptly, without
## touching the stoppie rate.
const WHEELIE_RISE_RATE_SCALE: float = 0.25
## Clutch-dump torque spike, biggest at low speed and fading with speed. Boosts BOTH the wheelie
## force (so a clutch-up lofts higher than steady power — "more power") and the climb rate (so it
## snaps up even when WHEELIE_RISE_RATE_SCALE is low). Higher = a stronger pop; too high loops light
## bikes off a hard dump. See _calc_normal_wheelie_target and _apply_wheelie_pitch.
const WHEELIE_CLUTCH_KICK_BOOST: float = 0.75
## Steering authority while up on the front wheel, above WHEELIE_STEER_FULL_SPEED (mirrors STOPPIE_STEER_SCALE).
const WHEELIE_STEER_SCALE: float = 0.5
## At/below this speed the wheelie steering cut is lifted so tight circle wheelies stay possible.
const WHEELIE_STEER_FULL_SPEED: float = 8.0
## Rear brake pulls the front down during a wheelie, scaled by bd.return_speed (works on throttle too).
const WHEELIE_REAR_BRAKE_DROP: float = 3.0

const CLUTCH_KICK_WINDOW: float = 0.2
# Fraction of bike's 1st-gear torque needed to clutch-pop — blocks high-gear pops
const CLUTCH_POP_MIN_POWER_FRAC: float = 0.65
# Clutch pops are a low-speed launch move. Above this fraction of max_speed (e.g. rolling fast
# downhill on slope gravity) a clutch dump must NOT loft the front — use a power wheelie instead.
const CLUTCH_POP_MAX_SPEED_FRAC: float = 0.4
# Bunny hop: from a wheelie up to HOP_MAX_BALANCE_FRAC of the balance point, lean forward with the gas
# off. The nose rocks down on the ground and the rear launches once it passes level. Airtime
# 2 * HOP_VELOCITY / FALL_GRAVITY (0.23s) stays under AIR_TRICK_MIN_AIRTIME, so it's a bump to the
# air-trick / landing systems.
const HOP_MAX_BALANCE_FRAC: float = 0.5
const HOP_VELOCITY: float = 4.6
# Nose-down rate per radian of wheelie (1/s) — the rock down to level always takes 1 / this (~0.125s).
const HOP_PITCH_KICK: float = 8.0
# Wheel-force (power × bd.acceleration) floor to start a wheelie / clutch-pop — auto-scales by bike
# strength. Kept low enough that a light bike (the mini) clears it across a usable RPM band, not just
# a sliver at peak; this also makes clutch-ups easier in general. NOT the loop threshold (that's the
# balance-point crossing). Decoupled from DRIFT_BREAK_FORCE so drift traction-break is unaffected.
const POWER_WHEELIE_MIN_FORCE: float = 15.0
const FALL_GRAVITY: float = 40
const AIR_DRAG: float = 11.0 # speed loss while airborne. TODO - turn into a curve
const MIN_SPEED_FROM_AIR_DRAG: float = 5.0
# Unstable surface (collision layer 5) — gravel/sand/etc. Scaled by bike's unstable_surface_factor.
const UNSTABLE_LAYER_MASK: int = 16 # 1 << 4 (layer 5)
# Proportional drag (per sec) on unstable ground at factor=1 — caps top speed without stalling launches
const UNSTABLE_DRAG_RATE: float = 0.1
const UNSTABLE_WHEELIE_SUPPRESSION: float = 0.4 # wheelie target scaled by (1 - factor * this)
const UNSTABLE_STEER_SUPPRESSION: float = 0.5 # turn_rate scaled by (1 - factor * this)
# Ramp / loop tuning
const SURFACE_BLEND_SPEED_MIN: float = 3.0 # up_direction alignment speed at rest
const SURFACE_BLEND_SPEED_MAX: float = 40.0 # alignment speed at full speed (must track loops)
const SURFACE_BLEND_SPEED_FALL: float = 0.25 # airborne alignment back to global UP
const ADHESION_ANGLE: float = 80.0 # degrees — adhesion speed check kicks in here
const RAMP_DOWNHILL_FACTOR: float = 1.25 # slope-gravity multiplier rolling downhill (adds speed)
const RAMP_UPHILL_FACTOR: float = 0.85 # slope-gravity multiplier climbing uphill (bleeds speed)
# Dedicated slope gravity — gentler than FALL_GRAVITY (which is tuned for arcade air time and is
# far too punishing on grades). Drives the downhill assist / uphill bleed.
const SLOPE_GRAVITY: float = 18.0
# Grades steeper than this can't be climbed under power — engine drive is blocked and gravity
# bleeds the bike to a stall. Stalling out (near-stopped) on such a grade crashes (CrashController).
const MAX_CLIMB_ANGLE_DEG: float = 40.0
const STALL_CRASH_SPEED: float = 1.0 # near-stopped threshold for the steep-slope stall crash
const MIN_LOOP_SPEED: float = 20.0 # speed needed at fully inverted (180°)
# Trick tuning
const TRICK_DISABLE_ANGLE: float = 30.0 # (degrees)
const AIR_TRICK_ROTATION_SPEED: float = 4.0 # rad/s pitch control while airborne
const WHEELIE_AIR_GRACE: float = 1.0 # short hops (curbs) keep the wheelie pitch_angle
const LANDING_SNAP_ANGLE_DEG: float = 30.0 # forgiveness window — flips landing this close to upright snap to neutral
# Steering authority while up on the front wheel. Reduced input is allowed; shoving past the
# crash threshold (CrashController.stoppie_steer_crash_threshold) washes the loaded front out.
const STOPPIE_STEER_SCALE: float = 0.5
# Auto stoppie — hold LT past AUTO_STOPPIE_BRAKE above this fraction of bd.max_speed for
# AUTO_STOPPIE_HOLD_SECS and the rear lifts without leaning forward.
const AUTO_STOPPIE_BRAKE: float = 0.9
const AUTO_STOPPIE_SPEED_FRAC: float = 0.6
const AUTO_STOPPIE_HOLD_SECS: float = 0.25
# Reverse — hold any brake while stopped to roll backwards. No clutch needed.
const REVERSE_MAX_SPEED: float = 2.0
const REVERSE_ACCEL: float = 8.0
const REVERSE_BRAKE_THRESHOLD: float = 0.3
const REVERSE_THROTTLE_MAX: float = 0.5 # on the gas = burnout/launch prep, not a reverse roll
# Drift / powerslide
const DRIFT_MIN_SPEED: float = 6.0 # below this it's a stationary burnout (slip stays ~0)
const DRIFT_BRAKE_HOLD: float = 0.4 # rear-brake input that sustains a brake slide
const DRIFT_STEER_ENTRY: float = 0.3 # steer needed to kick a brake slide loose
# power×accel torque gate to break traction. Kept at the wheelie gate's OLD value (was aliased to it)
# so lowering that gate for easier wheelies/clutch-ups leaves drift feel unchanged.
const DRIFT_BREAK_FORCE: float = 21.6
const DRIFT_POWER_MIN_RPM_RATIO: float = 0.7 # power slide needs revs — can't lug into a burnout at low RPM
# Stationary burnout — a max-RPM clutch dump against a held front brake spins up the rear from a standstill
const BURNOUT_FRONT_BRAKE_MIN: float = 0.5 # front brake to pin the bike; also blocks throttle accel in _speed_calc
const BURNOUT_MIN_RPM_RATIO: float = 0.85
const DRIFT_RECOVER_RATE: float = 2.0 # rad/s grip pulls the travel line back to heading
const DRIFT_RECOVER_SUPPRESS: float = 0.8 # how much drive (0..1) suppresses recovery (holds the slide)
const DRIFT_YAW_RATE: float = 1.6 # rad/s the heading carves per full steer while drifting
const DRIFT_SPEED_SCRUB: float = 0.6 # speed bleed per sec, proportional to |slip_angle|
const DRIFT_MAX_SLIP_ANGLE_DEG: float = 70.0 # clamp just past the 60° spinout so crash fires, no wrap
const BALANCE_LOCK_INPUT_EPS: float = 0.1 # throttle/brake/lean "touch" that releases the balance lock
var is_reversing: bool = false
var speed: float = 0.0
var roll_angle: float = 0.0 # lean left/right
var pitch_angle: float = 0.0 # + = wheelie, - = stoppie
## Latched once a wheelie's power targets past the balance point — the loop is then committed and
## survives an auto-upshift dropping the target, so a strong bike revved out in a low gear still loops.
## Synced (drives the pitch trajectory across ticks). Cleared by easing throttle / lean-forward / rear
## brake / the wheelie coming down. See _pitch_angle_calc.
var wheelie_committed: bool = false
var slip_angle: float = 0.0 # signed radians: heading vs velocity direction. Synced via RollbackSynchronizer.
var is_drifting: bool = false # re-derived each tick from synced inputs + slip_angle (not synced directly)
# true ONLY in a braking-held stoppie (not a coast/landing/burnout); gates scoring + washout crash
var is_stoppie: bool = false
var stoppie_brake_hold_time: float = 0.0 # auto-stoppie hard-brake hold accumulator (synced)
# true while pitch sits in the wheelie balance window. Re-derived each tick from the synced
# pitch_angle (not synced directly). Gates the right-stick trick tweaks + the wheelie cam.
var in_balance_point: bool = false
# Wheelie balance lock: holds the bike hands-free at the balance point (pitch + speed frozen)
# until released. Synced (persistent sim state). Toggled by an RB tap in the balance point, or
# via set_balance_locked() so a future powerup item can drive the same mechanism.
var balance_locked: bool = false
var hop_pitch_vel: float = 0.0 # synced — nose-down rate from the hop, cleared on landing
var bunny_hopped: bool = false # true on the tick a hop fires; TrickController latches it

var air_pitch_total: float = 0.0 # cumulative pitch rotation while airborne (for flip counting)
var air_time: float = 0.0 # time since takeoff (for wheelie grace window)
var was_on_floor: bool = false # previous tick's floor state (for landing detection)
var is_on_floor: bool = false # cached once per tick to avoid redundant move_and_slide calls
var speed_pct: float = 0.0 # speed / max_speed, cached per tick
var _wheelie_grace_consumed: bool = false # true once grace expired and pitch_angle was zeroed

# spawn protection - todo move?
var _default_spawn_timer: float = 1.0
var _spawn_timer: float = _default_spawn_timer

# Wheelie physics
var _rb_prev_held: bool = false # synced — RB rising-edge detection for the balance-lock toggle
var _lock_throttle_released: bool = false # synced — rule C: re-pressing throttle exits after a release
var _prev_clutch_held: bool = false
var _clutch_kick_window: float = 0.0
var _hop_launch_vel: float = 0.0 # synced — >0 while the hop rocks down on the ground, awaiting launch
var _balance_point_decay_mult: float = 0.85
# Blocks a wheelie chaining straight into a stoppie — must pass through normal first. Set while in a
# wheelie, cleared when brake + lean-forward aren't both held (forces a fresh press for the stoppie).
var _stoppie_locked_by_wheelie: bool = false
var _floor_normal: Vector3 = Vector3.UP # cached per tick — only valid when is_on_floor
var _on_unstable_surface: bool = false # touching layer 5 (unstable_collision), cached per tick


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

	# Synced freeze honored here so client prediction freezes too (input_disabled only gated the owning client).
	if player_entity.movement_locked:
		player_entity.velocity = Vector3.ZERO
		speed = 0.0
		return

	was_on_floor = is_on_floor
	is_on_floor = is_on_floor_netfox()
	_on_unstable_surface = _detect_unstable_surface()
	if is_on_floor:
		_floor_normal = _get_blended_surface_normal()
		# Landing — normalize pitch to effective angle from upright
		# e.g. 290° → -70° (70° from ground), full 360° → ~0°
		if not was_on_floor:
			pitch_angle = fmod(pitch_angle, TAU)
			if pitch_angle > PI:
				pitch_angle -= TAU
			elif pitch_angle < -PI:
				pitch_angle += TAU
			# Landing forgiveness: a near-upright landing after a flip snaps to neutral. Past the
			# wheelie / stoppie thresholds any jump lands as that trick (a stoppie decays unless
			# braked); over-rotations past the bike's max still crash via CrashController.
			var did_flip := air_pitch_total >= PI # half-turn+ = a flip attempt, not a held wheelie
			if (
				did_flip
				and pitch_angle >= deg_to_rad(TrickController.STOPPIE_PITCH_THRESHOLD_DEG)
				and pitch_angle <= deg_to_rad(TrickController.WHEELIE_PITCH_THRESHOLD_DEG)
			):
				pitch_angle = 0.0
			# Nose-first touchdown on the gas — the drive plants the rear, no stoppie under power.
			if pitch_angle < 0.0 and input_controller.nfx_throttle > 0.5:
				pitch_angle = 0.0
			air_pitch_total = 0.0
			air_time = 0.0
			_wheelie_grace_consumed = false
			hop_pitch_vel = 0.0
	else:
		# Takeoff — start grace window. Short hops (e.g. curbs) keep the wheelie;
		# once grace expires we zero pitch_angle so longer airtime lets air tricks
		# accumulate from level.
		if was_on_floor:
			air_pitch_total = 0.0
			air_time = 0.0
			_wheelie_grace_consumed = false
		air_time += delta
		if not _wheelie_grace_consumed and air_time >= WHEELIE_AIR_GRACE:
			# Clear a leftover ground-wheelie pitch after a long hop — but NEVER mid-flip.
			# air_pitch_total grows from air lean, so a meaningful value means the rider is
			# actively flipping; zeroing then whips the visual ("speeds up halfway") and discards
			# the rotation the landing-forgiveness snap relies on (causing late-flip land crashes).
			if air_pitch_total < deg_to_rad(LANDING_SNAP_ANGLE_DEG):
				pitch_angle = 0.0
				air_pitch_total = 0.0
			_wheelie_grace_consumed = true
	_speed_calc(delta)
	speed_pct = clampf(speed / player_entity.bike_definition.max_speed, 0.0, 1.0)
	_update_surface_alignment(delta)
	wobble_controller.update_is_wobbling()
	_drift_calc(delta)
	wobble_controller.tick(delta) # carves heading via rotate_y — slots with drift/steer (ORDER MATTERS)
	_steer_calc(delta)
	_velocity_calc(delta)
	_pitch_angle_calc(delta)

	# Trigger 5 — front wheel setting down from a ground wheelie (fires once, as the wheelie ends).
	# Injects after wobble_controller.tick, so it's picked up next tick (wobble_vel is synced).
	if is_on_floor and player_entity.trick_controller.wheelie_setting_down(delta):
		wobble_controller.kick_from_misalign("trigger 5 (wheelie set-down)", player_entity.velocity)
	wobble_controller.trick_feed(delta)

	# Apply movement
	var pre_slide_velocity := player_entity.velocity
	player_entity.velocity *= NetworkTime.physics_factor
	player_entity.move_and_slide()
	player_entity.velocity /= NetworkTime.physics_factor

	# Trigger 2 — judged here because the touchdown slide deflects velocity (a steep landing can reverse it).
	if not is_on_floor and player_entity.is_on_floor():
		wobble_controller.kick_bad_landing(pre_slide_velocity)

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
			+" | spd=%.1f vel=(%.1f,%.1f,%.1f) | trick=%s"
		)
		% [
			is_on_floor,
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


## True when near-stopped on a grade too steep for the bike to climb — CrashController
## stall-crashes the rider. Bounded below ADHESION_ANGLE so loop walls (handled by the
## adhesion / peel-off system) aren't mistaken for an un-climbable grade.
func is_stalled_on_steep_slope() -> bool:
	if not is_on_floor or speed >= STALL_CRASH_SPEED:
		return false
	var slope_angle = _floor_normal.angle_to(Vector3.UP)
	return (
		slope_angle > deg_to_rad(MAX_CLIMB_ANGLE_DEG) and slope_angle < deg_to_rad(ADHESION_ANGLE)
	)


## Blend normals from front + rear raycasts for smoother ramp transitions.
## Falls back to CharacterBody3D floor normal if neither raycast hits.
func _get_blended_surface_normal() -> Vector3:
	var front_hit = front_raycast.is_colliding()
	var rear_hit = rear_raycast.is_colliding()

	if front_hit and rear_hit:
		return (
			front_raycast
			.get_collision_normal()
			.lerp(rear_raycast.get_collision_normal(), 0.5)
			.normalized()
		)
	if front_hit:
		return front_raycast.get_collision_normal()
	if rear_hit:
		return rear_raycast.get_collision_normal()

	return player_entity.get_floor_normal()


## Align bike's up_direction to surface normal for ramp/loop riding
func _update_surface_alignment(delta: float):
	var pe = player_entity

	if is_on_floor:
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
			var blend_speed = lerpf(SURFACE_BLEND_SPEED_MIN, SURFACE_BLEND_SPEED_MAX, speed_pct)
			var t = clampf(blend_speed * delta, 0.0, 1.0)
			pe.up_direction = pe.up_direction.slerp(_floor_normal, t).normalized()
	else:
		_detach_from_surface(delta)


## Blend up_direction back to global up (airborne or detaching).
## More inverted = slower correction — rider falls on their head off a loop.
func _detach_from_surface(delta: float):
	var inversion = player_entity.up_direction.angle_to(Vector3.UP) / PI # 0=upright, 1=inverted
	# Upright: corrects quickly. Fully inverted: nearly frozen so they fall on their head.
	var correction_speed = lerpf(
		SURFACE_BLEND_SPEED_FALL, SURFACE_BLEND_SPEED_FALL * 0.05, inversion
	)
	player_entity.up_direction = (
		player_entity.up_direction.slerp(Vector3.UP, correction_speed * delta).normalized()
	)


## Front brake does nothing while the front wheel is lofted (wheelie) — nothing to brake in the air.
## pitch_angle here is last tick's value (_pitch_angle_calc runs later), matching is_in_wheelie()'s lag.
func _effective_front_brake() -> float:
	if pitch_angle > deg_to_rad(TrickController.WHEELIE_PITCH_THRESHOLD_DEG):
		return 0.0
	return input_controller.nfx_front_brake


## Rear brake does nothing while the rear wheel is up (stoppie) — nothing to brake in the air.
func _effective_rear_brake() -> float:
	if pitch_angle < deg_to_rad(TrickController.STOPPIE_PITCH_THRESHOLD_DEG):
		return 0.0
	return input_controller.nfx_rear_brake


## Calculate speed from input / power output
func _speed_calc(delta: float):
	var bd = player_entity.bike_definition
	var is_boosting: bool = player_entity.boost_controller.is_boosting
	var boost_accel: float = BoostController.BOOST_ACCEL_MULT if is_boosting else 1.0
	var boost_speed: float = BoostController.BOOST_SPEED_MULT if is_boosting else 1.0

	# Balance lock hovers the bike — hold speed steady (pitch is held in _pitch_angle_calc).
	if balance_locked:
		return

	# Airborne
	if not is_on_floor:
		is_reversing = false
		return

	# Reverse — hold any brake from a near-stop. Bypasses normal accel/brake/slope.
	var brake_total = _effective_front_brake() + _effective_rear_brake()
	# Off-gas only — a burnout / launch prep (front brake + throttle) must not read as reverse.
	var reverse_input = (
		brake_total > REVERSE_BRAKE_THRESHOLD
		and input_controller.nfx_throttle < REVERSE_THROTTLE_MAX
	)
	if reverse_input and (is_reversing or speed <= 0.5):
		is_reversing = true
		speed = move_toward(speed, -REVERSE_MAX_SPEED, REVERSE_ACCEL * delta)
		return
	if is_reversing:
		# Inputs released — decay back to 0, then resume normal logic next tick.
		speed = move_toward(speed, 0.0, REVERSE_ACCEL * delta)
		if speed >= 0.0:
			is_reversing = false
			speed = 0.0
		return

	# Slope analysis (heading-based so it stays stable at low speed, unlike a velocity
	# direction that goes noisy near a stop). slope_dot > 0 = pointing downhill, < 0 = climbing.
	# Used by both the acceleration gate and the slope gravity below.
	var slope_angle = _floor_normal.angle_to(Vector3.UP)
	var gravity_on_surface = Vector3.DOWN - _floor_normal * Vector3.DOWN.dot(_floor_normal)
	var forward_dir = - player_entity.global_transform.basis.z
	var slope_dot = gravity_on_surface.dot(forward_dir)
	# Too steep to climb — block engine drive; gravity then bleeds the bike to a stall (crash).
	var too_steep_to_climb = slope_angle > deg_to_rad(MAX_CLIMB_ANGLE_DEG) and slope_dot < 0.0

	# Acceleration (uses gearing power output)
	# Hard braking (> 0.5) cuts throttle so the brake can always bring you to a
	# stop. Light braking keeps throttle for trail-braking.
	var power = gearing_controller.get_power_output()
	var gear_max_speed = gearing_controller.get_gear_max_speed(gearing_controller.current_gear) * boost_speed
	if power > 0 and speed < gear_max_speed and brake_total <= 0.5 and not too_steep_to_climb:
		speed += bd.acceleration * power * boost_accel * delta
		speed = minf(speed, gear_max_speed)
	# Engine braking — applies when not on throttle, stronger at higher RPM
	elif power <= 0 and speed > 0.5:
		var rpm_factor = gearing_controller.get_rpm_ratio()
		speed = move_toward(speed, 0, bd.engine_brake_strength * rpm_factor * delta)

	# Braking
	var total_brake = _effective_front_brake() + _effective_rear_brake()
	if total_brake > 0:
		speed = move_toward(speed, 0, bd.brake_strength * total_brake * delta)

	# Slope gravity — projects a dedicated (gentler) gravity along the surface. Downhill
	# (slope_dot > 0) adds speed; uphill bleeds it with NO min-speed floor, so the bike actually
	# slows to a stop climbing instead of creeping up forever. Guarded on motion so a fully
	# stopped bike doesn't spontaneously roll off.
	if is_on_floor and player_entity.velocity.length_squared() > 0.01:
		var factor = RAMP_DOWNHILL_FACTOR if slope_dot > 0.0 else RAMP_UPHILL_FACTOR
		speed += SLOPE_GRAVITY * slope_dot * factor * delta
		speed = maxf(speed, 0.0)

	# Unstable surface drag — proportional to speed so low-speed launches still work.
	# Equilibrium with throttle settles around a fraction of normal top speed.
	var unstable_factor = get_unstable_factor()
	if unstable_factor > 0 and speed > 0:
		speed -= speed * UNSTABLE_DRAG_RATE * unstable_factor * delta

	speed = minf(speed, bd.max_speed * boost_speed)


## Calculate roll_angle & set player_entity.rotation
func _steer_calc(delta: float):
	var bd = player_entity.bike_definition

	var amount_normalized_rename_me := 1.0
	if player_entity.trick_controller.current_trick == TrickController.Trick.TWO_LEFT_FEET:
		amount_normalized_rename_me = 0.5
	elif speed < 1 and not is_reversing:
		amount_normalized_rename_me = 0.2

	# One wheel off the ground cuts steering authority. Scale the TARGET, not the accumulated
	# roll_angle — multiplying roll every tick compounds toward ~4% (kills steering AND puts the
	# washout out of reach), whereas a target scale settles at a true fraction. Derived inline from
	# pitch since _pitch_angle_calc hasn't run yet this tick. Wheelie keeps full steer at a crawl so
	# tight circle wheelies stay possible.
	var trick_steer_scale := 1.0
	if pitch_angle < deg_to_rad(TrickController.STOPPIE_PITCH_THRESHOLD_DEG):
		trick_steer_scale = STOPPIE_STEER_SCALE
	elif (
		pitch_angle > deg_to_rad(TrickController.WHEELIE_PITCH_THRESHOLD_DEG)
		and speed > WHEELIE_STEER_FULL_SPEED
	):
		trick_steer_scale = WHEELIE_STEER_SCALE

	# ONCE STOPPED, LERP BACK TO DEFAULT POSE

	# Curve-based speed factor for steering and lean. Reverse bypasses the curves —
	# they're tuned for forward speed and bottom out near 0, so we'd lose all authority.
	var lean_factor = 1.0 if is_reversing else bd.lean_curve.sample(speed_pct)
	var steer_input = - input_controller.nfx_steer if is_reversing else input_controller.nfx_steer
	var target_lean = steer_input * bd.max_lean_angle_rad * lean_factor * trick_steer_scale
	roll_angle = lerpf(roll_angle, target_lean, bd.lean_speed * delta) * amount_normalized_rename_me

	# Steering — bell curve: low at standstill, peaks mid-low speed, tapers at top speed.
	# Uses abs(speed) so reverse rolling still turns the body.
	if absf(speed) > 0.5 and not is_drifting: # steering stays live while wobbling — the wobble rides on top
		var steer_factor = 1.0 if is_reversing else (bd.steer_curve.sample(speed_pct) if bd.steer_curve else 1.0)
		var turn_rate = bd.turn_speed * steer_factor * (1.0 - get_unstable_factor() * UNSTABLE_STEER_SUPPRESSION)
		DebugUtils.DebugMsg(
			(
				"Steer: spd=%.1f spd%%=%.0f%% curve=%.2f rate=%.2f"
				% [speed, speed_pct * 100, steer_factor, turn_rate]
			),
			OS.has_feature("debug") and debug_verbose
		)
		player_entity.rotate_y(-roll_angle * turn_rate * delta)

	# Align bike basis so local Y points along up_direction (ramp riding)
	var target_up = player_entity.up_direction
	var current_forward = - player_entity.global_transform.basis.z
	var right = current_forward.cross(target_up)
	if right.length_squared() > 0.001:
		right = right.normalized()
		var adjusted_forward = target_up.cross(right).normalized()
		player_entity.global_transform.basis = Basis(right, target_up, -adjusted_forward)


## Calculate player_entity.velocity & set slope angle
func _velocity_calc(delta: float):
	# Apply velocity following slope
	var forward = - player_entity.global_transform.basis.z
	# Drift: velocity travels along heading rotated by slip_angle (tail out). slip_angle==0
	# (normal riding) leaves this identical to forward.
	var travel_dir = forward
	if is_drifting:
		# Rotate about global Y to match the heading carve (rotate_y) so slip stays
		# consistent on ramps; .slide(_floor_normal) below reprojects onto the surface.
		travel_dir = forward.rotated(Vector3.UP, slip_angle)
	if is_on_floor:
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
			speed = new_h # keep speed in sync for landing, wheel spin, steering

	# Gravity — integrated onto velocity.y so airborne flight arcs like a real parabola
	# instead of dropping at a constant rate.
	if !is_on_floor:
		player_entity.velocity.y -= FALL_GRAVITY * delta


## Orchestrates pitch_angle: clutch detection → wheelie target → stoppie → apply
func _pitch_angle_calc(delta: float):
	_update_clutch_dump_detection()
	bunny_hopped = false
	is_stoppie = false # _stoppie_calc re-asserts it below; stays false when airborne / in a wheelie / on steep ground
	in_balance_point = false # re-asserted below when in the window; false when airborne / wobbling / steep

	if wobble_controller.is_wobbling:
		balance_locked = false
		# Can't pop tricks mid-tank-slapper — bleed pitch to neutral. A trick wobble (trigger 6) keeps
		# an up wheelie's physics, so the rider can climb into the balance point to settle it.
		var trick_wheelie := (
			wobble_controller.wobble_from_trick
			and pitch_angle > deg_to_rad(TrickController.WHEELIE_PITCH_THRESHOLD_DEG)
		)
		if not trick_wheelie:
			pitch_angle = move_toward(
				pitch_angle, 0.0, player_entity.bike_definition.return_speed * delta
			)
			return

	# Airborne trick control — lean to flip, no decay (weightless)
	if not is_on_floor:
		# A bump or slope crest isn't a jump — the lock resumes on touchdown.
		if air_time >= TrickController.AIR_TRICK_MIN_AIRTIME:
			balance_locked = false
		# Hop rock stops short of a stoppie — the usual brake + lean method starts one after landing.
		if hop_pitch_vel > 0.0:
			pitch_angle = maxf(
				pitch_angle - hop_pitch_vel * delta,
				deg_to_rad(TrickController.STOPPIE_PITCH_THRESHOLD_DEG)
			)
		# The hop owns pitch until landing — the held lean-forward that fired it would double the rock.
		if input_controller.nfx_lean != 0 and hop_pitch_vel == 0.0:
			# Lean back (negative) = backflip (positive pitch), lean forward = frontflip
			var rotation_delta = input_controller.nfx_lean * AIR_TRICK_ROTATION_SPEED * delta
			pitch_angle -= rotation_delta
			air_pitch_total += abs(rotation_delta)
		return

	var bd = player_entity.bike_definition
	var in_wheelie = pitch_angle > deg_to_rad(TrickController.WHEELIE_PITCH_THRESHOLD_DEG)
	var in_stoppie = pitch_angle < deg_to_rad(TrickController.STOPPIE_PITCH_THRESHOLD_DEG)
	if in_wheelie: # arm the lock so the coming-down nose can't flow straight into a stoppie
		_stoppie_locked_by_wheelie = true
	var bp_low = deg_to_rad(bd.wheelie_balance_point_deg - bd.wheelie_balance_point_width_deg)
	var bp_high = deg_to_rad(bd.wheelie_balance_point_deg + bd.wheelie_balance_point_width_deg)
	in_balance_point = pitch_angle >= bp_low and pitch_angle <= bp_high
	var above_balance_point = pitch_angle > bp_high

	# Disable tricks on steep surfaces — decay pitch back to neutral
	var surface_angle = player_entity.up_direction.angle_to(Vector3.UP)
	if surface_angle > deg_to_rad(TRICK_DISABLE_ANGLE):
		balance_locked = false
		if pitch_angle != 0:
			pitch_angle = move_toward(pitch_angle, 0, bd.return_speed * delta)
		return

	if _bunny_hop_calc(in_wheelie, delta):
		return

	# Balance lock: RB-tap toggle + exit rules, then hover at the balance point. Leaning fwd/back
	# nudges the held pitch; drift out of the sweet spot and the lock drops (rider lost balance).
	_update_balance_lock()
	if balance_locked:
		if input_controller.nfx_lean != 0.0:
			pitch_angle -= input_controller.nfx_lean * bd.rotation_speed * delta
		else:
			pitch_angle = move_toward(
				pitch_angle, deg_to_rad(bd.wheelie_balance_point_deg), bd.rotation_speed * delta
			)
		if pitch_angle >= bp_low and pitch_angle <= bp_high:
			in_balance_point = true
			return
		set_balance_locked(false) # left the sweet spot — fall through to normal wheelie physics

	# --- Wheelie ---
	var wheelie_target = 0.0
	if _can_initiate_wheelie(in_wheelie) and not in_stoppie:
		wheelie_target = _calc_normal_wheelie_target(bd)
		# Loop commit: once the bike's power targets past the balance point (or pitch is already there),
		# it's going over — LATCH it. The latch survives an auto-upshift dropping the target below the
		# threshold, so a strong bike revved out in 1st keeps looping as it shifts up (the log showed it
		# stalling at ~78° right when it upshifted). A weak bike never targets past bp_high, so it never
		# latches and just holds a wheelie.
		if wheelie_target > bp_high or above_balance_point:
			wheelie_committed = true
	else:
		wheelie_committed = false
	# Bail out of a committed loop by easing throttle, leaning forward, rear-braking, or once it has
	# come down — the rider's saves. (Lean-forward / rear-brake recovery is applied further below too.)
	if (
		not in_wheelie
		or input_controller.nfx_throttle < 0.5
		or input_controller.nfx_lean > 0.0
		or _effective_rear_brake() > 0.0
	):
		wheelie_committed = false
	# Committed → drive to the loop and climb hard through the balance window (see _apply_wheelie_pitch).
	var punch_through = wheelie_committed
	if wheelie_committed:
		wheelie_target = _calc_above_balance_point_target(bd, bp_low, bp_high)

	DebugUtils.DebugMsg(
		(
			(
				"pitch_angle: %.2f | wheelie_target: %.2f | balance_point: %.2f | "
				+"max_wheelie: %.2f | in_bp: %s"
			)
			% [
				rad_to_deg(pitch_angle),
				rad_to_deg(wheelie_target),
				bd.wheelie_balance_point_deg,
				bd.max_wheelie_angle_deg,
				in_balance_point
			]
		),
		OS.has_feature("debug") and debug_verbose
	)

	# Lean forward recovery — pull the front wheel down
	if input_controller.nfx_lean > 0 and in_wheelie:
		pitch_angle = move_toward(
			pitch_angle, 0, bd.return_speed * input_controller.nfx_lean * 2.0 * delta
		)

	# Off-gas front-wheel drop — only once lean is released (leaning back still holds the wheelie).
	# Speed only slightly slows it (floored at 0.5) so releasing lean at speed still brings it down.
	if in_wheelie and input_controller.nfx_lean >= 0 and input_controller.nfx_throttle < 0.5:
		var speed_ratio = clampf(speed / (bd.max_speed * 0.5), 0.0, 1.0)
		var wheelie_gravity = bd.return_speed * (1.0 - speed_ratio * 0.5)
		# Balance point stabilizes the wheelie — gravity is dampened here too
		if in_balance_point:
			wheelie_gravity *= _balance_point_decay_mult * 2.0
		pitch_angle = move_toward(pitch_angle, 0, wheelie_gravity * delta)

	# Rear brake stabs the front down (rear wheel loads, weight pitches forward). Works on throttle
	# too, so you can chop a wheelie with the brake instead of only lean/off-gas. Rear brake is live
	# in a wheelie (rear is grounded); _effective_rear_brake only zeroes it in a stoppie.
	if in_wheelie and _effective_rear_brake() > 0.0:
		pitch_angle = move_toward(
			pitch_angle, 0, bd.return_speed * _effective_rear_brake() * WHEELIE_REAR_BRAKE_DROP * delta
		)

	# Rev limiter — power cuts at redline (get_power_output returns 0), so the force-driven wheelie
	# target collapses on its own and the front eases down. No extra pitch slam: it used to shove the
	# nose down harder than the climb, which blocked a strong bike from looping out at redline. Just
	# bleed a little speed to signal the limiter.
	if in_wheelie and gearing_controller.is_rev_limited:
		speed = move_toward(speed, speed * 0.95, bd.max_speed * 0.1 * delta)

	_apply_wheelie_pitch(bd, wheelie_target, in_balance_point, punch_through, delta)

	# --- Stoppie ---
	if not in_wheelie:
		_stoppie_calc(bd, in_stoppie, delta)

	# TODO: easy mode clamp


## Fires from a low wheelie on lean forward with the gas off (on-gas lean forward is still recovery).
## The nose rocks down on the ground first; the rear only leaves once it passes level (weight shifted
## forward). Returns true while that ground phase owns pitch.
func _bunny_hop_calc(in_wheelie: bool, delta: float) -> bool:
	if _hop_launch_vel == 0.0:
		hop_pitch_vel = 0.0 # landed, or the launch never left the floor
		var max_pitch := deg_to_rad(
			player_entity.bike_definition.wheelie_balance_point_deg * HOP_MAX_BALANCE_FRAC
		)
		if not (
			in_wheelie
			and pitch_angle <= max_pitch
			and input_controller.nfx_throttle < 0.5
			and input_controller.nfx_lean >= 0.5
		):
			return false
		bunny_hopped = true
		hop_pitch_vel = pitch_angle * HOP_PITCH_KICK
		_hop_launch_vel = HOP_VELOCITY
	pitch_angle -= hop_pitch_vel * delta
	if pitch_angle <= 0.0:
		player_entity.velocity.y += _hop_launch_vel
		_hop_launch_vel = 0.0
	return true


## Engage/release the wheelie balance lock. Exposed as a plain toggle so a pickup item can drive
## the same hands-free hold, not just the RB tap. Resets the throttle-release gate on engage.
func set_balance_locked(locked: bool) -> void:
	balance_locked = locked
	_lock_throttle_released = false


## RB-tap toggle + exit rules for the balance lock. Runs after in_balance_point is known this tick.
func _update_balance_lock() -> void:
	var rb := input_controller.nfx_trick_held
	var rb_tapped := rb and not _rb_prev_held
	_rb_prev_held = rb

	if balance_locked:
		# Rule C: throttle can be released while locked, but touching it again releases the lock.
		if input_controller.nfx_throttle < BALANCE_LOCK_INPUT_EPS:
			_lock_throttle_released = true
		var throttle_exit := (
			_lock_throttle_released and input_controller.nfx_throttle >= BALANCE_LOCK_INPUT_EPS
		)
		# Lean is NOT an exit — it adjusts the held pitch in _pitch_angle_calc, dropping the lock
		# only if it leaves the sweet spot. Brake still bails immediately.
		var control_exit := (
			_effective_front_brake() > BALANCE_LOCK_INPUT_EPS
			or _effective_rear_brake() > BALANCE_LOCK_INPUT_EPS
		)
		if rb_tapped or throttle_exit or control_exit:
			set_balance_locked(false)
	elif rb_tapped and in_balance_point:
		set_balance_locked(true)


## Apply wheelie pitch toward target, or decay back to 0. punch_through = the bike has the power to
## loop, so climb at full rate through the balance point instead of damping/rate-scaling it (those
## would leave a strong bike stuck just short of the loop).
func _apply_wheelie_pitch(
	bd: BikeSkinDefinition,
	wheelie_target: float,
	in_balance_point: bool,
	punch_through: bool,
	delta: float
):
	if wheelie_target > 0:
		var spd = bd.rotation_speed
		if in_balance_point and not punch_through:
			spd *= _balance_point_decay_mult
		var rate_scale = 1.0 if punch_through else WHEELIE_RISE_RATE_SCALE
		var climb = spd * rate_scale
		# Clutch dump snaps the front up fast — added AFTER rate_scale so a low WHEELIE_RISE_RATE_SCALE
		# doesn't blunt the pop. Fades with speed (a launch move).
		if _clutch_kick_window > 0:
			var speed_falloff = 1.0 - clampf(speed / (bd.max_speed * 0.3), 0.0, 1.0)
			climb += bd.rotation_speed * WHEELIE_CLUTCH_KICK_BOOST * speed_falloff
		pitch_angle = move_toward(pitch_angle, wheelie_target, climb * delta)
	elif pitch_angle > 0:
		var decay_speed = (
			bd.return_speed * _balance_point_decay_mult if in_balance_point else bd.return_speed
		)
		pitch_angle = move_toward(pitch_angle, 0, decay_speed * delta)


## Stoppie physics: brake + lean forward lifts the rear wheel (manual), or a long hard front-brake
## hold at high speed lifts it on its own (auto — see AUTO_STOPPIE_*).
func _stoppie_calc(bd: BikeSkinDefinition, in_stoppie: bool, delta: float):
	# Only the front brake pitches the nose down — the rear can't lift itself off the ground.
	var total_brake = _effective_front_brake()
	var max_stoppie_rad = deg_to_rad(bd.max_stoppie_angle_deg)

	# Dynamic brake threshold: need more brake to start, less to sustain at deeper angles
	var stoppie_ratio = clampf(abs(pitch_angle) / max_stoppie_rad, 0.0, 1.0)
	var required_brake = lerpf(0.5, 0.15, stoppie_ratio)

	# Clear the after-wheelie lock once the stoppie inputs are released — forces a fresh press, so a
	# wheelie can't chain straight into a stoppie (wheelie -> normal -> stoppie is still fine).
	if not (total_brake > required_brake and input_controller.nfx_lean > 0.3):
		_stoppie_locked_by_wheelie = false

	# Auto hold timer: counts while LT is held hard at high speed. Once the nose is up the sustain
	# threshold applies instead, so easing LT lowers the stoppie rather than dropping it outright.
	var auto_brake = required_brake if in_stoppie else AUTO_STOPPIE_BRAKE
	if total_brake > auto_brake and (in_stoppie or speed > bd.max_speed * AUTO_STOPPIE_SPEED_FRAC):
		stoppie_brake_hold_time += delta
	else:
		stoppie_brake_hold_time = 0.0

	var can_lift = (
		not _stoppie_locked_by_wheelie
		and speed > 3.0
		and abs(roll_angle) < deg_to_rad(10)
		and not is_drifting # a burnout/brake-slide is weight-back — can't pitch onto the front
		and input_controller.nfx_throttle <= 0.5 # no stoppies under power
	)
	var manual_stoppie = (
		can_lift and total_brake > required_brake and input_controller.nfx_lean > 0.3
	)
	var auto_stoppie = can_lift and stoppie_brake_hold_time > AUTO_STOPPIE_HOLD_SECS
	var can_stoppie = manual_stoppie or auto_stoppie
	# Scores the whole time the nose is up (symmetric with the wheelie's pitch check), including a
	# nose-first landing off the gas (on the gas it flattens on touchdown); a burnout (is_drifting)
	# is the one case to exclude.
	is_stoppie = in_stoppie and not is_drifting

	if can_stoppie or in_stoppie:
		var speed_factor = clampf(speed / (bd.max_speed * 0.25), 0.0, 1.0)
		var stoppie_target: float
		if manual_stoppie:
			# Target deepens with brake + lean — speed just needs a minimum
			var brake_pct = clampf(total_brake * 1.5, 0.0, 1.0)
			# Target can exceed max — crash controller will trigger if you go over
			stoppie_target = - max_stoppie_rad * (0.5 + brake_pct * 0.7) * speed_factor
		else:
			# Auto: deepens with LT pressure and keeps climbing while held — hold too long and it goes over.
			var hold_ramp = (
				(stoppie_brake_hold_time - AUTO_STOPPIE_HOLD_SECS) / AUTO_STOPPIE_HOLD_SECS
			)
			stoppie_target = - max_stoppie_rad * total_brake * hold_ramp * speed_factor

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

	# Clutch dump pop — gates on POTENTIAL power (ignores engagement, since clutch_value is still ~1.0
	# at the dump instant) × acceleration, the same wheel-force units as the power gate below. A bike
	# too weak to loft (mini) can't clutch-pop one either, and a tall gear (3rd+) lacks the torque.
	var clutch_pop = _clutch_kick_window > 0 and input_controller.nfx_throttle > 0.5
	if clutch_pop:
		# Low-speed launch move only — don't let slope-inflated downhill speed clutch-pop a wheelie.
		if speed > bd.max_speed * CLUTCH_POP_MAX_SPEED_FRAC:
			return false
		return gearing_controller.get_potential_power_output() * bd.acceleration > POWER_WHEELIE_MIN_FORCE

	# Power wheelie — needs forward motion + throttle + delivered force. Lean-back is NOT required
	# (it only boosts the target in _calc_normal_wheelie_target); throttle + power alone lofts the
	# front. Gate uses power × bd.acceleration (bike's actual wheel force), so weaker bikes
	# (lower acceleration) auto-fail without needing a per-bike flag.
	if speed <= 1:
		return false
	var force = gearing_controller.get_power_output() * bd.acceleration
	return input_controller.nfx_throttle > 0.7 and force > POWER_WHEELIE_MIN_FORCE


## Drift entry. Mirror of the wheelie clutch/power gates but gated on lean FORWARD
## (lean back = wheelie, lean forward = drift), plus a rear-brake-slide entry.
func _can_initiate_drift() -> bool:
	if is_drifting:
		return true
	if not is_on_floor:
		return false

	# Stationary burnout — a max-RPM clutch dump against a held front brake lights up the rear from
	# a standstill. Checked before the min-speed gate so it starts at ~0 velocity; the front brake
	# also blocks throttle accel in _speed_calc, so you sit and spin until you release it and roll
	# into a normal power drift (is_drifting carries straight over).
	if speed < DRIFT_MIN_SPEED:
		return (
			_clutch_kick_window > 0
			and input_controller.nfx_throttle > 0.5
			and input_controller.nfx_front_brake > BURNOUT_FRONT_BRAKE_MIN
			and input_controller.nfx_lean > 0.3
			and gearing_controller.get_rpm_ratio() > BURNOUT_MIN_RPM_RATIO
		)

	# Brake-slide entry — steer + hold rear brake breaks the rear loose. Accessible, safe to release.
	if _is_brake_slide_input():
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

	# Power slide — floored throttle at high RPM + enough delivered force to break traction.
	# The RPM gate is what stops a lean-forward + gas + steer burnout in any gear at any revs.
	var force = gearing_controller.get_power_output() * bd.acceleration
	return (
		input_controller.nfx_throttle > 0.7
		and gearing_controller.get_rpm_ratio() > DRIFT_POWER_MIN_RPM_RATIO
		and force > DRIFT_BREAK_FORCE
	)


## Maintain is_drifting and integrate slip_angle. Runs before _velocity_calc so
## velocity picks up the slip this tick. No-op (and slip decays to 0) when not drifting.
func _drift_calc(delta: float):
	# --- entry / exit ---
	# A tank-slapper takes over from drifting (and airborne / crashed unwind slip too).
	if player_entity.is_crashed or not is_on_floor or wobble_controller.is_wobbling:
		is_drifting = false
		wobble_controller.wobble_brake_hold_time = 0.0
		slip_angle = move_toward(slip_angle, 0.0, DRIFT_RECOVER_RATE * delta)
		return

	if not is_drifting:
		# Trigger 1b: a high-speed brake-slide entry wobbles instead of starting a drift.
		if _is_brake_slide_input() and speed_pct > WobbleController.WOBBLE_BRAKE_ENTRY_SPEED_FRAC:
			var kick := signf(input_controller.nfx_steer) * WobbleController.WOBBLE_BRAKE_ENTRY_STRENGTH
			wobble_controller.wobble_vel += kick
			DebugUtils.DebugMsg(
				"wobble trigger 1b (high-speed brake entry): spd=%.0f%%" % (speed_pct * 100.0),
				OS.has_feature("debug") and debug_verbose
			)
		else:
			is_drifting = _can_initiate_drift()

	wobble_controller.update_brake_slide(delta) # trigger 1a

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


func _is_brake_slide_input() -> bool:
	return (
		_effective_rear_brake() > DRIFT_BRAKE_HOLD
		and absf(input_controller.nfx_steer) > DRIFT_STEER_ENTRY
	)


## Calculate wheelie target. Loft is driven by the bike's real wheel force (get_power_output ×
## acceleration — the SAME quantity the start gate uses), mapped straight to an angle. A strong or
## peaky power band drives the target past the balance point (loops); a weaker one tops out below it;
## a bike too weak to clear the start gate never gets here (the mini). All of it follows the existing
## power_curve, gearing and acceleration — no per-bike wheelie flag. Lean adds authority on a capable
## bike; the start gate (not this function) is what keeps a too-weak bike from lofting at all.
func _calc_normal_wheelie_target(bd: BikeSkinDefinition) -> float:
	var max_wheelie_rad = deg_to_rad(bd.max_wheelie_angle_deg)
	# Unstable surfaces shrink the achievable target so reaching the balance point takes more input.
	var unstable_scale = 1.0 - get_unstable_factor() * UNSTABLE_WHEELIE_SUPPRESSION
	# Force = the bike's real wheel force (same quantity as the start gate). During a clutch dump the
	# clutch is still disengaged, so get_power_output() reads ~0 — fall back to potential power there
	# (what the clutch-pop gate uses) or a clutch-up would loft nothing.
	var power_out = gearing_controller.get_power_output()
	if _clutch_kick_window > 0:
		# Clutch dump: engagement ~0 so get_power_output() reads ~0 — use potential power, then add the
		# dump's torque SPIKE so a clutch-up lofts harder than steady power (biggest at low speed).
		var speed_falloff := 1.0 - clampf(speed / (bd.max_speed * 0.3), 0.0, 1.0)
		power_out = maxf(power_out, gearing_controller.get_potential_power_output())
		power_out *= 1.0 + WHEELIE_CLUTCH_KICK_BOOST * speed_falloff
	var power_target = power_out * bd.acceleration * WHEELIE_FORCE_TO_ANGLE
	if power_target <= 0.0:
		return 0.0 # no power = no wheelie; lean alone can't float one (keeps the mini planted)
	# Lean-back (negative) adds on top, lean-forward trims — as a fraction of max_wheelie.
	var target = power_target - input_controller.nfx_lean * WHEELIE_LEAN_INFLUENCE * max_wheelie_rad
	return clampf(target, 0.0, max_wheelie_rad) * unstable_scale


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
		# Golden-angle spread per peer id — deterministic so server & client resimulate
		# the same push during rollback (randf() here caused constant desync corrections).
		var push_angle = fposmod(int(str(player_entity.name)) * 2.399963, TAU)
		var offset = Vector3(cos(push_angle), 0.5, sin(push_angle))
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
	wheelie_committed = false
	slip_angle = 0.0
	is_drifting = false
	is_stoppie = false
	stoppie_brake_hold_time = 0.0
	in_balance_point = false
	balance_locked = false
	_rb_prev_held = false
	_lock_throttle_released = false
	_stoppie_locked_by_wheelie = false
	is_reversing = false
	was_on_floor = false
	_prev_clutch_held = false
	_clutch_kick_window = 0.0
	hop_pitch_vel = 0.0
	_hop_launch_vel = 0.0
	bunny_hopped = false
	air_pitch_total = 0.0
	air_time = 0.0
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
	if wobble_controller == null:
		issues.append("wobble_controller must not be empty")
	if rear_raycast == null:
		issues.append("rear_raycast must not be empty")
	if front_raycast == null:
		issues.append("front_raycast must not be empty")
	return issues
