extends MultiplayerSynchronizer

@export var input_dir: Vector2

func _ready():
    # If not the local client
    if get_multiplayer_authority() != multiplayer.get_unique_id():
        set_process(false)
        set_physics_process(false)
    
    # can i comment this out?
    input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

func _physics_process(_delta):
    input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    

# # Called every frame. 'delta' is the elapsed time since the previous frame.
# func _process(delta):
# 	if Input.is_action_just_pressed("jump"):
# 		jump.rpc()

# @rpc("call_local")
# func jump():
# 	if multiplayer.is_server():
# 		player.do_jump = true