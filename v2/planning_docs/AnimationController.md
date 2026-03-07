# AnimationController

Central API for all rider animation - procedural dynamics, polish animations, and tricks.

## Architecture

```
PlayerEntity
├── VisualRoot (Node3D)           # Rotates for lean (bike + rider together)
│   ├── CharacterSkin
│   │   ├── IKController          # FABRIK solver, holds @export refs to IKTargets/*
│   │   ├── IKAnimationPlayer     # IK marker animations (polish/tricks)
│   │   ├── AnimationPlayer       # Skeleton animations
│   │   └── IKTargets/            # Actual marker nodes animated by IKAnimationPlayer
│   │       ├── ButtPosition
│   │       ├── ChestTarget
│   │       ├── HeadTarget
│   │       ├── LeftHand / RightHand
│   │       ├── LeftArmMagnet / RightArmMagnet
│   │       ├── LeftFoot / RightFoot
│   │       └── LeftLegMagnet / RightLegMagnet
│   └── BikeSkin                  # Rotates independently for wheelie/stoppie
│
└── _Components
    ├── AnimationController
    ├── MovementController
    ├── InputController
    └── CameraController
```

## State Machine

```gdscript
enum RiderState {
    RIDING,   # Procedural active, IK enabled
    IDLE,     # Procedural paused, IK animations playing
    TRICK,    # IK disabled, skeleton animation playing
    RAGDOLL,  # Everything disabled
}
```

## Public API

```gdscript
# Procedural control (automatic in RIDING state)
func set_procedural_enabled(enabled: bool)
func set_lean(amount: float)         # -1 to 1, left to right
func set_weight_shift(amount: float) # -1 to 1, back to forward
func set_bike_pitch(amount: float)   # -1 to 1, stoppie to wheelie

# Polish animations (IK marker anims)
func play_idle_animation(anim_name: String)
func play_land_settle()

# Trick animations (skeleton anims)
func play_trick(trick_name: String)
func cancel_trick()

# Ragdoll
func start_ragdoll()
func stop_ragdoll()

# Setup (called by PlayerEntity after IK init)
func initialize()
```

---

## Rotation Layers

Two independent rotation systems:

| Layer | Node | Controls | Example |
|-------|------|----------|---------|
| Lean | `VisualRoot` | Z rotation | Bike + rider tilt into turns |
| Bike Pitch | `BikeSkin` | X rotation | Wheelies, stoppies |

Lean is automatic from steering input. Bike pitch is set manually:
```gdscript
animation_controller.set_bike_pitch(0.5)  # Half wheelie
animation_controller.set_bike_pitch(-0.3) # Slight stoppie
```

---

## IK System

### How It Works

1. **Base positions** set by `CharacterSkin.set_ik_targets_for_bike()` from bike markers
2. **FABRIK3D** solves bone positions to reach marker targets
3. **IKController** applies marker rotations to end bones (FABRIK only handles position)
4. **AnimationController** applies procedural offsets on top of base positions

### IK Markers

Located in `CharacterSkin` scene under `IKTargets` (sibling of `IKController`, not a child of it). `IKController` holds `@export` references pointing to them:

| Node name (in `IKTargets`) | GDScript ref (on `IKController`) | Controls | Used For |
|----------------------------|----------------------------------|----------|----------|
| `ButtPosition` | `butt_pos` | Hips bone position | Seat position, lean offset |
| `ChestTarget` | `ik_chest` | Spine bone rotation | Torso lean/twist |
| `HeadTarget` | `ik_head` | Head bone rotation | Look direction |
| `LeftHand` / `RightHand` | `ik_left_hand` / `ik_right_hand` | Hand position + rotation | Grip handlebars |
| `LeftArmMagnet` / `RightArmMagnet` | `ik_left_arm_magnet` / `ik_right_arm_magnet` | Elbow position | Arm bend direction |
| `LeftFoot` / `RightFoot` | `ik_left_foot` / `ik_right_foot` | Foot position + rotation | Foot pegs |
| `LeftLegMagnet` / `RightLegMagnet` | `ik_left_leg_magnet` / `ik_right_leg_magnet` | Knee position | Leg bend direction |

### Bone-to-Marker Mapping

```
Hips         <- butt_pos (position only)
Spine        <- ik_chest (rotation)
Head         <- ik_head (rotation)
LeftHand     <- ik_left_hand (position + rotation)
RightHand    <- ik_right_hand (position + rotation)
LeftFoot     <- ik_left_foot (position + rotation)
RightFoot    <- ik_right_foot (position + rotation)
```

---

## Creating IK Animations

IK animations animate the **markers**, not the skeleton directly. This works for any character skin since all skins use the same marker structure.

### Step 1: Open the Scene

Prefer opening `player_entity.tscn` — this lets you see the character on the bike. You can also open `character_skin.tscn` directly. The IK markers are under `IKTargets` (a direct child of `CharacterSkin`, sibling of `IKController`).

### Step 2: Create Animation in IKAnimationPlayer

