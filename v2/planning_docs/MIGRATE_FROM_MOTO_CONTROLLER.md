# Migration Guide: Moto Player Controller → DankNooner v2

> Porting singleplayer player controller from `_TMP_/` to multiplayer

## Overview

**Source**: `_TMP_/` - copied from moto-player-controller singleplayer demo
**Target**: `entities/player/` - existing PlayerEntity with netfox + skins

### What's Already Done in v2

- **Skin system complete**: `BikeSkinDefinition`, `CharacterSkinDefinition`, `BikeSkin`, `CharacterSkin`
- **IK working**: Character mounts bike via IK targets from skin definition
- **AnimationController**: Procedural lean/weight-shift, IK enable/disable, ragdoll API
- **Controllers established**: `MovementController`, `InputController`, `CameraController`
- **Netfox sync**: `RollbackSynchronizer` + `TickInterpolator` configured
- **rb_* pattern**: `rb_do_respawn` already implemented as reference

### Design Goals

1. **Keep controller separation** - don't flatten everything into PlayerEntity
2. **Extend existing controllers** - physics goes in MovementController, not inlined
3. **Multiplayer-first** - all physics in `_rollback_tick()`, proper sync
4. **Use existing skin resources** - add physics/gearing to `BikeSkinDefinition`
5. **Defer difficulty modes** - start with manual shifting only (HARD mode)

### Migration Summary

| From _TMP_/              | Action       | Target                                          |
| ------------------------ | ------------ | ----------------------------------------------- |
| BikeState                | **EXTEND**   | Add state vars to PlayerEntity + MovementCtrl   |
| BikePhysics              | **EXTEND**   | Extend MovementController                       |
| BikeGearing              | **NEW**      | Create GearingController component              |
| BikeTricks (physics)     | **NEW**      | Create TrickController component                |
| BikeTricks (scoring)     | **DEFER**    | → TrickManager later (Milestone 2)              |
| BikeCrash                | **NEW**      | Create CrashController component                |
| BikeAnimation            | **EXTEND**   | Extend existing AnimationController             |
| BikeAudio                | **DEFER**    | Milestone 2 (AudioController or AudioManager)   |
| BikeUI                   | **DEFER**    | Milestone 3 (HUD)                               |
| BikeCamera               | **EXTEND**   | Extend existing CameraController                |
| BikeInput                | **EXTEND**   | Extend existing InputController                 |
| BikeResource             | **EXTEND**   | Add gearing/physics to BikeSkinDefinition       |
| IKCharacterMesh          | **DONE**     | Already exists as CharacterSkin                 |
| BikeComponent base class | **DROP**     | Use @export references (existing pattern)       |
| Difficulty modes         | **DEFER**    | Start with manual shifting only                 |

---

## Current v2 Architecture

```
PlayerEntity (CharacterBody3D)
├── @export Controllers:
│   ├── MovementController  - basic accel/brake/steer (needs gearing/physics)
│   ├── InputController     - throttle, brake, steer, lean (needs rear_brake, trick)
│   ├── CameraController    - TPS/FPS toggle (needs FOV scaling)
│   └── AnimationController - procedural lean, IK, ragdoll (needs trick animations)
│
├── @onready Visuals:
│   ├── %VisualRoot         - rotates for lean/pitch
│   ├── %CharacterSkin      - IK rider mesh
│   └── %BikeSkin           - bike mesh from definition
│
├── @export Definitions:
│   ├── bike_definition: BikeSkinDefinition     - mesh, markers, collision
│   └── character_definition: CharacterSkinDefinition
│
├── Netfox (configured):
│   ├── RollbackSynchronizer - state + input properties
│   └── TickInterpolator     - smooth remote players
│
└── Existing rb_* pattern:
    └── rb_do_respawn → on_respawn()
```

---

## Target Architecture

