# AnimationController

Central API for all rider animation — procedural dynamics, polish (IK) animations, and tricks (skeleton).

## Architecture

```
PlayerEntity
├── VisualRoot (Node3D)              # Rotates for lean (Z) + pitch (X) — bike + rider together
│   ├── CharacterSkin
│   │   ├── IKController             # FABRIK solver, holds refs to body markers
│   │   ├── IKAnimationPlayer        # IK marker animations (polish/tricks)
│   │   ├── AnimationPlayer          # Skeleton animations
│   │   └── IKTargets/               # Character-owned body-shape markers
│   └── BikeSkin                     # Contact-point markers (seat, pegs, handlebars, wheel pivots)
│
└── _Controllers/
    ├── AnimationController
    ├── MovementController
    ├── InputController
    └── CameraController
```

### Marker Ownership

- **Bike owns** contact points (`BikeSkinDefinition`): seat, handlebar, peg, front/rear wheel ground + edge positions. Right side mirrored from left at runtime.
- **Character owns** body-shape markers (`CharacterSkin/IKTargets`): chest, head, arm/leg magnets.
- `PlayerEntity._init_ik()` wires bike markers to IKController via `set_bike_markers()`.

### Steering

`BikeSkin` creates a `SteeringHandleBarProxy` under the steering `RotationPoint`. When `rotate_steering()` fires, the proxy (and thus hand IK target) follows automatically — no manual math.

### Per-Bike Rider Pose

Chest/head/magnet transforms are stored on `BikeSkinDefinition` and applied at init by `PlayerEntity._apply_rider_pose_from_definition()`. Editor tools on `AnimationController` let you author and save these.

---

## State Machine

```gdscript
enum RiderState {
    RIDING,   # Procedural active, IK enabled
    IDLE,     # Procedural paused, IK animations playing
    TRICK,    # IK disabled, skeleton animation playing
    RAGDOLL,  # Everything disabled
}
```

Transitions fire `state_changed(new_state)`.

## Public API

```gdscript
func initialize()                           # Called by PlayerEntity after IK init
func set_procedural_enabled(enabled: bool)

func play_idle_animation(anim_name: String) # IK polish anim
func play_land_settle()                     # TODO

func play_trick(trick_name: String)         # Skeleton anim, disables IK
func cancel_trick()                         # Back to RIDING

func start_ragdoll()
func stop_ragdoll()
```

---

## Rotation Layers

Two independent rotations on `visual_root`:

| Layer | Axis | Source | Notes |
|-------|------|--------|-------|
| Lean  | `rotation.z` | `movement_controller.roll_angle` | Cornering tilt |
| Pitch | `rotation.x` | `movement_controller.pitch_angle` | Wheelie/stoppie (with pivot offset) |

In the air, pitch directly lerps to `-pitch_angle`. On ground it's clamped to the bike's `max_wheelie_angle_deg` / `max_stoppie_angle_deg`.

## Wheelie/Stoppie Pivot

`_apply_pivot_offset()` lerps the pivot along the tire's contact arc based on pitch. Which wheel arc is chosen comes from `trick_controller.current_trick` (wheelie → rear, stoppie → front); when not in a trick, the sign of `rotation.x` decides, letting mid-transition unwind smoothly.

At 0° the pivot is the ground contact; at 90° it's the back of the tire (wheelie) or front of the tire (stoppie). Keeps the bike from clipping through the ground on deep tricks.

---

## IK System

### Flow

1. `PlayerEntity._init_ik()` → `IKController.set_bike_markers()` wires bike contact points.
2. Rider pose loaded from `BikeSkinDefinition`.
3. FABRIK3D solves bone positions to marker targets.
4. `IKController` applies marker rotations to end bones (FABRIK handles position only).
5. `AnimationController` applies procedural offsets on top.

### Bone ← Marker

```
Hips      <- butt_pos            (position only, bike-owned)
Spine     <- ik_chest            (rotation, character-owned)
Head      <- ik_head             (rotation, character-owned)
L/R Hand  <- ik_left/right_hand  (position + rotation, bike-owned via proxy)
L/R Foot  <- ik_left/right_foot  (position + rotation, bike-owned via proxy)
L/R Elbow <- ik_left/right_arm_magnet  (bend direction, character-owned)
L/R Knee  <- ik_left/right_leg_magnet  (bend direction, character-owned)
```

---

## Creating IK (Polish) Animations

IK animations animate **character-owned markers** (chest, head, magnets). Contact-point markers (hands, feet, butt) are bike-owned — don't keyframe them.

1. Open `player_entity.tscn`.
2. Select `IKAnimationPlayer` → **Animation > New**, save under `IK_anim_lib`.
3. Keyframe `position`/`rotation` on character-owned markers at `t=0` AND the end frame (see note below).
4. Play via `animation_controller.play_idle_animation("name")`.

> **Always keyframe at t=0.** `IKAnimationPlayer` is seeked by ratio in some flows; without a t=0 keyframe the animation snaps on first play.

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

On `BikeSkinDefinition`: `lean_multiplier`, `weight_shift_multiplier`, `max_wheelie_angle_deg`, `max_stoppie_angle_deg`.

---

## Editor Workflow

Open `player_entity.tscn`, select `AnimationController`:

- **Init IK from Bike** — creates hand/foot proxies, loads rider pose from `BikeSkinDefinition`.
- **Save Default Pose** — writes current chest/head/magnet transforms back to `BikeSkinDefinition`.
- **Play Default Pose** — restores markers to saved pose (use before authoring a new animation).

---

## Netfox

Procedural animation is cosmetic-only, runs locally per client, no sync needed. Input/movement state is already synced; animation derives from that. Tricks that affect physics need the `rb_*` pattern (see `CLAUDE.md`).
