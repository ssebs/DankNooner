extends MultiplayerSynchronizer

@export var input_dir: Vector2

func _ready():
    # If not the local client
    if get_multiplayer_authority() != multiplayer.get_unique_id():
        set_process(false)
        set_physics_process(false)

func _physics_process(_delta):
    input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
