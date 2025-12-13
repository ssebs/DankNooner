extends CharacterBody2D

@export var speed = 500.0

@export var player_id := 1:
    set(val):
        player_id = val
        %InputSynchronizer.set_multiplayer_authority(val)

@export var direction = Vector2.ZERO

func _apply_movement_from_input(_delta):
    direction = %InputSynchronizer.input_dir * speed
    
    velocity = direction
    move_and_slide()

func _physics_process(delta):
    if multiplayer.is_server():
        _apply_movement_from_input(delta)