```
PlayerEntity (CharacterBody3D)
├── @export Controllers:
│   ├── MovementController    - EXTENDED: gearing-aware acceleration, lean physics
│   ├── InputController       - EXTENDED: rear_brake, trick, clutch signals
│   ├── CameraController      - EXTENDED: FOV scaling, crash cam
│   ├── AnimationController   - EXTENDED: trick animations, pitch/lean visuals
│   ├── GearingController     - NEW: RPM, gear shifts, clutch, power output
│   ├── TrickController       - NEW: wheelie/stoppie physics, boost
│   └── CrashController       - NEW: angle checks, brake grab, crash trigger
│
├── PlayerEntity synced state:
│   ├── speed, lean_angle, pitch_angle, fishtail_angle
│   ├── current_gear, current_rpm, clutch_value
│   └── is_boosting, is_crashed
│
├── rb_* discrete actions:
│   ├── rb_gear_up, rb_gear_down
│   ├── rb_activate_boost
│   └── rb_do_respawn
│
├── Signals:
│   ├── trick_changed(trick_type: int)
│   ├── crashed()
│   └── respawned()
│
└── BikeSkinDefinition EXTENDED:
    ├── Existing: mesh, markers, collision, colors, animation multipliers
    └── NEW: gearing config, physics tuning, trick thresholds
```

---

## Milestone 1: Core Physics

> Get the bike feeling right with gearing and wheelie/stoppie

### 1.1 Extend BikeSkinDefinition

Add gearing and physics tuning to the existing resource:

```gdscript
# In bike_skin_definition.gd - ADD these export groups

@export_group("Gearing")
@export var gear_ratios: Array[float] = [2.92, 2.05, 1.6, 1.46, 1.15, 1.0]
@export var num_gears: int = 6
@export var max_rpm: float = 11000.0
@export var idle_rpm: float = 1000.0
@export var stall_rpm: float = 800.0

@export_group("Physics")
@export var max_speed: float = 120.0
@export var acceleration: float = 12.0
@export var brake_strength: float = 20.0
@export var friction: float = 2.0
@export var engine_brake_strength: float = 12.0
@export var max_lean_angle_deg: float = 45.0
@export var lean_speed: float = 2.5
@export var min_turn_radius: float = 0.25
@export var max_turn_radius: float = 3.0
@export var turn_speed: float = 2.0

@export_group("Tricks")
@export var max_wheelie_angle_deg: float = 85.0
@export var max_stoppie_angle_deg: float = 55.0
@export var wheelie_rpm_threshold: float = 0.65  # RPM ratio where wheelies can start
@export var wheelie_balance_point_deg: float = 60.0
@export var rotation_speed: float = 2.0
@export var return_speed: float = 3.0

# Computed getter
var max_lean_angle_rad: float:
    get: return deg_to_rad(max_lean_angle_deg)
```

### 1.2 Extend InputController

Add new synced inputs and signals:

```gdscript
# In input_controller.gd - ADD these

signal clutch_held_changed(held: bool, just_pressed: bool)
signal trick_changed(is_pressed: bool)

# New synced inputs (add to RollbackSynchronizer input_properties)
var rear_brake: float = 0.0:
    set(value):
        if rear_brake != value:
            rear_brake = value

var trick: bool = false:
    set(value):
        if trick != value:
            trick = value
            trick_changed.emit(value)

var clutch_held: bool = false

# In _update_input_for_server():
rear_brake = Input.get_action_strength("brake_rear")
trick = Input.is_action_pressed("trick_mod")

# Clutch handling (tap vs hold)
var clutch_now = Input.is_action_pressed("clutch")
if clutch_now != clutch_held:
    clutch_held = clutch_now
    clutch_held_changed.emit(clutch_held, clutch_now)
```

Update RollbackSynchronizer in player_entity.tscn:
```
input_properties = Array[String]([
    "%InputController:throttle",
    "%InputController:front_brake",
    "%InputController:rear_brake",
    "%InputController:steer",
    "%InputController:lean",
    "%InputController:trick"
])
```

### 1.3 Add State to PlayerEntity

Add synced physics state:

```gdscript
# In player_entity.gd - ADD these vars

# Physics state (synced via RollbackSynchronizer state_properties)
var speed: float = 0.0
var lean_angle: float = 0.0
var pitch_angle: float = 0.0        # + = wheelie, - = stoppie
var fishtail_angle: float = 0.0
var ground_pitch: float = 0.0       # Slope alignment

# Gearing state (synced)
var current_gear: int = 1
var current_rpm: float = 1000.0
var clutch_value: float = 0.0
var rpm_ratio: float = 0.0

# Trick/boost state (synced)
var is_boosting: bool = false
var boost_count: int = 2

# Crash state (synced)
var is_crashed: bool = false

# Discrete actions (rb_* pattern)
var rb_gear_up: bool = false
var rb_gear_down: bool = false
var rb_activate_boost: bool = false
# rb_do_respawn already exists
```

