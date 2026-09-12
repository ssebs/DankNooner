@tool
class_name CrashController extends Node

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var movement_controller: MovementController

@export var is_sim_difficulty: bool = false
@export var crash_lean_threshold_deg: float = 80.0
@export var brake_grab_rate_threshold: float = 20
@export var brake_lean_sensitivity: float = 0.7
## How many degrees the lean-crash threshold drops at full unstable_surface_factor.
@export var unstable_lean_threshold_reduction_deg: float = 25.0
## Min front-brake input to trigger a lowside while steering on an unstable surface.
@export var unstable_lowside_brake_threshold: float = 0.5
## Min |roll_angle| (deg) required for the unstable front-brake lowside.
@export var unstable_lowside_steer_threshold_deg: float = 15.0
## Drift over-rotation crash angle (tail came all the way around).
@export var drift_spinout_angle_deg: float = 70.0  # matches DRIFT_MAX_SLIP_ANGLE_DEG in movement controller
## Min |slip| for a highside on grip regain.
@export var drift_highside_angle_deg: float = 55.0
## |slip| at/above which a chop highsides instantly; below it (down to drift_highside_angle_deg) a
## chop throws a recoverable speed wobble first that only highsides if it grows past the limit.
@export var drift_highside_hard_angle_deg: float = 65.0
## Angular kick (rad/s) a moderate drift chop injects into the wobble instead of an instant highside.
## Big enough to swing wide and last a beat so there's time to countersteer out of it.
@export var drift_chop_wobble_strength: float = 9.0
## Min speed for a highside to be dangerous.
@export var drift_highside_min_speed: float = 12.0
## Lean (deg) allowed in a stoppie before the loaded front tire washes out (lowside). Reads
## roll_angle (already time-eased) not raw steer, so a KBM tap stays under it but a hard hold crosses.
@export var stoppie_steer_crash_angle_deg: float = 10.0
## At/below this speed, a stoppie held high enough (see fraction below) can be pivot-steered
## without washing out — you're balanced on the front, not carrying speed the tire can wash off.
@export var stoppie_pivot_max_speed: float = 10.0
## Fraction of max_stoppie_angle_deg the nose must be past to count as "high enough" to pivot.
@export var stoppie_pivot_min_angle_frac: float = 0.7
## Throttle release rate (per sec) that highsides at drift_highside_angle_deg (forgiving).
@export var highside_chop_forgiving: float = 6.0
## Throttle release rate that highsides near the spinout angle (twitchy — small lift snaps).
@export var highside_chop_twitchy: float = 1.5
## Upward+lateral launch speed applied to a highside crash.
@export var highside_launch_force: float = 14.0
## At/above this impact speed a player-to-player hit hard-crashes; below it both riders wobble.
@export var wobble_ram_max_speed: float = 15.0
## Angular kick (rad/s) applied to both riders on a low-speed player-to-player tap.
@export var wobble_ram_strength: float = 6.0

var _prev_front_brake: float = 0.0
var _prev_throttle: float = 0.0
var _brake_was_grabbed: bool = false
var _prev_trick: TrickController.Trick = TrickController.Trick.NONE

var _crash_min_speed: float = 10.0
var _crash_angle: float = 60.0


func _ready():
	if Engine.is_editor_hint():
		return


## Called from MovementController after physics
func on_movement_rollback_tick(delta: float):
	if player_entity.is_crashed:
		return

	_update_brake_grab(delta)
	_detect_air_trick_landing()
	_detect_drift_crash(delta)
	_detect_crash()
	# Cache trick state AFTER detection — trick_controller already ran this tick and
	# transitioned to ground state on landing, so we use last tick's value to detect "landed mid-trick".
	_prev_trick = player_entity.trick_controller.current_trick


## Crash if the player touches down mid air-trick. Releasing the trick before landing is safe.
## Checks _prev_trick (last tick's), not current_trick: trick_controller runs before us and has
## already transitioned to the ground state on the landing tick.
func _detect_air_trick_landing():
	if not movement_controller._is_on_floor:
		return
	var just_landed = not movement_controller._was_on_floor
	if just_landed and TrickController.is_air_trick(_prev_trick):
		DebugUtils.DebugMsg("landed mid air-trick crash (%s)" % TrickController.trick_to_str(_prev_trick))
		trigger_crash()


## Sets player_entity.grip_usage
func _update_brake_grab(delta: float):
	var front_brake = input_controller.nfx_front_brake

	var brake_delta = (front_brake - _prev_front_brake) / delta
	_prev_front_brake = front_brake

	if front_brake < 0.2:
		_brake_was_grabbed = false
	elif front_brake > 0.9 and brake_delta > brake_grab_rate_threshold:
		_brake_was_grabbed = true

	# Compute brake danger (grip_usage) for HUD display
	var lean_ratio = abs(movement_controller.roll_angle) / deg_to_rad(crash_lean_threshold_deg)
	var max_safe_brake = 1.0 - (lean_ratio * brake_lean_sensitivity)
	if front_brake > 0.1:
		player_entity.grip_usage = clamp(front_brake / max(max_safe_brake, 0.01), 0.0, 1.0)
	else:
		player_entity.grip_usage = move_toward(player_entity.grip_usage, 0.0, 3.0 * delta)


