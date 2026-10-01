@tool
## The speed wobble (tank-slapper): a damped oscillator on the heading plus the triggers that kick it.
## Driven by MovementController mid-tick (heading carve must slot between drift and steer), not by
## PlayerEntity._rollback_tick. CrashController highsides past WOBBLE_CRASH_ANGLE_DEG.
class_name WobbleController extends Node

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var movement_controller: MovementController

const WOBBLE_SPRING: float = 120.0 # restoring spring (rad/s² per rad) — higher = tighter
const WOBBLE_DAMPING: float = 1.5 # base per-sec taper
const WOBBLE_COUNTERSTEER_BONUS: float = 8.0 # extra damping when countersteering (fast save)
const WOBBLE_OFFGAS_BONUS: float = 3.0 # extra damping from off-gas + steer (slower save)
const WOBBLE_FEED: float = 6.0 # energy/sec added when steering into the swing
const WOBBLE_RECOVER_BOOST: float = 6.0 # extra damping that ramps up as you near center (forgiving)
const WOBBLE_MIN_SPEED: float = 15.0 # below this no wobble starts, and slowing kills an active one
const WOBBLE_CRASH_ANGLE_DEG: float = 60.0 # |wobble_angle| past this highsides
# Triggers 1a (brake-slide release), 1b (high-speed brake entry), 5 (wheelie set-down) and 6 (wheelie
# trick off the balance point) are always on.
const WOBBLE_RELEASE_MIN_HOLD: float = 0.25 # 1a: brake-slide hold (sec) that wobbles
const WOBBLE_RELEASE_MIN_ANGLE_DEG: float = 30.0 # 1a: release slip (deg) that wobbles
const WOBBLE_RELEASE_STRENGTH: float = 6.0 # 1a kick (rad/s)
const WOBBLE_BRAKE_ENTRY_SPEED_FRAC: float = 0.6 # 1b: speed frac above which entry wobbles
const WOBBLE_BRAKE_ENTRY_STRENGTH: float = 7.0 # 1b kick (rad/s)
const WOBBLE_LANDING_MIN_AIRTIME: float = 0.5 # trigger 2: only jumps longer than this wobble
const WOBBLE_LANDING_ANGLE_DEG: float = 20.0 # trigger 2: landing misalignment (deg) window
const WOBBLE_LANDING_STRENGTH: float = 0.4 # trigger 2 kick (rad/s) per deg past the window
const WOBBLE_LANDING_HARD_OVER_DEG: float = 50.0 # deg past the window that highsides outright (no cap)
const WOBBLE_TRICK_FEED: float = 2.0 # trigger 6: feed (rad/s²) per deg a wheelie trick is off the balance point
const WOBBLE_TRICK_CRASH_MISS_DEG: float = 45.0 # trigger 6: deg off balance point = crash-sized swing

const WOBBLE_EPS: float = 0.03 # |wobble_angle|/|wobble_vel| below this counts as settled (snaps clean)

# Tank-slapper. angle/vel/hold are synced (perturb heading — see CLAUDE.md Multiplayer); is_wobbling re-derived.
var wobble_angle: float = 0.0 # signed yaw perturbation (rad)
var wobble_vel: float = 0.0 # its angular velocity (rad/s)
var wobble_brake_hold_time: float = 0.0 # brake-slide hold accumulator (trigger 1a)
var is_wobbling: bool = false
var wobble_from_trick: bool = false # synced — trigger 6 fed this wobble; the wheelie stays up until it settles


## Re-derive is_wobbling from the synced angle/vel (is_wobbling itself isn't synced).
func update_is_wobbling() -> void:
	is_wobbling = absf(wobble_angle) > WOBBLE_EPS or absf(wobble_vel) > WOBBLE_EPS


