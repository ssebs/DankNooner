# Scratch Pad

---

## Multiplayer Metadata Refactor

### Problem

Player metadata is fragmented:

- Username sent via `update_username` RPC (MultiplayerManager)
- Skins sent via `update_player_skins` RPC (GamemodeManager → `_player_skins` dict)
- Two separate RPCs on connect, multiple broadcasts

### Solution

- `PlayerDefinition` resource holds all player identity data (username, skins, money, xp)
- `SaveManager` persists local player's `PlayerDefinition` to `user://savegame.json`
- Single `update_player_metadata` RPC replaces both username and skin RPCs
- `lobby_players` changes from `Dict[int, String]` to `Dict[int, PlayerDefinition]`

### Todos

- [x] **Create SaveManager**
- [x] **Add serialization to PlayerDefinition**
- [ ] **Update customization ui to load/save playerdefinition**
- [ ] **Consolidate RPCs in MultiplayerManager**

  - Change `lobby_players` type: `Dict[int, String]` → `Dict[int, PlayerDefinition]`
  - Add `update_player_metadata(data: Dictionary)` RPC
  - Remove `update_username()` RPC

- [ ] **Remove skin handling from GamemodeManager**

  - Delete `_player_skins` dict
  - Delete `update_player_skins()` RPC
  - Pull skins from `lobby_players[id].bike_skin` when spawning

- [ ] **Update LobbyMenuState**

  - On connect: single `update_player_metadata.rpc_id(1, save_manager.get_local_player_definition().to_network_dict())`

- [ ] **Update PlayerListUI**

  - Change `update_from_dict()` to use `PlayerDefinition` instead of raw dict

- [ ] **Update Documentation**
