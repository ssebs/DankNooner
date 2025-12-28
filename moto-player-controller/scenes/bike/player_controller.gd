class_name PlayerController extends CharacterBody3D

@onready var mesh = %Mesh
@onready var rear_wheel = %RearWheelMarker
@onready var front_wheel = %FrontWheelMarker
@onready var engine_sound = %EngineSound
@onready var tire_screech = %TireScreechSound

@onready var gear_label = %GearLabel
@onready var speed_label = %SpeedLabel
@onready var throttle_bar = %ThrottleBar
@onready var brake_danger_bar = %BrakeDangerBar

# Skid marks
var skidmark_texture = preload("res://assets/skidmarktex.png")
var skid_spawn_timer: float = 0.0
const SKID_SPAWN_INTERVAL: float = 0.05  # Spawn a mark every 50ms while skidding
const SKID_MARK_LIFETIME: float = 5.0

# Rotation angles
var pitch_angle: float = 0.0
var lean_angle: float = 0.0

# Movement
var speed: float = 0.0
var steering_angle: float = 0.0
var fishtail_angle: float = 0.0  # Rear-end slide angle when drifting

# Rotation tuning
@export var max_wheelie_angle: float = deg_to_rad(80)
@export var max_stoppie_angle: float = deg_to_rad(50)
@export var max_lean_angle: float = deg_to_rad(40)
@export var rotation_speed: float = 2.0
@export var return_speed: float = 3.0
@export var min_turn_radius: float = 0.25   # Tight turns at low speed
@export var max_turn_radius: float = 3.0   # Wide turns at high speed

# Movement tuning
@export var max_speed: float = 60.0
@export var acceleration: float = 15.0
@export var brake_strength: float = 25.0
@export var friction: float = 5.0
@export var steering_speed: float = 5.5
@export var max_steering_angle: float = deg_to_rad(35)
@export var turn_speed: float = 2.0  # How fast the bike actually turns

# Fishtail/drift tuning
@export var max_fishtail_angle: float = deg_to_rad(90)  # Max rear-end slide angle
@export var fishtail_speed: float = 8.0  # How fast fishtail builds
@export var fishtail_recovery_speed: float = 3.0  # How fast fishtail recovers

# Crash tuning
@export var crash_wheelie_threshold: float = deg_to_rad(75)  # Wheelie too far
@export var crash_stoppie_threshold: float = deg_to_rad(45)  # Stoppie too far
@export var crash_brake_rate_threshold: float = 10.0  # Brake input change per second
@export var idle_tip_speed_threshold: float = 3.0  # Speed below which you start tipping
@export var idle_tip_rate: float = 0.5  # How fast you tip when idle
@export var crash_lean_threshold: float = deg_to_rad(80)  # Fall over at this lean
@export var respawn_delay: float = 2.0

# Gear system
@export var num_gears: int = 6
@export var max_rpm: float = 8000.0
@export var idle_rpm: float = 1000.0
@export var stall_rpm: float = 500.0  # Engine stalls below this RPM
@export var gear_ratios: Array[float] = [2.8, 1.9, 1.4, 1.1, 0.95, 0.8]  # Higher = more torque, less top speed
var current_gear: int = 1
var current_rpm: float = 0.0
var is_stalled: bool = false

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Crash state
var is_crashed: bool = false
var crash_timer: float = 0.0
var crash_pitch_direction: float = 0.0  # Non-zero for wheelie/stoppie crashes
var crash_lean_direction: float = 0.0   # Non-zero for sideways crashes
var last_throttle_input: float = 0.0
var last_clutch_input: float = 0.0
var idle_tip_angle: float = 0.0
var has_started_moving: bool = false  # Track if bike has moved yet (stable at spawn)
var front_brake_hold_time: float = 0.0  # How long front brake held at high speed
var brake_danger_level: float = 0.0  # 0-1, how close to brake crash
var spawn_position: Vector3
var spawn_rotation: Vector3

func _ready():
    spawn_position = global_position
    spawn_rotation = rotation

