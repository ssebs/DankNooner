# Network Manager Refactor Plan

## Before

| File                 | Responsibilities                                                                                        |
| -------------------- | ------------------------------------------------------------------------------------------------------- |
| `MultiplayerManager` | ENet connection setup, connection mode routing, peer signals, lobby_players dict, PlayerDefinition sync |
| `GamemodeManager`    | Match state, game mode enum, late-joiner sync, spawn/despawn RPCs, level start coordination             |
| `SpawnManager`       | Local player instantiation/removal                                                                      |
| `LevelManager`       | Level loading/unloading                                                                                 |

## After

| Manager                                                | Responsibility                                         |
| ------------------------------------------------------ | ------------------------------------------------------ |
| **ConnectionManager** (rename from MultiplayerManager) | ENet lifecycle, peer signals, Noray/IP routing         |
| **LobbyManager** (new)                                 | lobby_players dict, PlayerDefinition sync              |
| **GamemodeManager**                                    | Match state, late-joiner sync, coordinates level/spawn |
| **SpawnManager**                                       | Spawn RPCs + local instantiation                       |
| **LevelManager**                                       | Level loading (unchanged)                              |

## What Moves Where

### MultiplayerManager → ConnectionManager (rename + remove lobby stuff)

- Rename file and class
- Remove lobby_players, sync RPCs, lobby_players_updated signal

### MultiplayerManager → LobbyManager (new file)

- `lobby_players` dict
- `update_player_metadata()` RPC
- `_sync_lobby_players()` RPC
- `lobby_players_updated` signal

### GamemodeManager → SpawnManager

- `_spawn_all_players()` → `spawn_all_players()`
- `_rpc_spawn_player()` RPC
- `_rpc_despawn_player()` RPC

### GamemodeManager (keeps)

- `MatchState`, `GameMode` enums
- `match_state`, `game_mode`, `current_level_name`
- `start_game()`, `end_game()`
- `_sync_game_to_late_joiner()`, `_request_late_spawn()`

---

## Claude Code Prompt

Implement the refactor described in PLAN.md. Follow CLAUDE.md patterns.

Steps:

1. Rename multiplayer_manager.gd → connection_manager.gd, update class_name
2. Create new lobby_manager.gd, move lobby_players dict and sync RPCs from ConnectionManager
3. Move spawn RPCs from GamemodeManager to SpawnManager
4. Update all @export references and signal connections across the codebase
5. Update ManagerManager scene to wire the new managers

Relevant files:

- managers/network/multiplayer_manager.gd
- managers/spawn_manager.gd
- managers/level_manager.gd
