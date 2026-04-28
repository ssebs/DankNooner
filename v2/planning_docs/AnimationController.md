# AnimationController

Central API for all rider animation — procedural dynamics, IK polish animations, and skeleton tricks. Built around a per-frame **pose pipeline** that lets procedural state, IK marker positions, and start/stop animations all blend cleanly without fighting each other.

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
├── IKAnimationPlayer                # Authoring-only AnimationPlayer (library holder)
│
└── _Controllers/
    ├── AnimationController
    │   └── AnimRunner               # CustomAnimPlayer — runtime additive blender
    ├── MovementController
    ├── InputController
    └── CameraController
```

### Marker Ownership

All IK markers are **owned by `PlayerEntity`** and exported on it directly. Per-bike *values* (positions/rotations) live on `BikeSkinDefinition` and are applied via the pose pipeline at runtime.

- **Hand/foot targets** are reconstructed every tick from `BikeSkinDefinition`, anchored to the steering handlebar's parent (hands) and `bike_skin` (feet) — see `_apply_bike_to_pose()`.
- **Chest/head/magnets/butt** are positioned once at init from `BikeSkinDefinition`, then driven procedurally and/or by animation deltas.
- Wheel markers are editor handles for pivot/raycast positions; values live on `BikeSkinDefinition`.

### Steering

`BikeSkin` creates a `SteeringHandleBarProxy` under the steering `RotationPoint`. Hand sync multiplies the handlebar parent's `global_transform` by the saved hand local transforms, then converts the result into IKTargets-parent local space so the value can be added to the pose alongside animation deltas.

### Per-Bike Rider Pose

Chest/head/magnet/hand/foot/butt/wheel-marker transforms are stored on `BikeSkinDefinition` and applied at init by `PlayerEntity._apply_rider_pose_from_definition()` (and by the editor "Init IK from Bike" button). Use the editor tools on `AnimationController` to author and save these per bike.

---

## Pose Pipeline

Every frame `_update_riding` / `_update_idle` runs the same 4-stage pipeline. **No stage writes to actual nodes** except `_commit_pose()`. This is what makes blending work — proc state, anim deltas, and the committed values are kept separate.

```
_next_proc_pose()        → carries proc state across frames (no anim baked in)
   ↓
_apply_bike_to_pose()    → hand/foot positions from BikeSkinDefinition
   ↓
_apply_riding_common()   → lean Z, chest yaw, butt/chest weight shift
_apply_pitch_ground/air()→ wheelie/stoppie/air pitch X
_apply_pivot_offset()    → tire contact arc pivot
   ↓
_proc_pose = pose        → snapshot proc-only state for next frame
final = pose.duplicate() → branch
   ↓
_apply_anim_deltas()     → CustomAnimPlayer.tick() + add (sample(t) - sample(0)) * weight
   ↓
_commit_pose(final)      → only place that touches markers / visual_root
```

### `_RiderPose` (inner class, bottom of file)

Plain data: `visual_root_pos/rot`, `butt_pos`, `chest_pos/rot`, `head_pos/rot`, `left/right_hand_pos/rot`, `left/right_foot_pos/rot`. Has `duplicate()` for the proc/final split. Allocated per frame; cheap.

### Why Proc & Anim Are Kept Separate

If proc lerps read from the live nodes, last frame's `committed = proc + anim_delta` becomes this frame's "current," and the anim delta leaks into the lerp — drift. By caching `_proc_pose` and applying anim deltas only to a duplicate, proc has continuous state and anim layers cleanly on top.

`_proc_pose` is reset to `null` (forcing reseed from defaults) in `set_procedural_enabled(true)` and `stop_ragdoll()`.

---

## CustomAnimPlayer (Runtime)

Lives at `utils/custom_anim_player.gd`. A lightweight, additive-blend runner — **does not** use Godot's `AnimationPlayer.play()` at runtime. Instead it samples Animation resources directly with `Animation.value_track_interpolate(track, time)`, computes `(sample(t) - sample(0)) * weight`, and returns the delta for callers to add to their pose.

### Public API

```gdscript
play(anim, speed=1.0, looping=true, fade_speed=4.0) -> Layer
play_backwards(anim, speed=1.0, looping=true, fade_speed=4.0) -> Layer
play_one_shot(anim, speed=1.0, fade_speed=4.0) -> Layer  # plays once, HOLDS end pose
stop(layer, fade_speed=4.0)         # fades out, removed at weight 0
stop_all()                          # drop everything, no fade
tick(delta)                         # advance times + weights
sample(track_path) -> Variant       # null if no layer animates this path
sample_vec3(track_path) -> Vector3  # 0 fallback
sample_float(track_path) -> float   # 0 fallback
get_layers() -> Array[Layer]
```

### Layer

Returned by `play*()`. Cache the handle to query state or stop later.

```gdscript
get_duration() -> float
get_time() -> float
is_playing() -> bool
# fields: anim, speed, time, looping, hold_at_end, weight, target_weight, fade_speed, finished
```

### Loop / One-shot / Hold Modes

| Mode | Call | Time at end | Weight at end |
|------|------|-------------|---------------|
| Loop | `play(anim, _, true)` | wraps via `fposmod` | stays |
| One-shot, auto-fade | `play(anim, _, false)` | clamps | auto-fades to 0, layer removed |
| One-shot, **hold** | `play_one_shot(anim)` | clamps | stays at 1 until `stop()` |

`hold_at_end` is the flag behind it — `play_one_shot` just sets `looping=false, hold_at_end=true`. Use **hold** for "settle into pose, stay there" anims (idle, crouch, brace). Use auto-fade one-shots for transient gestures (wave, flinch).

### How Animations Layer

- Each active layer contributes `(value_track_interpolate(t) - value_track_interpolate(0)) * weight` for every value track.
- `t=0` IS the authored default pose (the convention is to keyframe defaults at t=0), so the difference is the *offset the animator drew*.
- Multiple layers stack. A fading-out layer cleanly hands off to a fading-in one.
- Non-loop layers auto-fade once `time` reaches `anim.length` (or 0 going backwards).

### Idle Flow (current pattern for hold + blend out)

```gdscript
# stop moving
_idle_layer = _anim_runner.play_one_shot(_idle_anim, 1.0)

