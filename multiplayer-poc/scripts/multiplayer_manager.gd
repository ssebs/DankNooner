extends Node


const PORT: int = 42069

var multiplayer_scene = preload("res://scenes/networked_player.tscn")
var _players_spawn_node: Node2D

func start_server():
    var peer = ENetMultiplayerPeer.new()
    peer.create_server(PORT)
    multiplayer.multiplayer_peer = peer

    multiplayer.peer_connected.connect(_add_player_to_game)
    multiplayer.peer_disconnected.connect(_rm_player)

    _players_spawn_node = get_tree().current_scene.get_node("Players")

    # Join as a client too
    _add_player_to_game(1)


func start_client(ip_addr: String = "127.0.0.1"):
    var peer = ENetMultiplayerPeer.new()
    peer.create_client(ip_addr, PORT)
    multiplayer.multiplayer_peer = peer
    

func _add_player_to_game(id: int):
    print("New Player: %s" % id)
    var player_to_add = multiplayer_scene.instantiate()
    player_to_add.name = str(id)

    _players_spawn_node.add_child(player_to_add, true)


func _rm_player(id: int):
    print("Deleting %s" % id)

    if not _players_spawn_node.has_node(str(id)):
        return
    _players_spawn_node.get_node(str(id)).queue_free()
