class_name Motorcycle extends AnimatableBody3D

signal finished_run(has_crashed: bool)

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var rotate_point: Node3D = %RotatePoint
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var gravity = 50
var disable_input = false
var has_started = false
var speed = 1

func _ready():
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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

# capture window + set throttle input
func _input(event: InputEvent):
    # Capture/uncapture the mouse w/ click/escape
    if event is InputEventMouseButton:
        if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
            if !disable_input:
                Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        if !has_started:
            has_started = true

    if event is InputEventKey:
        if event.keycode == KEY_ESCAPE:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    
    if disable_input:
        return

    # Set throttle input
    if event is InputEventMouseMotion:
        if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
            SignalBus.throttle_input += -1 * event.relative.y
            # print("Mouse Motion rel: ", event.relative)


func _physics_process(delta):
    if disable_input:
        return
    

    var current_x_angle_deg = rotate_point.global_rotation_degrees.x
    var input_info: Dictionary = {
        'input_angle': 0.0,
        'swerve_dir': "", # "", left, right
    }

    # Get user inputs
    if !Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        SignalBus.throttle_input = lerpf(SignalBus.throttle_input, 0, 5 * delta)
    input_info = handle_user_input(input_info)
    
    # print("throttle_input:", SignalBus.throttle_input)
    # print("speed:", speed)
    speed = clampf(speed * SignalBus.throttle_input, 1, 100)

    # lower the bike down if you're doing a wheelie
    if current_x_angle_deg > 0 && current_x_angle_deg <= 90:
        input_info['input_angle'] -= gravity

    # crash checks
    if current_x_angle_deg > 90:
        finish_up("crash", true)
        return

    if has_started && SignalBus.score > 200 && current_x_angle_deg < 0:
        finish_up("stoppie", false)
        return

    # swerve the bike
    if !anim_player.is_playing():
        # todo: check if we're on the edge of the road, if so crash
        match input_info['swerve_dir']:
            "left":
                anim_player.play("swerve_left")
            "right":
                anim_player.play("swerve_right")
    
    # print("input_angle: %.1f" % [input_info['input_angle']])
    # print("current_angle: %.1f" % [current_x_angle_deg])
    
    # actually rotate the bike & send info to SignalBus
    rotate_point.rotate_x(deg_to_rad(input_info['input_angle']) * 3 * delta)
    SignalBus.angle_deg = rotate_point.global_rotation_degrees.x
    if has_started:
        SignalBus.distance += delta * speed
        SignalBus.score += roundi((SignalBus.distance * SignalBus.angle_deg) / 100)

func finish_up(anim_name: String, has_crashed: bool):
    disable_input = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    anim_player.animation_finished.connect(func(_anim_name: String):
        queue_free()
        finished_run.emit(has_crashed)
    )
    anim_player.play(anim_name)
