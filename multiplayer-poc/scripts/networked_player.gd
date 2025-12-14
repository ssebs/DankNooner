extends CharacterBody2D

@export var speed = 500.0

func _enter_tree():
    %InputSynchronizer.set_multiplayer_authority(name.to_int())

func _ready():
    %Label.text = "ID: " + name

func _physics_process(delta):
    if multiplayer.is_server():
        _apply_movement_from_input(delta)

func _apply_movement_from_input(_delta):
    velocity = %InputSynchronizer.input_dir * speed
    move_and_slide()
