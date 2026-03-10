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
  - Runs other controllers' `on_movement_rollback_tick()` in a specific order
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
  - **CrashController**
    - Checks input_controller's values from `on_movement_rollback_tick()`
