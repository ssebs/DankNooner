@tool
class_name CrashController extends Node

## Picks how the bike wreck tumbles (BikeWreck). Visual only.
enum CrashType {
	LOWSIDE,
	HIGHSIDE,
	WALL,
}

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var movement_controller: MovementController
@export var wobble_controller: WobbleController

const IS_SIM_DIFFICULTY: bool = false
const CRASH_LEAN_THRESHOLD_DEG: float = 80.0
const BRAKE_GRAB_RATE_THRESHOLD: float = 20
## How many degrees the lean-crash threshold drops at full unstable_surface_factor.
const UNSTABLE_LEAN_THRESHOLD_REDUCTION_DEG: float = 25.0
## Min front-brake input to trigger a lowside while steering on an unstable surface.
const UNSTABLE_LOWSIDE_BRAKE_THRESHOLD: float = 0.5
## Min |roll_angle| (deg) required for the unstable front-brake lowside.
const UNSTABLE_LOWSIDE_STEER_THRESHOLD_DEG: float = 15.0
## Drift over-rotation crash angle (tail came all the way around).
const DRIFT_SPINOUT_ANGLE_DEG: float = 70.0  # matches DRIFT_MAX_SLIP_ANGLE_DEG in movement controller
## Min |slip| when grip returns (drive released) that wobbles — countersteer under it to exit clean.
const DRIFT_HIGHSIDE_ANGLE_DEG: float = 30.0
## |slip| at/above which grip returning highsides instantly; below it (down to DRIFT_HIGHSIDE_ANGLE_DEG)
## it throws a recoverable speed wobble first that only highsides if it grows past the limit.
const DRIFT_HIGHSIDE_HARD_ANGLE_DEG: float = 65.0
## Angular kick (rad/s) a moderate drift release injects into the wobble instead of an instant highside.
## Big enough to swing wide and last a beat so there's time to countersteer out of it.
const DRIFT_CHOP_WOBBLE_STRENGTH: float = 9.0
## Min speed for a highside to be dangerous.
const DRIFT_HIGHSIDE_MIN_SPEED: float = 12.0
## Lean (deg) allowed in a stoppie before the loaded front tire washes out (lowside). Reads
## roll_angle (already time-eased) not raw steer, so a KBM tap stays under it but a hard hold crosses.
const STOPPIE_STEER_CRASH_ANGLE_DEG: float = 10.0
## At/below this speed, a stoppie held high enough (see fraction below) can be pivot-steered
## without washing out — you're balanced on the front, not carrying speed the tire can wash off.
const STOPPIE_PIVOT_MAX_SPEED: float = 10.0
## Fraction of max_stoppie_angle_deg the nose must be past to count as "high enough" to pivot.
const STOPPIE_PIVOT_MIN_ANGLE_FRAC: float = 0.7
## Upward+lateral launch speed applied to a highside crash.
const HIGHSIDE_LAUNCH_FORCE: float = 14.0
## At/above this impact speed a player-to-player hit hard-crashes; below it both riders wobble.
const WOBBLE_RAM_MAX_SPEED: float = 15.0
## Angular kick (rad/s) applied to both riders on a low-speed player-to-player tap, or a glancing wall hit.
const WOBBLE_RAM_STRENGTH: float = 6.0
## Fraction of speed lost on a glancing (non-crash) layer-2 wall hit.
const WALL_GLANCE_SPEED_LOSS: float = 0.25
## A grabbed front brake (KBM: any press — a digital brake always grabs) held this long (s) while
## leaned past WASHOUT_MIN_LEAN_DEG above WASHOUT_MIN_SPEED washes the front out. Easing off saves it.
const WASHOUT_TIME: float = 0.4
## Front brake past this is a grab (pad: squeezed fast) and counts toward a washout.
const WASHOUT_BRAKE: float = 0.9
const WASHOUT_MIN_LEAN_DEG: float = 15.0
const WASHOUT_MIN_SPEED: float = 10.0
## Power washout: too much gas for the lean, held WASHOUT_TIME above WASHOUT_MIN_SPEED, spins the
## rear out (lowside). Gas allowed falls off steeply only near max lean — like IRL, roll on as you
## stand it up. Drive you can hold at full lean (maintenance throttle):
const POWER_WASHOUT_MAX_LEAN_DRIVE: float = 0.45
## Lean usage (fraction of max lean for this speed) at which full gas starts washing out.
const POWER_WASHOUT_FULL_GAS_LEAN: float = 0.9
## Layer-2 hits only crash at/above this speed, and only head-on: within this angle of the wall's
## normal. Race bots crash by the same rule (NPCRaceState).
const CRASH_MIN_SPEED: float = 10.0
const CRASH_MAX_ANGLE_DEG: float = 60.0

