class_name Motorcycle extends AnimatableBody3D

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var rotate_point: Node3D = %RotatePoint

var gravity = .98
var disable_input = false

func _ready():
    pass

func handle_user_input(ret: Dictionary) -> Dictionary:
    if Input.is_action_pressed("throttle"):
        ret['x_angle'] = 2
    elif Input.is_action_pressed("brake"):
        ret['x_angle'] = -2
    
    if Input.is_action_pressed("lean_left"):
        ret['z_angle'] = 1
    elif Input.is_action_pressed("lean_right"):
        ret['z_angle'] = -1
    
    if Input.is_action_pressed("lean_back"):
        ret['x_angle'] += 1
    elif Input.is_action_pressed("lean_forward"):
        ret['x_angle'] -= 1
    
    return ret

func _physics_process(delta):
    var rotate_info: Dictionary = {
        'x_angle': 0.0,
        'z_angle': 0.0,
    }
    if !disable_input:
        rotate_info = handle_user_input(rotate_info)

    var x_angle_rad = rotate_info['x_angle']

    var current_x_angle_deg = rotate_point.global_rotation_degrees.x
    # print('x: ', current_x_angle_deg)
    
    if current_x_angle_deg > 0 && current_x_angle_deg <= 90:
        x_angle_rad -= gravity

    
    if current_x_angle_deg < 0:
        x_angle_rad = 0
        rotate_point.global_rotation_degrees.x = 0
    elif current_x_angle_deg > 90:
        disable_input = true
        anim_player.play("crash")

    rotate_point.rotate_x(x_angle_rad * delta)
    rotate_point.rotate_z(rotate_info["z_angle"] * delta)

    # print('final x: ', rotate_point.global_rotation_degrees.x)