# Migration Guide: Moto Player Controller → DankNooner v2

> Porting singleplayer player controller from `moto-player-controller/` to multiplayer

## Overview

**Source**: `TMP_/` - copied from moto-player-controller singleplayer demo
**Target**: `entities/player/` - existing PlayerEntity with netfox

### Design Goals

1. **Simplify** - flatten component hierarchy, inline where possible
2. **Multiplayer-first** - all physics in `_rollback_tick()`, proper sync
3. **Separate concerns** - PlayerEntity owns physics, TrickManager owns scoring

### Current v2 State

- PlayerEntity with MovementController (basic physics)
- InputController (throttle, brake, steer, lean)
- CameraController, MeshComponent, BikeDefinition
- RollbackSynchronizer + TickInterpolator configured

### Migration Summary

| From TMP_/                | Action      | Notes                                      |
| ------------------------- | ----------- | ------------------------------------------ |
| BikeState                 | **FLATTEN** | Properties go directly on PlayerEntity     |
| BikePhysics               | **INLINE**  | Replace MovementController, ~80 lines      |
| BikeGearing               | **INLINE**  | Add to PlayerEntity, ~50 lines             |
| BikeTricks (physics)      | **INLINE**  | Wheelie/stoppie angles, boost, ~60 lines   |
| BikeTricks (scoring)      | **MOVE**    | → TrickManager (new manager)               |
| BikeCrash                 | **INLINE**  | Crash detection + brake grab, ~40 lines    |
| BikeAnimation             | **DEFER**   | Milestone 3 (lean visuals, rider IK)       |
| BikeAudio                 | **INLINE**  | Simple engine pitch function, ~15 lines    |
| BikeUI                    | **DEFER**   | Milestone 3 (HUD)                          |
| BikeCamera                | **MERGE**   | Extend existing CameraController           |
| BikeInput                 | **EXTEND**  | Add rear_brake, trick to InputController   |
| BikeResource              | **EXTEND**  | Add gearing/physics to BikeDefinition      |
| IKCharacterMesh           | **DEFER**   | Milestone 3 (rider mesh)                   |
| BikeComponent base class  | **DROP**    | Not needed, use @export references         |
| Difficulty modes          | **DROP**    | Start with manual shifting only            |

---

## Simplified Architecture

```
PlayerEntity (CharacterBody3D)
├── Synced state (RollbackSynchronizer):
│   ├── global_transform, velocity
│   ├── speed, lean_angle, pitch_angle, fishtail_angle
│   ├── current_gear, current_rpm
│   └── is_boosting
│
├── Synced input:
│   └── throttle, front_brake, rear_brake, steer, lean, trick
│
├── Discrete actions (rb_* pattern):
│   └── rb_gear_up, rb_gear_down, rb_activate_boost, rb_do_respawn
│
├── _rollback_tick():
│   ├── process_gearing()       # RPM, gear shifts
│   ├── process_trick_physics() # wheelie/stoppie angles, boost
│   ├── process_physics()       # acceleration, steering, velocity
│   └── check_crash()           # angle thresholds, brake grab
│
├── Signals:
│   └── trick_changed(type), crashed, respawned
│
├── Components (existing):
│   ├── InputController         # extended with rear_brake, trick
│   ├── CameraController        # extended with FOV scaling, crash cam
│   └── MeshComponent           # unchanged
│
├── Local-only (guarded by is_local_client):
│   └── _update_engine_audio()  # inline function
│
└── BikeDefinition (Resource)   # extended with gearing/physics tuning

TrickManager (new Manager)
├── Observes all PlayerEntities via trick_changed signal
├── Tracks active tricks, durations
├── Scoring, combos, multipliers
└── Emits signals for UI/leaderboards
```

---

## Milestone 1: Core Physics

> Get the bike feeling right with gearing and basic tricks

### 1.1 Extend InputController

Add new synced inputs:

```gdscript
# Add to InputController
var rear_brake: float = 0.0
var trick: bool = false

# Add to input_properties in RollbackSynchronizer
"%InputController:rear_brake",
"%InputController:trick"
```

