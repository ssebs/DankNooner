# Manual RPC Spawning Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace MultiplayerSpawner with server-authoritative RPC spawns controlled by GamemodeManager.

**Architecture:** GamemodeManager owns spawn/despawn timing and broadcasts RPCs. LevelManager handles local node instantiation. All peers (including server) execute the same spawn/despawn code via `call_local` RPCs.

**Tech Stack:** Godot 4.6, GDScript, netfox for rollback sync

---

## Task 1: Update LevelManager - Rename spawn_player to add_player_locally

**Files:**
- Modify: `managers/level_manager.gd:80-91`

**Step 1: Rename spawn_player and remove authority check**

Replace lines 80-91:

```gdscript
## Instantiate and add player node locally (no authority check)
## Called by GamemodeManager RPC on all peers
func add_player_locally(peer_id: int, username: String):
	print("Adding player locally: %s - %s" % [peer_id, username])

	var player_to_add = current_level.player_entity_scene.instantiate() as PlayerEntity
	player_to_add.name = str(peer_id)

	current_level.player_spawn_pos.add_child(player_to_add, true)
	player_to_add.set_username_label(username)
```

**Step 2: Verify no syntax errors**

Open the file in Godot editor, check for red squiggles.

**Step 3: Commit**

```bash
git add managers/level_manager.gd
git commit -m "refactor: rename spawn_player to add_player_locally, remove server check"
```

---

## Task 2: Update LevelManager - Rename despawn_player to remove_player_locally

**Files:**
- Modify: `managers/level_manager.gd:94-98`

**Step 1: Rename despawn_player**

Replace lines 94-98:

```gdscript
## Remove player node locally (no authority check)
## Called by GamemodeManager RPC on all peers
func remove_player_locally(peer_id: int):
	if !current_level.player_spawn_pos.has_node(str(peer_id)):
		return

	current_level.player_spawn_pos.get_node(str(peer_id)).queue_free()
```

**Step 2: Commit**

```bash
git add managers/level_manager.gd
git commit -m "refactor: rename despawn_player to remove_player_locally"
```

---

## Task 3: Add spawn/despawn RPCs to GamemodeManager

**Files:**
- Modify: `managers/gamemodes/gamemode_manager.gd`

**Step 1: Add _rpc_spawn_player RPC after line 82**

Add after `_request_late_spawn` function:

```gdscript
## Server broadcasts to all peers to spawn a player
@rpc("call_local", "reliable")
func _rpc_spawn_player(peer_id: int, username: String):
	level_manager.add_player_locally(peer_id, username)


## Server broadcasts to all peers to despawn a player
@rpc("call_local", "reliable")
func _rpc_despawn_player(peer_id: int):
	level_manager.remove_player_locally(peer_id)
```

**Step 2: Commit**

```bash
git add managers/gamemodes/gamemode_manager.gd
git commit -m "feat: add _rpc_spawn_player and _rpc_despawn_player RPCs"
```

---

## Task 4: Update _spawn_all_players to use RPC

**Files:**
- Modify: `managers/gamemodes/gamemode_manager.gd:43-45`

**Step 1: Replace _spawn_all_players**

Replace lines 43-45:

```gdscript
func _spawn_all_players():
	if !multiplayer.is_server():
		return

	for peer_id in multiplayer_manager.lobby_players:
		var username = multiplayer_manager.lobby_players[peer_id]
		_rpc_spawn_player.rpc(peer_id, username)
```

**Step 2: Commit**

```bash
git add managers/gamemodes/gamemode_manager.gd
git commit -m "refactor: _spawn_all_players now uses RPC broadcast"
```

---

## Task 5: Update _request_late_spawn for full sync

**Files:**
- Modify: `managers/gamemodes/gamemode_manager.gd:77-82`

**Step 1: Replace _request_late_spawn to sync existing players**

Replace the function:

```gdscript
## Late-joining client requests the server to spawn their player
@rpc("any_peer", "call_local", "reliable")
func _request_late_spawn(peer_id: int):
	if !multiplayer.is_server():
		return

	# Spawn the new player for everyone
	var username = multiplayer_manager.lobby_players[peer_id]
	_rpc_spawn_player.rpc(peer_id, username)

	# Send existing players to the late-joiner
	for existing_id in multiplayer_manager.lobby_players:
		if existing_id == peer_id:
			continue
		var existing_username = multiplayer_manager.lobby_players[existing_id]
		_rpc_spawn_player.rpc_id(peer_id, existing_id, existing_username)
```

**Step 2: Commit**

```bash
git add managers/gamemodes/gamemode_manager.gd
git commit -m "feat: _request_late_spawn now syncs existing players to late-joiner"
```

---

## Task 6: Connect player_disconnected for despawn

**Files:**
- Modify: `managers/gamemodes/gamemode_manager.gd:21-25`

**Step 1: Add signal connection in _ready**

