# Steam Integration + Workshop Levels — Plan

> Parked plan. Nothing here is built. Two independent tracks: **A** (Steam networking/invites)
> and **B** (user-made levels, distributed via Workshop). B's steps 1–5 don't need Steam at all.

**Constraints**

- Keep the non-Steam path: IP/port and WebRTC stay, web builds stay working.
- Friendslop, no leaderboards — cheating is not a concern. Mod code running on players' machines
  is accepted.
- Modders author levels **in the Godot editor** and export them; no in-game editor.

---

## Track A — Steam networking

### Current state (verified 2026-10-08)

`ConnectionManager` already delegates to swappable handlers selected by `connection_mode`:
`MultiplayerIPPort` (ENet) and `MultiplayerWebRTC` (signaling + metered TURN). Both expose
`start_server(solo)`, `stop_server()`, `connect_client(addr)`, `disconnect_client()`, `get_addr()`
and the `connection_failed` / `connection_succeeded` signals. Steam is a third handler.

Mode is picked in `play_menu_state.gd` (`_auto_detect_connection_mode`, `ipport_toggle`) and
`lobby_menu_state.gd` (freeroam forces IP_PORT / WEBRTC on web).

### Option A1 — Steam lobbies + invites only, keep WebRTC transport (smallest)

Host creates a Steam lobby and stores the WebRTC lobby code in lobby metadata. Joining via invite
reads the code and calls `connect_client(code)` as normal. Gets invites, "Join Game" from the
friends list and rich presence. Transport and netfox untouched. Still depends on the signaling server and TURN.

### Option A2 — `SteamMultiplayerPeer` transport

Steam Datagram Relay replaces the signaling server and TURN, and hides player IPs.

### Steps

1. **Spike: addon on 4.7** — install GodotSteam, confirm it loads on Godot 4.7 and whether
   `SteamMultiplayerPeer` ships in the GDExtension build or a separate variant.
   Verify: `Steam.steamInitEx()` succeeds with app ID 480 (Spacewar).
2. **Steam init** — init + `Steam.run_callbacks()` each frame, `steam_appid.txt` for dev.
3. **`MultiplayerSteam` handler** (A2 only) — same shape as `MultiplayerWebRTC`:
   - `start_server`: `createLobby` → on `lobby_created`, `create_host(0)`, return peer;
     `get_addr()` returns lobby ID.
   - `connect_client(lobby_id)`: `joinLobby` → on `lobby_joined`, `create_client(getLobbyOwner(), 0)`.
   - cleanup: `leaveLobby`.
   - `ConnectionManager`: add `STEAM` to `ConnectionMode`, `steam_handler` export, `match` arm,
     config warning.
   Verify: two machines, two Steam accounts, a full MP session. **Watch netfox rollback/jitter**
   and confirm peer IDs are normal ints with host = 1 (`lobby_manager`/spawning key on peer ID).
4. **Invites** — "Invite friends" button → `activateGameOverlayInviteDialog(lobby_id)`. Handle
   `join_requested` from **any** menu state (route to lobby as client) and cold-launch
   `+connect_lobby <id>`. The menu routing is the tricky part.
5. **Menu wiring** — host defaults to Steam when Steam is running; toggle falls back to
   IP/WebRTC. Freeroam keeps local ENet.
6. **Non-Steam builds** — web has no extension; any static reference to `Steam` /
   `SteamMultiplayerPeer` is a parse error there. Gate on `Engine.has_singleton("Steam")` /
   `ClassDB.class_exists`, or split by export feature tag.

### Testing note

Needs two Steam accounts on two machines; can't loop locally like IP/port. Budget for it.

### Steamworks APIs worth knowing (beyond MultiplayerPeer)

- `ISteamNetworkingSockets` / SDR — the transport behind A2
- `ISteamMatchmaking` — lobbies, metadata, lobby search
- `ISteamFriends` — invites, rich presence (`connect` key → "Join Game"), persona names/avatars
- `ISteamUGC` — Workshop (Track B)
- Optional later: lobby browser, persona names in lobby list, voice

---

## Track B — User-made levels (Godot editor → `.pck` → Workshop)

### Model

Modder builds a level in a copy of the project under `res://mods/<id>/`, exports a `.pck`.
Game loads it with `ProjectSettings.load_resource_pack(path, false)` and instantiates the scene.
Mod scenes reference base-game scripts/assets by `res://` path, which resolve against the base pack.

### Why it fits (verified 2026-10-08)

- A level is just a `LevelDefinition` root + `player_spawn_pos` marker
  (`levels/level_definition.gd`). `grid_markers` and `traffic_settings` are optional.
- Gamemode tasks are authored in the level scene, so custom maps get races/events for free.

### Steps

1. **Spike** — hand-build one level in a project copy, export, load in game, spawn into it.
   Answers:
   - Exporting **only the mod's files**: patch-PCK export (verify it exists in 4.7) vs export filters.
   - `uid://` refs inside a loaded pack resolve (historically flaky).
   - `replace_files = false` prevents mods overwriting base files.
   - PCK must be exported from the same engine version as the game.
2. **Level registry refactor** — `LevelName` enum → string key (`builtin:<name>` / `mod:<id>`).
   Touches `level_manager.gd` (enum, `possible_levels`, `level_name_map`, `spawn_level`),
   `gamemode_manager.gd` spawn/RPC paths, `time_attack_component.gd` save keys, level select UI.
   Check save data for persisted enum ints.
3. **Mod loader** — scan `user://mods/` for packs + manifest (name, thumbnail, scene path),
   register into the level registry.
4. **MP sync** — host sends level key + pack hash; client without a matching pack is blocked with
   a clear message (later: auto-download via Workshop).
5. **Modder template + guide** — empty level scene with required nodes, export preset, short
   how-to. Optional: editor plugin "Export my level" button.
6. **Workshop** (needs real app ID) — upload tool via GodotSteam UGC
   (`createItem` → `setItemContent` → `submitItemUpdate`); subscribed items install into the same
   mods folder the loader already scans.

### Bikes (later, if wanted)

- Skins/colors: data-only version of `BikeSkinDefinition` — cheap, safe.
- Custom meshes: runtime glTF (`GLTFDocument`) attached to existing rig points.
- Custom handling: skip unless needed.

---

## Open questions

- How do modders get the project? Public repo → clone. Private → stripped SDK project (base
  scripts, player scene, task scripts, shared assets), with ongoing sync cost.
- Track A: A1 (lobbies over WebRTC) or A2 (`SteamMultiplayerPeer`)?
- Steamworks app ID ($100 fee) — needed before Workshop and shipping; 480 works for dev.
