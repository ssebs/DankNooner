# Netfox Integration Plan

Server-authoritative physics with client-side prediction using netfox.

## Phase 1: Addon Setup

- [ ] Enable netfox plugin in Project Settings
- [ ] Verify NetworkTime and NetworkRollback autoloads are active

## Phase 2: Player Scene Restructure

- [ ] `player_entity.gd` `_enter_tree()`: set `set_multiplayer_authority(1)` (server owns player body)
- [ ] Keep `is_local_client` check (still needed for camera/input capture)
- [ ] Remove or disable `MultiplayerSynchronizer` (RollbackSynchronizer replaces it)
- [ ] Configure `RollbackSynchronizer` state properties (CharacterBody3D-compatible):
  - `.:global_transform`
  - `.:velocity`
  - `MovementController:current_speed`
  - `MovementController:angular_velocity`
- [ ] Set input authority: player owns their `InputController`
  ```gdscript
  input_controller.set_multiplayer_authority(peer_id)
  ```
- [ ] Configure input properties on RollbackSynchronizer:
  - `InputController:throttle`
  - `InputController:front_brake`
  - `InputController:steer`
  - `InputController:lean`

## Phase 3: Input Controller Changes

- [ ] Change authority check from `is_local_client` to `is_multiplayer_authority()`:
  ```gdscript
  func _process(delta: float) -> void:
      if not is_multiplayer_authority():
          return
      _update_input()
  ```
- [ ] Remove `@export var player_entity` dependency for authority check
- [ ] Ensure input properties are plain vars (netfox syncs them automatically)
- [ ] Keep signals for local effects (camera switch, etc.) - these don't need sync

## Phase 4: Movement Controller Changes

- [ ] Remove `is_local_client` guard - `_rollback_tick()` runs on ALL peers
- [ ] Replace `_physics_process()` with `_rollback_tick()`:

  ```gdscript
  func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
      # Read input from InputController (synced by RollbackSynchronizer)
      var throttle_val = input_controller.throttle
      var steer_val = input_controller.steer
      var brake_val = input_controller.front_brake

      # Existing physics logic (acceleration, steering, etc.)
      # ...

      # Apply velocity and move
      player_entity.velocity = calculated_velocity
      player_entity.move_and_slide()
  ```

- [ ] Use `is_fresh` to gate sounds/particles (prevent replay during rollback):
  ```gdscript
  if is_fresh:
      # Play engine sound, spawn particles, etc.
  ```
- [ ] Handle collisions in rollback-safe way

## Phase 5: Spawn & Authority Setup

- [ ] In `multiplayer_manager.gd` `_spawn_player()`, after adding to scene:

  ```gdscript
  # Server owns the player body
  player.set_multiplayer_authority(1)

  # Player owns their input
  player.input_controller.set_multiplayer_authority(peer_id)

  # Initialize rollback synchronizer
  player.rollback_synchronizer.process_settings()
  player.rollback_synchronizer.process_authority()
  ```

- [ ] Add `@onready var rollback_synchronizer` reference to PlayerEntity

## Phase 6: Test

- [ ] Host + 1 client: verify both players move smoothly
- [ ] Check input responsiveness (should feel local despite server authority)
- [ ] Verify no jitter/rubber-banding under normal conditions
- [ ] Test with simulated latency if possible (netfox has debug tools)

## Notes

- `RollbackSynchronizer` replaces `MultiplayerSynchronizer` for player entities
- Input properties and state properties can be on different nodes (avoids ownership conflict)
- `_rollback_tick()` runs on ALL peers - server is authoritative, clients predict
- CharacterBody3D uses `velocity` + `move_and_slide()`, not RigidBody3D physics
- `current_speed` and `angular_velocity` in MovementController are manual floats, must be synced
- `is_local_client` still needed for camera setup, but NOT for input authority checks
