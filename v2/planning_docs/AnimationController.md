# AnimationController

Central API for all rider animation — procedural dynamics, IK polish animations, and skeleton tricks.

## Architecture

```
PlayerEntity
├── VisualRoot (Node3D)              # Rotates for lean (Z) + pitch (X) — bike + rider together
│   ├── CharacterSkin
│   │   ├── IKController             # FABRIK solver
│   │   └── AnimationPlayer          # Skeleton (trick) animations
│   └── BikeSkin                     # Visual mesh + steering proxy + wheels
│
├── IKTargets/                       # All IK markers live here (PlayerEntity-owned)
│   ├── butt_target, chest_target, head_target
│   ├── left/right_hand_target, left/right_foot_target
│   └── left/right_arm_magnet, left/right_leg_magnet
│
├── WheelMarkers/                    # Editor-authored wheel pivot markers
│   └── front/rear_wheel_ground/front/back_marker
│
├── IKAnimationPlayer                # IK marker animations (polish)
│
└── _Controllers/
    ├── AnimationController
    ├── MovementController
    ├── InputController
    └── CameraController
```

### Marker Ownership

All IK markers are now **owned by `PlayerEntity`** and exported on it directly. There is no more bike-vs-character split at the node level. Per-bike *values* (positions/rotations) live on `BikeSkinDefinition` and are applied to the PlayerEntity-owned markers at init.

- **Hand/foot targets** are reconstructed every tick from `BikeSkinDefinition` values, anchored to the steering handlebar's parent (hands) and `bike_skin` (feet) — so steering and bike orientation flow through automatically. See `_sync_targets_from_bike()`.
- **Chest/head/magnets/butt** are positioned once at init from `BikeSkinDefinition`, then driven procedurally (or by `IKAnimationPlayer`).
- Wheel markers are editor-authored handles for pivot/raycast positions; their values live on `BikeSkinDefinition`.

### Steering

`BikeSkin` creates a `SteeringHandleBarProxy` under the steering `RotationPoint`. `_sync_targets_from_bike()` multiplies the handlebar parent's `global_transform` against the saved hand local transforms, so the hands follow steering for free.

### Per-Bike Rider Pose

Chest/head/magnet/hand/foot/butt/wheel-marker transforms are stored on `BikeSkinDefinition` and applied at init by `PlayerEntity._apply_rider_pose_from_definition()` (and by the editor "Init IK from Bike" button). Use the editor tools on `AnimationController` to author and save these per bike.

---

## State Machine

```gdscript
enum RiderState {
    RIDING,   # Procedural active, IK + target sync enabled
    IDLE,     # Procedural still ticking, target sync OFF, IK anim plays "idle"
    TRICK,    # IK disabled, skeleton AnimationPlayer drives pose
    RAGDOLL,  # Everything disabled
}
```

Transitions fire `state_changed(new_state)`.

- **RIDING → IDLE**: when speed < 0.5 and steer < 0.1 for `idle_timeout` seconds. Disables target sync and plays `ik_anim_player` "idle".
- **IDLE → RIDING**: plays "idle" backwards at 2x, awaits half its length, re-enables IK and target sync.

## Public API

```gdscript
func initialize()                           # Caches refs, captures base poses, root_nodes the IK anim player
func set_procedural_enabled(enabled: bool)

func enable_target_sync()                   # Hand/foot targets snap to bike each tick
func disable_target_sync()                  # Release targets so an animation can drive them

func play_trick(trick_name: String)         # Skeleton anim, disables IK
func cancel_trick()                         # Back to RIDING

func start_ragdoll()
func stop_ragdoll()
func do_reset()                             # Called from PlayerEntity.do_respawn (TODO)
```

---

## Rotation Layers

Two independent rotations on `visual_root`:

| Layer | Axis | Source | Notes |
|-------|------|--------|-------|
| Lean  | `rotation.z` | `movement_controller.roll_angle` | Cornering tilt |
| Pitch | `rotation.x` | `movement_controller.pitch_angle` | Wheelie/stoppie (with pivot offset) |

In the air, target sync is disabled and pitch directly lerps to `-pitch_angle`. On ground (basic/wheelie/stoppie) it's clamped to the bike's `max_wheelie_angle_deg` / `max_stoppie_angle_deg`.

## Wheelie/Stoppie Pivot