func _physics_process(delta):
    if is_crashed:
        handle_crash_state(delta)
        return

    handle_gear_shifting()
    handle_acceleration(delta)
    handle_steering(delta)
    handle_lean_input(delta)
    handle_idle_tipping(delta)
    handle_skidding(delta)
    check_crash_conditions(delta)
    apply_movement(delta)
    apply_mesh_rotation()
    update_rpm()
    update_audio()
    update_ui()
    move_and_slide()


func handle_gear_shifting():
    var clutch = Input.get_action_strength("clutch")

    if Input.is_action_just_pressed("gear_up"):
        if clutch > 0.5:
            if current_gear < num_gears:
                current_gear += 1
        else:
            # Grind gears - play screech sound
            tire_screech.volume_db = linear_to_db(0.3)
            tire_screech.play()

    if Input.is_action_just_pressed("gear_down"):
        if clutch > 0.5:
            if current_gear > 1:
                current_gear -= 1
        else:
            # Grind gears - play screech sound
            tire_screech.volume_db = linear_to_db(0.3)
            tire_screech.play()


func get_max_speed_for_gear(gear: int = -1) -> float:
    # Each gear has a different top speed based on its ratio
    # Lower gears (higher ratio) = lower top speed but more acceleration
    # Higher gears (lower ratio) = higher top speed but less acceleration
    if gear == -1:
        gear = current_gear
    var gear_ratio = gear_ratios[gear - 1]
    var lowest_ratio = gear_ratios[num_gears - 1]  # Highest gear has lowest ratio
    return max_speed * (lowest_ratio / gear_ratio)


func get_min_speed_for_gear() -> float:
    # Minimum speed for a gear before stalling
    # 1st gear has no minimum
    if current_gear == 1:
        return 0.0
    return get_max_speed_for_gear(current_gear - 1) * 0.25  # 25% of previous gear's max


func get_acceleration_for_gear() -> float:
    # Lower gears (higher ratio) = more acceleration
    var gear_ratio = gear_ratios[current_gear - 1]
    var base_ratio = gear_ratios[num_gears - 1]  # Normalize to highest gear
    return acceleration * (gear_ratio / base_ratio)


func update_rpm():
    var throttle = Input.get_action_strength("throttle_pct")
    var clutch = Input.get_action_strength("clutch")
    var gear_max_speed = get_max_speed_for_gear()
    var gear_min_speed = get_min_speed_for_gear()

    # When clutch is held, RPM is directly controlled by throttle (free revving)
    if clutch > 0.5:
        var target_rpm = lerpf(idle_rpm, max_rpm, throttle)
        current_rpm = lerpf(current_rpm, target_rpm, 0.2)  # Smooth transition
    else:
        # RPM based on speed relative to current gear's speed band
        var speed_in_band = clamp(speed - gear_min_speed, 0.0, gear_max_speed - gear_min_speed)
        var band_size = gear_max_speed - gear_min_speed
        var speed_ratio = speed_in_band / band_size if band_size > 0 else 0.0
        var target_rpm = lerpf(idle_rpm, max_rpm, clamp(speed_ratio, 0.0, 1.0))
        current_rpm = lerpf(current_rpm, target_rpm, 0.1)  # Smooth RPM climb

    # Check for stall - below minimum speed for current gear without clutch
    if not is_stalled and clutch < 0.5 and speed < gear_min_speed and current_gear > 1:
        is_stalled = true
        current_gear = 1  # Reset to 1st gear when stalling
        engine_sound.stop()

    # Restart engine with throttle + clutch while stalled
    if is_stalled and clutch > 0.5 and throttle > 0.3:
        is_stalled = false
        current_rpm = idle_rpm