## Seconds into a brake washout, 0 when not washing out. Synced; drives grip_usage + squeal.
var washout_time: float = 0.0
## Seconds into a power washout (gas at lean), 0 when not. Synced; drives grip_usage + skids.
var power_washout_time: float = 0.0

var _prev_front_brake: float = 0.0
var _prev_drift_drive_held: bool = false
var _brake_was_grabbed: bool = false
var _prev_air_trick: TrickController.Trick = TrickController.Trick.NONE


func _ready():
	if Engine.is_editor_hint():
		return


## Called from MovementController after physics
func on_movement_rollback_tick(delta: float):
	if player_entity.is_crashed:
		return

	_update_brake_grab(delta)
	_detect_air_trick_landing()
	_detect_drift_crash()
	_detect_crash()
	# Cache AFTER detection — trick_controller already ran this tick and transitioned to ground
	# state on landing, so we use last tick's value to detect "landed mid-trick". Only a real jump
	# counts: a wheelie/ground trick over a brief hop (bump, wheelie bounce) lands safely.
	var airborne := (
		not movement_controller.is_on_floor
		and movement_controller.air_time >= TrickController.AIR_TRICK_MIN_AIRTIME
	)
	_prev_air_trick = (
		player_entity.trick_controller.current_trick if airborne else TrickController.Trick.NONE
	)


## Crash if the player touches down mid air-trick, or with the bike turned under them (shuvit).
## Releasing the trick before landing is safe.
## Checks _prev_air_trick (last tick's), not current_trick: trick_controller runs before us and has
## already transitioned to the ground state on the landing tick.
func _detect_air_trick_landing():
	if not movement_controller.is_on_floor:
		return
	var just_landed = not movement_controller.was_on_floor
	if just_landed and TrickController.is_air_trick(_prev_air_trick):
		DebugUtils.DebugMsg("landed mid air-trick crash (%s)" % TrickController.trick_to_str(_prev_air_trick))
		trigger_crash(CrashType.HIGHSIDE)
	# MovementController only keeps shuv_yaw on a landing outside the snap window (a 180 bails).
	elif just_landed and movement_controller.shuv_yaw != 0.0:
		DebugUtils.DebugMsg("landed crooked shuvit crash (%.0f°)" % rad_to_deg(movement_controller.shuv_yaw))
		trigger_crash(CrashType.HIGHSIDE)


## Sets washout_time, power_washout_time + player_entity.grip_usage
func _update_brake_grab(delta: float):
	var front_brake = input_controller.nfx_front_brake

	var brake_delta = (front_brake - _prev_front_brake) / delta
	_prev_front_brake = front_brake

	if front_brake < 0.2:
		_brake_was_grabbed = false
	elif front_brake > WASHOUT_BRAKE and brake_delta > BRAKE_GRAB_RATE_THRESHOLD:
		_brake_was_grabbed = true

	var lean := absf(movement_controller.roll_angle)
	var washing_out := (
		(_brake_was_grabbed or not input_controller.is_gamepad)
		and front_brake > WASHOUT_BRAKE
		and movement_controller.is_on_floor
		and not movement_controller.is_reversing
		and movement_controller.speed > WASHOUT_MIN_SPEED
		and lean > deg_to_rad(WASHOUT_MIN_LEAN_DEG)
	)
	washout_time = washout_time + delta if washing_out else 0.0

	# Power risk: drive / gas allowed at this lean (1 = washing out). Allowed gas is
	# MAX_LEAN_DRIVE / lean^k, with k picked so full gas hits the limit at FULL_GAS_LEAN.
	var power_risk := 0.0
	if (
		movement_controller.is_on_floor
		and not movement_controller.is_reversing
		and not movement_controller.is_drifting
		and not movement_controller.is_grinding
		and not player_entity.trick_controller.is_in_wheelie()
		and movement_controller.speed > WASHOUT_MIN_SPEED
	):
		var k := log(POWER_WASHOUT_MAX_LEAN_DRIVE) / log(POWER_WASHOUT_FULL_GAS_LEAN)
		var lean_load := pow(movement_controller.get_lean_usage(), k)
		power_risk = clampf(movement_controller.drive * lean_load / POWER_WASHOUT_MAX_LEAN_DRIVE, 0.0, 1.0)
	power_washout_time = power_washout_time + delta if power_risk >= 1.0 else 0.0

	# Grip danger (grip_usage) for HUD/shake: washout progress, the gas closing in on the limit, plus
	# a fast squeeze while leaned.
	var danger := maxf(washout_time / WASHOUT_TIME, power_risk)
	if input_controller.is_gamepad:
		var lean_factor := clampf(lean / deg_to_rad(WASHOUT_MIN_LEAN_DEG), 0.0, 1.0)
		danger = maxf(danger, clampf(brake_delta / BRAKE_GRAB_RATE_THRESHOLD, 0.0, 1.0) * lean_factor)
	# Hold the peak through a washout so a grab's spike doesn't dip while washout_time catches up.
	var decay := 0.0 if washout_time > 0.0 else 3.0 * delta
	player_entity.grip_usage = maxf(danger, move_toward(player_entity.grip_usage, 0.0, decay))


