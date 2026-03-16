# Player Controller

> Physics, proceedural animations, rollback/sync, input, gearbox, crash, tricks

## Scene Structure

- PlayerEntity (kinematicbody)
  - Netfox Syncros
  - VisualRoot
    - CharacterSkin
    - BikeSkin
  - Markers
  - Controllers:
    - `<see below>`

**PlayerEntity** Runs other controllers' `on_movement_rollback_tick()` in a specific order

## Netcode

> Hybrid: server-authoritative physics, client-local derived state

- **PlayerEntity** has
  - **RollbackSynchronizer** (vars to sync w/ lag comp)
    - Client-side prediction and Server reconciliation = Rollback
    - `input_controller.gd` "gathers" input for this process
      - `nfx_` vars are sync'd for use in `_rollback_tick()`
      - `rb_` vars are sync'd in the same file to emit signals
  - **TickInterpolator** (smooth'd vars from above)
- Client => Server (input via RollbackSynchronizer):
  - `nfx_` input vars
    - `nfx_throttle`, `nfx_brake`, `nfx_steer`, `nfx_lean`
    - `nfx_gear_ratio` (final ratio, computed client-side by GearingController)
  - `rb_` oneshots
    - `rb_current_trick` — broadcast for remote display/scoring
    - `rb_crashed` — notify GamemodeManager of crash
    - `rb_do_respawn` — triggered by GamemodeManager (owns respawn logic)
- Server => Clients (authoritative physics via RollbackSynchronizer):
  - `global_transform` (position & rotation)
  - `velocity`
  - `speed`
  - TickInterpolator smooths: `global_transform`, `velocity`
- Client-local (derived from synced physics state, no sync needed):
  - GearingController — clutch, gear shifts, RPM blend => produces `nfx_gear_ratio`
  - TrickController — wheelie/stoppie detection, `pitch_angle`
  - CrashController — brake grab, crash detection, emits `crashed(reason)`
  - AnimationController — procedural animation, lean/pitch/fishtail visual angles
  - CameraController — FPS/TPS switching
  - Audio — engine sound RPM parameter
  - Visual angles: `lean_angle`, `pitch_angle`, `fishtail_angle` (derived from velocity/speed/ground)

## Controllers:

- **InputController**
  - Local to client
  - Send values to server via `RollbackSynchronizer`
- **CameraController**
  - Local to client
  - Directly set current_camera on client
- **AnimationController**
  - Local to client
- **MovementController**
  - Server sync'd via `RollbackSynchronizer`
  - Applies `rb_` pattern vars in `_rollback_tick()`
  - Run `_physics_calculations()`
    - Set `player_entity.speed` (speed # for re-calculating & other classes)
    - Set `player_entity.velocity` (actual movement # for move_and_slide)
    - Set `player_entity.rotation`
    - Set `player_entity.lean_angle`
  - Apply movement from calculations
  - Handle `on_crashed()`
- **GearingController**
  - Checks input_controller's values
    - Set local clutch_hold_time
    - Handle gear shift
  - `on_movement_rollback_tick()`
    - Update clutch value from held/delay
      - Set `player_entity.clutch_value`
    - Blend RPM from clutch values & current gear
      - Set `player_entity.current_rpm`
- **TrickController**
  - Checks input_controller's values from `on_movement_rollback_tick()`
    - Detect current trick & emit signal if changed
    - wheelie
      - Set `player_entity.pitch_angle`
    - stoppie
      - Set `player_entity.pitch_angle`
- **CrashController**
  - Checks input_controller's values from `on_movement_rollback_tick()`
  - Update brake grab values
    - Set `player_entity.grip_usage`
  - Detect crash & `trigger_crash()` if one is happening
    - Emit `crashed(reason)`
