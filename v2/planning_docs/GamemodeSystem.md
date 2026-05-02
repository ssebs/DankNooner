# Gamemode System

How `FreeRoamGameMode`, `TutorialGameMode`, `StreetRaceGameMode` (and future event-driven modes) hang together. For *authoring* a tutorial / event content, see [GamemodeEventAndGameModeLessonAndTutorial](./GamemodeEventAndGameModeLessonAndTutorial.md).

## Pieces

| Piece | File | Role |
|---|---|---|
| `GamemodeManager` | `managers/gamemodes/gamemode_manager.gd` | Match state, `TGameMode` enum, hosts the gamemode state machine, late-joiner sync |
| `GameMode` (base) | `managers/gamemodes/gamemode.gd` | `State` subclass; server-authoritative |
| `FreeRoamGameMode` | `.../free_roam/` | Default mode. Wires event circles → confirm HUD → transition |
| `TutorialGameMode` | `.../tutorial/` | Walks `EventStartCircle.get_lessons()` per peer; per-lesson `Objective.check()` |
| `StreetRaceGameMode` | `.../street_race/` | Stub — will use the same lesson/objective shape for laps/checkpoints |
| `GameModeEventConfirmHUD` | `managers/gamemodes/hud/` | Per-peer RPC'd confirm dialog |
| `GamemodeStateContext` | `utils/state_machine/` | Carries `peer_id`, `gamemode_event`, `event_start_circle` through transitions |

`TGameMode`: `FREE_FROAM, STREET_RACE, STUNT_RACE, TUTORIAL`. `_gamemode_map` in `GamemodeManager` wires the enum to the `GameMode` node instances exported on the manager.

## Lobby integration

The lobby is *the* shared roster. All event-mode logic reads from it; nothing else maintains a player list.

- `LobbyManager.lobby_players: Dictionary[int, PlayerDefinition]` — peer_id → player def. Server-owned, broadcast via `_sync_lobby_players`.
- `lobby_players_updated` signal — `SpawnManager` listens and adjusts spawn/despawn.
- Every event-driven gamemode iterates `lobby_manager.lobby_players` to build per-peer state, teleport players, gate input, and tally results. Tutorial does this in `_build_player_states()` / `_teleport_players_to_start()` / `_set_all_players_input_disabled()`.
- Players who join mid-event come through `player_latejoined` (see below) and are appended to the existing per-peer state on the fly.

When the gamemode is over, `_return_to_free_roam()` flips everyone back via `_rpc_transition_gamemode.rpc(FREE_FROAM, peer_id)`. The lobby roster is unchanged — only the active state on each peer's machine.

## Authority

- All event gamemodes are **server-authoritative**. `Update()` early-returns on clients.
- Transition: client calls `change_gamemode.rpc_id(1, enum, peer_id)` → server fires `_rpc_transition_gamemode.rpc(...)` (`call_local`, reliable) → every peer's state machine transitions in lockstep.
- `pending_gamemode_event` and `pending_event_start_circle` on `GamemodeManager` are set right before the transition (by free roam on HUD submit) and copied into the new `GamemodeStateContext`. They're one-shot; cleared on read.

## Manager signals (consumed by each GameMode)

`GamemodeManager` re-emits these for whichever gamemode is active. Connect in `Enter()`, disconnect in `Exit()`.

- `player_spawned(peer_id)`
- `player_crashed(peer_id)` — gamemodes decide respawn policy. FreeRoam: respawn in place after delay. Tutorial: respawn at `start_circle.start_marker` + clear current `lesson_state`.
- `player_latejoined(peer_id)` — usually forwarded to `gamemode_manager.latespawn_player(peer_id)`.
- `player_disconnected(peer_id)` — despawn if `IN_GAME`. Event modes also remove the peer from their per-player state dict.

## Late-joiner sync

`GamemodeManager._sync_game_to_late_joiner` (sent by server on client connect when `match_state == IN_GAME`) sets the joiner's level + active gamemode and transitions their state machine. The joiner then RPC's `_request_late_spawn`; the active gamemode handles spawn via `player_latejoined`.

For event modes that hold per-peer state (Tutorial), the joiner's `TutorialPlayerState` is created lazily — currently only via the initial `_build_player_states()`. Late-join into a tutorial mid-run is **not** fully supported (the joiner has no lesson state); they'll spectate until the round ends. Track this when adding new event modes.

## Adding a new event-driven gamemode

1. Add to `GamemodeManager.TGameMode` enum.
2. Create `class_name FooGameMode extends GameMode`. Implement `Enter` / `Update` / `Exit`. Guard server-only logic with `multiplayer.is_server()`.
3. In `Enter`, read `(state_context as GamemodeStateContext).event_start_circle` to get your course root + start marker + lessons.
4. Add the node under the state machine in `main_game.tscn`, `@export` it on `GamemodeManager`, and register it in `_gamemode_map` in `_ready()`.
5. Connect `player_crashed` / `player_disconnected` / `player_latejoined` per the policy you want.
6. To return to free roam: `gamemode_manager._rpc_transition_gamemode.rpc(FREE_FROAM, peer_id)` (see `TutorialGameMode._return_to_free_roam`).

If your new mode doesn't use the lesson/objective system (e.g. pure timer or score), skip the `event_start_circle.get_lessons()` part and use whatever per-peer structures you need. The lobby + transition + late-join scaffolding is the same.

## Out of scope

- **Drop-in sessions** (GTA-style): one peer starts a session, others keep riding outside it. Deferred until dedicated servers — peer-to-peer party-within-a-party is awkward.
- Multiple events per circle with in-circle selection (see TODO on `EventStartCircle.gamemode_event`).
