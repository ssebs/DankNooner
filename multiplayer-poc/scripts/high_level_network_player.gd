extends CharacterBody2D

@export var speed = 500.0

@onready var hitbox: Area2D = %Hitbox

func _enter_tree() -> void:
    set_multiplayer_authority(name.to_int())

func _physics_process(_delta):
    if !is_multiplayer_authority(): return

    velocity = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * speed

    move_and_slide()


# BROKEN

#     if Input.is_action_just_pressed("ui_accept"):
#         try_attack()

# func try_attack():
#     for body in hitbox.get_overlapping_bodies():
#         if body is CharacterBody2D and body != self:
#             var target_id = body.name.to_int()
#             request_damage_player.rpc_id(1, target_id, 25)

# @rpc("any_peer", "call_local", "reliable")
# func request_damage_player(target_id: int, _amount: int):
#     if !multiplayer.is_server(): return
    
#     var target = get_node_or_null("../" + str(target_id))
#     if target:
#         target.queue_free()  # Server despawns locally
#         despawn_player.rpc(target_id)  # Tell clients to despawn

# @rpc("any_peer", "call_remote", "reliable")
# func despawn_player(player_id: int):
#     var player = get_node_or_null("../" + str(player_id))
#     if player:
#         player.queue_free()