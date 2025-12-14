class_name NetworkedPlayer extends CharacterBody2D

@export var bullet_scn: PackedScene = preload("res://scenes/bullet.tscn")
@export var shoot_bullet: bool = false

const speed = 500.0

func _enter_tree():
    %InputSynchronizer.set_multiplayer_authority(name.to_int())

func _ready():
    %Label.text = "ID: " + name

func _physics_process(delta):
    if multiplayer.is_server():
        _apply_movement_from_input(delta)
    
    # Spawn the bullets on both the server and clients
    _apply_oneshots_from_input()

func _apply_movement_from_input(_delta):
    velocity = %InputSynchronizer.input_dir * speed
    move_and_slide()

func _apply_oneshots_from_input():
    # Bullet spawning
    if shoot_bullet:
        shoot_bullet = false
        var bullet = bullet_scn.instantiate() as RigidBody2D
        bullet.position = %BulletSpawnPos.position
        add_child(bullet)

