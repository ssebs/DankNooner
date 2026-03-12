# WebRTC Multiplayer Setup

## How it works

The host's game instance runs an embedded WebSocket signaling server (port 9080). Clients connect to it to exchange WebRTC offers/answers/ICE candidates, then communicate peer-to-peer.

The STUN/TURN server helps peers discover their public IPs and punch through NAT. If direct P2P fails, TURN relays traffic as a fallback.

## What you need

1. **STUN/TURN server** running on `stun.ssebs.com` via coturn
2. **Port 9080 open** on the host machine (for the signaling WebSocket server)
3. **`webrtc-native` GDExtension** installed in the Godot project (required for desktop builds)

## coturn setup

Install and run coturn on your server. Minimal `/etc/turnserver.conf`:

```
listening-port=3478
realm=ssebs.com
server-name=stun.ssebs.com

# For STUN only, no credentials needed.
# For TURN relay, uncomment and set credentials:
# lt-cred-mech
# user=myuser:mypassword
```

Docker alternative:

```bash
docker run -d --network=host coturn/coturn \
  -n --listening-port=3478 --realm=ssebs.com
```

## Godot project setup

1. Add a `MultiplayerWebRTC` node as a child of `ConnectionManager` in the scene tree
2. Wire the `webrtc_handler` export on `ConnectionManager` to point to it
3. Set `connection_mode` to `WEBRTC` in the inspector
4. Configure exports on `MultiplayerWebRTC`:
   - `signaling_port`: 9080 (default)
   - `stun_server`: `stun:stun.ssebs.com:3478` (default)
   - `turn_server`: (optional) `turn:stun.ssebs.com:3478` if you enable TURN
   - `turn_username` / `turn_credential`: match coturn config

## Connection flow

1. Host: `start_server()` → starts signaling server on port 9080, fetches public IP, connects to itself, creates lobby → returns `ip:lobby_code`
2. Client: `connect_client("ip:lobby_code")` → connects to host's signaling server via WebSocket, joins lobby, exchanges WebRTC negotiation, establishes P2P connection

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 9080 | TCP | WebSocket signaling (host machine) |
| 3478 | UDP | STUN/TURN (stun.ssebs.com) |