1. Select `IKAnimationPlayer` node
2. In the Animation panel: **Animation > New**, name it, save it **under `IK_anim_lib`**
3. Add tracks for marker transforms using the actual node names under `IKTargets`:
   - `IKTargets/HeadTarget:position` / `IKTargets/HeadTarget:rotation`
   - `IKTargets/ChestTarget:position` / `IKTargets/ChestTarget:rotation`
   - `IKTargets/ButtPosition:position`
   - `IKTargets/LeftHand:position` / `IKTargets/LeftHand:rotation`
   - `IKTargets/RightHand:position` / `IKTargets/RightHand:rotation`
   - `IKTargets/LeftFoot:position` / `IKTargets/LeftFoot:rotation`
   - `IKTargets/RightFoot:position` / `IKTargets/RightFoot:rotation`
   - `IKTargets/LeftArmMagnet:position`, `IKTargets/RightArmMagnet:position`
   - `IKTargets/LeftLegMagnet:position`, `IKTargets/RightLegMagnet:position`

### Step 3: Keyframe Marker Positions/Rotations

Animate markers by moving them in the viewport or setting values in the inspector. The IK system will move the bones to follow.

**Tips:**
- Magnets control bend direction (elbow/knee)
- End markers (hand/foot) control final position AND rotation
- `butt_pos` moves the whole pelvis
- Keep movements subtle for polish anims

### Step 4: Play via AnimationController

```gdscript
animation_controller.play_idle_animation("idle_fidget")
```

This pauses procedural animation and plays the IK animation. When done, call:
```gdscript
animation_controller.set_procedural_enabled(true)
```

---

## Creating Trick Animations (Skeleton)

For complex tricks that can't be achieved with IK, use skeleton animations.

### Step 1: Create Animation in AnimationPlayer

1. Select `AnimationPlayer` node in `CharacterSkin`
2. Create animation (e.g., "trick_superman")
3. Add bone transform tracks directly

### Step 2: Play via AnimationController

```gdscript
animation_controller.play_trick("trick_superman")
```

This **disables IK** and plays the skeleton animation directly. When done:
```gdscript
animation_controller.cancel_trick()  # Returns to RIDING state, re-enables IK
```

---

## Procedural Animation Details

Runs automatically in `RIDING` state. Driven by input/movement:

| Effect | Input Source | Target |
|--------|--------------|--------|
| Lean (rider) | `input_controller.steer` | `butt_pos.x`, `ik_chest.rotation.y` |
| Lean (visual) | `input_controller.steer` | `visual_root.rotation.z` |
| Weight shift | `input_controller.lean` | `butt_pos.z` |
| Bike pitch | `set_bike_pitch()` | `bike_skin.rotation.x` |

### Tuning

In `BikeSkinDefinition`:
```gdscript
@export var lean_multiplier: float = 1.0
@export var weight_shift_multiplier: float = 1.0
```

In `AnimationController` inspector:
- `lean_smoothing` - How fast lean responds (higher = snappier)
- `weight_shift_smoothing` - How fast weight shift responds
- `max_lean_angle` - Max visual lean in degrees (default 25)
- `max_bike_pitch` - Max wheelie/stoppie angle (default 30)

---

## Animation Workflow Summary

### For IK Animations (Polish)
1. Open `character_skin.tscn`
2. Select `IKAnimationPlayer`
3. Create animation, keyframe marker transforms
4. Call `play_idle_animation("anim_name")`

### For Skeleton Animations (Tricks)
1. Open `character_skin.tscn`
2. Select `AnimationPlayer`
3. Create animation, keyframe bone transforms
4. Call `play_trick("trick_name")`

### For Procedural Tweaks
1. Modify `_update_procedural_animation()` in `animation_controller.gd`
2. Adjust multipliers in bike definition or controller exports

---

## Editor Workflow (Authoring from player_entity.tscn)

Open `player_entity.tscn` to author animations with the character on the bike.

### Setup (once per bike)
1. Select `AnimationController` in the scene tree
2. Click **"Init IK from Bike"** — positions IK targets from the bike's attachment markers
3. Manually adjust marker rotations in the viewport (grip angle, foot angle, etc.)
4. Click **"Save Default Pose"** — saves position + rotation of all 11 IK targets as `"default_pose"` in `IK_anim_lib.res`

### Authoring each animation (e.g. a trick)
1. Click **"Reset to Default Pose"** — restores markers to the saved base
2. Select `IKAnimationPlayer` in the scene tree
3. In the Animation panel: **Animation > New** — name it and save it **under `IK_anim_lib`** (the library name must match)
4. At **time=0**, keyframe `position` and `rotation` for all markers you intend to animate — this locks in the base/default state
5. Scrub to **time=1**, move/rotate the desired markers to the trick pose, then update those keyframes
6. Animations are bike-agnostic — base positions come from the current bike's markers at runtime

> **Why keyframe at t=0?** The `IKAnimationPlayer` is seeked by ratio (e.g. `wheelie_arm_drag` is seeked 0→1 based on pitch). Without t=0 keyframes the animation has no defined start, causing snapping when it first plays. Always bookend both ends.

---

## Netfox Considerations

- Procedural animation is **cosmetic-only** (doesn't affect physics)
- Runs locally on each client, no sync needed
- Input/movement state already synced, procedural derives from that
- Tricks affecting physics would need the `rb_*` pattern from CLAUDE.md
