# HUDController Debug HUD Migration Design

## Goal

Migrate the commented-out Debug HUD region from `player_entity.gd` into `HUDController`, build out the UI scene, and expose data via `@export var` property setters.

## Components

### hud_controller.gd

- `@export var` with `set(v)` for each data input:
  - `speed: float` → SpeedLabel text (overridden by `is_crashed`)
  - `current_gear: int` → GearLabel text
  - `is_stalled: bool` → GearLabel prefix ("STALLED - " prefix)
  - `rpm_ratio: float` → RPMBar value + modulate
  - `throttle: float` → ThrottleBar value + modulate
  - `clutch_value: float` → ClutchBar value + modulate
  - `grip_usage: float` → GripBar value + modulate
  - `last_trick: int` → TrickLabel text + visible
  - `boost_count: int` → BoostLabel text
  - `is_boosting: bool` → BoostLabel suffix + modulate
  - `is_crashed: bool` → SpeedLabel text override

- Each setter assigns value then calls a private `_update_<field>()` func
- Each update func guards with `if not is_node_ready(): return`
- `func show_hud()` / `func hide_hud()` toggle `visible`
- `@onready` refs for all UI nodes via unique names

### hud_controller.tscn

Root: HUDController (Control, full rect anchor)
- VBoxContainer (anchor top-left, offset_left=16, offset_top=16, min_width=250, separation=4)
  - SpeedLabel (Label, unique name)
  - GearLabel (Label, unique name)
  - RPMLabel (Label, text="RPM")
  - RPMBar (ProgressBar, unique name, min_size=(200,20), max=1.0, step=0.01, no percentage)
  - ThrottleLabel (Label, text="Throttle")
  - ThrottleBar (ProgressBar, unique name, same settings)
  - ClutchLabel (Label, text="Clutch")
  - ClutchBar (ProgressBar, unique name, same settings)
  - GripLabel (Label, text="Brake Danger")
  - GripBar (ProgressBar, unique name, same settings)
  - TrickLabel (Label, unique name, visible=false)
  - BoostLabel (Label, unique name)

### player_entity.gd changes

- Remove entire `#region Debug HUD` block (commented code + `_debug_*` var declarations)
- Add `_process(delta)` that sets hud_controller vars when `is_local_client` and `hud_controller != null`
- In `_deferred_init`: call `hud_controller.show_hud()` for local client, `hud_controller.hide_hud()` for remote

## Modulate colors (matching original)

- RPM: >0.9 → red, >0.7 → yellow, else → blue
- Throttle: >0.9 → red, else → green
- Clutch: always orange
- Grip: >0.8 → red, >0.5 → orange, else → green
- Boost active: yellow; inactive: white
