# Slope Physics Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the bike follow ground angles (ramps, loops), with speed-based centrifugal sticking and realistic ramp launches.

**Architecture:** Two raycasts at wheel positions detect ground slope. Movement controller computes a `ground_pitch` angle and redirects velocity along the surface tangent. Entity stays upright for physics stability — all visual slope rotation happens in animation_controller via `visual_root`. On ramp launch, velocity retains its slope direction and gravity creates a natural arc. Angular momentum is conserved for smooth rotation in air.

**Tech Stack:** Godot 4.6, GDScript, netfox rollback, CharacterBody3D

---

## Design Decisions

**Why NOT rotate `player_entity.rotation.x`:** Rotating the CharacterBody3D changes collision shape orientation, which can break `move_and_slide()` floor detection on steep slopes and cause clipping. Instead, we keep the entity upright and handle slope alignment two ways:
1. **Physics:** Compute a slope-aligned forward vector for velocity direction
2. **Visuals:** Add `ground_pitch` to `visual_root.rotation.x` in animation_controller

**Sign convention for `ground_pitch`:** Positive = uphill (front wheel higher than rear). This is the natural slope angle. Animation controller negates it for Godot's rotation.x (where positive = nose down).

**Gravity multiplier:** The existing airborne gravity uses `9.8 * 4.0` for snappy feel. Slope gravity on ground uses `9.8 * 1.0` — the 4x multiplier would make hills feel too punishing.

**Rollback caveat:** `force_raycast_query()` queries the current physics state, not historical state during netfox rollback replays. Ground detection will use stale collision data during reconciliation. This is acceptable — slope angles change slowly and the visual smoothing (lerp) masks any jitter from stale data.

**Wheel position space:** `BikeSkinDefinition.front/rear_wheel_ground_position` are in bike-local space (relative to bike mesh origin). Since `visual_root` starts at entity origin with zero offset, these positions map correctly to entity-local space for raycast placement. If `mesh_position_offset` is non-zero on a bike skin, the ray positions may need adjustment — verify during Task 1 testing.

---

## File Structure

- **Modify:** `entities/player/controllers/movement_controller.gd` — raycasts, ground detection, velocity refactor
- **Modify:** `entities/player/controllers/animation_controller.gd` — add ground_pitch to visual rotation

---

### Task 1: Add Variables and Create Raycasts

**Files:**
- Modify: `entities/player/controllers/movement_controller.gd`

- [ ] **Step 1: Add new variables after existing var declarations (line ~13)**

```gdscript
# Slope physics
var ground_pitch: float = 0.0  # radians, positive = uphill
var _angular_velocity: float = 0.0  # rad/s, pitch change rate for launch conservation
var is_airborne: bool = false
var _front_ray: RayCast3D
var _rear_ray: RayCast3D
```

Add these after the `_balance_point_decay_mult` line (after line 22).

- [ ] **Step 2: Create raycasts in `_ready()`, after the editor hint return**

```gdscript
func _ready():
	if Engine.is_editor_hint():
		return

	player_entity.respawned.connect(_on_respawn)

	# Slope detection raycasts at wheel positions
	var bd = player_entity.bike_definition
	_front_ray = RayCast3D.new()
	_front_ray.position = bd.front_wheel_ground_position + Vector3.UP * 0.3
	_front_ray.target_position = Vector3.DOWN * 0.6
	_front_ray.enabled = true
	player_entity.add_child(_front_ray)

	_rear_ray = RayCast3D.new()
	_rear_ray.position = bd.rear_wheel_ground_position + Vector3.UP * 0.3
	_rear_ray.target_position = Vector3.DOWN * 0.6
	_rear_ray.enabled = true
	player_entity.add_child(_rear_ray)
```

The rays start 0.3m above wheel ground position and cast 0.6m down, giving 0.3m of detection below the wheel contact point.

- [ ] **Step 3: Have human run the game — verify no errors on spawn, bike rides normally. Also verify raycast positions look correct by checking `front/rear_wheel_ground_position` values in the bike definition resource — if `mesh_position_offset` is non-zero, ray positions may need offsetting.**

- [ ] **Step 4: Commit**

```
feat: add slope physics variables and raycasts to movement controller
```

---

### Task 2: Ground Detection Function

**Files:**
- Modify: `entities/player/controllers/movement_controller.gd`

- [ ] **Step 1: Add `_update_ground_detection()` function**