Update RollbackSynchronizer state_properties:
```
state_properties = Array[String]([
    ":global_transform",
    ":velocity",
    ":speed",
    ":lean_angle",
    ":pitch_angle",
    ":fishtail_angle",
    ":current_gear",
    ":current_rpm",
    ":is_boosting",
    ":is_crashed",
    "%MovementController:current_speed",
    "%MovementController:angular_velocity"
])
```

### 1.4 Create GearingController

New component at `entities/player/controllers/gearing_controller.gd`:

```gdscript
@tool
class_name GearingController extends Node

signal gear_changed(new_gear: int)
signal engine_stalled
signal engine_started

@export var player_entity: PlayerEntity
@export var input_controller: InputController

# Clutch config (can move to BikeSkinDefinition later)
@export var clutch_engage_speed: float = 6.0
@export var clutch_release_speed: float = 2.5
@export var clutch_tap_amount: float = 0.35

var clutch_hold_time: float = 0.0
var is_stalled: bool = false


func _ready():
    if Engine.is_editor_hint():
        return
    input_controller.clutch_held_changed.connect(_on_clutch_input)
    input_controller.gear_up_pressed.connect(_on_gear_up)
    input_controller.gear_down_pressed.connect(_on_gear_down)


## Called from MovementController._rollback_tick()
func process_gearing(delta: float):
    _update_clutch(delta)
    _blend_rpm_to_target(delta)
    _apply_rpm_limits()
    player_entity.rpm_ratio = _get_rpm_ratio()


func _update_clutch(delta: float):
    if input_controller.clutch_held:
        clutch_hold_time += delta
        player_entity.clutch_value = move_toward(
            player_entity.clutch_value, 1.0, clutch_engage_speed * delta
        )
    else:
        clutch_hold_time = 0.0
        player_entity.clutch_value = move_toward(
            player_entity.clutch_value, 0.0, clutch_release_speed * delta
        )


func _blend_rpm_to_target(delta: float):
    var bd = player_entity.bike_definition
    var engagement = get_clutch_engagement()

    # Calculate wheel-driven RPM
    var gear_ratio = bd.gear_ratios[player_entity.current_gear - 1]
    var gear_max_speed = bd.max_speed * (bd.gear_ratios[bd.num_gears - 1] / gear_ratio)
    var speed_ratio = player_entity.speed / gear_max_speed if gear_max_speed > 0 else 0.0
    var wheel_rpm = speed_ratio * bd.max_rpm

    # Throttle-driven RPM
    var throttle_rpm = lerpf(bd.idle_rpm, bd.max_rpm, input_controller.throttle)

    # Blend based on clutch engagement
    var target_rpm = lerpf(throttle_rpm, wheel_rpm, engagement)
    player_entity.current_rpm = lerpf(player_entity.current_rpm, target_rpm, 8.0 * delta)


func _apply_rpm_limits():
    var bd = player_entity.bike_definition
    player_entity.current_rpm = clamp(player_entity.current_rpm, bd.idle_rpm, bd.max_rpm)


func _get_rpm_ratio() -> float:
    var bd = player_entity.bike_definition
    if bd.max_rpm <= bd.idle_rpm:
        return 0.0
    return (player_entity.current_rpm - bd.idle_rpm) / (bd.max_rpm - bd.idle_rpm)


## Returns power multiplier (0-1) based on current RPM and gear
func get_power_output() -> float:
    if is_stalled:
        return 0.0

    var engagement = get_clutch_engagement()
    if engagement < 0.05:
        return 0.0

    var rpm_ratio = _get_rpm_ratio()
    var power_curve = rpm_ratio * (2.0 - rpm_ratio)  # Peaks around 75% RPM

    var bd = player_entity.bike_definition
    var gear_ratio = bd.gear_ratios[player_entity.current_gear - 1]
    var base_ratio = bd.gear_ratios[bd.num_gears - 1]
    var torque_multiplier = gear_ratio / base_ratio

    return input_controller.throttle * power_curve * torque_multiplier * engagement


func get_clutch_engagement() -> float:
    return 1.0 - player_entity.clutch_value


func _on_clutch_input(_held: bool, just_pressed: bool):
    if just_pressed:
        player_entity.clutch_value = minf(
            player_entity.clutch_value + clutch_tap_amount, 1.0
        )


func _on_gear_up():
    player_entity.rb_gear_up = true


func _on_gear_down():
    player_entity.rb_gear_down = true


func shift_gear(direction: int):
    var bd = player_entity.bike_definition
    var new_gear = clamp(player_entity.current_gear + direction, 1, bd.num_gears)
    if new_gear != player_entity.current_gear:
        player_entity.current_gear = new_gear
        gear_changed.emit(new_gear)
```