func _detect_crash():
	var bd = player_entity.bike_definition

	# Killbox — always crash regardless of speed/angle
	for i in player_entity.get_slide_collision_count():
		var collision = player_entity.get_slide_collision(i)
		if collision.get_collider() is Killbox:
			DebugUtils.DebugMsg("killbox crash")
			trigger_crash(CrashType.WALL)
			return

	# If in air, don't crash by angle
	if movement_controller.is_on_floor:
		# Wheelie crash
		if movement_controller.pitch_angle > deg_to_rad(bd.max_wheelie_angle_deg):
			DebugUtils.DebugMsg("wheelie crash")
			trigger_crash(CrashType.HIGHSIDE)
			return

		# Stoppie crash — over-rotated past the limit (went over the bars)
		if movement_controller.pitch_angle < -deg_to_rad(bd.max_stoppie_angle_deg):
			DebugUtils.DebugMsg("stoppie crash")
			trigger_crash(CrashType.HIGHSIDE)
			return

		# Stoppie washout — leaning too hard on the single loaded front tire tucks it (lowside).
		# Reduced steering is allowed (MovementController.STOPPIE_STEER_SCALE); past this it lets go.
		# Exception: at low speed a high-enough stoppie is a balanced pivot — steer freely, no washout.
		var stoppie_pivot := (
			movement_controller.speed <= STOPPIE_PIVOT_MAX_SPEED
			and (
				absf(movement_controller.pitch_angle)
				>= deg_to_rad(bd.max_stoppie_angle_deg * STOPPIE_PIVOT_MIN_ANGLE_FRAC)
			)
		)
		if (
			movement_controller.is_stoppie
			and not stoppie_pivot
			and absf(movement_controller.roll_angle) > deg_to_rad(STOPPIE_STEER_CRASH_ANGLE_DEG)
		):
			DebugUtils.DebugMsg("stoppie steer washout crash")
			trigger_crash(CrashType.LOWSIDE)
			return

		# Grind bail — turned too far across the rail, or out of speed on it. Pitch bails are the
		# wheelie / stoppie limits above.
		if movement_controller.is_grinding and (
			absf(movement_controller.grind_yaw) > deg_to_rad(MovementController.GRIND_MAX_YAW_DEG)
			or movement_controller.speed < MovementController.GRIND_MIN_SPEED
		):
			DebugUtils.DebugMsg("grind bail crash")
			trigger_crash(CrashType.LOWSIDE)
			return

		# Stalled on a grade too steep to climb — bike can't hold, rider drops it
		if movement_controller.is_stalled_on_steep_slope():
			DebugUtils.DebugMsg("steep slope stall crash")
			trigger_crash(CrashType.LOWSIDE)
			return

		# Speed wobble peaked past the limit — the tank-slapper throws them over the high side.
		if (
			wobble_controller.is_wobbling
			and (
				absf(wobble_controller.wobble_angle)
				> deg_to_rad(WobbleController.WOBBLE_CRASH_ANGLE_DEG)
			)
		):
			DebugUtils.DebugMsg(
				"speed wobble HIGHSIDE (angle=%.1f°)" % rad_to_deg(wobble_controller.wobble_angle)
			)
			trigger_crash(CrashType.HIGHSIDE, _highside_launch(signf(wobble_controller.wobble_angle)))
			return

		# Lean crash — threshold tightens on unstable surfaces (gravel/sand)
		var unstable_factor = movement_controller.get_unstable_factor()
		var effective_lean_threshold = (
			CRASH_LEAN_THRESHOLD_DEG - UNSTABLE_LEAN_THRESHOLD_REDUCTION_DEG * unstable_factor
		)
		if abs(movement_controller.roll_angle) >= deg_to_rad(effective_lean_threshold):
			DebugUtils.DebugMsg("lean crash")
			trigger_crash(CrashType.LOWSIDE)
			return

		# Unstable lowside — front brake while steering on gravel/sand washes the front wheel out.
		# Not while reversing: a reverse roll holds the brake by design (see REVERSE_BRAKE_THRESHOLD)
		# and steering leans the bike, so this would fire on every backward turn.
		if (
			unstable_factor > 0
			and not movement_controller.is_reversing
			and input_controller.nfx_front_brake > UNSTABLE_LOWSIDE_BRAKE_THRESHOLD
			and (
				abs(movement_controller.roll_angle)
				> deg_to_rad(UNSTABLE_LOWSIDE_STEER_THRESHOLD_DEG)
			)
		):
			DebugUtils.DebugMsg("unstable lowside crash")
			trigger_crash(CrashType.LOWSIDE)
			return

		if washout_time >= WASHOUT_TIME:
			DebugUtils.DebugMsg("brake washout crash")
			trigger_crash(CrashType.LOWSIDE, Vector3.ZERO, "FEED_BAILED_BRAKE_GRAB")
			return

		if power_washout_time >= WASHOUT_TIME:
			DebugUtils.DebugMsg("power washout crash")
			trigger_crash(CrashType.LOWSIDE, Vector3.ZERO, "FEED_BAILED_POWER_WASHOUT")
			return

	# Upside-down landing — checked separately because inverted up_direction breaks is_on_floor()
	# Skip on steep surfaces (loops) — inverted up_direction is expected there
	var bike_up_angle = player_entity.up_direction.angle_to(Vector3.UP)
	if bike_up_angle > deg_to_rad(120):
		for i in player_entity.get_slide_collision_count():
			var collision = player_entity.get_slide_collision(i)
			if collision.get_normal().angle_to(Vector3.UP) < deg_to_rad(45):
				DebugUtils.DebugMsg("upside-down crash (angle=%.1f°)" % rad_to_deg(bike_up_angle))
				trigger_crash(CrashType.HIGHSIDE)
				return

	# Collision with layer 2 obstacle — only head-on hits at speed
	if movement_controller.speed >= CRASH_MIN_SPEED:
		for i in player_entity.get_slide_collision_count():
			var collision = player_entity.get_slide_collision(i)
			var collider = collision.get_collider()
			if is_crash_obstacle(collider):
				var angle := impact_angle_deg(collision, movement_controller.pre_slide_velocity)
				if angle < CRASH_MAX_ANGLE_DEG:
					# Low-speed player-to-player tap: both riders wobble instead of crashing.
					# NPCs and static obstacles fall through to the hard crash.
					if collider is PlayerEntity and movement_controller.speed < WOBBLE_RAM_MAX_SPEED:
						DebugUtils.DebugMsg("player ram wobble (angle=%.1f)" % angle)
						wobble_controller.wobble_vel += WOBBLE_RAM_STRENGTH  # self — deterministic on all peers
						_wobble_rammed_racer(collider)  # server broadcasts the victim's wobble
						return
					DebugUtils.DebugMsg("obstacle crash (angle=%.1f)" % angle)
					_crash_rammed_racer(collider)
					trigger_crash(CrashType.WALL)
					return
				# Glancing hit: reflect heading off the wall, wobble away + speed penalty.
				# Once per wobble so contact can't stack it.
				if not wobble_controller.is_wobbling:
					var fwd := -player_entity.global_transform.basis.z
					var fwd_flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
					var n: Vector3 = collision.get_normal()
					var n_flat := Vector3(n.x, 0.0, n.z).normalized()
					# Mirror only the into-wall part — a heading already angled away is left alone.
					var reflected := fwd_flat - 2.0 * minf(fwd_flat.dot(n_flat), 0.0) * n_flat
					player_entity.rotate_y(fwd_flat.signed_angle_to(reflected, Vector3.UP))
					var away := signf(fwd.signed_angle_to(n, Vector3.UP))
					wobble_controller.wobble_vel += away * WOBBLE_RAM_STRENGTH
					movement_controller.speed *= 1.0 - WALL_GLANCE_SPEED_LOSS
					DebugUtils.DebugMsg(
						"wall glance wobble (angle=%.1f) collider=%s shape=%s pos=%s normal=%s"
						% [
							angle,
							collider.get_path(),
							collision.get_collider_shape(),
							collision.get_position(),
							n,
						]
					)
					return