Add this new function after `_velocity_calc()`:

```gdscript
## Compute ground_pitch from front/rear wheel raycasts
func _update_ground_detection(delta: float):
	_front_ray.force_raycast_query()
	_rear_ray.force_raycast_query()

	var front_hit = _front_ray.is_colliding()
	var rear_hit = _rear_ray.is_colliding()
	var prev_ground_pitch = ground_pitch

	if front_hit and rear_hit:
		var front_point = _front_ray.get_collision_point()
		var rear_point = _rear_ray.get_collision_point()
		var diff = front_point - rear_point
		var horizontal_dist = Vector2(diff.x, diff.z).length()
		# Positive = uphill (front higher than rear)
		ground_pitch = atan2(diff.y, horizontal_dist)
		is_airborne = false
	elif front_hit or rear_hit:
		# One wheel off ground (wheelie/stoppie) — decay toward zero
		ground_pitch = move_toward(ground_pitch, 0.0, 1.0 * delta)
		is_airborne = false
	else:
		is_airborne = true

	# Track pitch change rate for angular momentum on launch
	# Smoothed to avoid noise from mesh seams and uneven geometry
	if delta > 0:
		var raw_angular_vel = (ground_pitch - prev_ground_pitch) / delta
		_angular_velocity = lerpf(_angular_velocity, raw_angular_vel, 5.0 * delta)
```

- [ ] **Step 2: Call `_update_ground_detection()` at start of `on_movement_rollback_tick()`**

Insert the call right before `_speed_calc(delta)`:

```gdscript
func on_movement_rollback_tick(delta: float):
	if Engine.is_editor_hint():
		return
	if player_entity.is_crashed:
		return

	_update_ground_detection(delta)
	_speed_calc(delta)
	_steer_calc(delta)
	_velocity_calc(delta)
	_pitch_angle_calc(delta)

	# Apply movement
	player_entity.velocity *= NetworkTime.physics_factor
	player_entity.move_and_slide()
	player_entity.velocity /= NetworkTime.physics_factor

	_handle_player_collision(delta)
```

- [ ] **Step 3: Have human test on flat ground — no behavior change expected. Add a `print("ground_pitch: %.2f | airborne: %s" % [rad_to_deg(ground_pitch), is_airborne])` temporarily to verify values make sense**

- [ ] **Step 4: Commit**

```
feat: add ground detection from wheel raycasts
```

---

### Task 3: Refactor Velocity Calc — Grounded Path

**Files:**
- Modify: `entities/player/controllers/movement_controller.gd`

This task fixes two issues with the original velocity calc:
1. Speed needs to account for slope (velocity has a Y component on slopes, but `_speed_calc` only measures horizontal)
2. Grounded velocity needs a downward snap force to keep the entity on the surface during downhill sections

- [ ] **Step 1: Update `_speed_calc()` to account for slope velocity**

Change the speed derivation at the top of `_speed_calc()` to use full velocity length when grounded, and add slope gravity here (single source of truth for speed changes):

```gdscript
## Calculate speed from input / power output
func _speed_calc(delta: float):
	var bd = player_entity.bike_definition

	# Derive speed from synced velocity — use full length when grounded (velocity has Y component on slopes)
	if is_airborne:
		speed = Vector2(player_entity.velocity.x, player_entity.velocity.z).length()
	else:
		speed = player_entity.velocity.length()
		# Slope gravity: uphill slows, downhill accelerates (1x gravity, not 4x)
		speed -= 9.8 * sin(ground_pitch) * delta
		speed = maxf(speed, 0.0)

	# Acceleration (uses gearing power output)
	var power = gearing_controller.get_power_output()
	var gear_max_speed = gearing_controller.get_gear_max_speed()
	if power > 0 and speed < gear_max_speed:
		speed += bd.acceleration * power * delta
		speed = minf(speed, gear_max_speed)
	# Engine braking — applies when not on throttle, stronger at higher RPM
	elif power <= 0 and speed > 0.5:
		# print("engine brake")
		var rpm_factor = gearing_controller._get_rpm_ratio()
		speed = move_toward(speed, 0, bd.engine_brake_strength * rpm_factor * delta)

	# Braking
	var total_brake = input_controller.nfx_front_brake + input_controller.nfx_rear_brake
	if total_brake > 0:
		speed = move_toward(speed, 0, bd.brake_strength * total_brake * delta)

	# print("speed %.2f" % speed)
```

