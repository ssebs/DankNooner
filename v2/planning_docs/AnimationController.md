# AnimationController

Central API for all rider animation - procedural dynamics, polish animations, and tricks.

## Architecture

```
PlayerEntity
├── _Components
│   ├── AnimationController (NEW)
│   │   @export character_skin: CharacterSkin
│   │   @export bike_skin: BikeSkin
│   │   @export movement_controller: MovementController
│   │   @export input_controller: InputController
│   │
│   ├── MovementController
│   ├── InputController
│   └── CameraController
│
├── CharacterSkin
│   ├── IKController (markers + FABRIK)
│   ├── IKAnimationPlayer (polish anims)
│   └── AnimationPlayer (skeleton anims for tricks)
│
└── BikeSkin
```

## Layers

### Layer 1: Procedural (continuous)
Runs in `_physics_process()`, driven by movement/input state:

| Effect | Input | Target |
|--------|-------|--------|
| Lean | `input_controller.steer` | butt.x, chest.rotation.y |
| Weight shift | `movement_controller.acceleration` | butt.z |
| Speed tuck | `movement_controller.current_speed` | chest.position.y (optional) |

Base positions come from bike markers (existing `set_ik_targets_for_bike()`).
Procedural applies **offsets** on top.

Multipliers stored in `BikeSkinDefinition`:
```gdscript
@export var lean_multiplier: float = 1.0
@export var weight_shift_multiplier: float = 1.0
```

### Layer 2: Polish Animations (discrete)
Played via `IKAnimationPlayer`, temporarily override procedural:

| Animation | Trigger |
|-----------|---------|
| idle_fidget | stopped for N seconds |
| look_around | random while idle |
| land_settle | after landing jump/trick |
| celebration | after successful trick |

These animate IK markers directly. When playing, procedural pauses.

### Layer 3: Trick Animations (full override)
Disables IK entirely, plays on `CharacterSkin.anim_player` (skeleton).

---

## State Machine

```gdscript
enum RiderState {
    RIDING,      # Procedural active, IK enabled
    IDLE,        # Procedural paused, playing idle anims
    TRICK,       # IK disabled, skeleton anim playing
    RAGDOLL,     # Everything disabled
}
```

## API

```gdscript
class_name AnimationController extends Node

# State
var current_state: RiderState = RiderState.RIDING

# Procedural control
func set_procedural_enabled(enabled: bool)
func set_lean(amount: float)        # -1 to 1
func set_weight_shift(amount: float) # -1 to 1

# Polish animations
func play_idle_animation(anim_name: String)
func play_land_settle()

# Tricks
func play_trick(trick_name: String)
func cancel_trick()

# Ragdoll
func start_ragdoll()
func stop_ragdoll()

# Setup (called by PlayerEntity._ready())
func initialize()
```

## Implementation Steps

1. **Create `animation_controller.gd`** under `entities/player/components/`
   - Extend `Node`
   - Add exports for dependencies
   - Implement state enum and transitions

2. **Move IK init from PlayerEntity**
   - `_init_ik()` logic moves to `AnimationController.initialize()`
   - Store base positions for procedural offset math

3. **Implement procedural layer**
   - `_physics_process()` reads movement/input
   - Calculates offsets, applies to IK markers
   - Only runs when `current_state == RIDING`

4. **Add multipliers to BikeSkinDefinition**
   - `lean_multiplier`, `weight_shift_multiplier`
   - Read these in `initialize()`

5. **Wire up in player_entity.tscn**
   - Add AnimationController under _Components
   - Wire exports in inspector
   - Call `animation_controller.initialize()` in `_ready()`

6. **Create shared IK animation library** (later)
   - Idle fidgets, land settle, etc.
   - Assign to `IKAnimationPlayer`

---

## Integration with Existing Code

### PlayerEntity changes
```gdscript
@export var animation_controller: AnimationController

func _ready():
    _init_mesh()
    _init_collision_shape()
    animation_controller.initialize()  # Replaces _init_ik()
```

### CharacterSkin stays mostly the same
- `set_ik_targets_for_bike()` still sets base positions
- `IKController` still does FABRIK
- `AnimationController` manipulates markers after base positions set

### Ragdoll integration
```gdscript
func start_ragdoll():
    current_state = RiderState.RAGDOLL
    character_skin.disable_ik()
    character_skin.start_ragdoll()

func stop_ragdoll():
    character_skin.stop_ragdoll()
    character_skin.enable_ik()
    current_state = RiderState.RIDING
```

---

## Netfox Considerations

Procedural animation is cosmetic-only (doesn't affect physics), so:
- Runs locally on each client
- No need to sync via RollbackSynchronizer
- Input/movement state already synced, procedural derives from that

Tricks that affect physics (if any) would need the `rb_*` pattern from CLAUDE.md.
