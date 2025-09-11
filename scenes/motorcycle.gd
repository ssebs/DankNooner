class_name Motorcycle extends AnimatableBody3D

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var rotate_point: Node3D = %RotatePoint

var gravity = .98
var disable_input = false
var deadspaces_deg = 1
var input_info: Dictionary = {
    'x_angle': 0.0,
    'swerve_dir': "", # "", left, right
}

func _ready():
    pass

# Uses input_info's dictionary
func handle_user_input(ret: Dictionary) -> Dictionary:
    if Input.is_action_pressed("throttle"):
        ret['x_angle'] = 2
    elif Input.is_action_pressed("brake"):
        ret['x_angle'] = -2
        
    if Input.is_action_pressed("lean_back"):
        ret['x_angle'] += 1
    elif Input.is_action_pressed("lean_forward"):
        ret['x_angle'] -= 1
    
    if Input.is_action_pressed("lean_left"):
        ret['swerve_dir'] = "left"
    elif Input.is_action_pressed("lean_right"):
        ret['swerve_dir'] = "right"
    return ret

func _physics_process(delta):
    if disable_input:
        return
    
    input_info = handle_user_input(input_info)
    var x_angle_rad = input_info['x_angle']
    var current_x_angle_deg = rotate_point.global_rotation_degrees.x
    
    # lower the bike down
    if current_x_angle_deg > 0 && current_x_angle_deg <= 90:
        x_angle_rad -= gravity

    # ground + crash checks
    if current_x_angle_deg < 0:
        x_angle_rad = 0
        rotate_point.global_rotation_degrees.x = 0
        return
    elif current_x_angle_deg > 90:
        do_crash()
        return
    
    print("nx: %.1f" % [x_angle_rad])
    print("cx: %.1f" % [current_x_angle_deg])
    
    # rotate the bike
    rotate_point.rotate_x(x_angle_rad * delta)
    
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
        'x_angle': 0.0,
        'swerve_dir': 0,
    }

func do_crash():
    disable_input = true
    anim_player.play("crash")
    SignalBus.notify_ui.emit("You crashed!")