func handle_acceleration(delta):
    var throttle = Input.get_action_strength("throttle_pct")
    var front_brake = Input.get_action_strength("brake_front_pct")
    var rear_brake = Input.get_action_strength("brake_rear")
    var clutch = Input.get_action_strength("clutch")

    # Get speed band for current gear
    var gear_max_speed = get_max_speed_for_gear()
    var gear_min_speed = get_min_speed_for_gear()

    # Can't accelerate when stalled
    if is_stalled:
        throttle = 0

    # Accelerate (reduced power when clutch is held)
    if throttle > 0:
        var effective_throttle = throttle * (1.0 - clutch * 0.8)  # 80% power loss with full clutch
        var target_speed = gear_max_speed * effective_throttle

        # Acceleration rate - matches RPM lerp feel
        # Lower gears accelerate faster (higher ratio = more torque)
        var gear_ratio = gear_ratios[current_gear - 1]
        var base_ratio = gear_ratios[num_gears - 1]
        var accel_rate = 0.08 * (gear_ratio / base_ratio)  # ~0.08 base, scales with gear

        # Reduce acceleration when below gear's minimum speed (lugging the engine)
        if speed < gear_min_speed and current_gear > 1:
            var lug_factor = speed / gear_min_speed if gear_min_speed > 0 else 0.0
            accel_rate *= lug_factor * 0.3  # Very weak acceleration when lugging

        # Don't accelerate past gear's max speed (at max RPM)
        if speed < gear_max_speed or current_rpm < max_rpm:
            speed = lerpf(speed, target_speed, accel_rate)

    # Brake
    var total_brake = clamp(front_brake + rear_brake, 0, 1)
    if total_brake > 0:
        speed = move_toward(speed, 0, brake_strength * total_brake * delta)

    # Natural friction when no input
    if throttle == 0 and total_brake == 0:
        speed = move_toward(speed, 0, friction * delta)


func handle_steering(delta):
    var steer_input = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")

    # Snappier steering at low speeds
    var speed_factor = 1.0 + (1.0 - clamp(speed / 10.0, 0.0, 1.0)) * 1.5  # Up to 2.5x faster at low speed
    var effective_steering_speed = steering_speed * speed_factor

    if steer_input != 0:
        steering_angle = move_toward(steering_angle, max_steering_angle * steer_input, effective_steering_speed * delta)
    else:
        steering_angle = move_toward(steering_angle, 0, effective_steering_speed * 2 * delta)


func handle_lean_input(delta):
    var lean_input = Input.get_action_strength("lean_back") - Input.get_action_strength("lean_forward")
    var steer_input = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
    var throttle = Input.get_action_strength("throttle_pct")
    var clutch = Input.get_action_strength("clutch")
    var front_brake = Input.get_action_strength("brake_front_pct")
    var rear_brake = Input.get_action_strength("brake_rear")
    var total_brake = clamp(front_brake + rear_brake, 0.0, 1.0)

    # Detect clutch dump (clutch released quickly while revving)
    var clutch_dump = last_clutch_input > 0.7 and clutch < 0.3 and throttle > 0.5
    last_throttle_input = throttle
    last_clutch_input = clutch

    # Can't START a wheelie/stoppie while turning, but can continue one
    var is_in_wheelie = pitch_angle > deg_to_rad(5)
    var is_in_stoppie = pitch_angle < deg_to_rad(-5)
    var is_turning = abs(steering_angle) > 0.2
    var can_start_trick = not is_turning

    # Wheelie: need high RPM OR clutch dump to pop one
    # Once in wheelie, throttle maintains it, releasing gas or braking lowers it
    var wheelie_target = 0.0
    var rpm_ratio = (current_rpm - idle_rpm) / (max_rpm - idle_rpm)
    var at_high_rpm = rpm_ratio > 0.85  # Near redline
    var can_pop_wheelie = lean_input > 0.3 and throttle > 0.7 and (at_high_rpm or clutch_dump)

    if speed > 1 and (is_in_wheelie or (can_pop_wheelie and can_start_trick)):
        if throttle > 0.3:
            # Throttle maintains wheelie height, brake counters it
            wheelie_target = max_wheelie_angle * throttle * (1.0 - total_brake)
            # Lean input adds minor influence
            wheelie_target += max_wheelie_angle * lean_input * 0.15
        # else: wheelie_target stays 0, wheelie will lower

    # Stoppie: requires lean forward to start, then brake controls height
    var stoppie_target = 0.0
    var wants_stoppie = lean_input < -0.3 and front_brake > 0.7
    if speed > 1 and (is_in_stoppie or (wants_stoppie and can_start_trick)):
        # Front brake controls stoppie, throttle counters it
        stoppie_target = -max_stoppie_angle * front_brake * (1.0 - throttle * 0.5)
        # Lean input adds minor influence
        stoppie_target += -max_stoppie_angle * (-lean_input) * 0.15

    # Apply pitch based on which trick is active
    if wheelie_target > 0:
        pitch_angle = move_toward(pitch_angle, wheelie_target, rotation_speed * delta)
    elif stoppie_target < 0:
        pitch_angle = move_toward(pitch_angle, stoppie_target, rotation_speed * delta)
        if not tire_screech.playing:
            tire_screech.volume_db = linear_to_db(0.5)
            tire_screech.play()
    else:
        pitch_angle = move_toward(pitch_angle, 0, return_speed * delta)
        if tire_screech.playing:
            tire_screech.stop()
    
    # Side lean (mix of input and speed-based auto-lean in turns)
    var turn_lean = 0.0
    if speed > 1:
        turn_lean = -steering_angle * 0.6  # Auto-lean into turns

    # At low speed, leaning is dangerous - you can fall over
    # Throttle helps keep the bike upright (gyroscopic effect from wheels)
    var low_speed_threshold = 5.0  # ~18 km/h
    var target_lean = -max_lean_angle * steer_input * 0.4 + turn_lean

    if speed < low_speed_threshold:
        # Reduce steering authority at low speed
        var speed_authority = clamp(speed / low_speed_threshold, 0.1, 1.0)
        target_lean *= speed_authority

    lean_angle = move_toward(lean_angle, target_lean, rotation_speed * delta)