- [ ] **Step 2: Add `_velocity_calc_grounded()` function**

Add after `_update_ground_detection()`:

```gdscript
## Grounded velocity: redirect along slope tangent with ground-stick force
func _velocity_calc_grounded(delta: float):
	# Flat forward direction (ignore any entity pitch)
	var forward_flat = -player_entity.global_transform.basis.z
	forward_flat.y = 0
	forward_flat = forward_flat.normalized()

	# Rotate forward onto the slope surface
	var right = forward_flat.cross(Vector3.UP).normalized()
	var slope_forward = forward_flat.rotated(right, ground_pitch)

	player_entity.velocity = slope_forward * speed

	# Ground-stick force: push entity into surface to maintain floor contact
	# Without this, the bike floats off on downhill slopes and at zero speed
	player_entity.velocity.y -= 9.8 * delta
```

- [ ] **Step 3: Replace `_velocity_calc()` to dispatch between grounded and airborne**

```gdscript
## Calculate player_entity.velocity based on grounded/airborne state
func _velocity_calc(delta: float):
	if is_airborne:
		_velocity_calc_airborne(delta)
	else:
		_velocity_calc_grounded(delta)
```

- [ ] **Step 4: Add temporary airborne stub so it compiles**

```gdscript
## Airborne velocity: projectile physics (stub — implemented in Task 4)
func _velocity_calc_airborne(delta: float):
	player_entity.velocity.y -= 9.8 * delta * 4.0
```

- [ ] **Step 5: Have human test on flat ground and on a ramp — bike should ride normally on flat, follow slopes on ramps. Speed should decrease going uphill, increase downhill. Bike should NOT float on downhill sections.**

- [ ] **Step 6: Commit**

```
feat: refactor grounded velocity to follow slope tangent
```

---

### Task 4: Refactor Velocity Calc — Airborne Path

**Files:**
- Modify: `entities/player/controllers/movement_controller.gd`

- [ ] **Step 1: Replace airborne stub with full implementation**

```gdscript
## Airborne velocity: projectile physics with angular momentum
func _velocity_calc_airborne(delta: float):
	# Gravity acts on the velocity vector directly (projectile arc)
	player_entity.velocity.y -= 9.8 * delta * 4.0

	# Conserve angular momentum: keep rotating ground_pitch at launch rate
	ground_pitch += _angular_velocity * delta

	# Blend rotation toward velocity direction for natural arc feel
	var horiz_speed = Vector2(player_entity.velocity.x, player_entity.velocity.z).length()
	if horiz_speed > 0.5:
		var vel_pitch = atan2(player_entity.velocity.y, horiz_speed)
		ground_pitch = lerpf(ground_pitch, vel_pitch, 2.0 * delta)

	# Dampen angular velocity over time
	_angular_velocity = move_toward(_angular_velocity, 0.0, abs(_angular_velocity) * 0.5 * delta)

	# Recompute speed from horizontal velocity (vertical handled by gravity)
	speed = horiz_speed
```

- [ ] **Step 2: Have human test ramp launches — bike should launch off ramps with a parabolic arc, rotating smoothly to follow the arc. Landing should transition back to grounded smoothly**

- [ ] **Step 3: Commit**

```
feat: add airborne projectile physics with angular momentum
```

---

### Task 5: Centrifugal Stick Logic

**Files:**
- Modify: `entities/player/controllers/movement_controller.gd`

- [ ] **Step 1: Add centrifugal check at end of `_velocity_calc_grounded()`, before the ground-stick force**

Insert before the `# Ground-stick force` line in `_velocity_calc_grounded()`:

```gdscript
	# Centrifugal stick check: does speed generate enough force to hold the surface?
	# Centripetal acceleration = v * omega (where omega = angular velocity of pitch change)
	# If gravity pull-away exceeds centripetal acceleration → detach
	if abs(_angular_velocity) > 0.01:
		var centripetal_accel = speed * abs(_angular_velocity)
		# Gravity component pulling away from surface (only matters on convex terrain like crests)
		var gravity_pull = 9.8 * cos(ground_pitch)
		if gravity_pull > centripetal_accel:
			is_airborne = true
			# Preserve current velocity for projectile arc
			return
```