func _detect_crash():
	var bd = player_entity.bike_definition

	# Killbox — always crash regardless of speed/angle
	for i in player_entity.get_slide_collision_count():
		var collision = player_entity.get_slide_collision(i)
		if collision.get_collider() is Killbox:
			DebugUtils.DebugMsg("killbox crash")
			trigger_crash()
			return

	# If in air, don't crash by angle
	if movement_controller._is_on_floor:
		# Wheelie crash
		if movement_controller.pitch_angle > deg_to_rad(bd.max_wheelie_angle_deg):
			DebugUtils.DebugMsg("wheelie crash")
			trigger_crash()
			return

		# Stoppie crash — over-rotated past the limit (went over the bars)
		if movement_controller.pitch_angle < -deg_to_rad(bd.max_stoppie_angle_deg):
			DebugUtils.DebugMsg("stoppie crash")
			trigger_crash()
			return

		# Stoppie washout — leaning too hard on the single loaded front tire tucks it (lowside).
		# Reduced steering is allowed (MovementController.STOPPIE_STEER_SCALE); past this it lets go.
		# Exception: at low speed a high-enough stoppie is a balanced pivot — steer freely, no washout.
		var stoppie_pivot := (
			movement_controller.speed <= stoppie_pivot_max_speed
			and (
				absf(movement_controller.pitch_angle)
				>= deg_to_rad(bd.max_stoppie_angle_deg * stoppie_pivot_min_angle_frac)
			)
		)
		if (
			movement_controller.is_stoppie
			and not stoppie_pivot
			and absf(movement_controller.roll_angle) > deg_to_rad(stoppie_steer_crash_angle_deg)
		):
			DebugUtils.DebugMsg("stoppie steer washout crash")
			trigger_crash()
			return

		# Stalled on a grade too steep to climb — bike can't hold, rider drops it
		if movement_controller.is_stalled_on_steep_slope():
			DebugUtils.DebugMsg("steep slope stall crash")
			trigger_crash()
			return

		# Speed wobble peaked past the limit — the tank-slapper throws them over the high side.
		if (
			movement_controller.is_wobbling
			and (
				absf(movement_controller.wobble_angle)
				> deg_to_rad(movement_controller.wobble_crash_angle_deg)
			)
		):
			DebugUtils.DebugMsg(
				"speed wobble HIGHSIDE (angle=%.1f°)" % rad_to_deg(movement_controller.wobble_angle)
			)
			trigger_crash(_highside_launch(signf(movement_controller.wobble_angle)))
			return

		# Lean crash — threshold tightens on unstable surfaces (gravel/sand)
		var unstable_factor = movement_controller.get_unstable_factor()
		var effective_lean_threshold = (
			crash_lean_threshold_deg - unstable_lean_threshold_reduction_deg * unstable_factor
		)
		if abs(movement_controller.roll_angle) >= deg_to_rad(effective_lean_threshold):
			DebugUtils.DebugMsg("lean crash")
			trigger_crash()
			return

		# Unstable lowside — front brake while steering on gravel/sand washes the front wheel out.
		# Not while reversing: a reverse roll holds the brake by design (see REVERSE_BRAKE_THRESHOLD)
		# and steering leans the bike, so this would fire on every backward turn.
		if (
			unstable_factor > 0
			and not movement_controller.is_reversing
			and input_controller.nfx_front_brake > unstable_lowside_brake_threshold
			and (
				abs(movement_controller.roll_angle)
				> deg_to_rad(unstable_lowside_steer_threshold_deg)
			)
		):
			DebugUtils.DebugMsg("unstable lowside crash")
			trigger_crash()
			return

		# Brake grab while turning (sim difficulty + gamepad only)
		if (
			_brake_was_grabbed
			# and is_sim_difficulty
			and input_controller.is_gamepad
			and abs(movement_controller.roll_angle) > deg_to_rad(15)
		):
			DebugUtils.DebugMsg("brake grab crash")
			trigger_crash()

	# Upside-down landing — checked separately because inverted up_direction breaks is_on_floor()
	# Skip on steep surfaces (loops) — inverted up_direction is expected there
	var bike_up_angle = player_entity.up_direction.angle_to(Vector3.UP)
	if bike_up_angle > deg_to_rad(120):
		for i in player_entity.get_slide_collision_count():
			var collision = player_entity.get_slide_collision(i)
			if collision.get_normal().angle_to(Vector3.UP) < deg_to_rad(45):
				DebugUtils.DebugMsg("upside-down crash (angle=%.1f°)" % rad_to_deg(bike_up_angle))
				trigger_crash()
				return

	# Collision with layer 2 obstacle — only head-on hits at speed
	if movement_controller.speed >= _crash_min_speed:
		for i in player_entity.get_slide_collision_count():
			var collision = player_entity.get_slide_collision(i)
			var collider = collision.get_collider()
			if collider is CollisionObject3D and collider.collision_layer & 2:
				var angle = rad_to_deg(
					collision.get_normal().angle_to(-player_entity.velocity.normalized())
				)
				if angle < _crash_angle:
					# Low-speed player-to-player tap: both riders wobble instead of crashing.
					# NPCs and static obstacles fall through to the hard crash.
					if collider is PlayerEntity and movement_controller.speed < wobble_ram_max_speed:
						DebugUtils.DebugMsg("player ram wobble (angle=%.1f)" % angle)
						movement_controller.wobble_vel += wobble_ram_strength  # self — deterministic on all peers
						_wobble_rammed_racer(collider)  # server broadcasts the victim's wobble
						return
					DebugUtils.DebugMsg("obstacle crash (angle=%.1f)" % angle)
					_crash_rammed_racer(collider)
					trigger_crash()
					return
				DebugUtils.DebugMsg("no crash (angle=%.1f)" % angle)