### 1.5 Create TrickController

New component at `entities/player/controllers/trick_controller.gd`:

```gdscript
@tool
class_name TrickController extends Node

signal trick_started(trick_type: int)
signal trick_ended(trick_type: int)
signal boost_started
signal boost_ended

enum Trick { NONE, WHEELIE_SITTING, WHEELIE_STANDING, STOPPIE, FISHTAIL }

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var gearing_controller: GearingController

@export var boost_duration: float = 2.0
@export var boost_speed_multiplier: float = 1.5

var _boost_timer: float = 0.0
var _last_trick: Trick = Trick.NONE


func _ready():
    if Engine.is_editor_hint():
        return


## Called from MovementController._rollback_tick()
func process_tricks(delta: float):
    _update_wheelie(delta)
    _update_stoppie(delta)
    _update_boost(delta)
    _detect_trick_changes()


func _update_wheelie(delta: float):
    var bd = player_entity.bike_definition
    var in_wheelie = player_entity.pitch_angle > deg_to_rad(15)

    # Wheelie initiation: lean back + high RPM + throttle
    var rpm_above_threshold = player_entity.rpm_ratio >= bd.wheelie_rpm_threshold
    var can_pop = (input_controller.lean > 0.3 and
                   input_controller.throttle > 0.7 and
                   rpm_above_threshold)
    var fast_enough = player_entity.speed > 1

    var wheelie_target = 0.0
    if fast_enough and player_entity.is_on_floor() and (in_wheelie or can_pop):
        if input_controller.throttle > 0.3:
            wheelie_target = deg_to_rad(bd.max_wheelie_angle_deg) * input_controller.throttle
            if input_controller.lean > 0:
                wheelie_target += deg_to_rad(bd.max_wheelie_angle_deg) * input_controller.lean * 0.15

    # Apply wheelie pitch
    if wheelie_target > 0:
        player_entity.pitch_angle = move_toward(
            player_entity.pitch_angle, wheelie_target, bd.rotation_speed * delta
        )
    elif player_entity.pitch_angle > 0:
        # Return to ground, lean forward helps
        var return_mult = 1.0
        if input_controller.lean < 0:
            return_mult = 1.0 + abs(input_controller.lean) * 2.0
        player_entity.pitch_angle = move_toward(
            player_entity.pitch_angle, 0, bd.return_speed * return_mult * delta
        )


func _update_stoppie(delta: float):
    var bd = player_entity.bike_definition
    var in_stoppie = player_entity.pitch_angle < deg_to_rad(-10)

    # Stoppie: lean forward + front brake
    var wants_stoppie = (input_controller.lean < -0.1 and
                         input_controller.front_brake > 0.5)

    # Scale max angle by speed
    var speed_scale = clamp(player_entity.speed / 15.0, 0.0, 1.0)
    var effective_max = deg_to_rad(bd.max_stoppie_angle_deg) * speed_scale

    var stoppie_target = 0.0
    if player_entity.speed > 1 and player_entity.is_on_floor() and (in_stoppie or wants_stoppie):
        stoppie_target = -effective_max * input_controller.front_brake

    # Apply stoppie pitch
    if stoppie_target < 0:
        player_entity.pitch_angle = move_toward(
            player_entity.pitch_angle, stoppie_target, bd.rotation_speed * delta
        )
    elif player_entity.pitch_angle < 0:
        player_entity.pitch_angle = move_toward(
            player_entity.pitch_angle, 0, bd.return_speed * delta
        )


func _update_boost(delta: float):
    if not player_entity.is_boosting:
        return

    _boost_timer -= delta
    if _boost_timer <= 0:
        player_entity.is_boosting = false
        boost_ended.emit()


func activate_boost():
    if player_entity.is_boosting or player_entity.boost_count <= 0:
        return

    player_entity.boost_count -= 1
    player_entity.is_boosting = true
    _boost_timer = boost_duration
    boost_started.emit()


func get_effective_max_speed() -> float:
    var bd = player_entity.bike_definition
    if player_entity.is_boosting:
        return bd.max_speed * boost_speed_multiplier
    return bd.max_speed


func _detect_trick_changes():
    var current = _detect_current_trick()
    if current != _last_trick:
        if _last_trick != Trick.NONE:
            trick_ended.emit(_last_trick)
        if current != Trick.NONE:
            trick_started.emit(current)
        _last_trick = current


func _detect_current_trick() -> Trick:
    if player_entity.pitch_angle > deg_to_rad(15):
        if input_controller.trick:
            return Trick.WHEELIE_STANDING
        return Trick.WHEELIE_SITTING
    elif player_entity.pitch_angle < deg_to_rad(-10):
        return Trick.STOPPIE
    elif abs(player_entity.fishtail_angle) > deg_to_rad(10):
        return Trick.FISHTAIL
    return Trick.NONE
```

