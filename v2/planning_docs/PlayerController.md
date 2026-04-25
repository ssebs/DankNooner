# Player Controller

> Physics, procedural animations, rollback/sync, input, gearbox, crash, tricks

## Scene Structure

- PlayerEntity (CharacterBody3D)
  - Netfox Syncs (RollbackSynchronizer, TickInterpolator)
  - VisualRoot (Node3D) — rotates for lean (Z) and pitch (X), bike + rider together
    - CharacterSkin (with IKController + skeleton AnimationPlayer)
    - BikeSkin (visual mesh + steering proxy + wheels)
  - IKTargets/ — all IK markers (butt, chest, head, L/R hand/foot, L/R arm/leg magnets)
  - WheelMarkers/ — editor-authored wheel pivot markers
  - IKAnimationPlayer — IK marker animations (idle, polish)
  - NameLabel (Label3D)
  - CollisionShape3D
  - Front/RearRayCast
  - _Controllers/ — see below

`PlayerEntity._rollback_tick()` runs controllers in this order:
1. MovementController
2. GearingController
3. TrickController
4. CrashController

(InputController gathers input on `NetworkTime.before_tick_loop`, before the rollback tick.)

`bike_definition` and `character_definition` are `@export`'d on `PlayerEntity` and drive everything per-bike (mesh, collision, raycasts, rider pose, wheel markers, gearing, physics, trick limits — see [Skins.md](./Skins.md)).

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
  - AnimationController — procedural animation + RiderState machine + IK target sync
  - CameraController — FPS/TPS switching
  - HUDController — polls controllers in `_process()`, listens to discrete signals
  - Audio — engine sound RPM parameter via `rpm_updated` signal

## State owned by each component

- **PlayerEntity** (synced or DELETE_ME)
  - `is_boosting`, `boost_count` (DELETE_ME)
  - `is_crashed` (DELETE_ME)
  - `grip_usage` (DELETE_ME — display only)
  - Owns IK marker nodes (`IKTargets/*`) and wheel markers (`WheelMarkers/*`)
- **MovementController** (local, derived from physics)
  - `speed` — scalar speed from velocity
  - `roll_angle` — lean left/right
  - `pitch_angle` — wheelie (+) / stoppie (-), in **radians**
  - `yaw_angle` — twist left/right (unused currently)
- **GearingController** (local)
  - `_current_gear`, `_current_rpm`, `_clutch_value`, `_rpm_ratio`
- **TrickController** (local)
  - `current_trick` (Trick enum: NONE, WHEELIE_SITTING, WHEELIE_MOD, STOPPIE)
- **AnimationController** (local)
  - `current_state` (RiderState enum: RIDING, IDLE, TRICK, RAGDOLL)
  - `_targets_synced_from_bike` flag

## Controllers

On `do_respawn`, PlayerEntity iterates `_Controllers` children and calls `do_reset()` on any that have it.

- **InputController** (`input_controller.gd`)
  - Local to client, extends Node3D
  - Gathers `nfx_` vars on `NetworkTime.before_tick_loop` for RollbackSynchronizer
  - Processes local input in `_process()`: gear shifts, trick held, clutch held, camera
  - Detects gamepad vs KBM via `_unhandled_input()`
  - Provides `add_vibration()` / `stop_vibration()` for controller rumble
- **CameraController**
  - Local to client
  - Directly set current_camera on client
- **AnimationController** (`animation_controller.gd`) — see [AnimationController.md](./AnimationController.md)
  - Local to client, runs in `_process()` (not rollback)
  - RiderState machine: RIDING → IDLE → TRICK → RAGDOLL
  - In RIDING:
    - `visual_root.rotation.x` ← pitch (wheelie/stoppie), with pivot offset along the tire arc
    - `visual_root.rotation.z` ← lean from `movement_controller.roll_angle`
    - Procedural butt shift (lateral) and chest/butt fwd-back weight shift from `nfx_lean`
    - `_sync_targets_from_bike()` rebuilds hand/foot global transforms each tick from `BikeSkinDefinition` values, anchored to the steering handlebar parent (hands) and `bike_skin` (feet) — so steering flows through for free
  - IDLE: target sync OFF, plays IK "idle" animation
  - TRICK: IK off, skeleton AnimationPlayer drives pose
  - Editor tools: Init IK from Bike, Save Default Pose, Play Default Pose
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
- **HUDController** (`hud_controller.gd`)
  - Local to client, extends Control, child of `_Controllers`
  - `@export` refs to: `player_entity`, `movement_controller`, `input_controller`, `gearing_controller`, `trick_controller`, `crash_controller`
  - Continuous values polled in `_process()`: speed, throttle, brake, clutch, grip
  - Discrete events via signals: `gear_changed`, `trick_started`, `trick_ended`, `crashed`, `respawned`
  - All display strings use `tr()` localization keys (HUD_THROTTLE, HUD_SPEED, etc.)
  - `show_hud()` / `hide_hud()` called from `PlayerEntity._deferred_init()` based on `is_local_client`
