# Multiplayer Authority Refactor Plan

Server-authoritative physics with client input. Prep for netfox integration.

## Phase 1: Authority Change

- [ ] `player_entity.gd` `_enter_tree()`: change to `set_multiplayer_authority(1)`
- [ ] Keep `is_local_client` check (still needed for camera/input capture)

## Phase 2: Input RPC

- [ ] `input_controller.gd`: add input buffer dict at top of file
  ```gdscript
  static var server_input_buffer: Dictionary = {}  # peer_id -> input_state
  ```
- [ ] Add `receive_input()` RPC:
  ```gdscript
  @rpc("any_peer", "unreliable_ordered")
  func receive_input(input_state: Dictionary):
      var sender_id = multiplayer.get_remote_sender_id()
      server_input_buffer[sender_id] = input_state
  ```
- [ ] In `_process()`: after `_update_input()`, send to server:
  ```gdscript
  if multiplayer.is_server():
      server_input_buffer[multiplayer.get_unique_id()] = _get_input_state()
  else:
      receive_input.rpc_id(1, _get_input_state())
  ```
- [ ] Add helper:
  ```gdscript
  func _get_input_state() -> Dictionary:
      return {"throttle": throttle, "front_brake": front_brake, "steer": steer, "lean": lean}
  ```

## Phase 3: Server-Side Movement

- [ ] `movement_controller.gd` `_physics_process()`: change guard to:
  ```gdscript
  if not multiplayer.is_server():
      return
  ```
- [ ] Get input from buffer instead of `input_controller` directly:
  ```gdscript
  var peer_id = int(player_entity.name)
  var input = InputController.server_input_buffer.get(peer_id, {})
  var throttle_val = input.get("throttle", 0.0)
  # etc...
  ```

## Phase 4: Position Sync

- [ ] Add `MultiplayerSynchronizer` as child of `PlayerEntity` in scene
- [ ] Configure sync properties: `position`, `rotation`, `velocity`
- [ ] Set replication interval (~20-30ms for smooth updates)

## Phase 5: Test

- [ ] Host + 1 client: verify host sees client move
- [ ] Verify client sees host move
- [ ] Check input responsiveness

## Later: Netfox Integration

- [ ] Add tick number to input_state
- [ ] Replace `MultiplayerSynchronizer` with netfox `RollbackSynchronizer`
- [ ] Implement client-side prediction replay
