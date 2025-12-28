# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Godot 4.5 motorcycle physics simulation and player controller. Uses GDScript with a component-based architecture where a main `PlayerController` (CharacterBody3D) orchestrates specialized components for physics, gearing, tricks, crash handling, audio, and UI.

## Architecture

### Component System

The player controller ([player_controller.gd](scenes/bike/player_controller.gd)) delegates to six specialized components in `scenes/bike/components/`:

| Component | Responsibility |
|-----------|----------------|
| `BikePhysics` | Speed, acceleration, braking, steering, lean angles, gravity |
| `BikeGearing` | 6-speed transmission, RPM, clutch engagement, gear shifting |
| `BikeTricks` | Wheelies, stoppies, fishtail/skid physics, skid mark spawning |
| `BikeCrash` | Crash detection thresholds, respawn timer, collision handling |
| `BikeAudio` | Engine pitch scaling, tire screech, gear grinding sounds |
| `BikeUI` | HUD elements, controller vibration feedback |

### Communication Pattern

Components communicate via Godot signals. Key signal flows:
- `bike_gearing.gear_grind` → `bike_audio.play_gear_grind()`
- `bike_tricks.skid_mark_requested` → spawns Decal in scene
- `bike_crash.crashed` → triggers crash animation and respawn

### Node References

Uses Godot's unique name syntax (`%NodeName`) for reliable node access. Components receive their dependencies via `setup()` calls in `_ready()`.

### Physics Loop

All physics updates occur in `_physics_process(delta)` with this flow:
1. Check crash state (early return if crashed)
2. Gather input
3. Update gearing/RPM
4. Physics calculations (acceleration, steering, lean)
5. Trick handling (wheelies, stoppies, skidding)
6. Crash detection
7. Apply movement and mesh rotation
8. Update audio/UI
9. `move_and_slide()` and ground alignment

## Key Physics Values

- **BikePhysics:** max_speed=60, acceleration=20, brake_force=25, max_steering=35°, max_lean=45°
- **BikeGearing:** gear_ratios=[2.8, 1.9, 1.4, 1.1, 0.95, 0.8], idle_rpm=1000, max_rpm=9000
- **BikeTricks:** max_wheelie=80°, max_stoppie=50°, wheelie_rpm_range=65%-95%
- **BikeCrash:** wheelie_crash=75°, stoppie_crash=55°, lean_crash=80°

## Input Actions

Defined in `project.godot`. Main inputs: `throttle_pct`, `brake_front_pct`, `brake_rear`, `steer_left/right`, `lean_forward/back`, `clutch`, `gear_up/down`, `trick`, `pause`

## Collision Layers

- Layer 1: Ground/terrain
- Layer 2: Obstacles that trigger crashes on collision

## Current Development Focus

Per README.md - fixing lean/tip-in/steering feel, brake slam behavior, and tweaking physics values for good game feel. Character animation and state machine are future work.