## Trigger 1a. Accumulate brake-slide hold; on release a long hold OR big angle wobbles.
func update_brake_slide(delta: float):
	var mc := movement_controller
	if mc.is_drifting and input_controller.nfx_rear_brake > MovementController.DRIFT_BRAKE_HOLD:
		wobble_brake_hold_time += delta
		return
	if wobble_brake_hold_time <= 0.0:
		return
	var release_slip := absf(mc.slip_angle)
	if (
		wobble_brake_hold_time > WOBBLE_RELEASE_MIN_HOLD
		or release_slip > deg_to_rad(WOBBLE_RELEASE_MIN_ANGLE_DEG)
	):
		var kick_sign := signf(mc.slip_angle) if release_slip > 0.01 else signf(input_controller.nfx_steer)
		if kick_sign == 0.0:
			kick_sign = 1.0
		wobble_vel += kick_sign * WOBBLE_RELEASE_STRENGTH
		DebugUtils.DebugMsg(
			(
				"wobble trigger 1a (rear-brake release): slip=%.0f° hold=%.2fs"
				% [rad_to_deg(release_slip), wobble_brake_hold_time]
			),
			OS.has_feature("debug") and movement_controller.debug_verbose
		)
	wobble_brake_hold_time = 0.0


## Trigger 6. A right-stick trick run outside the wheelie balance point pumps a wobble up to a swing
## sized by how far off the window pitch is; past that size, tick damps it back down.
func trick_feed(delta: float):
	var miss_deg := _balance_point_miss_deg()
	if (
		movement_controller.speed < WOBBLE_MIN_SPEED
		or miss_deg <= 0.0
		or _amplitude() >= _trick_target_amp()
		or not player_entity.trick_controller.is_wheelie_stick_trick()
	):
		return
	# Pump the current swing; a fresh one starts toward the steer side.
	var kick_sign := signf(wobble_vel) if is_wobbling else signf(input_controller.nfx_steer)
	if kick_sign == 0.0:
		kick_sign = 1.0
	wobble_vel += kick_sign * WOBBLE_TRICK_FEED * miss_deg * delta
	wobble_from_trick = true


## Swing (rad) a trick wobble settles toward: the crash angle at WOBBLE_TRICK_CRASH_MISS_DEG off the
## balance point, 0 inside it.
func _trick_target_amp() -> float:
	var miss_ratio := _balance_point_miss_deg() / WOBBLE_TRICK_CRASH_MISS_DEG
	return deg_to_rad(WOBBLE_CRASH_ANGLE_DEG) * miss_ratio


## Peak |wobble_angle| this swing reaches (rad), from its angle + velocity.
func _amplitude() -> float:
	return sqrt(wobble_angle * wobble_angle + wobble_vel * wobble_vel / WOBBLE_SPRING)


## Degrees pitch sits outside the wheelie balance window (0 inside it).
func _balance_point_miss_deg() -> float:
	var bd = player_entity.bike_definition
	var pitch_deg := rad_to_deg(movement_controller.pitch_angle)
	var off_center := absf(pitch_deg - bd.wheelie_balance_point_deg)
	return maxf(off_center - bd.wheelie_balance_point_width_deg, 0.0)


## Trigger 2. A jump landing with the heading off travel wobbles by how far off it is.
func kick_bad_landing(landing_velocity: Vector3):
	if movement_controller.air_time < WOBBLE_LANDING_MIN_AIRTIME: # short hops / curbs never wobble
		return
	kick_from_misalign("trigger 2 (bad landing)", landing_velocity)


