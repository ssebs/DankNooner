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
    - `nfx_throttle`, `nfx_front_brake`, `nfx_rear_brake`, `nfx_steer`, `nfx_lean`, `nfx_boost_held`
    - `nfx_target_gear` (absolute requested gear — see GearingController below)
  - `rb_` oneshots (on PlayerEntity)
    - `rb_do_respawn` — triggered by CrashController auto-respawn or GamemodeManager
    - Consuming the flag anchors the respawn to that tick (`_respawn_tick` +
      `_respawn_target`); resims of that tick re-apply the state part
      (`_apply_respawn_state`) — otherwise netfox's resimulation (server: late remote
      input; client: prediction) rebuilds from pre-respawn history and undoes the
      teleport, and clients never see race-grid teleports (the first application lands
      on a predicted tick, which is never broadcast)
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
  - `boost_amount` (segments, 0..3), `boost_burn_target`, `boost_burn_rate`, `boost_prev_held`,
    `combo_time`, `combo_grace`, `combo_multiplier`, `is_boosting` — all netfox state
    properties. Filled by `TrickController._accrue_combo()` and spent by
    `MovementController._boost_calc()`, both inside the rollback tick. Writing any of these
    from a manager's `_process()` does NOT work: `RollbackSynchronizer._before_tick()`
    re-applies every state property from history each tick, wiping the write.
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
  - `current_trick` (Trick enum: NONE, WHEELIE_SITTING, WHEELIE_MOD, STOPPIE, BACKFLIP, FRONTFLIP, THREESIXTY, HEEL_CLICKER, HIGH_CHAIR, TWO_LEFT_FEET, DRIFT)
- **AnimationController** (local)
  - `current_state` (RiderState enum: RIDING, IDLE, RAGDOLL — TRICK is stubbed/disabled)
  - `_targets_synced_from_bike` flag

## Controllers

On `do_respawn`, PlayerEntity iterates `_Controllers` children and calls `do_reset()` on any that have it.

- **InputController** (`input_controller.gd`)
  - Local to client, extends Node3D
  - Gathers `nfx_` vars on `NetworkTime.before_tick_loop` for RollbackSynchronizer
  - Processes local input in `_process()`: gear shifts, trick held, clutch held, camera
  - `_auto_shift()` — automatic transmission when the `auto_transmission` setting is on.
    Up at `AUTO_UPSHIFT_RPM_RATIO` (0.95), down at `AUTO_DOWNSHIFT_RPM_RATIO` (0.5),
    `AUTO_SHIFT_COOLDOWN` (0.4s) between shifts. Compares against `nfx_target_gear` rather
    than `GearingController.current_gear`, which only catches up on the next rollback tick.
  - Detects gamepad vs KBM via `_unhandled_input()`
  - Provides `add_vibration()` / `stop_vibration()` for controller rumble
- **CameraController**
  - Local to client
  - Directly set current_camera on client
- **AnimationController** (`animation_controller.gd`) — see [AnimationController.md](./AnimationController.md)
  - Local to client, runs in `_process()` (not rollback)
  - RiderState machine: RIDING ↔ IDLE, RAGDOLL (TRICK stubbed — see [AnimationController.md](./AnimationController.md))
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
  - `_boost_calc()` — boost meter spend. Runs **before** the `is_crashed` bail-out so a crash
    cancels an active burn. The meter is 3 discrete segments; a rising edge on `nfx_boost_held`
    commits a burn down to `boost_burn_target` that **releasing the button cannot cancel**.
    One segment = `BOOST_SEGMENT_SECS` (1s, so 3s total spent piecemeal); pressing on a full
    meter instead commits all three over `BOOST_FULL_BURN_SECS` (4s). While boosting,
    `_speed_calc()` scales engine drive by `BOOST_ACCEL_MULT` and lifts both the gear cap and
    the `bd.max_speed` ceiling by `BOOST_SPEED_MULT`. The rising edge uses the synced
    `boost_prev_held` so it survives resimulation.
  - `_handle_player_collision()` — spawn protection to avoid spawning inside other players
  - Calls `player_entity.move_and_slide()` with `NetworkTime.physics_factor`
  - **Unstable surfaces** (collision layer 5 — gravel/sand/etc):
    - Cached per tick as `_on_unstable_surface` via `_detect_unstable_surface()` (iterates slide collisions after `is_on_floor_netfox()`)
    - `get_unstable_factor()` returns `bike_definition.unstable_surface_factor` (0..1) when touching layer 5, else 0 — set to `0.0` on dirtbike `.tres` to fully ignore
    - Effects scaled by factor: proportional drag (`UNSTABLE_DRAG_RATE`, caps top speed without stalling launches), reduced wheelie target (`UNSTABLE_WHEELIE_SUPPRESSION`, harder to hold a wheelie / reach balance point), reduced turn rate (`UNSTABLE_STEER_SUPPRESSION`)
    - CrashController also reads `get_unstable_factor()` (see below)
