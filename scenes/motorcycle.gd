class_name Motorcycle extends AnimatableBody3D

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var rotate_point: Node3D = %RotatePoint

var gravity = .98
var disable_input = false
var deadspaces_deg = 1
var input_info: Dictionary = {
    'input_angle': 0.0,
    'swerve_dir': "", # "", left, right
}

func _ready():
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    # var throttle_input from mouse
    # use brake w/ space to save it, but lose speed

# Uses input_info's dictionary
func handle_user_input(ret: Dictionary) -> Dictionary:
    if Input.is_action_pressed("lean_back"):
        ret['input_angle'] += 1
    elif Input.is_action_pressed("lean_forward"):
        ret['input_angle'] -= 1
    
    if Input.is_action_pressed("lean_left"):
        ret['swerve_dir'] = "left"
    elif Input.is_action_pressed("lean_right"):
        ret['swerve_dir'] = "right"

    ret['input_angle'] += SignalBus.throttle_input
    if Input.is_action_pressed("brake"):
        ret['input_angle'] = -2
    
    return ret

func _input(event: InputEvent):
    # Capture/uncapture the mouse w/ click/escape
    if event is InputEventMouseButton:
        if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        
        # on LMB release
        if !event.pressed:
            SignalBus.throttle_input = 0
            lerpf(SignalBus.throttle_input, 0, 0.5)
    
    if event is InputEventKey:
        if event.keycode == KEY_ESCAPE:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    
    # Set throttle input
    if event is InputEventMouseMotion:
        if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
            SignalBus.throttle_input += -1 * event.relative.y
            # print("Mouse Motion rel: ", event.relative)


func _physics_process(delta):
    if disable_input:
        return
    
    # keyboard stuff
    input_info = handle_user_input(input_info)
    var input_angle_deg = input_info['input_angle']
    var current_x_angle_deg = rotate_point.global_rotation_degrees.x
    
    # lower the bike down
    if current_x_angle_deg > 0 && current_x_angle_deg <= 90:
        input_angle_deg -= gravity

    # ground + crash checks
    if current_x_angle_deg < 0:
        input_angle_deg = 0
        rotate_point.global_rotation_degrees.x = 0
        return
    elif current_x_angle_deg > 90:
        do_crash()
        return
    
    print("input_angle: %.1f" % [input_angle_deg])
    print("current_angle: %.1f" % [current_x_angle_deg])
    
    # rotate the bike
    rotate_point.rotate_x(rad_to_deg(input_angle_deg) * delta)
    
    # swerve the bike
    if !anim_player.is_playing():
        # todo: check if we're on the edge of the road, if so crash
        match input_info['swerve_dir']:
            "left":
                anim_player.play("swerve_left")
            "right":
                anim_player.play("swerve_right")
    
    # send info to SignalBus
    SignalBus.angle_deg = rotate_point.global_rotation_degrees.x
    # reset
    input_info = {
        'input_angle': 0.0,
        'swerve_dir': 0,
    }

func do_crash():
    disable_input = true
    anim_player.play("crash")
    SignalBus.notify_ui.emit("You crashed!")
