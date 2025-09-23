class_name Motorcycle extends AnimatableBody3D

signal finished_run(has_crashed: bool, msg: String)

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var rotate_point: Node3D = %RotatePoint
@onready var camera: Camera3D = %Camera3D
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer

var gravity = 50
var disable_input = false
var has_started = false
var is_lerping_to_stop = false

func _ready():
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    SignalBus.motorcycle_collision.connect(func(msg: String):
        finish_up("crash", true, msg)
    )
    if !Engine.is_editor_hint():
        audio_player.volume_linear = SignalBus.volume


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

    if !Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        SignalBus.throttle_input = lerpf(SignalBus.throttle_input, 0, 5 * delta)
    else:
        SignalBus.throttle_input += randf_range(-2.5, 2.5)
    
    input_info = handle_user_input(input_info)
    SignalBus.speed = clampf(SignalBus.speed * SignalBus.throttle_input, 1, 180)

    # Gameplay stuff
    if has_started:
        SignalBus.distance += delta * SignalBus.speed
        SignalBus.fuel -= delta
        
        # ran out of gas
        if SignalBus.fuel <= 0:
            finish_up("regular_stop", false, "Ran out of gas.")
            return

        # landed back down
        if SignalBus.distance > 400 && current_x_angle_deg < 0:
            finish_up("stoppie", false, "Run finished!")
            return
        
        # Use time between 75=>90 for bonus
        if SignalBus.angle_deg >= 75 && current_x_angle_deg <= 90:
            SignalBus.bonus_time += delta

        # lower the bike down if you're doing a wheelie
        if current_x_angle_deg > 0 && current_x_angle_deg <= 90:
            input_info['input_angle'] -= gravity
 
        # looped the bike
        if current_x_angle_deg > 90:
            finish_up("crash", true, "You looped it!")
            return
        
        # turn the bike
        if !anim_player.is_playing():
            match input_info['swerve_dir']:
                "left":
                    # anim_player.play("swerve_left")
                    self.position.x -= 8 * delta
                "right":
                    # anim_player.play("swerve_right")
                    self.position.x += 8 * delta

        # 
        # Actually rotate the bike & send new angle to SignalBus
        # 
        do_rotate(input_info['input_angle'], delta)

#region gameplay stuff
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
    
    if disable_input:
        return

    # Set throttle input
    if event is InputEventMouseMotion:
        if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
            SignalBus.throttle_input += -1 * event.relative.y
            
            # print("Mouse Motion rel: ", event.relative)

# Uses input_info's dictionary & throttle_input
func handle_user_input(ret: Dictionary) -> Dictionary:
    if Input.is_action_pressed("lean_back"):
        ret['input_angle'] += 1
    elif Input.is_action_pressed("lean_forward"):
        ret['input_angle'] -= 1
    
    if Input.is_action_pressed("lean_left"):
        ret['swerve_dir'] = "left"
    elif Input.is_action_pressed("lean_right"):
        ret['swerve_dir'] = "right"

    ret['input_angle'] = SignalBus.throttle_input
    if Input.is_action_pressed("brake"):
        ret['input_angle'] = -80
    
    return ret
#endregion