func handle_skidding(delta):
    var rear_brake = Input.get_action_strength("brake_rear")

    # Skid when rear brake is held and moving
    var is_skidding = rear_brake > 0.5 and speed > 2 and is_on_floor()

    if is_skidding:
        # Spawn skid marks
        skid_spawn_timer += delta
        if skid_spawn_timer >= SKID_SPAWN_INTERVAL:
            skid_spawn_timer = 0.0
            spawn_skid_mark()

        # Fishtail - rear end swings out dramatically when skidding
        # Even without steering, the rear wants to come around
        var steer_influence = steering_angle / max_steering_angle  # -1 to 1

        # Base fishtail from steering direction (rear swings opposite to turn)
        var target_fishtail = -steer_influence * max_fishtail_angle * rear_brake

        # More fishtail at higher speeds
        var speed_factor = clamp(speed / 20.0, 0.5, 1.5)
        target_fishtail *= speed_factor

        # Add instability - rear wants to swing out even more once started
        if abs(fishtail_angle) > deg_to_rad(15):
            target_fishtail *= 1.3  # Amplify once sliding

        fishtail_angle = move_toward(fishtail_angle, target_fishtail, fishtail_speed * delta)

        # Play tire screech while fishtailing
        if not tire_screech.playing:
            tire_screech.volume_db = linear_to_db(0.7)
            tire_screech.play()
    else:
        skid_spawn_timer = 0.0
        # Recover fishtail when not skidding
        fishtail_angle = move_toward(fishtail_angle, 0, fishtail_recovery_speed * delta)


func spawn_skid_mark():
    # Create a decal at the rear wheel position
    var decal = Decal.new()
    decal.texture_albedo = skidmark_texture
    decal.size = Vector3(0.15, 0.5, 0.4)  # Width, height (into ground), length
    decal.cull_mask = 1  # Only affect default layer

    # Store transform values before adding to tree
    var rear_wheel_global = rear_wheel.global_position
    var bike_rotation = global_rotation

    # Add to scene tree first (required before setting global transforms)
    get_tree().current_scene.add_child(decal)

    # Now set global transforms (node is in tree)
    decal.global_position = Vector3(rear_wheel_global.x, rear_wheel_global.y - 0.05, rear_wheel_global.z)
    decal.global_rotation = bike_rotation

    # Create timer to remove after lifetime
    var timer = get_tree().create_timer(SKID_MARK_LIFETIME)
    timer.timeout.connect(func(): if is_instance_valid(decal): decal.queue_free())