Add discrete action signals (existing pattern):

```gdscript
signal gear_up_pressed
signal gear_down_pressed
```

### 1.2 Extend BikeDefinition

Add gearing and physics tuning:

```gdscript
# Gearing
@export var gear_ratios: Array[float] = [0.4, 0.55, 0.7, 0.85, 0.95, 1.0]
@export var max_rpm: float = 12000.0
@export var idle_rpm: float = 1000.0

# Physics
@export var max_speed: float = 100.0
@export var acceleration: float = 20.0
@export var brake_strength: float = 40.0
@export var max_lean_angle_deg: float = 45.0
@export var lean_speed: float = 3.0

# Wheelie/stoppie
@export var wheelie_threshold_rpm: float = 8000.0
@export var max_wheelie_angle_deg: float = 70.0
@export var max_stoppie_angle_deg: float = 45.0
```

### 1.3 Add State to PlayerEntity

Replace MovementController state with full physics state:

```gdscript
# Synced state (add to RollbackSynchronizer state_properties)
var speed: float = 0.0
var lean_angle: float = 0.0
var pitch_angle: float = 0.0        # + = wheelie, - = stoppie
var fishtail_angle: float = 0.0
var current_gear: int = 1
var current_rpm: float = 1000.0
var is_boosting: bool = false

# Discrete actions
var rb_gear_up: bool = false
var rb_gear_down: bool = false
var rb_activate_boost: bool = false
```

### 1.4 Inline Physics Processing

Replace MovementController with inline functions in PlayerEntity:

```gdscript
func _rollback_tick(delta: float, _tick: int, _is_fresh: bool):
    # Handle discrete actions
    if rb_gear_up:
        _shift_gear(1)
        rb_gear_up = false
    if rb_gear_down:
        _shift_gear(-1)
        rb_gear_down = false
    if rb_do_respawn:
        _on_respawn()
        rb_do_respawn = false

    # Process systems (ORDER MATTERS)
    _process_gearing(delta)
    _process_trick_physics(delta)
    _process_physics(delta)
    _check_crash()
```

**Processing order matters**: Gearing → Tricks → Physics because:
- Gearing calculates RPM and power output
- Tricks modify pitch_angle (wheelie/stoppie)
- Physics reads both to calculate final velocity

### 1.5 Port Key Physics Functions

From `bike_physics.gd`, simplified:

```gdscript
func _process_physics(delta: float):
    if is_on_floor():
        _update_riding(delta)
    else:
        _update_airborne(delta)

    velocity *= NetworkTime.physics_factor
    move_and_slide()

func _update_riding(delta: float):
    # Acceleration (uses RPM-based power)
    var power = _get_power_output()
    var throttle = input_controller.throttle
    speed = move_toward(speed, bike_definition.max_speed * power,
                        bike_definition.acceleration * throttle * delta)

    # Braking
    var brake = input_controller.front_brake + input_controller.rear_brake
    speed = move_toward(speed, 0, bike_definition.brake_strength * brake * delta)

    # Steering
    var turn_rate = _get_turn_rate()
    var steer = input_controller.steer
    rotation.y -= steer * turn_rate * delta

    # Lean
    lean_angle = lerp(lean_angle, steer * bike_definition.max_lean_angle,
                      bike_definition.lean_speed * delta)

    # Apply velocity
    velocity = -transform.basis.z * speed
    velocity.y = -9.8 if not is_on_floor() else 0
```

### 1.6 Port Gearing (Simplified)

From `bike_gearing.gd`, no difficulty modes:

```gdscript
func _process_gearing(delta: float):
    # Calculate target RPM from speed and gear
    var gear_ratio = bike_definition.gear_ratios[current_gear - 1]
    var max_speed_for_gear = bike_definition.max_speed * gear_ratio
    var speed_ratio = clamp(speed / max_speed_for_gear, 0.0, 1.0)

    var target_rpm = lerp(bike_definition.idle_rpm, bike_definition.max_rpm, speed_ratio)
    current_rpm = lerp(current_rpm, target_rpm, 5.0 * delta)

func _shift_gear(direction: int):
    var new_gear = clamp(current_gear + direction, 1, bike_definition.gear_ratios.size())
    if new_gear != current_gear:
        current_gear = new_gear

func _get_power_output() -> float:
    # Power curve based on RPM
    var rpm_ratio = (current_rpm - bike_definition.idle_rpm) / \
                    (bike_definition.max_rpm - bike_definition.idle_rpm)
    return clamp(rpm_ratio, 0.1, 1.0)
```

