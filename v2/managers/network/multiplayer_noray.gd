class_name MultiplayerNoray extends Node

signal connection_failed(reason: String)

@export var noray_host: String = "noray.ssebs.com"
# @export var noray_host: String = "noray.casa.ssebs.com"
@export var force_relay_mode: bool = false

var oid: String = ""

func _ready():
	if OS.is_debug_build():
		print("replacing noray_host for debug")
		noray_host = "noray.casa.ssebs.com"

## Registers with Noray and returns an ENet server peer.
func start_server() -> ENetMultiplayerPeer:
	Noray.on_connect_nat.connect(_handle_noray_client_connect)
	Noray.on_connect_relay.connect(_handle_noray_client_connect)

	await _register_with_noray()

	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(Noray.local_port)
	if err != OK:
		printerr("failed to create server on Noray port %d" % Noray.local_port)
		return null
	return peer


## Disconnects Noray signals for server mode.
func stop_server():
	if Noray.on_connect_nat.is_connected(_handle_noray_client_connect):
		Noray.on_connect_nat.disconnect(_handle_noray_client_connect)
	if Noray.on_connect_relay.is_connected(_handle_noray_client_connect):
		Noray.on_connect_relay.disconnect(_handle_noray_client_connect)
	oid = ""


## Connects to a Noray host via NAT/relay. Returns OK on success.
func connect_client(noray_host_oid: String) -> Error:
	var err = await _register_with_noray()
	if err != OK:
		connection_failed.emit("Failed to register w/ noray server")
		return err

	Noray.on_connect_nat.connect(_handle_noray_connect_nat)
	Noray.on_connect_relay.connect(_handle_noray_connect)
	Noray.on_command.connect(_handle_noray_command)
	oid = noray_host_oid

	if force_relay_mode:
		err = Noray.connect_relay(oid)
	else:
		err = Noray.connect_nat(oid)

	if err != OK:
		printerr("failed to connect_nat")
		Noray.on_connect_nat.disconnect(_handle_noray_connect_nat)
		Noray.on_connect_relay.disconnect(_handle_noray_connect)
		Noray.on_command.disconnect(_handle_noray_command)
		return err

	return OK


## Disconnects Noray signals for client mode.
func disconnect_client():
	if Noray.on_connect_nat.is_connected(_handle_noray_connect_nat):
		Noray.on_connect_nat.disconnect(_handle_noray_connect_nat)
	if Noray.on_connect_relay.is_connected(_handle_noray_connect):
		Noray.on_connect_relay.disconnect(_handle_noray_connect)
	if Noray.on_command.is_connected(_handle_noray_command):
		Noray.on_command.disconnect(_handle_noray_command)
	oid = ""


## Returns current Noray OID.
func get_addr() -> String:
	return oid


#region Internal

func _register_with_noray() -> Error:
	var err = await Noray.connect_to_host(noray_host, 8890)
	if err != OK:
		printerr("noray failed to connect to noray @ %s" % noray_host)
		return err

	Noray.register_host()
	await Noray.on_pid
	oid = Noray.oid

	err = await Noray.register_remote()
	if err != OK:
		printerr("noray failed to connect to register_remote")
		return err

	return OK


func _handle_noray_client_connect(address: String, port: int):
	var peer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var err = await PacketHandshake.over_enet(peer.host, address, port)
	if err != OK:
		printerr("noray packed handshake failed")


func _handle_noray_connect_nat(address: String, port: int):
	var err = await _handle_noray_connect(address, port)
	if err != OK:
		printerr("NAT connection failed, trying relay")
		Noray.connect_relay(oid)


func _handle_noray_connect(address: String, port: int) -> Error:
	var udp = PacketPeerUDP.new()
	udp.bind(Noray.local_port)
	udp.set_dest_address(address, port)

	var err = await PacketHandshake.over_packet_peer(udp)
	udp.close()

	if err != OK:
		return err

	# Connect to host
	var peer = ENetMultiplayerPeer.new()
	err = peer.create_client(address, port, 0, 0, 0, Noray.local_port)

	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	return OK


func _handle_noray_command(command: String, data: String):
	if command == "error":
		printerr("Noray error: %s" % data)
		connection_failed.emit(data)

#endregion