# start moving again
_anim_runner.stop(_idle_layer)
```

Layer fades in via `fade_speed`, plays once, holds end pose. `stop()` fades it out. The blend handles the transition both ways — no reverse-play hack, no `await` timer. This is the template for any "settle into a pose, leave on demand" animation.

### Authoring vs. Runtime

- `IKAnimationPlayer` (in scene) is the **authoring/library** node only. Edit animations there, save them in its `AnimationLibrary`.
- Runtime caches `Animation` resources off it (`ik_anim_player.get_animation("idle")`) and feeds them to `_anim_runner` (a `CustomAnimPlayer` child added in `initialize()`).
- Don't call `.play()` on `IKAnimationPlayer` at runtime — `_anim_runner` owns playback.

### Track Path Convention

`_anim_runner` finds tracks by exact `NodePath` match. `AnimationController` defines constants for each marker path (e.g. `_PATH_LHAND_POS = ^"IKTargets/LeftHandTarget:position"`). Authored anims must use these full paths — **don't use `%UniqueName` shorthand**, it won't match.

If you add a new marker that anims should drive, add a `_PATH_*` const + a line in `_apply_anim_deltas`.

---

## State Machine

```gdscript
enum RiderState {
    RIDING,   # Proc pipeline + IK + bike→pose hand sync
    IDLE,     # Proc pipeline runs minimal (just unwinds pitch); idle anim layers on top
    RAGDOLL,  # IK + proc disabled
}
```

Transitions fire `state_changed(new_state)`.

- **RIDING → IDLE**: when speed < 0.5 and steer < 0.1 for `idle_timeout` seconds. Disables target sync (so the anim's hand keyframes aren't overwritten), starts `_anim_runner.play(_idle_anim, 1.0, true)`. Layer fades in.
- **IDLE → RIDING**: `_anim_runner.stop(_idle_layer)` — layer fades out and is removed. Re-enables IK and target sync.

The old `await get_tree().create_timer(...)` half-anim wait is gone — fades happen via blend weights, no timer needed.

## Public API

```gdscript
func initialize()                           # Caches refs, captures base poses, creates AnimRunner, caches anim resources
func set_procedural_enabled(enabled: bool)  # Reseeds _proc_pose on enable

func enable_target_sync()                   # Hand/foot read from bike each tick
func disable_target_sync()                  # Skip bike→pose for hands/feet (let anim drive)