### 1.7 Port Trick Physics (Simplified)

From `bike_tricks.gd`, physics only (no scoring):

```gdscript
func _process_trick_physics(delta: float):
    _update_wheelie(delta)
    _update_stoppie(delta)
    _update_boost(delta)

func _update_wheelie(delta: float):
    var lean_back = input_controller.lean < -0.5
    var has_power = current_rpm > bike_definition.wheelie_threshold_rpm

    if lean_back and has_power and is_on_floor():
        # Pull wheelie up
        pitch_angle = move_toward(pitch_angle,
            deg_to_rad(bike_definition.max_wheelie_angle_deg),
            2.0 * delta)
    elif pitch_angle > 0:
        # Return to ground
        pitch_angle = move_toward(pitch_angle, 0, 3.0 * delta)

func _update_stoppie(delta: float):
    var lean_forward = input_controller.lean > 0.5
    var braking = input_controller.front_brake > 0.5

    if lean_forward and braking and speed > 10 and is_on_floor():
        pitch_angle = move_toward(pitch_angle,
            -deg_to_rad(bike_definition.max_stoppie_angle_deg),
            2.0 * delta)
    elif pitch_angle < 0:
        pitch_angle = move_toward(pitch_angle, 0, 3.0 * delta)

func _update_boost(delta: float):
    if rb_activate_boost and not is_boosting:
        is_boosting = true
        _boost_timer = 2.0
        rb_activate_boost = false

    if is_boosting:
        _boost_timer -= delta
        if _boost_timer <= 0:
            is_boosting = false
```

### 1.8 Port Crash Detection (Simplified)

From `bike_crash.gd`:

```gdscript
func _check_crash():
    var max_wheelie = deg_to_rad(bike_definition.max_wheelie_angle_deg + 10)
    var max_stoppie = deg_to_rad(bike_definition.max_stoppie_angle_deg + 10)
    var max_lean = deg_to_rad(80)

    if pitch_angle > max_wheelie:
        _trigger_crash()
    elif pitch_angle < -max_stoppie:
        _trigger_crash()
    elif abs(lean_angle) > max_lean:
        _trigger_crash()

func _trigger_crash():
    rb_do_respawn = true  # For now, just respawn
    crashed.emit()
```

### Milestone 1 Deliverable

- Ride with gears (manual shifting)
- Wheelie and stoppie physics work
- Boost works
- Crash detection triggers respawn
- Syncs in multiplayer (2 clients, no desync)

---

## Milestone 2: TrickManager & Polish

> Scoring system and feel improvements

### 2.1 Create TrickManager

New manager that observes PlayerEntities:

```gdscript
class_name TrickManager extends BaseManager

var _active_tricks: Dictionary = {}  # peer_id → {trick, start_time, score}

func _ready():
    # Connect to all spawned players
    pass

func _on_player_trick_changed(peer_id: int, trick_type: int):
    if trick_type != Trick.NONE:
        _start_trick(peer_id, trick_type)
    else:
        _end_trick(peer_id)

func _start_trick(peer_id: int, trick_type: int):
    _active_tricks[peer_id] = {
        "trick": trick_type,
        "start_time": Time.get_ticks_msec(),
        "score": 0
    }
    trick_started.emit(peer_id, trick_type)

func _end_trick(peer_id: int):
    if peer_id in _active_tricks:
        var data = _active_tricks[peer_id]
        var duration = (Time.get_ticks_msec() - data.start_time) / 1000.0
        var score = _calculate_score(data.trick, duration)
        trick_ended.emit(peer_id, data.trick, score)
        _active_tricks.erase(peer_id)
```

