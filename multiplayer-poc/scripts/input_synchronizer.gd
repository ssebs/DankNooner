class_name InputSynchronizer extends MultiplayerSynchronizer

@export var player: NetworkedPlayer
@export var input_dir: Vector2

func _ready():
    # If not the local client
    if get_multiplayer_authority() != multiplayer.get_unique_id():
        set_process(false)
        set_physics_process(false)

func _physics_process(_delta):
    input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")

    if Input.is_action_just_pressed("shoot"):
        tell_clients_to_shoot_bullet.rpc_id(1)
    if Input.is_action_just_pressed("rotate"):
        tell_clients_to_animate.rpc_id(1, multiplayer.get_unique_id())

@rpc("any_peer", "call_local", "reliable")
func tell_clients_to_shoot_bullet():
    player.shoot_bullet.rpc()

@rpc("any_peer", "call_local", "reliable")
func tell_clients_to_animate(_id: int):
    if multiplayer.is_server():
        player.play_rotate_anim.rpc()
