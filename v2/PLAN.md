# Wheelie Physics Implementation Plan

## Overview

Replace raw `pitch_angle -= nfx_lean * delta` in movement_controller with full wheelie physics: RPM/clutch-dump initiation, balance point zone, and lean recovery. Trick_controller stays as a pure classifier.

## movement_controller.gd Changes

### New State

```gdscript
var _prev_clutch_held: bool = false
var _clutch_kick_window: float = 0.0
var _balance_point_decay_mult: float = 0.25
const CLUTCH_KICK_WINDOW: float = 0.4
```

### `_pitch_angle_calc(delta)` — Orchestrator

Replaces current raw lean logic.

1. `_update_clutch_dump_detection()`
2. `wheelie_target = _calc_wheelie_target(delta)`
3. If `wheelie_target > 0`: `move_toward` target at `rotation_speed` (use `_balance_point_decay_mult` when in balance zone)
4. Elif `pitch_angle > 0`: `move_toward 0` at `return_speed` (slower decay in balance zone)
5. Lean forward recovery: if `nfx_lean > 0` and in wheelie, `move_toward(0, return_speed * lean * 2)`
6. `# TODO: rear brake pull-down`
7. `# TODO: easy mode clamp`

### `_update_clutch_dump_detection()`

- Compare `input_controller.clutch_held` vs `_prev_clutch_held`
- On release (was held -> not held) while `nfx_throttle > 0.5`: set `_clutch_kick_window = CLUTCH_KICK_WINDOW`
- Decrement `_clutch_kick_window` each tick
- Store `_prev_clutch_held = input_controller.clutch_held`

### `_calc_wheelie_target(delta) -> float`

**Initiation checks:**
- Already in wheelie (`pitch_angle > wheelie_threshold`) OR all of:
  - `nfx_lean < -0.3` (lean back)
  - `nfx_throttle > 0.7`
  - RPM above `bike_definition.wheelie_rpm_threshold` OR `_clutch_kick_window > 0`
  - Not turning (`abs(roll_angle) < small threshold`)
  - `speed > 1`

**Normal zone** (below balance point):
- `target = max_wheelie_angle_rad * throttle`
- Lean back adds 15% extra: `target += max_wheelie_angle_rad * abs(nfx_lean) * 0.15`

**Balance point zone** (above `wheelie_balance_point_deg`):
- Lean input adjusts target within zone
- `lean_influence = nfx_lean * (max_wheelie_angle_rad - balance_point_rad)`
- `balance_target = pitch_angle + lean_influence * 0.75`
- Throttle >= 0.5: can push higher, `target = max(wheelie_target, balance_target)`
- Throttle < 0.5: unstable drift
  - Below midpoint of zone: drifts down via `move_toward(balance_target, 0, delta)`
  - Above midpoint: drifts toward crash via `move_toward(balance_target, max_wheelie_angle + small_margin, delta)`

**Returns 0.0** if no wheelie conditions met.

### `do_reset()` Update

Add: `_prev_clutch_held = false`, `_clutch_kick_window = 0.0`

## trick_controller.gd Changes

### Remove
- `CLUTCH_KICK_WINDOW` const
- `_clutch_kick_window` var
- `_prev_clutch_held` var

### `do_reset()` Update
Remove clutch-related resets (`_clutch_kick_window = 0.0`, `_prev_clutch_held = false`).
Keep: `current_trick = Trick.NONE`, `_last_trick = Trick.NONE`, `movement_controller.pitch_angle = 0`.

### No Changes
- `_detect_current_trick()` — unchanged, reads `movement_controller.pitch_angle`
- Signals, exports, configuration warnings — unchanged

## bike_definition — No Changes

Already has: `max_wheelie_angle_deg`, `wheelie_rpm_threshold`, `wheelie_balance_point_deg`, `rotation_speed`, `return_speed`

## Implementation Order

1. Clean up trick_controller.gd (remove clutch state)
2. Add new state vars to movement_controller.gd
3. Implement `_update_clutch_dump_detection()`
4. Implement `_calc_wheelie_target(delta)`
5. Rewrite `_pitch_angle_calc(delta)` as orchestrator
6. Update `do_reset()`