### 1.6 Extend MovementController

Update to use gearing and trick systems:

```gdscript
# In movement_controller.gd - REPLACE/EXTEND

@export var gearing_controller: GearingController
@export var trick_controller: TrickController

func _rollback_tick(delta: float, _tick: int, _is_fresh: bool):
    if Engine.is_editor_hint():
        return

    # Handle discrete actions
    if player_entity.rb_gear_up:
        gearing_controller.shift_gear(1)
        player_entity.rb_gear_up = false
    if player_entity.rb_gear_down:
        gearing_controller.shift_gear(-1)
        player_entity.rb_gear_down = false
    if player_entity.rb_activate_boost:
        trick_controller.activate_boost()
        player_entity.rb_activate_boost = false
    if player_entity.rb_do_respawn:
        player_entity.on_respawn()
        player_entity.rb_do_respawn = false

    # Process systems (ORDER MATTERS)
    gearing_controller.process_gearing(delta)
    trick_controller.process_tricks(delta)
    _process_physics(delta)

    # Apply movement
    player_entity.velocity *= NetworkTime.physics_factor
    player_entity.move_and_slide()
    player_entity.velocity /= NetworkTime.physics_factor


func _process_physics(delta: float):
    var bd = player_entity.bike_definition

    # Gravity
    if not player_entity.is_on_floor():
        player_entity.velocity.y -= 9.8 * delta * 4.0  # gravity_mult
        return

    # Acceleration (uses gearing power output)
    var power = gearing_controller.get_power_output()
    var effective_max = trick_controller.get_effective_max_speed()

    if power > 0 and player_entity.speed < effective_max:
        player_entity.speed += bd.acceleration * power * delta
        player_entity.speed = minf(player_entity.speed, effective_max)

    # Braking
    var total_brake = input_controller.front_brake + input_controller.rear_brake
    if total_brake > 0:
        player_entity.speed = move_toward(
            player_entity.speed, 0, bd.brake_strength * total_brake * delta
        )
    elif input_controller.throttle == 0:
        # Engine braking
        player_entity.speed = move_toward(
            player_entity.speed, 0, bd.engine_brake_strength * delta
        )

    # Steering (only when moving)
    if player_entity.speed > 2:
        var turn_rate = _get_turn_rate()
        player_entity.rotate_y(-player_entity.lean_angle * turn_rate * delta)

    # Lean
    var target_lean = input_controller.steer * bd.max_lean_angle_rad
    if player_entity.is_boosting:
        target_lean *= 0.5  # Reduce steering during boost
    player_entity.lean_angle = lerpf(
        player_entity.lean_angle, target_lean, bd.lean_speed * delta
    )

    # Apply velocity following slope
    var forward = -player_entity.global_transform.basis.z
    if player_entity.is_on_floor():
        player_entity.velocity = forward.slide(
            player_entity.get_floor_normal()
        ).normalized() * player_entity.speed
    else:
        player_entity.velocity = forward * player_entity.speed


func _get_turn_rate() -> float:
    var bd = player_entity.bike_definition
    var speed_pct = player_entity.speed / bd.max_speed
    var turn_radius = lerpf(bd.min_turn_radius, bd.max_turn_radius, speed_pct)
    return bd.turn_speed / turn_radius
```

