# Multiplayer Lobby & Game Flow

This document explains the complete flow of the multiplayer lobby system, from hosting/joining through game start.

## Overview

The lobby system uses ENet for networking with two connection modes:

- **Noray**: NAT traversal via relay server (default)
- **IP/Port**: Direct connection (requires port forwarding)

---

## High-Level Flow

```mermaid
flowchart LR
    subgraph Phase1[" "]
        A[PlayMenu] -->|Host/Join/Freeroam| B[LobbyMenu]
    end
    subgraph Phase2[" "]
        B -->|Players connect| C[Waiting in Lobby]
    end
    subgraph Phase3[" "]
        C -->|Host clicks Start| D[InGame]
    end
```

Three phases:

1. **[Phase 1: Host Starts Server](#phase-1-host-starts-server)** - Host creates server, gets invite code
2. **[Phase 2: Client Joins](#phase-2-client-joins)** - Client connects using invite code
3. **[Phase 3: Game Starts](#phase-3-game-starts)** - Host starts, all peers spawn into level

---

## Phase 1: Host Starts Server

When the host clicks "Host" in PlayMenu:

```mermaid
sequenceDiagram
    participant Play as PlayMenuState
    participant Lobby as LobbyMenuState
    participant MM as MultiplayerManager
    participant Handler as Noray/IPPort Handler

    Play->>Lobby: transitioned(LobbyStateContext.NewHost)
    Lobby->>MM: start_server()
    MM->>Handler: start_server()
    Handler-->>MM: ENetMultiplayerPeer + OID/IP
    MM->>MM: _on_peer_connected(1)
    Note right of MM: Host is always peer ID 1
    MM->>MM: update_username.rpc_id(1, 1, "HostName")
    MM-->>Lobby: game_id_set("abc123-OID")
    Lobby->>Lobby: Display OID, copy to clipboard
    MM-->>Lobby: lobby_players_updated({1: "HostName"})
    Lobby->>Lobby: player_list shows host
```

**Result**: Host sees lobby with their name, invite code displayed and copied to clipboard.

---

## Phase 2: Client Joins

When client enters the invite code and clicks "Join":

```mermaid
sequenceDiagram
    participant Play as PlayMenuState
    participant Lobby as LobbyMenuState
    participant MM as MultiplayerManager
    participant Handler as Handler
    participant HostMM as Host's MultiplayerManager

    Play->>Lobby: transitioned(LobbyStateContext.NewJoin)
    Play->>MM: connect_client("abc123-OID")
    MM->>Handler: connect_client()
    Handler-->>MM: connection_succeeded
    MM-->>Lobby: client_connection_succeeded

    Note over MM: Check if ENet fully connected
    MM->>MM: Wait for connected_to_server if needed
    MM->>MM: _on_enet_connected()

    Lobby->>HostMM: update_username.rpc_id(1, my_id, "ClientName")
    HostMM->>HostMM: lobby_players[client_id] = "ClientName"
    HostMM-->>Lobby: sync_lobby_players.rpc(full_dict)
    Lobby->>Lobby: player_list shows all players
```

**Result**: Both host and client see full player list with usernames.

---

## Phase 3: Game Starts

When host clicks "Start":

```mermaid
sequenceDiagram
    participant HostLobby as Host LobbyMenuState
    participant ClientLobby as Client LobbyMenuState
    participant LM as LevelManager

    HostLobby->>HostLobby: start_game.rpc()
    HostLobby-->>ClientLobby: start_game.rpc()

    par All peers execute
        HostLobby->>LM: spawn_level(level_name)
        LM->>LM: spawn_players()
        Note over LM: For each id in lobby_players:<br/>instantiate PlayerEntity
    and
        ClientLobby->>LM: spawn_level(level_name)
        LM->>LM: spawn_players()
    end
```

**Result**: All peers load the same level with all players spawned.

---

## Deep Dive: Connection Signals

The system has multiple connection signals. Here's why each exists:

### Signal Timeline

```mermaid
sequenceDiagram
    participant Handler as Handler
    participant MM as MultiplayerManager
    participant Godot as Godot Multiplayer
    participant Lobby as LobbyMenuState

    rect rgb(40, 40, 60)
        Note over Handler,Lobby: Stage 1: Handler Success
        Handler->>MM: connection_succeeded
        Note right of MM: ENet peer created<br/>Handshake may be in progress
    end

    rect rgb(40, 60, 40)
        Note over Handler,Lobby: Stage 2: ENet Connected
        Godot->>MM: connected_to_server (if needed)
        MM->>MM: _on_enet_connected()
        MM-->>Lobby: client_connection_succeeded
        Note right of Lobby: NOW safe to send RPCs
    end

    rect rgb(60, 40, 40)
        Note over Handler,Lobby: Stage 3: Server Sees Peer
        Godot->>MM: peer_connected(client_id)
        MM->>MM: Add to lobby_players dict
    end

    rect rgb(60, 60, 40)
        Note over Handler,Lobby: Stage 4: Username Synced
        Lobby->>MM: update_username RPC
        MM-->>Lobby: lobby_players_updated
        Note right of Lobby: UI shows player with name
    end
```

### Signal Reference

| Signal                        | Source             | When                 | Purpose               |
| ----------------------------- | ------------------ | -------------------- | --------------------- |
| `connection_succeeded`        | Handler            | ENet peer created    | Low-level success     |
| `client_connection_succeeded` | MultiplayerManager | ENet fully connected | **Safe for RPCs**     |
| `peer_connected(id)`          | Godot              | Server sees peer     | Add to lobby dict     |
| `game_id_set(addr)`           | MultiplayerManager | Got OID/IP           | Display invite code   |
| `lobby_players_updated`       | MultiplayerManager | After sync RPC       | Update player list UI |

### Why Two Stages?

```mermaid
flowchart TD
    A[Handler: connection_succeeded] -->|"ENet peer exists"| B{Bidirectional ready?}
    B -->|No| C[Wait for connected_to_server]
    B -->|Yes| D[_on_enet_connected]
    C --> D
    D -->|"Emit client_connection_succeeded"| E[Lobby receives signal]
    E -->|"Safe now"| F[Send username RPC]
```

Edge cases handled:

1. Handler succeeds but ENet handshake fails
2. ENet connects but server doesn't acknowledge
3. Client tries RPC before channel ready

The ENet ready check is handled inside `MultiplayerManager._on_handler_connection_succeeded()`, so `client_connection_succeeded` only fires once the peer is fully connected and RPCs are safe to send.

Code pattern in `multiplayer_manager.gd:178-186`:

```gdscript
func _on_handler_connection_succeeded():
    if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
        multiplayer.connected_to_server.connect(_on_enet_connected, CONNECT_ONE_SHOT)
    else:
        _on_enet_connected()

func _on_enet_connected():
    client_connection_succeeded.emit()
```

---

## Deep Dive: Username RPC Flow

```mermaid
flowchart TB
    subgraph Client["Client Side"]
        C1[_on_enet_connected]
        C2["update_username.rpc_id(1, my_id, my_name)"]
        C1 --> C2
    end

    subgraph Server["Server Side"]
        S1["update_username() handler"]
        S2["lobby_players[id] = name"]
        S3["sync_lobby_players.rpc(dict)"]
        S1 --> S2 --> S3
    end

    subgraph All["All Peers"]
        A1["sync_lobby_players() handler"]
        A2["lobby_players = dict"]
        A3["lobby_players_updated.emit()"]
        A4["player_list.update_from_dict()"]
        A1 --> A2 --> A3 --> A4
    end

    C2 -->|"RPC to peer 1"| S1
    S3 -->|"Broadcast"| A1
```

### RPC Signatures

```gdscript
# Client → Server
@rpc("any_peer", "call_local", "reliable")
func update_username(id: int, username: String):
    if !multiplayer.is_server(): return
    lobby_players[id] = username
    sync_lobby_players.rpc(lobby_players)

# Server → All
@rpc("call_local", "reliable")
func sync_lobby_players(players: Dictionary):
    lobby_players = players
    lobby_players_updated.emit(players)
```

**Why this pattern?**

- Server is authoritative (single source of truth)
- Full dict sync prevents delta bugs
- `call_local` ensures server updates its own UI
- `reliable` ensures critical data arrives

---

## Deep Dive: Level Selection Sync

```mermaid
sequenceDiagram
    participant HostUI as Host LevelSelectUI
    participant HostLobby as Host Lobby
    participant ClientLobby as Client Lobby
    participant ClientUI as Client LevelSelectUI

    HostUI->>HostLobby: level_selected
    HostLobby->>HostLobby: share_selected_level_with_clients.rpc(idx)
    HostLobby-->>ClientLobby: RPC

    par
        HostLobby->>HostUI: set_selected_index(idx)
    and
        ClientLobby->>ClientUI: set_selected_index(idx)
    end
```

Clients see the same level selected, but only host can change it.

---

## Deep Dive: Player Spawning

```mermaid
flowchart TB
    A["start_game.rpc()"] --> B["level_manager.spawn_level()"]
    B --> C["level_manager.spawn_players()"]
    C --> D["for id in lobby_players"]
    D --> E["_spawn_player(id)"]
    E --> F["PlayerEntity.instantiate()"]
    F --> G["node.name = str(id)"]
    G --> H["set_username_label(name)"]
```

```gdscript
func _spawn_player(id: int):
    var uname = multiplayer_manager.lobby_players[id]
    var player = player_scene.instantiate() as PlayerEntity
    player.name = str(id)  # Critical for netfox sync
    current_level.player_spawn_pos.add_child(player, true)
    player.set_username_label(uname)
```

**Key detail**: Node name = peer ID, which netfox uses for rollback sync.

---

## State Machine Overview

```mermaid
stateDiagram-v2
    [*] --> PlayMenu

    PlayMenu --> LobbyMenu: Host/Join/Freeroam

    state LobbyMenu {
        [*] --> Setup
        Setup --> Waiting: Connected
        Waiting --> Waiting: Players join/leave
        Setup --> Failed: Error/Timeout
        Waiting --> Failed: Disconnect
        Failed --> [*]
    }

    LobbyMenu --> InGame: start_game.rpc()
    LobbyMenu --> PlayMenu: Back

    InGame --> PauseMenu: ESC
    PauseMenu --> InGame: Resume
    PauseMenu --> PlayMenu: Quit
```

---

## Error Handling

### Connection Timeout

```mermaid
sequenceDiagram
    participant Lobby as LobbyMenuState
    participant Timer as TimeoutTimer (30s)

    Lobby->>Timer: start()
    alt Success
        Lobby->>Timer: stop()
    else Timeout
        Timer->>Lobby: timeout
        Lobby->>Lobby: Show toast, go back
    end
```

### Server Disconnect

```mermaid
sequenceDiagram
    participant Godot as Godot Multiplayer
    participant MM as MultiplayerManager
    participant Lobby as LobbyMenuState

    Godot->>MM: server_disconnected
    MM->>MM: disconnect_client()
    MM-->>Lobby: server_disconnected
    Lobby->>Lobby: _on_back_pressed()
```

---

## Connection Mode Detection

```mermaid
flowchart LR
    Input[User enters code] --> Check{Valid IP?}
    Check -->|"192.168.1.1"| IP[IP/Port Mode]
    Check -->|No| Check2{21-char OID?}
    Check2 -->|"abc123..."| Noray[Noray Mode]
    Check2 -->|No| Invalid[Invalid]
```

```gdscript
func _auto_detect_connection_mode(text: String):
    if text.is_valid_ip_address():
        multiplayer_manager.connection_mode = ConnectionMode.IP_PORT
    elif _is_valid_noray_oid(text):
        multiplayer_manager.connection_mode = ConnectionMode.NORAY
```

---

## Key Code Locations

| Component           | File                   | Lines   |
| ------------------- | ---------------------- | ------- |
| Host button         | play_menu_state.gd     | 106-108 |
| Join button         | play_menu_state.gd     | 111-119 |
| Server startup      | multiplayer_manager.gd | 33-49   |
| Client connect      | multiplayer_manager.gd | 70-86   |
| Username RPC        | multiplayer_manager.gd | 152-165 |
| Connection handling | multiplayer_manager.gd | 178-186 |
| Game start RPC      | lobby_menu_state.gd    | 164-168 |
| Player spawning     | level_manager.gd       | 86-99   |
| Player list UI      | player_list_ui.gd      | 15-36   |