- **GearingController** (`gearing_controller.gd`)
  - `on_movement_rollback_tick()`:
    - Apply `input_controller.nfx_target_gear` (absolute requested gear, synced as netfox
      input — NOT edge-triggered, so stale-input reuse / dropped snapshots on the server
      can't skip or double-apply shifts), emits `gear_changed`
    - Update `_clutch_value` from `clutch_held` input
    - Blend `_current_rpm` between free-rev and wheel-loaded RPM based on clutch engagement
  - Public API:
    - `get_power_output()` — throttle × power curve × torque multiplier × engagement
    - `get_gear_max_speed()` — max speed for current gear
  - Emits `gear_changed(new_gear)`, `rpm_updated(rpm_ratio)`
- **TrickController** (`trick_controller.gd`)
  - Detects ground tricks (wheelie variants, stoppie) from `movement_controller.pitch_angle` and air tricks (flips, heel clicker, high chair) from input + airtime
  - Some tricks (e.g. high chair) latch — entry on a gesture, persist while the gating input + condition hold
  - Emits `trick_started(trick_type)` / `trick_ended(trick_type)` on transitions
  - `_accrue_combo()` — accrues `combo_time` / `combo_grace` / `combo_multiplier` and fills
    `boost_amount` while any trick is held. `TrickManager` banks the score off these when the
    combo ends — see [ComboAndBoost.md](./ComboAndBoost.md) for the full system + tunables
- **CrashController** (`crash_controller.gd`)
  - Runs in rollback tick after the other controllers
  - Detects crashes from over-rotation (wheelie/stoppie past trick limits, side lean), brake grabs while turning, killbox/obstacle collisions, upside-down landings, and landing while still mid air-trick
  - **Unstable surfaces**: lean-crash threshold tightens (scaled by `movement_controller.get_unstable_factor()` via `unstable_lean_threshold_reduction_deg`); front brake while steering on unstable triggers a lowside (`unstable_lowside_brake_threshold`, `unstable_lowside_steer_threshold_deg`)
  - `trigger_crash()` — sets `is_crashed`, zeros velocity, starts ragdoll
  - Auto-respawn after 3s via timer (TODO: move to GamemodeManager)
  - Emits `crashed`
- **HUDController** (`hud_controller.gd`)
  - Local to client, extends Control, child of `_Controllers`
  - `@export` refs to: `player_entity`, `movement_controller`, `input_controller`, `gearing_controller`, `trick_controller`, `crash_controller`
  - Continuous values polled in `_process()`: speed, throttle, brake, clutch, grip, plus the
    synced `boost_amount` / `combo_multiplier` fed to `BoostGauge` + `ComboCounter`
    (`player/hud_elements/`)
  - Discrete events via signals: `gear_changed`, `trick_started`, `trick_ended`, `crashed`, `respawned`
  - All display strings use `tr()` localization keys (HUD_THROTTLE, HUD_SPEED, etc.)
  - `show_hud()` / `hide_hud()` called from `PlayerEntity._deferred_init()` based on `is_local_client`