Update the _ready function:

```gdscript
func _ready():
	if Engine.is_editor_hint():
		return
	multiplayer_manager.client_connection_succeeded.connect(_on_client_connection_succeeded)
	multiplayer_manager.player_connected.connect(_on_player_connected)
	multiplayer_manager.player_disconnected.connect(_on_player_disconnected)
```

**Step 2: Add handler after _on_client_connection_succeeded**

Add new function:

```gdscript
func _on_player_disconnected(peer_id: int):
	if !multiplayer.is_server():
		return

	if match_state == MatchState.IN_GAME:
		_rpc_despawn_player.rpc(peer_id)
```

**Step 3: Commit**

```bash
git add managers/gamemodes/gamemode_manager.gd
git commit -m "feat: GamemodeManager handles player_disconnected for despawn"
```

---

## Task 7: Remove despawn_player call from MultiplayerManager

**Files:**
- Modify: `managers/network/multiplayer_manager.gd:164-174`

**Step 1: Remove despawn_player call from _on_peer_disconnected**

Replace lines 164-174:

```gdscript
func _on_peer_disconnected(id: int):
	print("Player %s disconnected" % id)
	player_disconnected.emit(id)

	lobby_players.erase(id)
	sync_lobby_players.rpc(lobby_players)
```

**Step 2: Commit**

```bash
git add managers/network/multiplayer_manager.gd
git commit -m "refactor: remove despawn_player call, GamemodeManager owns despawn now"
```

---

## Task 8: Remove player_scene export from MultiplayerManager

**Files:**
- Modify: `managers/network/multiplayer_manager.gd:17`

**Step 1: Delete line 17**

Remove this line:
```gdscript
@export var player_scene = preload("res://entities/player/player_entity.tscn")
```

**Step 2: Commit**

```bash
git add managers/network/multiplayer_manager.gd
git commit -m "refactor: remove unused player_scene export"
```

---

## Task 9: Remove MultiplayerSpawner from test_01_level.gd

**Files:**
- Modify: `levels/test_levels/test_01/test_01_level.gd`

**Step 1: Replace entire file contents**

```gdscript
@tool
extends LevelDefinition


func _ready():
	if Engine.is_editor_hint():
		return
	# Server disconnect is handled by multiplayer.server_disconnected signal
	# which is already connected in MultiplayerManager.connect_client()
```

**Step 2: Commit**

```bash
git add levels/test_levels/test_01/test_01_level.gd
git commit -m "refactor: remove MultiplayerSpawner references from test_01_level"
```

---

## Task 10: Remove MultiplayerSpawner node from test_01_level.tscn

**Files:**
- Modify: `levels/test_levels/test_01/test_01_level.tscn`

**Step 1: Delete MultiplayerSpawner node in Godot editor**

1. Open `test_01_level.tscn` in Godot
2. Select the `MultiplayerSpawner` node
3. Delete it (Del key or right-click > Delete)
4. Save the scene

**Step 2: Remove ext_resource for player_entity (no longer needed by spawner)**

The `ext_resource` for player_entity.tscn (id="2_6hu6n") is still needed because `LevelDefinition` has `player_entity_scene` export. Keep it.

**Step 3: Commit**

```bash
git add levels/test_levels/test_01/test_01_level.tscn
git commit -m "refactor: remove MultiplayerSpawner node from test_01_level"
```

---

## Task 11: Manual Testing

**Test 1: Single player game start**
1. Start game as host
2. Select level, click Start
3. Verify player spawns and is controllable

**Test 2: Two player game start**
1. Host starts server
2. Client joins
3. Host clicks Start
4. Verify both players spawn on both screens

**Test 3: Late join**
1. Host starts server, clicks Start (in-game)
2. Client joins after game started
3. Verify:
   - Late-joiner sees host's player
   - Host sees late-joiner's player
   - Late-joiner can control their player

**Test 4: Player disconnect**
1. Two players in-game
2. Client disconnects
3. Verify client's player is removed from host's screen

**Test 5: Server disconnect**
1. Two players in-game
2. Host closes game
3. Verify client returns to menu with "Server disconnected" toast

---

## Summary of Changes

| File | Changes |
|------|---------|
| `managers/level_manager.gd` | Rename `spawn_player` → `add_player_locally`, `despawn_player` → `remove_player_locally`, remove server authority checks |
| `managers/gamemodes/gamemode_manager.gd` | Add `_rpc_spawn_player`, `_rpc_despawn_player` RPCs, update `_spawn_all_players` and `_request_late_spawn`, handle `player_disconnected` |
| `managers/network/multiplayer_manager.gd` | Remove `player_scene` export, remove `despawn_player` call |
| `levels/test_levels/test_01/test_01_level.gd` | Remove spawner references |
| `levels/test_levels/test_01/test_01_level.tscn` | Remove MultiplayerSpawner node |