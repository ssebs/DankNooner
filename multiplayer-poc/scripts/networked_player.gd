class_name NetworkedPlayer extends CharacterBody2D

@export var bullet_scn: PackedScene = preload("res://scenes/bullet.tscn")

const speed = 800.0

func _enter_tree():
    # Local client is the "server" for InputSynchronizer
    %InputSynchronizer.set_multiplayer_authority(name.to_int())

func _ready():
    %Label.text = "ID: " + name

func _physics_process(delta):
    if multiplayer.is_server():
        _apply_movement_from_input(delta)

func _apply_movement_from_input(_delta):
    velocity = %InputSynchronizer.input_dir * speed
    move_and_slide()

# Server must call this from input_synchronizer
@rpc("call_local")
func shoot_bullet():
    var bullet = bullet_scn.instantiate() as RigidBody2D
    bullet.position = %BulletSpawnPos.position
    add_child(bullet)

# Server must call this from input_synchronizer
@rpc("call_local")
func play_rotate_anim():
    if !%AnimationPlayer.is_playing():
        %AnimationPlayer.play("rotate_360")
