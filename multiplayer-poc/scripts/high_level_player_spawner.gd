extends MultiplayerSpawner

@export var network_player: PackedScene

func _ready():
    multiplayer.peer_connected.connect(spawn_player)
    # Here we connect to the "host_started" signal in the high_level_network_handler class.
    HighLevelNetworkHandler.host_started.connect(spawn_host_player)

func spawn_player(id: int):
    if !multiplayer.is_server(): return

    var player: Node = network_player.instantiate()
    player.name = str(id)

    get_node(spawn_path).call_deferred("add_child", player)


# In this function, which is connected to the "host_started" signal in the high_level_network_handler
# class, we spawn the server player. Easy right?
func spawn_host_player() -> void:
    if !multiplayer.is_server(): return
    spawn_player(multiplayer.get_unique_id())
