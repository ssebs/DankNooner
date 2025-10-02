class_name Motorcycle extends AnimatableBody3D

signal finished_run(has_crashed: bool, msg: String)

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var rotate_point: Node3D = %RotatePoint
@onready var camera: Camera3D = %Camera3D
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var speed_boost_timer: Timer = $SpeedBoostTimer

# moved from SignalBus
var angle_deg: float
var throttle_input: float:
    set(val):
        throttle_input = clampf(val, 0, 100)
var bonus_time: float: # aka dank time
    set(val):
        bonus_time = clampf(val, 0, 100)
var speed: float
var distance: float
var gravity = 50

# state related
var disable_input = false
var has_started = false
var is_lerping_to_stop = false

# to be set in _ready
var speed_boosts_remaining: int:
    set(val):
        speed_boosts_remaining = val
        if SignalBus.ui != null:
            SignalBus.ui.set_boosts_remaining_label_text(speed_boosts_remaining)

var max_speed: float
var fuel: float:
    set(val):
        fuel = val
        if SignalBus.ui != null:
            SignalBus.ui.fuel_progress.max_value = fuel
            SignalBus.ui.fuel_progress.value = fuel

func _ready():
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    SignalBus.motorcycle_collision.connect(func(msg: String):
        finish_up("crash", true, msg)
    )

    fuel = SignalBus.upgrade_stats.fuel_level * 10
    speed_boosts_remaining = SignalBus.upgrade_stats.speed_boost_level
    max_speed = lerp(180.0, 360.0, float(SignalBus.upgrade_stats.speed_level - 1) / float(UpgradeStatsRes.Level.HIGH - 1))

    if !Engine.is_editor_hint():
        audio_player.volume_linear = SignalBus.upgrade_stats.volume

#region input
# capture window + set throttle input
func _input(event: InputEvent):
    # Capture/uncapture the mouse w/ click/escape
    if event is InputEventMouseButton:
        if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
            if !disable_input:
                Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        if !has_started:
            has_started = true
            audio_player.play()

    if event is InputEventKey:
        if event.keycode == KEY_ESCAPE:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
            # TODO: if game mode is playing, switch to pause mode
        else:
            if !has_started:
                has_started = true
                audio_player.play()
    
    if disable_input:
        return

    # Set throttle input
    if event is InputEventMouseMotion:
        if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
            SignalBus.throttle_input -= event.relative.y

#endregion

func _physics_process(delta):
    # RPM Audio Pitch
    if SignalBus.throttle_input > 0:
        audio_player.pitch_scale = clampf(SignalBus.throttle_input / 100, 0.5, 3)
    
    # During crash / stoppie / end run
    if disable_input:
        if SignalBus.speed > 0:
            SignalBus.speed -= 5
            SignalBus.throttle_input -= 5
        if is_lerping_to_stop:
            if SignalBus.angle_deg > 0:
                do_rotate(-gravity, delta)
        return


    # Get & clean user inputs
    var current_x_angle_deg = rotate_point.global_rotation_degrees.x
    var input_info: Dictionary = {
        'input_angle': 0.0,
        'swerve_dir': "", # "", left, right
    }

    if !Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) && !Input.is_action_pressed("lean_forward"):
        SignalBus.throttle_input = lerpf(SignalBus.throttle_input, 0, 5 * delta)
    else:
        SignalBus.throttle_input += randf_range(-2.5, 2.5)
    
    if Input.is_action_pressed("lean_forward"):
        SignalBus.throttle_input += 6.9

    if Input.is_action_just_pressed("boost"):
        if speed_boosts_remaining > 0 && speed_boost_timer.time_left == 0:
            do_speed_boost(SignalBus.upgrade_stats.speed_boost_level * 42, 3)
            speed_boosts_remaining -= 1
            SignalBus.ui.set_boosts_remaining_label_text(speed_boosts_remaining)

    if Input.is_action_pressed("lean_left"):
        input_info['swerve_dir'] = "left"
    elif Input.is_action_pressed("lean_right"):
        input_info['swerve_dir'] = "right"

    input_info['input_angle'] = SignalBus.throttle_input
    if Input.is_action_pressed("brake"):
        input_info['input_angle'] = -80

    SignalBus.speed = clampf(SignalBus.speed * SignalBus.throttle_input, 1, max_speed)

    # Gameplay stuff
    if has_started:
        SignalBus.distance += delta * SignalBus.speed
        fuel -= delta
        
        # ran out of gas
        if fuel <= 0:
            finish_up("regular_stop", false, "Ran out of gas.")
            return

        # landed back down
        # TODO: make this optional
        if SignalBus.distance > 400 && current_x_angle_deg < 0:
            # finish_up("stoppie", false, "Run finished!")
            # return
            pass
        
        # Use time between 69=>90 for bonus
        if SignalBus.angle_deg >= 69 && current_x_angle_deg <= 90:
            SignalBus.bonus_time += delta

        # lower the bike down if you're doing a wheelie
        if current_x_angle_deg > 0 && current_x_angle_deg <= 90:
            input_info['input_angle'] -= gravity
 
        # looped the bike
        if current_x_angle_deg > 90:
            finish_up("crash", true, "You looped it!")
            return
        
        # turn the bike
        match input_info['swerve_dir']:
            "left":
                self.position.x -= 8 * delta
            "right":
                self.position.x += 8 * delta

        # 
        # Actually rotate the bike & send new angle to SignalBus
        # 
        do_rotate(input_info['input_angle'], delta)

#region gameplay stuff
func do_speed_boost(addl_amount: float, duration: float):
    var old_max_speed = max_speed
    speed_boost_timer.wait_time = duration

    max_speed += addl_amount

    speed_boost_timer.start()
    await speed_boost_timer.timeout
    speed_boost_timer.stop()
    max_speed = old_max_speed

func finish_up(anim_name: String = "", has_crashed: bool = false, msg: String = ''):
    disable_input = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    anim_player.animation_finished.connect(func(_anim_name: String):
        queue_free()
        finished_run.emit(has_crashed, msg)
    )
    if anim_name != "":
        anim_player.play(anim_name)

func do_rotate(deg: float, delta: float):
    rotate_point.rotate_x(deg_to_rad(deg) * 3 * delta)
    SignalBus.angle_deg = rotate_point.global_rotation_degrees.x

#endregion

## used in `regular_stop` animation
func lerp_rotation_to_stop():
    is_lerping_to_stop = true