### 2.2 Extend CameraController

Add from `bike_camera.gd`:

```gdscript
# FOV scaling with speed
func _process(delta: float):
    if not is_local_client: return
    _update_fov()
    _update_auto_reset(delta)

func _update_fov():
    var speed_ratio = player.speed / player.bike_definition.max_speed
    var target_fov = lerp(70.0, 90.0, speed_ratio)
    current_camera.fov = lerp(current_camera.fov, target_fov, 0.1)
```

### 2.3 Add Engine Audio

Simple inline function in PlayerEntity:

```gdscript
@onready var engine_audio: AudioStreamPlayer3D = %EngineAudio

func _process(delta: float):
    if is_local_client:
        _update_engine_audio()

func _update_engine_audio():
    var rpm_ratio = (current_rpm - bike_definition.idle_rpm) / \
                    (bike_definition.max_rpm - bike_definition.idle_rpm)
    engine_audio.pitch_scale = lerp(0.8, 2.0, rpm_ratio)

    if is_boosting:
        engine_audio.pitch_scale *= 1.2
```

### 2.4 Add Fishtail/Drift

```gdscript
func _update_fishtail(delta: float):
    var rear_braking = input_controller.rear_brake > 0.3
    var turning = abs(input_controller.steer) > 0.3

    if rear_braking and turning and speed > 20:
        var target = sign(input_controller.steer) * deg_to_rad(30)
        fishtail_angle = move_toward(fishtail_angle, target, 3.0 * delta)
    else:
        fishtail_angle = move_toward(fishtail_angle, 0, 5.0 * delta)
```

### 2.5 Brake Grab System

From `bike_crash.gd` - critical for feel:

```gdscript
var _brake_grab_timer: float = 0.0
var _last_brake_value: float = 0.0
var _is_wheel_locked: bool = false

func _update_brake_grab(delta: float):
    var brake = input_controller.front_brake

    # Detect 0→100% in < 0.4s
    if brake > 0.9 and _last_brake_value < 0.1:
        if _brake_grab_timer < 0.4:
            _is_wheel_locked = true

    if brake < 0.1:
        _brake_grab_timer = 0.0
        _is_wheel_locked = false
    else:
        _brake_grab_timer += delta

    _last_brake_value = brake

    # Locked wheel while turning = crash
    if _is_wheel_locked and abs(input_controller.steer) > 0.3:
        _trigger_crash()
```

### Milestone 2 Deliverable

- TrickManager tracks scores across all players
- Fishtail/drift works
- Brake grab causes crashes (feels right)
- Engine audio responds to RPM
- Camera FOV scales with speed

---

## Milestone 3: Visuals & Polish

> Character mesh, animations, HUD

### 3.1 Character Mesh & IK

- Import Mixamo-compatible character
- Add IK targets for rider positioning
- Implement ragdoll for crashes

### 3.2 Bike Animation

Rotate mesh based on lean/pitch:

```gdscript
func _update_bike_visuals():
    if not is_local_client: return

    # Lean rotation (Z axis)
    mesh_node.rotation.z = -lean_angle

    # Pitch rotation (X axis) for wheelie/stoppie
    mesh_node.rotation.x = pitch_angle
```

### 3.3 HUD (BikeUI)

- Speed display
- Gear indicator
- RPM bar
- Trick feed from TrickManager

### 3.4 Editor Tooling

- Extend auto_validator for new properties
- Add @tool previews for bike tuning

### Milestone 3 Deliverable

- Rider visible on bike with IK
- Ragdoll on crash
- HUD shows game state
- Can create new bikes via BikeDefinition

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
:is_boosting
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

### Signals (PlayerEntity)

```
trick_changed(trick_type: int)
crashed()
respawned()
```

### Processing Order in _rollback_tick()

```
1. Handle rb_* discrete actions
2. process_gearing()     - RPM, power output
3. process_trick_physics() - wheelie/stoppie angles, boost
4. process_physics()     - velocity from speed/steering
5. check_crash()         - angle thresholds
6. move_and_slide()
```

Physics depends on gearing (power) and tricks (angles), so they run first.
