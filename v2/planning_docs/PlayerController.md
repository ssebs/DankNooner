# Player Controller

> Physics, procedural animations, rollback/sync, input, gearbox, crash, tricks

## Scene Structure

- PlayerEntity (CharacterBody3D)
  - Netfox Syncs (RollbackSynchronizer, TickInterpolator)
  - VisualRoot
    - CharacterSkin
    - BikeSkin
  - NameLabel (Label3D)
  - CollisionShape3D
  - Controllers:
    - `<see below>`

**PlayerEntity** Runs other controllers' `on_movement_rollback_tick()` in a specific order:
1. GearingController
2. TrickController
3. MovementController
4. CrashController

## Netcode

> Hybrid: server-authoritative physics, client-local derived state

- **PlayerEntity** has
  - **RollbackSynchronizer** (vars to sync w/ lag comp)
    - Client-side prediction and Server reconciliation = Rollback
    - `input_controller.gd` "gathers" input for this process
      - `nfx_` vars are sync'd for use in `_rollback_tick()`
      - `rb_` vars are sync'd on PlayerEntity for discrete actions
  - **TickInterpolator** (smooth'd vars from above)
- Client => Server (input via RollbackSynchronizer):
  - `nfx_` input vars
    - `nfx_throttle`, `nfx_front_brake`, `nfx_rear_brake`, `nfx_steer`, `nfx_lean`
  - `rb_` oneshots (on PlayerEntity)
    - `rb_do_respawn` — triggered by CrashController auto-respawn or GamemodeManager
    - Signals:
      - `respawned(peer_id)`
      - `crashed(peer_id)`
      - `trick_started(peer_id, trick_type)`
      - `trick_ended(peer_id, trick_type)`
- Server => Clients (authoritative physics via RollbackSynchronizer):
  - `global_transform` (position & rotation)
  - `velocity`
  - TickInterpolator smooths: `global_transform`, `velocity`
- Client-local (derived from synced physics state, no sync needed):
  - Local InputController
    - `trick_held`
    - `clutch_held`
    - `cam_x`, `cam_y`
    - `gear_change_pressed` signal (direction: int)
    - `cam_switch_pressed` signal
  - GearingController — clutch, gear shifts, RPM blend => `get_power_output()`, `get_gear_max_speed()`
  - TrickController — detects current trick from `movement_controller.pitch_angle`
  - CrashController — brake grab, crash detection, emits `crashed`
  - AnimationController — procedural animation (lean, pitch, butt shift), RiderState machine
  - CameraController — FPS/TPS switching
  - Audio — engine sound RPM parameter via `rpm_updated` signal

## State owned by each component

- **PlayerEntity** (synced or DELETE_ME)
  - `is_boosting`, `boost_count` (DELETE_ME)
  - `is_crashed` (DELETE_ME)
  - `grip_usage` (DELETE_ME — display only)
- **MovementController** (local, derived from physics)
  - `speed` — scalar speed from velocity
  - `roll_angle` — lean left/right
  - `pitch_angle` — wheelie (+) / stoppie (-)
  - `yaw_angle` — twist left/right (unused currently)
- **GearingController** (local)
  - `_current_gear`, `_current_rpm`, `_clutch_value`, `_rpm_ratio`
- **TrickController** (local)
  - `current_trick` (Trick enum: NONE, WHEELIE_SITTING, WHEELIE_MOD, STOPPIE)
- **AnimationController** (local)
  - `current_state` (RiderState enum: RIDING, IDLE, TRICK, RAGDOLL)

## Controllers

On `do_respawn`, PlayerEntity calls all controllers' `do_reset()`

- **InputController** (`input_controller.gd`)
  - Local to client, extends Node3D
  - Gathers `nfx_` vars on `NetworkTime.before_tick_loop` for RollbackSynchronizer
  - Processes local input in `_process()`: gear shifts, trick held, clutch held, camera
  - Detects gamepad vs KBM via `_unhandled_input()`
  - Provides `add_vibration()` / `stop_vibration()` for controller rumble
- **CameraController**
  - Local to client
  - Directly set current_camera on client
- **AnimationController** (`animation_controller.gd`)
  - Local to client, runs in `_process()` (not rollback)
  - RiderState machine: RIDING → IDLE → TRICK → RAGDOLL
  - Procedural animation in RIDING state:
    - `visual_root.rotation.x` ← pitch (wheelie/stoppie) from `movement_controller.pitch_angle`
    - `visual_root.rotation.z` ← lean from `movement_controller.roll_angle`
    - `ik_chest.rotation.y` ← visual chest lean
    - `butt_pos.position.x` ← butt shift into turns
  - Editor tools: Init IK from Bike, Save/Play Default Pose
- **MovementController** (`movement_controller.gd`)
  - Runs in `_rollback_tick()` via `on_movement_rollback_tick()`
  - `_speed_calc()` — derives speed from velocity, applies acceleration from `gearing_controller.get_power_output()`, engine braking, braking
  - `_steer_calc()` — curve-based lean factor, turn radius from speed, applies `rotate_y()` and lean angle
  - `_velocity_calc()` — sets `player_entity.velocity` along forward dir, slope following, gravity
  - `_pitch_angle_calc()` — wheelie physics:
    - Clutch dump detection (`_update_clutch_dump_detection()`)
    - Power wheelie initiation (lean back + throttle + RPM threshold)
    - Balance point zone with instability
    - Lean forward recovery
  - `_handle_player_collision()` — spawn protection to avoid spawning inside other players
  - Calls `player_entity.move_and_slide()` with `NetworkTime.physics_factor`
- **GearingController** (`gearing_controller.gd`)
  - Listens to `input_controller.gear_change_pressed` for gear shifts
  - `on_movement_rollback_tick()`:
    - Update `_clutch_value` from `clutch_held` input
    - Blend `_current_rpm` between free-rev and wheel-loaded RPM based on clutch engagement
  - Public API:
    - `get_power_output()` — throttle × power curve × torque multiplier × engagement
    - `get_gear_max_speed()` — max speed for current gear
  - Emits `gear_changed(new_gear)`, `rpm_updated(rpm_ratio)`
- **TrickController** (`trick_controller.gd`)
  - Reads `movement_controller.pitch_angle` to detect current trick
  - Trick enum: NONE, WHEELIE_SITTING, WHEELIE_MOD, STOPPIE
  - Wheelie sitting: pitch > 15°
  - Wheelie mod: pitch > 15° + trick_held
  - Stoppie: pitch < -10°
  - Emits `trick_started(trick_type)`, `trick_ended(trick_type)`
- **CrashController** (`crash_controller.gd`)
  - Runs after MovementController in rollback tick
  - `_update_brake_grab()` — tracks front brake grab timing, sets `player_entity.grip_usage`
  - `_detect_crash()` — checks for:
    - Wheelie crash: `pitch_angle > max_wheelie_angle_deg`
    - Stoppie crash: `pitch_angle < -max_stoppie_angle_deg`
    - Lean crash: `roll_angle >= crash_lean_threshold_deg`
    - Brake grab while turning (sim difficulty + gamepad only)
  - `trigger_crash()` — sets `is_crashed`, zeros velocity, starts ragdoll
  - Auto-respawn after 3s via timer (TODO: move to GamemodeManager)
  - Emits `crashed`