func apply_movement(delta):
    var forward = -global_transform.basis.z

    if speed > 0.5:
        # Lerp between tight and wide turns based on speed
        var speed_pct = speed / max_speed
        var turn_radius = lerp(min_turn_radius, max_turn_radius, speed_pct)
        var turn_rate = turn_speed / turn_radius

        # Normal steering rotation
        rotate_y(-steering_angle * turn_rate * delta)

        # Fishtail adds dramatic extra rotation (rear sliding out hard)
        # But also scrubs speed since you're sliding sideways
        if abs(fishtail_angle) > 0.01:
            rotate_y(fishtail_angle * delta * 4.0)
            # Lose speed proportional to slide angle (sliding = friction)
            var slide_friction = abs(fishtail_angle) / max_fishtail_angle
            speed = move_toward(speed, 0, slide_friction * 15.0 * delta)

    velocity = forward * speed

    if not is_on_floor():
        velocity.y -= gravity * delta


func apply_mesh_rotation():
    mesh.transform = Transform3D.IDENTITY
    
    # Pitch pivot
    var pivot: Vector3
    if pitch_angle >= 0:
        pivot = rear_wheel.position
    else:
        pivot = front_wheel.position
    
    # Apply pitch
    if pitch_angle != 0:
        rotate_mesh_around_pivot(pivot, Vector3.RIGHT, pitch_angle)
    
    # Apply lean (including idle tip)
    var total_lean = lean_angle + idle_tip_angle
    if total_lean != 0:
        mesh.rotate_z(total_lean)


func rotate_mesh_around_pivot(pivot: Vector3, axis: Vector3, angle: float):
    var t = mesh.transform
    t.origin -= pivot
    t = t.rotated(axis, angle)
    t.origin += pivot
    mesh.transform = t


func update_ui():
    if is_stalled:
        gear_label.text = "STALLED"
    else:
        gear_label.text = "Gear: %d" % current_gear
    speed_label.text = "Speed: %d km/h" % int(speed * 3.6)  # Convert m/s to km/h

    # Throttle bar - green color, red at redline
    var throttle = Input.get_action_strength("throttle_pct")
    throttle_bar.value = throttle
    var rpm_ratio = (current_rpm - idle_rpm) / (max_rpm - idle_rpm)
    if rpm_ratio > 0.9:
        throttle_bar.modulate = Color(1.0, 0.2, 0.2)  # Red at redline
    else:
        throttle_bar.modulate = Color(0.2, 0.8, 0.2)  # Green

    # Brake danger bar - shows front brake, color changes with danger
    var front_brake = Input.get_action_strength("brake_front_pct")
    brake_danger_bar.value = front_brake
    if brake_danger_level > 0.1:
        # Color from yellow to red as danger increases
        var danger_color = Color(1.0, 1.0 - brake_danger_level, 0.0)  # Yellow -> Orange -> Red
        brake_danger_bar.modulate = danger_color
    else:
        # Normal brake color (blue-ish)
        brake_danger_bar.modulate = Color(0.3, 0.5, 0.9)

    # Controller vibration - combine multiple sources
    var weak_total = 0.0
    var strong_total = 0.0

    # Brake danger vibration
    if brake_danger_level > 0.1:
        weak_total += brake_danger_level * 1.0
        strong_total += brake_danger_level * brake_danger_level * 1.0

    # Fishtail vibration - rumble proportional to slide angle
    var fishtail_intensity = abs(fishtail_angle) / max_fishtail_angle
    if fishtail_intensity > 0.1:
        weak_total += fishtail_intensity * 0.6  # Moderate weak motor
        strong_total += fishtail_intensity * fishtail_intensity * 0.8  # Strong rumble when sliding hard

    # Redline vibration - engine buzzing at high RPM
    if rpm_ratio > 0.85 and not is_stalled:
        var redline_intensity = (rpm_ratio - 0.85) / 0.15  # 0-1 from 85% to 100% RPM
        weak_total += redline_intensity * 0.4  # Light buzz
        strong_total += redline_intensity * 0.2  # Subtle deep rumble

    # Apply combined vibration (clamp to max 1.0)
    if weak_total > 0.01 or strong_total > 0.01:
        Input.start_joy_vibration(0, clamp(weak_total, 0.0, 1.0), clamp(strong_total, 0.0, 1.0), 0.15)
    else:
        Input.stop_joy_vibration(0)


