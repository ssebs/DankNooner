extends Node
signal host_started()

const IP_ADDR: String = "localhost"
const PORT: int = 42069
# const MAX_CLIENTS = 20

var peer: ENetMultiplayerPeer

func start_server():
    peer = ENetMultiplayerPeer.new()
    # peer.create_server(PORT, MAX_CLIENTS)
    peer.create_server(PORT)
    multiplayer.multiplayer_peer = peer

func start_client():
    peer = ENetMultiplayerPeer.new()
    peer.create_client(IP_ADDR, PORT)
    multiplayer.multiplayer_peer = peer

# To create a server+player, or host player, we create a new function "start_host()".
# This function then starts the server like normal, but also calls a signal "host_started".
# Since this is an autoloaded class, other functions can connect to this signal, like I did
# in the "high_level_player_spawner". More comments there.
func start_host() -> void:
    start_server()
    host_started.emit()
