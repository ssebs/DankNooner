class_name Motorcycle extends AnimatableBody3D

@onready var rotate_point: Node3D = %RotatePoint

var gravity = 0.2
var disable_input = false

func _ready():
    pass

func handle_user_input(ret: Dictionary) -> Dictionary:
    if Input.is_action_pressed("throttle"):
        ret['x_angle'] = 1
    elif Input.is_action_pressed("brake"):
        ret['x_angle'] = -1
    
    if Input.is_action_pressed("lean_left"):
        ret['z_angle'] = -1
    elif Input.is_action_pressed("lean_right"):
        ret['z_angle'] = 1
    
    # if Input.is_action_pressed("lean_back"):
    #     print("back")
    # elif Input.is_action_pressed("lean_forward"):
    #     print("forward")
    
    return ret

func _physics_process(delta):
    var rotate_info: Dictionary = {
        'x_angle': 0.0,
        'z_angle': 0.0,
    }
    if !disable_input:
        rotate_info = handle_user_input(rotate_info)

    var x_angle = rotate_info['x_angle']

    rotate_point.rotate_x(x_angle * delta)
    rotate_point.rotate_z(rotate_info["z_angle"] * delta)

    
    var actual_x_angle_rad = rotate_point.global_rotation_degrees.x
    print('x: ', actual_x_angle_rad)

    if actual_x_angle_rad < 0:
        actual_x_angle_rad = 0
    elif actual_x_angle_rad > 0 && actual_x_angle_rad <= 90:
        x_angle -= gravity
    elif actual_x_angle_rad > 90:
        # disable_input = true
        print("flip, floop, ya screwed")