func update_audio():
    var throttle = Input.get_action_strength("throttle_pct")

    # No engine sound when stalled
    if is_stalled:
        if engine_sound.playing:
            engine_sound.stop()
        return

    # Engine runs when moving or throttle applied
    if speed > 0.5 or throttle > 0:
        if not engine_sound.playing:
            engine_sound.play()

        # Pitch based on RPM (0.8 at idle, up to 1.6 at max RPM)
        var rpm_ratio = (current_rpm - idle_rpm) / (max_rpm - idle_rpm)
        var target_pitch = lerpf(0.8, 1.6, clamp(rpm_ratio, 0.0, 1.0))
        engine_sound.pitch_scale = target_pitch
    else:
        if engine_sound.playing:
            engine_sound.stop()


func handle_idle_tipping(delta):
    var throttle = Input.get_action_strength("throttle_pct")
    var low_speed_threshold = 5.0  # ~18 km/h

    # Track if bike has ever started moving - once it has, tipping can occur
    if speed > 3.0:
        has_started_moving = true

    # At spawn or standstill before moving, stay perfectly upright
    if not has_started_moving:
        idle_tip_angle = 0.0
        return

    if speed < low_speed_threshold:
        # At low speed, lean angle contributes to tipping
        # If you're leaned over and not accelerating, you'll fall
        var lean_tip_contribution = 0.0
        if throttle < 0.3:
            # Lean angle pushes you toward falling in that direction
            lean_tip_contribution = lean_angle * 0.5  # Lean converts to tip

        if speed < idle_tip_speed_threshold and throttle == 0:
            # Very slow / stopped - random tip direction if not already tipping
            if idle_tip_angle == 0 and abs(lean_angle) < deg_to_rad(5):
                idle_tip_angle = 0.01 if randf() > 0.5 else -0.01
            elif abs(lean_angle) >= deg_to_rad(5):
                # Tip in the direction you're leaned
                idle_tip_angle = move_toward(idle_tip_angle, lean_angle, idle_tip_rate * 2.0 * delta)

        # Apply tipping (accelerated by lean)
        var tip_target = sign(idle_tip_angle + lean_tip_contribution) * crash_lean_threshold
        var tip_rate = idle_tip_rate * (1.0 + abs(lean_angle) / max_lean_angle)  # Faster tip when leaned
        idle_tip_angle = move_toward(idle_tip_angle, tip_target, tip_rate * delta)

        # Throttle fights the tip - gyroscopic effect straightens bike
        if throttle > 0.3:
            var recovery_rate = idle_tip_rate * 3.0 * throttle
            idle_tip_angle = move_toward(idle_tip_angle, 0, recovery_rate * delta)
    else:
        # At speed, no tipping - recover any existing tip
        idle_tip_angle = move_toward(idle_tip_angle, 0, idle_tip_rate * 3.0 * delta)