func start_ragdoll()
func stop_ragdoll()
func do_reset()                             # Called from PlayerEntity.do_respawn (TODO)
```

To play arbitrary IK anims from elsewhere, expose `_anim_runner` or wrap with helper methods — same `play()/stop()` API.

---

## Rotation Layers

Two independent rotations on `visual_root` (written into `pose.visual_root_rot`):

| Layer | Axis | Source | Notes |
|-------|------|--------|-------|
| Lean  | `rotation.z` | `movement_controller.roll_angle` | Cornering tilt |
| Pitch | `rotation.x` | `movement_controller.pitch_angle` | Wheelie/stoppie (with pivot offset) |

In the air, target sync is disabled and pitch directly lerps to `-pitch_angle`. On ground (basic/wheelie/stoppie) it's clamped to `max_wheelie_angle_deg` / `max_stoppie_angle_deg`.

## Wheelie/Stoppie Pivot

`_apply_pivot_offset_to_pose()` lerps the pivot along the tire's contact arc based on `pose.visual_root_rot.x`. Which wheel arc is chosen comes from `trick_controller.current_trick` (wheelie → rear, stoppie → front); when not in a trick, the sign of `rotation.x` decides, letting mid-transition unwind smoothly.

At 0° the pivot is the ground contact; at 90° it's the back of the tire (wheelie) or front of the tire (stoppie). Keeps the bike from clipping through the ground on deep tricks.

---

## IK System

### Flow

1. `PlayerEntity._init_ik()` (or editor "Init IK from Bike") calls `IKController.set_targets(...)` with all 11 PlayerEntity-owned markers.
2. Rider pose values loaded from `BikeSkinDefinition`.
3. `AnimationController` commits the pose every tick (markers' local position/rotation).
4. FABRIK3D solves bone positions to those marker targets each `_physics_process`.
5. `IKController` rotates end bones to match marker rotations (FABRIK is position-only).

### Bone ← Marker

```
Hips      <- butt_target            (position only)
Spine     <- chest_target           (position + rotation)
Head      <- head_target            (position + rotation)
L/R Hand  <- left/right_hand_target (position + rotation; rebuilt from handlebar parent each tick)
L/R Foot  <- left/right_foot_target (position + rotation; rebuilt from bike_skin each tick)
L/R Elbow <- left/right_arm_magnet  (bend direction)
L/R Knee  <- left/right_leg_magnet  (bend direction)
```

### Target Sync

Controls whether `_apply_bike_to_pose()` runs each tick. While `_targets_synced_from_bike` is true, hand/foot pose values are seeded from `BikeSkinDefinition` (handlebar/peg parent local space → IKTargets-parent local space). When false, the previous pose values persist, letting an animation drive hands/feet without being clobbered.

In the new pipeline this is *additive*-friendly: even with sync on, an animation playing on hands/feet adds its delta on top of the bike-derived base. Disable sync only when an anim should fully replace the bike pose (e.g. air flailing, hand-off-bar idle).

---

## Creating IK (Polish) Animations

IK animations animate marker tracks (rooted at `visual_root`). Now that animations are layered as **deltas from t=0**, their `t=0` keyframe IS treated as the default — write the anim from the default rest pose and the runtime subtracts it for you.

1. Open `player_entity.tscn`.
2. Select `IKAnimationPlayer` → **Animation > New**, save under `IK_anim_lib`.
3. Keyframe `position`/`rotation` on the relevant `IKTargets/*` markers at `t=0` AND end frame.
   - **Use full paths** like `IKTargets/LeftHandTarget:position`. Don't use `%UniqueName` shorthand.
4. Cache the anim in `AnimationController.initialize()` (`var _my_anim = ik_anim_player.get_animation("name")`).
5. Trigger via `_anim_runner.play(_my_anim, ...)` from a state transition or anywhere.

> **Always keyframe at t=0.** That keyframe is the "default" the runtime subtracts from each sample. Without it, the layer applies whatever the first existing keyframe value is as a constant offset.

## Creating Trick (Skeleton) Animations

For tricks IK can't achieve, use `CharacterSkin/AnimationPlayer` with bone transform tracks. (Trick state isn't fully wired into the new pipeline yet — in the future, a `TRICK` state will disable IK and let the skeleton anim drive directly.)

---

## Tuning

On `AnimationController` (inspector):
- `idle_timeout` — seconds of stillness before idle state
- `max_butt_offset` — lateral butt shift during lean
- `max_chest_yaw_deg` — chest twist toward turn direction
- `max_chest_lean_pitch_deg`, `max_chest_z_offset`, `max_butt_z_offset` — fwd/back weight shift from `nfx_lean`

On `BikeSkinDefinition`: `lean_multiplier`, `weight_shift_multiplier`, `max_wheelie_angle_deg`, `max_stoppie_angle_deg`, plus all per-bike marker positions/rotations.

---

## Editor Workflow

Open `player_entity.tscn`, select `AnimationController`:

- **Init IK from Bike** — calls `IKController.set_targets()`, loads rider pose + wheel markers from `BikeSkinDefinition`, syncs hand/foot targets.
- **Save Default Pose** — writes current chest/head/magnet/butt/wheel-marker transforms back to `BikeSkinDefinition`. Hand/foot pos+rot are converted into the handlebar-parent / bike_skin local space before saving (so they survive steering rotation).
- **Play Default Pose** — restores all markers from the saved definition values.

Auto-init runs on `_ready()` in the editor when `bike_skin`, `character_skin`, and the IK controller are all present.

The legacy `_sync_targets_from_bike()` (which sets `global_transform` directly) is still used by these editor tools for one-shot pose loading. Runtime uses `_apply_bike_to_pose` (pose pipeline, local-space) instead.

---

## Netfox

Procedural animation is cosmetic-only, runs locally per client, no sync needed. Input/movement state is already synced; animation derives from that. Tricks that affect physics need the `rb_*` pattern (see `CLAUDE.md`).

---

## Gotchas / Important Things to Know

Pitfalls that aren't obvious from the code alone — read this before changing the pipeline.

### 1. Never read live node values inside proc stages

`_apply_riding_common`, `_apply_pitch_*`, etc. **only** read from the `pose` parameter. Reading `player_entity.chest_target.rotation` would pull in the previous frame's `committed = proc + anim_delta`, and the anim delta would leak into the proc lerp and drift each frame. The split between `_proc_pose` and the committed `final_pose` is what prevents drift — preserve it.

### 2. Always keyframe at `t=0`

The runtime computes `delta = sample(t) - sample(0)`. The `t=0` keyframe IS the "default" the layer subtracts. If you forget it, Godot's interpolation falls back to the first existing keyframe, and the layer applies a constant offset forever even at weight 1 — looks like the rider is glued into the start pose.

### 3. Use full track paths, not `%UniqueName` shorthand

`_apply_anim_deltas` looks up tracks by exact `NodePath` match against the constants at the top of the file. Author tracks as `IKTargets/LeftHandTarget:position`, not `%LeftHandTarget:position`. If you see a track in the editor that "should be working" but does nothing, this is almost always why.

### 4. Pivot wheel is picked by sign of rot_x, NOT by trick state

`_apply_pivot_offset_to_pose` uses `rot_x < 0.0` to pick the rear-wheel pivot. Don't switch this back to `trick_controller.current_trick` — the trick state flips instantly while `rot_x` lerps, so during a wheelie↔stoppie transition the wrong wheel pivots and the bike clips through the ground for a fraction of a second. The mapping is: `_apply_pitch_ground` produces `rot_x < 0` for wheelie targets and `rot_x > 0` for stoppie, so the sign always matches the visible rotation.

### 5. `target_sync` controls bike→pose seeding, not output

`disable_target_sync()` skips `_apply_bike_to_pose` so previous pose values for hands/feet persist (lets an air-flailing anim drive them without being snapped back to the bars). It does NOT disable anim deltas or commits. With sync on, anim deltas still layer on top of the bike-derived base — that's intentional.

### 6. Reseed `_proc_pose = null` after any pose discontinuity

`set_procedural_enabled(true)` and `stop_ragdoll()` already do this. If you add another path that warps the rider (respawn, level reset, teleport), do the same — otherwise the next frame's lerp starts from stale state and you get a visible glide back to where the rider should be.

### 7. The legacy `_sync_targets_from_bike()` is for editor only

It writes `global_transform` directly. Editor tools (Init IK from Bike, Play Default Pose) use it for one-shot snapping. Runtime uses `_apply_bike_to_pose` instead. Don't call the legacy one from a runtime path — it bypasses the pose pipeline and any active anim layer will fight it.

### 8. CustomAnimPlayer modes

| Want | Call | Notes |
|------|------|-------|
| Looping background anim (idle bob) | `play(anim, 1.0, true)` | wraps; `stop()` to remove |
| One-shot gesture (wave, flinch) | `play(anim, 1.0, false)` | auto-fades out at end, removed |
| Settle into pose, hold | `play_one_shot(anim)` | clamps + holds; `stop()` to release |

`play_one_shot` is the right choice for any "play in, stay there until further notice" pose. Don't use the looping form for those — the anim will visibly snap back to t=0 every cycle.

### 9. The `IKAnimationPlayer` node is authoring-only at runtime

Edit anims there; never call `.play()` on it from runtime code. Cache the `Animation` resource in `initialize()` (as `_idle_anim` does) and feed it to `_anim_runner`. If you re-introduce `ik_anim_player.play(...)`, it will write directly to markers and fight the pose pipeline.