## Walls, obstacles and racers: anything on layer 2.
static func is_crash_obstacle(collider: Object) -> bool:
	# CSG walls report the CSG node itself as the collider, not a CollisionObject3D.
	var is_body := collider is CollisionObject3D or collider is CSGShape3D
	return is_body and collider.collision_layer & 2


## 0° is dead head-on. Pre-slide velocity: move_and_slide already stripped the into-wall part, so a
## head-on hit would read as glancing.
static func impact_angle_deg(collision: KinematicCollision3D, pre_slide_velocity: Vector3) -> float:
	return rad_to_deg(collision.get_normal().angle_to(-pre_slide_velocity.normalized()))


## We rode into another racer: they never see that collision from their side
## (slide collisions only report what YOU moved into), so take them down too.
## Server only — the client runs this same detection while predicting and must
## not fire off its own guess. Static obstacles fall through both branches.
func _crash_rammed_racer(collider: Object) -> void:
	if !multiplayer.is_server():
		return
	if collider is PlayerEntity or collider is NPCRiderEntity:
		player_entity.gamemode_manager.spawn_manager.knock_out_rider(collider, int(player_entity.name))


## Low-speed tap into another player: broadcast their wobble. Server only — the victim never sees
## the collision from their side. Mirrors _crash_rammed_racer; only PlayerEntity reaches here.
func _wobble_rammed_racer(collider: Object) -> void:
	if !multiplayer.is_server():
		return
	var victim := collider as PlayerEntity
	player_entity.gamemode_manager.spawn_manager.wobble_player.rpc(int(victim.name), WOBBLE_RAM_STRENGTH)


