extends Node

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
