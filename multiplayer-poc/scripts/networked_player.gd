extends CharacterBody2D

@export var speed = 500.0

@export var player_id := 1:
    set(val):
        player_id = val
        # Must be after %MultiplayerSynchronizer so player_id is available
        %InputSynchronizer.set_multiplayer_authority(val)

func _apply_movement_from_input(_delta):
    velocity = %InputSynchronizer.input_dir * speed

    move_and_slide()

func _physics_process(delta):
    if multiplayer.is_server():
        _apply_movement_from_input(delta)