## We rode into another racer: they never see that collision from their side
## (slide collisions only report what YOU moved into), so take them down too.
## Server only — the client runs this same detection while predicting and must
## not fire off its own guess. Static obstacles fall through both branches.
func _crash_rammed_racer(collider: Object) -> void:
	if !multiplayer.is_server():
		return
	if collider is PlayerEntity:
		var victim := collider as PlayerEntity
		player_entity.gamemode_manager.spawn_manager.crash_player.rpc(int(victim.name))
	elif collider is NPCRiderEntity:
		(collider as NPCRiderEntity).report_hit(player_entity)


## Low-speed tap into another player: broadcast their wobble. Server only — the victim never sees
## the collision from their side. Mirrors _crash_rammed_racer; only PlayerEntity reaches here.
func _wobble_rammed_racer(collider: Object) -> void:
	if !multiplayer.is_server():
		return
	var victim := collider as PlayerEntity
	player_entity.gamemode_manager.spawn_manager.wobble_player.rpc(int(victim.name), wobble_ram_strength)


## Drift crashes: spin-out (tail past the limit) or highside (tire hooks up on a
## throttle chop while still slipped). Rolling the throttle off slowly is safe.
func _detect_drift_crash(delta: float):
	var throttle = input_controller.nfx_throttle
	var release_rate = (_prev_throttle - throttle) / delta  # > 0 means letting off
	_prev_throttle = throttle

	if not movement_controller.is_drifting:
		return

	var slip = absf(movement_controller.slip_angle)

	# Spin-out — tail came all the way around.
	if slip > deg_to_rad(drift_spinout_angle_deg):
		DebugUtils.DebugMsg("drift spinout crash (slip=%.1f°)" % rad_to_deg(slip))
		trigger_crash()
		return

	# Highside — fast throttle chop while deep + fast. Chop tolerance shrinks as slip grows.
	if (
		slip > deg_to_rad(drift_highside_angle_deg)
		and movement_controller.speed > drift_highside_min_speed
	):
		var slip_ratio = clampf(
			(
				(slip - deg_to_rad(drift_highside_angle_deg))
				/ deg_to_rad(drift_spinout_angle_deg - drift_highside_angle_deg)
			),
			0.0,
			1.0
		)
		var chop_threshold = lerpf(highside_chop_forgiving, highside_chop_twitchy, slip_ratio)
		if release_rate > chop_threshold:
			var slip_sign = signf(movement_controller.slip_angle)
			if slip > deg_to_rad(drift_highside_hard_angle_deg):
				# Crazy angle — straight over the high side.
				DebugUtils.DebugMsg(
					"drift HIGHSIDE crash (slip=%.1f° rate=%.1f)" % [rad_to_deg(slip), release_rate]
				)
				trigger_crash(_highside_launch(slip_sign))
			else:
				# Recoverable angle — throw a wobble first; it highsides only if it grows past the limit.
				movement_controller.wobble_vel += slip_sign * drift_chop_wobble_strength
				DebugUtils.DebugMsg(
					"drift chop -> wobble (slip=%.1f° rate=%.1f)" % [rad_to_deg(slip), release_rate]
				)


## Highside launch: up + lateral toward the outside of the slide/swing (opposite the tail-out).
func _highside_launch(dir_sign: float) -> Vector3:
	var right := player_entity.global_transform.basis.x
	return (Vector3.UP + right * dir_sign).normalized() * highside_launch_force


func trigger_crash(launch_impulse: Vector3 = Vector3.ZERO):
	# Sim state only — visuals ride the is_crashed edge in _process (firing them in rollback left them stuck).
	player_entity.is_crashed = true
	player_entity.velocity = launch_impulse
	player_entity._crash_launch_impulse = launch_impulse


## Called from player_entity.gd's do_respawn
func do_reset():
	_prev_front_brake = 0.0
	_prev_throttle = 0.0
	_brake_was_grabbed = false
	_prev_trick = TrickController.Trick.NONE


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	if movement_controller == null:
		issues.append("movement_controller must not be empty")
	return issues
