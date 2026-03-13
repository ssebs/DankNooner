# WebRTC Multiplayer Setup

## Goal

Replace Noray NAT traversal with WebRTC. No port forwarding required for host or clients. A standalone signaling server on `ssebs.com` handles lobby creation and SDP/ICE relay. Once WebRTC connects, all game traffic is peer-to-peer.

## Architecture

```
Host  ──ws──►  Signaling Server (ssebs.com)  ◄──ws──  Client
                   (lobby + SDP/ICE relay)
  │                                                      │
  └──────────── WebRTC (via STUN/TURN) ─────────────────┘
                 (game data, peer-to-peer)
```

- **Signaling server** — standalone WebSocket service on `ssebs.com`. Manages lobbies, relays SDP offers/answers and ICE candidates between peers. Very lightweight, no game data passes through it.
- **STUN/TURN server** — coturn on `stun.ssebs.com`. STUN discovers public IPs for NAT punch-through. TURN relays as fallback if direct P2P fails.
- **Game clients** — both host and joining players connect to the signaling server as WebSocket clients. No one runs a server locally.

## What needs to happen

1. **Build standalone signaling server** — extract the embedded signaling logic from `multiplayer_webrtc.gd` (the `SignalingPeer`/`SignalingLobby` classes, `_poll_signaling_server`, `_sig_parse_msg`, etc.) into a standalone service. Run it alongside coturn on `ssebs.com`.
2. **Refactor `multiplayer_webrtc.gd`** — remove embedded signaling server code. Both host and client connect to the remote signaling server via WebSocket. Host creates a lobby, client joins by code.
3. **Address format** — lobby code only (no IP needed since everyone connects to the same signaling server).

## What you need

1. **Signaling server** running on `ssebs.com` (WebSocket, port TBD)
2. **STUN/TURN server** running on `stun.ssebs.com` via coturn
3. **`webrtc-native` GDExtension** installed in the Godot project (required for desktop builds)