## Inject a wobble sized by how far the bike's heading (yaw only) is off from its travel. Shared by the
## jump landing (trigger 2) and the wheelie set-down (trigger 5). No-op below min speed or when
## already aligned. A moderately-off angle is capped to a RECOVERABLE wobble, but one past the hard
## window keeps its full magnitude and blows past the crash angle — a crazy-crooked one highsides.
func kick_from_misalign(source: String, travel_velocity: Vector3):
	var speed := movement_controller.speed
	var fwd := -player_entity.global_transform.basis.z
	var h_vel := Vector3(travel_velocity.x, 0.0, travel_velocity.z)
	# Signed so the kick swings the way the heading is already off.
	var yaw_off := 0.0
	if h_vel.length() > 2.0:
		var fwd_flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
		yaw_off = fwd_flat.signed_angle_to(h_vel.normalized(), Vector3.UP)
	var over := rad_to_deg(absf(yaw_off)) - WOBBLE_LANDING_ANGLE_DEG
	DebugUtils.DebugMsg(
		(
			"%s: yaw=%.0f° over=%.0f spd=%.0f | window=%.0f min_spd=%.0f"
			% [source, rad_to_deg(yaw_off), over, speed, WOBBLE_LANDING_ANGLE_DEG, WOBBLE_MIN_SPEED]
		),
		OS.has_feature("debug") and movement_controller.debug_verbose
	)
	if speed < WOBBLE_MIN_SPEED or over <= 0.0: # too slow, or aligned enough — no wobble
		return
	var kick := over * WOBBLE_LANDING_STRENGTH
	if over < WOBBLE_LANDING_HARD_OVER_DEG:
		# Undamped swing peaks at kick / sqrt(spring) — cap it at 60% of the crash angle.
		kick = minf(kick, deg_to_rad(WOBBLE_CRASH_ANGLE_DEG) * 0.6 * sqrt(WOBBLE_SPRING))
	wobble_vel += signf(yaw_off) * kick
	DebugUtils.DebugMsg(
		"  -> %s WOBBLE (vel+=%.1f)" % [source, signf(yaw_off) * kick],
		OS.has_feature("debug") and movement_controller.debug_verbose
	)


## The tank-slapper: damped harmonic oscillator on the heading (countersteer/off-gas damp, steering
## in feeds; CrashController fires past the limit). Re-derives is_wobbling — 1a/1b inject in _drift_calc.
func tick(delta: float):
	var was_wobbling := is_wobbling # captured pre-recompute for the start/stop edge logs
	update_is_wobbling()
	if not is_wobbling:
		if was_wobbling:
			DebugUtils.DebugMsg("wobble ended (settled)", OS.has_feature("debug") and movement_controller.debug_verbose)
		wobble_angle = 0.0
		wobble_vel = 0.0
		wobble_from_trick = false
		return
	if not was_wobbling:
		DebugUtils.DebugMsg(
			"wobble started (vel=%.2f rad/s) — see trigger above for cause" % wobble_vel,
			OS.has_feature("debug") and movement_controller.debug_verbose
		)

	var steer := input_controller.nfx_steer
	var steering := absf(steer) > 0.1
	var into_swing := steering and signf(steer) == signf(wobble_vel)
	var damping := WOBBLE_DAMPING
	if steering and not into_swing:
		damping += WOBBLE_COUNTERSTEER_BONUS # countersteer — the fast save
	if steering and input_controller.nfx_throttle < 0.1:
		damping += WOBBLE_OFFGAS_BONUS # off-gas + steer — the slower universal save
	# More forgiving the closer to center you are — recovery accelerates as the swing shrinks.
	var amp_ratio := clampf(absf(wobble_angle) / deg_to_rad(WOBBLE_CRASH_ANGLE_DEG), 0.0, 1.0)
	damping += WOBBLE_RECOVER_BOOST * (1.0 - amp_ratio)
	# Slowing below min speed kills the wobble — a universal low-speed save. A trick wobble swinging
	# bigger than its pitch warrants (closing in on the balance point) mellows the same way.
	if movement_controller.speed < WOBBLE_MIN_SPEED or (
		wobble_from_trick and _amplitude() > _trick_target_amp()
	):
		damping += WOBBLE_RECOVER_BOOST * 3.0
	wobble_vel -= WOBBLE_SPRING * wobble_angle * delta
	wobble_vel *= exp(-damping * delta) # exp keeps damping stable even when the bonuses stack high
	# Feed only a swing that's still meaningful — so a near-settled wobble can actually settle
	# instead of a held steer pumping it forever.
	if into_swing and amp_ratio > 0.2:
		wobble_vel += signf(wobble_vel) * WOBBLE_FEED * absf(steer) * delta

	# rotate_y carves the same delta tracked in wobble_angle, so damping returns the heading.
	wobble_angle += wobble_vel * delta
	player_entity.rotate_y(wobble_vel * delta)


## Called from player_entity.gd's do_reset loop
func do_reset():
	wobble_angle = 0.0
	wobble_vel = 0.0
	wobble_brake_hold_time = 0.0
	is_wobbling = false
	wobble_from_trick = false


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	if movement_controller == null:
		issues.append("movement_controller must not be empty")
	return issues