### 1.7 Create CrashController

New component at `entities/player/controllers/crash_controller.gd`:

```gdscript
@tool
class_name CrashController extends Node

signal crashed
signal respawned

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var animation_controller: AnimationController

@export var crash_lean_threshold_deg: float = 80.0
@export var brake_grab_time_threshold: float = 0.4

var _brake_grab_timer: float = 0.0
var _brake_was_zero: bool = true
var _brake_was_grabbed: bool = false


func _ready():
    if Engine.is_editor_hint():
        return


## Called from MovementController after physics
func check_crash():
    if player_entity.is_crashed:
        return

    _update_brake_grab()

    var bd = player_entity.bike_definition

    # Wheelie crash
    if player_entity.pitch_angle > deg_to_rad(bd.max_wheelie_angle_deg):
        trigger_crash()
        return

    # Stoppie crash
    if player_entity.pitch_angle < -deg_to_rad(bd.max_stoppie_angle_deg):
        trigger_crash()
        return

    # Lean crash
    if abs(player_entity.lean_angle) >= deg_to_rad(crash_lean_threshold_deg):
        trigger_crash()
        return

    # Brake grab while turning
    if _brake_was_grabbed and abs(player_entity.lean_angle) > deg_to_rad(15):
        trigger_crash()


func _update_brake_grab():
    var front_brake = input_controller.front_brake

    if front_brake < 0.5:
        _brake_was_zero = true
        _brake_grab_timer = 0.0
        _brake_was_grabbed = false
    elif _brake_was_zero and front_brake > 0.1:
        _brake_was_zero = false
        _brake_grab_timer = 0.0
    elif not _brake_was_zero:
        _brake_grab_timer += get_physics_process_delta_time()
        if front_brake > 0.9 and not _brake_was_grabbed:
            _brake_was_grabbed = _brake_grab_timer < brake_grab_time_threshold


func trigger_crash():
    player_entity.is_crashed = true
    player_entity.speed = 0
    player_entity.velocity = Vector3.ZERO
    animation_controller.start_ragdoll()
    crashed.emit()

    # Auto-respawn after delay
    get_tree().create_timer(3.0).timeout.connect(_auto_respawn)


func _auto_respawn():
    if player_entity.is_crashed:
        player_entity.rb_do_respawn = true


func is_front_wheel_locked() -> bool:
    return _brake_was_grabbed
```

### 1.8 Wire Components in Scene

Update `player_entity.tscn`:

1. Add new controller nodes under `_Controllers`:
   - `GearingController`
   - `TrickController`
   - `CrashController`

2. Wire exports in inspector:
   - `GearingController.player_entity` → PlayerEntity
   - `GearingController.input_controller` → InputController
   - `TrickController.player_entity` → PlayerEntity
   - `TrickController.input_controller` → InputController
   - `TrickController.gearing_controller` → GearingController
   - `CrashController.player_entity` → PlayerEntity
   - `CrashController.input_controller` → InputController
   - `CrashController.animation_controller` → AnimationController
   - `MovementController.gearing_controller` → GearingController
   - `MovementController.trick_controller` → TrickController

3. Add to PlayerEntity exports:
   ```gdscript
   @export var gearing_controller: GearingController
   @export var trick_controller: TrickController
   @export var crash_controller: CrashController
   ```

### 1.9 Integrate with AnimationController

The AnimationController already has `set_bike_pitch()` in its public API (see [AnimationController.md](AnimationController.md)). TrickController should call this API rather than setting rotation directly.

**In TrickController** - after updating pitch_angle, call the animation API:

```gdscript
## Called from MovementController._rollback_tick()
func process_tricks(delta: float):
    _update_wheelie(delta)
    _update_stoppie(delta)
    _update_boost(delta)
    _detect_trick_changes()

    # Update visual via AnimationController API
    # Normalize pitch_angle to -1..1 range for the API
    var bd = player_entity.bike_definition
    var max_angle = maxf(deg_to_rad(bd.max_wheelie_angle_deg), deg_to_rad(bd.max_stoppie_angle_deg))
    var normalized_pitch = player_entity.pitch_angle / max_angle if max_angle > 0 else 0.0
    animation_controller.set_bike_pitch(normalized_pitch)
```

**Add @export to TrickController**:
```gdscript
@export var animation_controller: AnimationController
```

The AnimationController already handles:
- `set_bike_pitch(amount)` - rotates `BikeSkin` on X axis for wheelie/stoppie
- `set_lean(amount)` - already driven by `input_controller.steer` internally
- `set_weight_shift(amount)` - already driven by `input_controller.lean` internally

**Note**: The existing AnimationController reads from `input_controller` directly for lean/weight-shift, but we need `pitch_angle` from physics. The cleanest approach is to have TrickController call `set_bike_pitch()` each tick.

### Milestone 1 Deliverable

- [ ] Ride with gears (manual shifting via gear_up/gear_down inputs)
- [ ] RPM-based power output affects acceleration
- [ ] Clutch modulates engine-to-wheel connection
- [ ] Wheelie and stoppie physics work (pitch_angle)
- [ ] Lean physics work (lean_angle)
- [ ] Crash detection triggers ragdoll + respawn
- [ ] Visual pitch/lean on VisualRoot
- [ ] Syncs in multiplayer (2 clients, no desync)

---

## Milestone 2: Polish & Scoring

> Fishtail, boost, audio, trick scoring

### 2.1 Add Fishtail to TrickController

```gdscript
func _update_fishtail(delta: float):
    var rear_braking = input_controller.rear_brake > 0.5
    var turning = abs(input_controller.steer) > 0.3

    if rear_braking and turning and player_entity.speed > 20:
        var target = sign(input_controller.steer) * deg_to_rad(30)
        player_entity.fishtail_angle = move_toward(
            player_entity.fishtail_angle, target, 8.0 * delta
        )
    else:
        player_entity.fishtail_angle = move_toward(
            player_entity.fishtail_angle, 0, 3.0 * delta
        )
```

### 2.2 Create TrickManager (Scoring)

New manager at `managers/trick_manager.gd`:

```gdscript
class_name TrickManager extends BaseManager

signal trick_started(peer_id: int, trick_type: int)
signal trick_ended(peer_id: int, trick_type: int, score: float)
signal combo_updated(peer_id: int, combo: int, multiplier: float)

const TRICK_DATA = {
    1: {"name": "Sitting Wheelie", "points_per_sec": 10.0},
    2: {"name": "Standing Wheelie", "points_per_sec": 20.0},
    3: {"name": "Stoppie", "points_per_sec": 15.0},
    4: {"name": "Fishtail", "points_per_sec": 8.0},
}

var _active_tricks: Dictionary = {}  # peer_id → {trick, start_time, score}
var _scores: Dictionary = {}         # peer_id → total_score
var _combos: Dictionary = {}         # peer_id → {count, multiplier, timer}

func register_player(peer_id: int, player: PlayerEntity):
    player.trick_controller.trick_started.connect(
        func(t): _on_trick_started(peer_id, t)
    )
    player.trick_controller.trick_ended.connect(
        func(t): _on_trick_ended(peer_id, t)
    )
    _scores[peer_id] = 0.0
    _combos[peer_id] = {"count": 0, "multiplier": 1.0, "timer": 0.0}
```

### 2.3 Extend CameraController

Add FOV scaling:

```gdscript
# In camera_controller.gd - ADD

@export var min_fov: float = 70.0
@export var max_fov: float = 90.0
@export var fov_smoothing: float = 0.1

func _process(delta: float):
    if not player_entity or not player_entity.is_local_client:
        return
    _update_fov()

func _update_fov():
    var bd = player_entity.bike_definition
    var speed_ratio = player_entity.speed / bd.max_speed
    var target_fov = lerpf(min_fov, max_fov, speed_ratio)

    var cam = get_current_camera()
    if cam:
        cam.fov = lerpf(cam.fov, target_fov, fov_smoothing)
```