func check_crash_conditions(delta):
    var front_brake = Input.get_action_strength("brake_front_pct")

    var crash_reason = ""

    # Wheelie too far
    if pitch_angle > crash_wheelie_threshold:
        crash_reason = "wheelie"
        crash_pitch_direction = 1  # Fall backward
        crash_lean_direction = 0

    # Stoppie too far
    elif pitch_angle < -crash_stoppie_threshold:
        crash_reason = "stoppie"
        crash_pitch_direction = -1  # Fall forward
        crash_lean_direction = 0

    # Front brake danger - different outcomes based on lean/steering
    # Turning while braking hard = lowside crash
    # Straight braking = stoppie (which can lead to stoppie crash)
    if front_brake > 0.7 and speed > 20:
        front_brake_hold_time += delta

        # Turning makes it much more dangerous
        var turn_factor = abs(steering_angle) / max_steering_angle  # 0-1
        var lean_factor = abs(lean_angle) / max_lean_angle  # 0-1
        var instability = max(turn_factor, lean_factor)

        # Base threshold - reduced by speed and instability
        var speed_factor = clamp((speed - 20) / (max_speed - 20), 0.0, 1.0)
        var base_threshold = 0.5 * (1.0 - speed_factor * 0.3)  # 0.35s at max speed, 0.5s at 20

        # Turning/leaning reduces threshold dramatically
        var crash_time_threshold = base_threshold * (1.0 - instability * 0.7)  # Up to 70% reduction when turning hard

        # Calculate danger level (0-1)
        brake_danger_level = clamp(front_brake_hold_time / crash_time_threshold, 0.0, 1.0)

        if front_brake_hold_time > crash_time_threshold:
            if instability > 0.3:
                # Turning/leaning = lowside crash
                crash_reason = "brake"
                crash_pitch_direction = 0
                crash_lean_direction = -sign(steering_angle) if steering_angle != 0 else sign(lean_angle)
                tire_screech.volume_db = 0.0
                tire_screech.play()
            else:
                # Straight braking = force into stoppie (let stoppie crash handle the rest)
                # Rapidly pitch forward
                pitch_angle = move_toward(pitch_angle, -crash_stoppie_threshold * 1.2, 4.0 * delta)
    else:
        front_brake_hold_time = 0.0
        # Fade danger level when not in danger
        brake_danger_level = move_toward(brake_danger_level, 0.0, 5.0 * delta)

    # Idle tipping over
    if crash_reason == "" and abs(idle_tip_angle) >= crash_lean_threshold:
        crash_reason = "idle_tip"
        crash_pitch_direction = 0
        crash_lean_direction = sign(idle_tip_angle)

    # Total lean too far (from steering + idle tip)
    if crash_reason == "" and abs(lean_angle + idle_tip_angle) >= crash_lean_threshold:
        crash_reason = "lean"
        crash_pitch_direction = 0
        crash_lean_direction = sign(lean_angle + idle_tip_angle)

    if crash_reason != "":
        trigger_crash()


func trigger_crash():
    is_crashed = true
    crash_timer = 0.0
    # Keep speed for lowside crashes (sliding momentum), zero for others
    if crash_lean_direction != 0 and crash_pitch_direction == 0:
        # Lowside - keep momentum but reduce it
        speed *= 0.7
    else:
        speed = 0.0
        velocity = Vector3.ZERO


func handle_crash_state(delta):
    crash_timer += delta

    # Animate the crash - fall sideways or forward/back
    if crash_pitch_direction != 0:
        # Wheelie/stoppie crash - continue rotating in pitch direction
        pitch_angle = move_toward(pitch_angle, crash_pitch_direction * deg_to_rad(90), 3.0 * delta)
    elif crash_lean_direction != 0:
        # Lowside crash - fall over to the side while sliding
        lean_angle = move_toward(lean_angle, crash_lean_direction * deg_to_rad(90), 3.0 * delta)

        # Slide with friction - bike keeps moving but slows down
        if speed > 0.1:
            var forward = -global_transform.basis.z
            velocity = forward * speed
            speed = move_toward(speed, 0, 20.0 * delta)  # Strong friction while sliding
            move_and_slide()

    apply_mesh_rotation()

    # Respawn conditions:
    # - Lowside: when bike stops sliding
    # - Other crashes: after respawn_delay
    if crash_lean_direction != 0 and crash_pitch_direction == 0:
        # Lowside - respawn when stopped
        if speed < 0.1:
            respawn()
    else:
        # Wheelie/stoppie crashes - use timer
        if crash_timer >= respawn_delay:
            respawn()


func respawn():
    is_crashed = false
    global_position = spawn_position
    rotation = spawn_rotation
    pitch_angle = 0.0
    lean_angle = 0.0
    idle_tip_angle = 0.0
    steering_angle = 0.0
    speed = 0.0
    velocity = Vector3.ZERO
    fishtail_angle = 0.0
    front_brake_hold_time = 0.0
    brake_danger_level = 0.0
    last_throttle_input = 0.0
    last_clutch_input = 0.0
    crash_pitch_direction = 0.0
    crash_lean_direction = 0.0
    current_gear = 1
    current_rpm = idle_rpm
    is_stalled = false
    has_started_moving = false  # Reset so bike is stable at respawn
    mesh.transform = Transform3D.IDENTITY