## Drift crashes: spin-out (tail past the limit) or highside (tire hooks up when throttle and rear
## brake are both released while still slipped). Countersteer the slip down before letting go.
func _detect_drift_crash():
	var drive_held := (
		maxf(input_controller.nfx_throttle, input_controller.nfx_rear_brake)
		> MovementController.DRIFT_BRAKE_HOLD
	)
	var grip_returned := _prev_drift_drive_held and not drive_held
	_prev_drift_drive_held = drive_held

	if not movement_controller.is_drifting:
		return

	var slip = absf(movement_controller.slip_angle)

	# Spin-out — tail came all the way around.
	if slip > deg_to_rad(DRIFT_SPINOUT_ANGLE_DEG):
		DebugUtils.DebugMsg("drift spinout crash (slip=%.1f°)" % rad_to_deg(slip))
		trigger_crash(CrashType.LOWSIDE)
		return

	# Highside — grip returned while still slid out. Release speed doesn't matter, only the angle.
	if (
		grip_returned
		and slip > deg_to_rad(DRIFT_HIGHSIDE_ANGLE_DEG)
		and movement_controller.speed > DRIFT_HIGHSIDE_MIN_SPEED
	):
		var slip_sign = signf(movement_controller.slip_angle)
		if slip > deg_to_rad(DRIFT_HIGHSIDE_HARD_ANGLE_DEG):
			# Crazy angle — straight over the high side.
			DebugUtils.DebugMsg("drift HIGHSIDE crash (slip=%.1f°)" % rad_to_deg(slip))
			trigger_crash(CrashType.HIGHSIDE, _highside_launch(slip_sign))
		else:
			# Recoverable angle — throw a wobble first; it highsides only if it grows past the limit.
			wobble_controller.wobble_vel += slip_sign * DRIFT_CHOP_WOBBLE_STRENGTH
			DebugUtils.DebugMsg("drift release -> wobble (slip=%.1f°)" % rad_to_deg(slip))


## Highside launch: up + lateral toward the outside of the slide/swing (opposite the tail-out).
func _highside_launch(dir_sign: float) -> Vector3:
	var right := player_entity.global_transform.basis.x
	return (Vector3.UP + right * dir_sign).normalized() * HIGHSIDE_LAUNCH_FORCE


## hint_key: localization key that replaces "bailed" in the trick feed, "" for none.
func trigger_crash(
	crash_type: CrashType, launch_impulse: Vector3 = Vector3.ZERO, hint_key: String = ""
):
	# Sim state only — visuals ride the is_crashed edge in _process (firing them in rollback left them stuck).
	player_entity.is_crashed = true
	player_entity.crash_count += 1
	player_entity.velocity = launch_impulse
	player_entity.crash_launch_impulse = launch_impulse
	player_entity.crash_type = crash_type
	player_entity.crash_hint = hint_key


## Called from player_entity.gd's do_respawn
func do_reset():
	_prev_front_brake = 0.0
	_prev_drift_drive_held = false
	_brake_was_grabbed = false
	washout_time = 0.0
	_prev_air_trick = TrickController.Trick.NONE


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	if movement_controller == null:
		issues.append("movement_controller must not be empty")
	if wobble_controller == null:
		issues.append("wobble_controller must not be empty")
	return issues