- [ ] **Step 2: Have human test — at low speed on a crest/bump, bike should detach. At high speed, it should stick. Inside loops (if any exist), fast bikes should stay on the surface**

- [ ] **Step 3: Commit**

```
feat: add centrifugal stick check for slope detachment
```

---

### Task 6: Animation Controller Ground Pitch Integration

**Files:**
- Modify: `entities/player/controllers/animation_controller.gd`

- [ ] **Step 1: Update `_update_procedural_animation()` to include ground_pitch**

Replace the pitch section (the `target_pitch` and `visual_root.rotation.x` lines) with:

```gdscript
	# Pitch visual_root: ground slope + wheelie/stoppie
	var bd = player_entity.bike_definition
	var max_wheelie_rad = deg_to_rad(bd.max_wheelie_angle_deg)
	var max_stoppie_rad = deg_to_rad(bd.max_stoppie_angle_deg)
	var trick_pitch = -clamp(movement_controller.pitch_angle, -max_stoppie_rad, max_wheelie_rad)
	# ground_pitch positive = uphill = nose up = negative rotation.x
	var target_pitch = -movement_controller.ground_pitch + trick_pitch
	visual_root.rotation.x = lerpf(visual_root.rotation.x, target_pitch, blend)
```

The key change: `target_pitch` now includes `-movement_controller.ground_pitch` to tilt the visual to match the ground surface. `trick_pitch` handles wheelie/stoppie on top.

- [ ] **Step 2: Fix pivot offset to only use trick rotation (not ground slope)**

Replace the pivot section:

```gdscript
	# Pivot offset: rotate around rear wheel (wheelie) or front wheel (stoppie)
	# Only pivot for trick pitch, not ground slope
	var pivot: Vector3
	if trick_pitch < 0:
		pivot = bd.rear_wheel_ground_position
	else:
		pivot = bd.front_wheel_ground_position
	var rotated_pivot = Basis(Vector3.RIGHT, trick_pitch) * pivot
	visual_root.position = _base_visual_root_position + pivot - rotated_pivot
```

Changed: pivot decision uses `trick_pitch` instead of `visual_root.rotation.x`, and pivot rotation uses `trick_pitch` only. This prevents the ground slope from affecting the wheel-lift pivot.

- [ ] **Step 3: Have human test on ramps with wheelies — bike should visually tilt to follow slopes AND show wheelie/stoppie rotation on top of slope angle**

- [ ] **Step 4: Commit**

```
feat: add ground_pitch to visual rotation in animation controller
```

---

### Task 7: Reset Cleanup

**Files:**
- Modify: `entities/player/controllers/movement_controller.gd`

- [ ] **Step 1: Add new vars to `do_reset()`**

```gdscript
func do_reset():
	speed = 0.0
	roll_angle = 0.0
	pitch_angle = 0.0
	yaw_angle = 0.0
	_prev_clutch_held = false
	_clutch_kick_window = 0.0
	ground_pitch = 0.0
	_angular_velocity = 0.0
	is_airborne = false
```

- [ ] **Step 2: Have human test — crash and respawn on a ramp, verify bike resets cleanly to flat orientation**

- [ ] **Step 3: Commit**

```
feat: clear slope physics state on respawn
```

---

## Tuning Notes (Post-Implementation)

These values will likely need tuning during playtesting:

| Value | Location | What it controls |
|-------|----------|-----------------|
| `Vector3.UP * 0.3` / `Vector3.DOWN * 0.6` | Task 1, ray setup | Ray start height and detection range |
| `9.8 * sin(ground_pitch)` (1x gravity) | Task 3, slope gravity | How much hills affect speed |
| `9.8 * delta` | Task 3, ground-stick force | Downward force keeping entity on surface |
| `9.8 * delta * 4.0` | Task 4, airborne gravity | Fall speed (existing value) |
| `2.0 * delta` | Task 4, vel_pitch blend | How fast bike aligns to arc in air |
| `0.5 * delta` | Task 4, angular damping | How fast spin decays in air |
| `5.0 * delta` | Task 2, angular_velocity smoothing | Low-pass filter on pitch change rate |
| `1.0 * delta` | Task 2, single-hit decay rate | How fast ground_pitch decays during wheelie/stoppie |
| `cos(ground_pitch)` threshold | Task 5, centrifugal | Detach sensitivity on crests |
| `blend` (5.0 * delta) | Task 6, visual lerp | Ground pitch visual smoothing |
