# Movement Fix Plan

> Three bugs to fix. Rubber banding is highest priority. Keep code clean.
> Follow practices in CLAUDE.md. Don't remove print() debug statements (except the one hot-path print called out below). Don't remove TODO comments.

## Context

- Godot 4.6, GDScript, multiplayer with netfox rollback
- `PlayerEntity` (CharacterBody3D) uses composition with controller nodes
- Controllers called sequentially from `_rollback_tick()`: movement → gearing → trick → crash
- RollbackSynchronizer syncs state_properties (restored on rollback) and input_properties (synced from authority)
- `is_on_floor_netfox()` zero-velocity move_and_slide is the documented netfox workaround — do NOT remove it

## Task 1: Rubber Banding Fix (HIGHEST PRIORITY)

### 1A: Rename private vars to public for rollback sync

These variables are currently private (underscore prefix) but need to be synced by RollbackSynchronizer, which requires them to be public.

**`player/controllers/movement_controller.gd`:**
- Rename `_air_forward` → `air_forward` (all references in this file)

**`player/controllers/gearing_controller.gd`:**
- Rename `_current_gear` → `current_gear` (all references in this file)
- Rename `_current_rpm` → `current_rpm` (all references in this file)
- Rename `_clutch_value` → `clutch_value` (all references in this file)

Use find-and-replace within each file. Be careful not to rename other `_`-prefixed vars that don't need syncing.

### 1B: Add state properties to RollbackSynchronizer

**`player/player_entity.tscn`:**

Add these to the `state_properties` array on the `RollbackSynchronizer` node (line 124):

```
"%MovementController:air_forward"
"%GearingController:current_gear"
"%GearingController:current_rpm"
"%GearingController:clutch_value"
```

Also add `is_crashed` and `up_direction` for the root PlayerEntity:
```
":is_crashed"
":up_direction"
```

The full state_properties should become:
```
[":global_transform", ":velocity", ":up_direction", ":is_crashed", "%MovementController:pitch_angle", "%MovementController:roll_angle", "%MovementController:speed", "%MovementController:air_forward", "%GearingController:current_gear", "%GearingController:current_rpm", "%GearingController:clutch_value"]
```

Note: `speed` should already be in the list (user added it). If not, add it as `"%MovementController:speed"`.

### 1C: Remove hot-path print statement

**`player/controllers/movement_controller.gd`:**

Remove the print statement in `_update_surface_alignment()` around line 81-85:
```gdscript
# REMOVE THIS — runs every tick for every player, significant perf hit in multiplayer
print(
    (
        "surface: on_floor=true normal=%s angle=%.1f° up_dir=%s speed=%.1f"
        % [floor_normal, rad_to_deg(surface_angle), pe.up_direction, speed]
    )
)
```

This is the ONLY print to remove. All other prints (peel off, gear change, trick, crash) are event-based and should stay.

## Task 2: Loop Flying Fix

**Problem:** `_air_forward` is captured from `-player_entity.global_transform.basis.z` (basis forward). When steering on a loop, the basis is rotated by lean/steer, giving `_air_forward` a skewed direction with excessive upward component.

**`player/controllers/movement_controller.gd` — `_velocity_calc()`:**

Replace the `_air_forward` capture (around line 188):

```gdscript
# Before:
_air_forward = forward

# After:
if player_entity.velocity.length_squared() > 0.01:
    air_forward = player_entity.velocity.normalized()
else:
    air_forward = forward
```

Note: variable is now `air_forward` (no underscore) after Task 1A rename.

This captures the actual travel direction (already surface-projected by the previous tick's `forward.slide(floor_normal)`) instead of the basis forward which is affected by steering rotation.

## Task 3: Clutch Wheelie Hold Fix

**Problem:** Single clutch tap pops wheelie past balance point, where it stays forever with minimal input.

**`player/controllers/movement_controller.gd`:**

### 3A: Shorten clutch kick window
Change `CLUTCH_KICK_WINDOW` from `0.4` to `0.2` (line 11).

### 3B: Make balance point unstable without lean-back
In `_calc_balance_point_target()`, when throttle >= 0.5, also require lean-back input to hold position. If `nfx_lean >= 0` (not leaning back), the target should drift downward:

```gdscript
# Current (holds perfectly with just throttle):
if input_controller.nfx_throttle >= 0.5:
    return maxf(normal_target, balance_target)

# New (requires lean-back to sustain):
if input_controller.nfx_throttle >= 0.5:
    if input_controller.nfx_lean < -0.1:
        return maxf(normal_target, balance_target)
    else:
        # Not leaning back — drift toward falling forward
        return move_toward(balance_target, 0, bd.return_speed * 0.3 * delta)
```

### 3C: Increase no-throttle instability drift
In the same function, replace the slow drift speeds (currently just `delta`) with faster ones:

```gdscript
# Current:
if balance_target < midpoint:
    return move_toward(balance_target, 0, delta)
if balance_target > midpoint:
    return move_toward(balance_target, max_wheelie_rad + deg_to_rad(1), delta)

# New:
if balance_target < midpoint:
    return move_toward(balance_target, 0, bd.return_speed * 0.5 * delta)
if balance_target > midpoint:
    return move_toward(balance_target, max_wheelie_rad + deg_to_rad(1), bd.return_speed * 0.5 * delta)
```

## Files Changed

| File | Tasks |
|------|-------|
| `player/controllers/movement_controller.gd` | 1A, 1C, 2, 3A, 3B, 3C |
| `player/controllers/gearing_controller.gd` | 1A |
| `player/player_entity.tscn` | 1B |

## Execution Order

1. Task 1A (rename vars) — must come first, other tasks reference new names
2. Task 1B (update .tscn) — depends on 1A
3. Task 1C (remove print) — independent
4. Task 2 (loop flying) — uses renamed `air_forward`
5. Task 3A, 3B, 3C (clutch wheelie) — independent of others