### 2.4 Add Vibration to InputController

```gdscript
# In input_controller.gd

func _physics_process(delta: float):
    if not player_entity or not player_entity.is_local_client:
        return
    _update_vibration()

func _update_vibration():
    var weak = 0.0
    var strong = 0.0

    # Fishtail vibration
    var fishtail_intensity = abs(player_entity.fishtail_angle) / deg_to_rad(30)
    if fishtail_intensity > 0.1:
        weak += fishtail_intensity * 0.6
        strong += fishtail_intensity * fishtail_intensity * 0.8

    # Redline vibration
    if player_entity.rpm_ratio > 0.9:
        weak += 0.3
        strong += 0.5

    add_vibration(weak, strong)
```

### Milestone 2 Deliverable

- [ ] Fishtail/drift physics work
- [ ] TrickManager tracks scores across players
- [ ] Combo system with multiplier
- [ ] Camera FOV scales with speed
- [ ] Controller vibration for fishtail/redline
- [ ] Boost activation (double-tap trick button)

---

## Milestone 3: Audio & HUD

> Engine audio, visual polish, HUD elements

### 3.1 AudioController or Integration

Either create new AudioController or integrate with AudioManager:

```gdscript
func _update_engine_audio():
    if not player_entity.is_local_client:
        return

    var bd = player_entity.bike_definition
    var rpm_ratio = player_entity.rpm_ratio

    engine_audio.pitch_scale = lerpf(0.8, 2.0, rpm_ratio)
    if player_entity.is_boosting:
        engine_audio.pitch_scale *= 1.2
```

### 3.2 Create GameHUD

Shows per-player:
- Speed (km/h or mph)
- Gear indicator (1-6)
- RPM bar with redline
- Trick feed from TrickManager
- Boost count

### 3.3 Polish AnimationController

- Trick-specific animations (standing wheelie pose)
- Crash animations with direction
- Land settle animation

### Milestone 3 Deliverable

- [ ] Engine audio responds to RPM
- [ ] HUD shows speed, gear, RPM
- [ ] Trick feed shows active tricks
- [ ] Additional animations (standing wheelie, etc.)

---

## Reference

### Synced State (RollbackSynchronizer state_properties)

```
:global_transform
:velocity
:speed
:lean_angle
:pitch_angle
:fishtail_angle
:current_gear
:current_rpm
:clutch_value
:is_boosting
:is_crashed
```

### Synced Input (RollbackSynchronizer input_properties)

```
%InputController:throttle
%InputController:front_brake
%InputController:rear_brake
%InputController:steer
%InputController:lean
%InputController:trick
```

### Discrete Actions (rb_* pattern)

```
rb_gear_up
rb_gear_down
rb_activate_boost
rb_do_respawn
```

### Processing Order in _rollback_tick()

```
1. Handle rb_* discrete actions
2. gearing_controller.process_gearing()  - RPM, power output
3. trick_controller.process_tricks()     - wheelie/stoppie angles, boost
4. _process_physics()                    - velocity from speed/steering
5. crash_controller.check_crash()        - angle thresholds
6. move_and_slide()
```

### Component Wiring

```
PlayerEntity
├── @export gearing_controller → GearingController
├── @export trick_controller → TrickController
├── @export crash_controller → CrashController
├── @export movement_controller → MovementController
├── @export input_controller → InputController
├── @export camera_controller → CameraController
└── @export animation_controller → AnimationController

MovementController
├── @export gearing_controller → GearingController
└── @export trick_controller → TrickController

GearingController
├── @export player_entity → PlayerEntity
└── @export input_controller → InputController

TrickController
├── @export player_entity → PlayerEntity
├── @export input_controller → InputController
├── @export gearing_controller → GearingController
└── @export animation_controller → AnimationController

CrashController
├── @export player_entity → PlayerEntity
├── @export input_controller → InputController
└── @export animation_controller → AnimationController
```