`_apply_pivot_offset()` lerps the pivot along the tire's contact arc based on pitch. Which wheel arc is chosen comes from `trick_controller.current_trick` (wheelie → rear, stoppie → front); when not in a trick, the sign of `rotation.x` decides, letting mid-transition unwind smoothly.

At 0° the pivot is the ground contact; at 90° it's the back of the tire (wheelie) or front of the tire (stoppie). Keeps the bike from clipping through the ground on deep tricks.

---

## IK System

### Flow

1. `PlayerEntity._init_ik()` (or editor "Init IK from Bike") calls `IKController.set_targets(...)` with all 11 PlayerEntity-owned markers.
2. Rider pose values loaded from `BikeSkinDefinition`.
3. FABRIK3D solves bone positions to marker targets each tick.
4. `IKController` rotates end bones to match marker rotations (FABRIK is position-only).
5. `AnimationController` applies procedural offsets (lean shift, fwd/back weight shift) and re-syncs hand/foot transforms from the bike each tick.

### Bone ← Marker

```
Hips      <- butt_target            (position only)
Spine     <- chest_target           (position + rotation)
Head      <- head_target            (position + rotation)
L/R Hand  <- left/right_hand_target (position + rotation; rebuilt from handlebar parent)
L/R Foot  <- left/right_foot_target (position + rotation; rebuilt from bike_skin)
L/R Elbow <- left/right_arm_magnet  (bend direction)
L/R Knee  <- left/right_leg_magnet  (bend direction)
```

### Target Sync

While `_targets_synced_from_bike` is true, `_sync_targets_from_bike()` runs every tick and overwrites hand/foot global transforms from `BikeSkinDefinition` values. To let an animation drive hands/feet (e.g. an idle hand-off-the-bar pose, or air flailing), call `disable_target_sync()`. Re-enable with `enable_target_sync()` to snap back to the bike on the next tick.

---

## Creating IK (Polish) Animations

IK animations animate `IKAnimationPlayer`'s tracks (rooted at `visual_root`). Disable target sync in the state where the animation plays, otherwise hands/feet will be re-snapped to the bike each tick and clobber the keyframes.

1. Open `player_entity.tscn`.
2. Select `IKAnimationPlayer` → **Animation > New**, save under `IK_anim_lib`.
3. Keyframe `position`/`rotation` on the relevant `IKTargets/*` markers at `t=0` AND end frame.
4. Wire the animation into a state transition (see `_transition_to_idle` for the "idle" example).

> **Always keyframe at t=0.** The player is sometimes seeked by ratio; without a t=0 keyframe the animation snaps on first play.

## Creating Trick (Skeleton) Animations

For tricks IK can't achieve:

1. Select `CharacterSkin/AnimationPlayer`, create animation with bone transform tracks.
2. `animation_controller.play_trick("name")` — disables IK, plays skeleton.
3. `animation_controller.cancel_trick()` — returns to RIDING, re-enables IK.

---

## Tuning

On `AnimationController` (inspector):
- `idle_timeout` — seconds of stillness before idle state
- `max_butt_offset` — lateral butt shift during lean
- `max_chest_lean_pitch_deg`, `max_chest_z_offset`, `max_butt_z_offset` — fwd/back weight shift from `nfx_lean`

On `BikeSkinDefinition`: `lean_multiplier`, `weight_shift_multiplier`, `max_wheelie_angle_deg`, `max_stoppie_angle_deg`, plus all per-bike marker positions/rotations.

---

## Editor Workflow

Open `player_entity.tscn`, select `AnimationController`:

- **Init IK from Bike** — calls `IKController.set_targets()`, loads rider pose + wheel markers from `BikeSkinDefinition`, syncs hand/foot targets.
- **Save Default Pose** — writes current chest/head/magnet/butt/wheel-marker transforms back to `BikeSkinDefinition`. Hand/foot pos+rot are converted into the handlebar-parent / bike_skin local space before saving (so they survive steering rotation).
- **Play Default Pose** — restores all markers from the saved definition values.

Auto-init runs on `_ready()` in the editor when `bike_skin`, `character_skin`, and the IK controller are all present.

---

## Netfox

Procedural animation is cosmetic-only, runs locally per client, no sync needed. Input/movement state is already synced; animation derives from that. Tricks that affect physics need the `rb_*` pattern (see `CLAUDE.md`).
