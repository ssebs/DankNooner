# Drift / Powerslide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a controllable motorcycle drift/powerslide where the bike's heading diverges from its travel direction (a tracked slip angle), with two entry methods, countersteer control, and two crash modes (spin-out + highside).

**Architecture:** A new signed `slip_angle` on `MovementController` is the angle between the bike's heading (forward) and its velocity direction. Normal riding keeps it 0 (rail-based model unchanged). While `is_drifting`, `_velocity_calc` points velocity at `forward` rotated by `slip_angle`, and a new `_drift_calc` integrates the slip from drive input + steering. Crash decisions live in `CrashController` (consistent with existing wheelie/stoppie over-rotation), reading `movement_controller.slip_angle`. Trick state + animation reuse the existing registry pattern.

**Tech Stack:** Godot 4.6, GDScript, netfox (RollbackSynchronizer). Server-authoritative physics in `_rollback_tick`; drift state derives from synced `nfx_*` inputs + synced `slip_angle`, so it is rollback-deterministic.

---

## Project Conventions for This Plan (read first)

- **No automated tests.** This repo has no GDScript test harness; the rule is "Only have the human run the project." Each task's verification is **(a)** LSP lint-clean via `mcp__ide__getDiagnostics` (NOT shell), and **(b)** a scripted manual play-test the human runs. Do not invent a pytest suite.
- **Git:** Per `CLAUDE.md`, Claude does not run `git`/`gh`. Commit checkpoints below are written as suggested commands for the human (or executing agent with permission) to run — they are logical checkpoints, not Claude actions.
- **Debug output:** use `DebugUtils.DebugMsg(...)`, gated on `OS.has_feature("debug")` where noisy.
- **Tuning:** All `DRIFT_*` constants are first-pass values. The "feel" tasks (2, 4) require human play-testing to dial in. Ship the structure; expect to re-tune the numbers.
- **Sign convention:** `slip_angle > 0` = tail swung out to one side (bike heading is rotated relative to travel). The exact left/right mapping is cosmetic — flip a sign during play-testing if it feels inverted.

---

## File Map

| File | Responsibility | Change |
|------|----------------|--------|
| `player/controllers/movement_controller.gd` | Slip-angle state, drift constants, entry/exit detection, `_drift_calc` integration, velocity rotation, reset | Modify |
| `player/player_entity.tscn` | RollbackSynchronizer `state_properties` | Modify (add `slip_angle`) |
| `player/controllers/trick_controller.gd` | Report `Trick.DRIFT` when drifting | Modify |
| `player/controllers/crash_controller.gd` | Spin-out + highside crash, throttle-chop tracking, launch impulse | Modify |
| `player/controllers/animation_controller.gd` | Register `drift` trick anim (final, optional) | Modify |

---

## Task 1: Slip-angle state + synced var + velocity rotation (no behavior change yet)

Lays the foundation. `is_drifting` stays `false` this task, so riding is unchanged — this task's job is to add the plumbing and prove normal riding still works.

**Files:**
- Modify: `player/controllers/movement_controller.gd`
- Modify: `player/player_entity.tscn:1155`

- [ ] **Step 1: Add drift constants + state vars**

In `movement_controller.gd`, after the Reverse block (the `const REVERSE_BRAKE_THRESHOLD ...` / `var is_reversing` area, ~line 35-39), add:

```gdscript
# Drift / powerslide — see planning_docs/PLAN-DRIFT.md
const DRIFT_MIN_SPEED: float = 6.0  # below this it's a stationary burnout (slip stays ~0)
const DRIFT_BRAKE_HOLD: float = 0.4  # rear-brake input that sustains a brake slide
const DRIFT_STEER_ENTRY: float = 0.3  # steer needed to kick a brake slide loose
const DRIFT_BREAK_FORCE: float = POWER_WHEELIE_MIN_FORCE  # power×accel torque gate to break traction
const DRIFT_KICK_RATE: float = 2.5  # rad/s the tail swings out (scaled by drive + steer-into)
const DRIFT_RECOVER_RATE: float = 2.0  # rad/s grip pulls slip back toward 0
const DRIFT_RECOVER_SUPPRESS: float = 0.8  # how much drive (0..1) suppresses recovery
const DRIFT_COUNTERSTEER_AUTHORITY: float = 3.0  # extra recovery rad/s at full countersteer
const DRIFT_YAW_RATE: float = 1.6  # heading carve rad/s while drifting (aim the slide)
const DRIFT_SPEED_SCRUB: float = 0.6  # speed bleed per sec, proportional to |slip_angle|
const DRIFT_MAX_SLIP_ANGLE_DEG: float = 70.0  # clamp just past the 60° spinout so crash fires, no wrap
```

Then add to the state vars near `var pitch_angle` (~line 42):

```gdscript
var slip_angle: float = 0.0  # signed radians: heading vs velocity direction. Synced via RollbackSynchronizer.
var is_drifting: bool = false  # re-derived each tick from synced inputs + slip_angle (not synced directly)
```

- [ ] **Step 2: Rotate velocity by slip in `_velocity_calc`**

In `_velocity_calc(delta)`, replace the on-floor velocity assignment. Current code (~line 323-331):

```gdscript
	var forward = -player_entity.global_transform.basis.z
	if _is_on_floor:
		if player_entity.velocity.length_squared() > 0.01:
			air_forward = player_entity.velocity.normalized()
		else:
			air_forward = forward
		player_entity.velocity = forward.slide(_floor_normal).normalized() * speed
```

becomes:

```gdscript
	var forward = -player_entity.global_transform.basis.z
	# Drift: velocity travels along heading rotated by slip_angle (tail out). slip_angle==0
	# (normal riding) leaves this identical to forward.
	var travel_dir = forward
	if is_drifting:
		travel_dir = forward.rotated(player_entity.up_direction.normalized(), slip_angle)
	if _is_on_floor:
		if player_entity.velocity.length_squared() > 0.01:
			air_forward = player_entity.velocity.normalized()
		else:
			air_forward = travel_dir
		player_entity.velocity = travel_dir.slide(_floor_normal).normalized() * speed
```

- [ ] **Step 3: Reset slip in `do_reset()`**

In `do_reset()` (~line 586), add alongside the other resets:

```gdscript
	slip_angle = 0.0
	is_drifting = false
```

- [ ] **Step 4: Register `slip_angle` for rollback sync**

In `player/player_entity.tscn`, find the `RollbackSynchronizer` `state_properties` line (line ~1155). It currently reads:

```
state_properties = Array[String]([":global_transform", ":velocity", ":up_direction", ":is_crashed", "%MovementController:pitch_angle", "%MovementController:roll_angle", "%MovementController:speed", "%MovementController:air_forward", "%GearingController:current_gear", "%GearingController:current_rpm", "%GearingController:clutch_value"])
```

Add `"%MovementController:slip_angle"` after `"%MovementController:speed"`:

```
state_properties = Array[String]([":global_transform", ":velocity", ":up_direction", ":is_crashed", "%MovementController:pitch_angle", "%MovementController:roll_angle", "%MovementController:speed", "%MovementController:slip_angle", "%MovementController:air_forward", "%GearingController:current_gear", "%GearingController:current_rpm", "%GearingController:clutch_value"])
```

- [ ] **Step 5: Verify lint-clean**

Get diagnostics via `mcp__ide__getDiagnostics` for `player/controllers/movement_controller.gd`.
Expected: no diagnostics (empty array). Fix any `class-definitions-order` or type errors.

- [ ] **Step 6: Manual play-test — no regression**

Human runs the game (singleplayer Free Roam). Confirm: riding, turning, wheelie, stoppie, reverse all behave **exactly as before** (slip_angle stays 0, `is_drifting` never set yet). Nothing new should happen.

- [ ] **Step 7: Commit (human runs)**

```bash
git add player/controllers/movement_controller.gd player/player_entity.tscn
git commit -m "feat(drift): add slip_angle state + rollback sync (no behavior change)"
```

---

## Task 2: Drift entry/exit + `_drift_calc` integration (drift becomes functional, no crashes yet)

**Files:**
- Modify: `player/controllers/movement_controller.gd`

- [ ] **Step 1: Add `_can_initiate_drift()` (mirrors `_can_initiate_wheelie`, lean FORWARD)**

Add near `_can_initiate_wheelie` (~line 501):

```gdscript
## Drift entry. Mirror of the wheelie clutch/power gates but gated on lean FORWARD
## (lean back = wheelie, lean forward = drift), plus a rear-brake-slide entry.
func _can_initiate_drift() -> bool:
	if is_drifting:
		return true
	if not _is_on_floor or speed < DRIFT_MIN_SPEED:
		return false

	# Brake-slide entry — steer + hold rear brake breaks the rear loose. Accessible, safe to release.
	if (
		input_controller.nfx_rear_brake > DRIFT_BRAKE_HOLD
		and absf(input_controller.nfx_steer) > DRIFT_STEER_ENTRY
	):
		return true

	# Power entry — needs lean forward (distinguishes from wheelie's lean back).
	if input_controller.nfx_lean <= 0.3:
		return false
	var bd = player_entity.bike_definition

	# Clutch-dump pop (lean-forward variant) — same low-gear torque gate the wheelie pop uses.
	var clutch_pop = _clutch_kick_window > 0 and input_controller.nfx_throttle > 0.5
	if clutch_pop:
		var max_torque_mult = bd.gear_ratios[0] / bd.gear_ratios[bd.num_gears - 1]
		return (
			gearing_controller.get_potential_power_output()
			> max_torque_mult * CLUTCH_POP_MIN_POWER_FRAC
		)

	# Power slide — floored throttle + enough delivered force to break traction.
	var force = gearing_controller.get_power_output() * bd.acceleration
	return input_controller.nfx_throttle > 0.7 and force > DRIFT_BREAK_FORCE
```

- [ ] **Step 2: Add `_drift_calc()` (entry/exit + slip integration + carve)**

Add after `_steer_calc` / before `_velocity_calc` definitions (anywhere in the func section; suggested ~after `_steer_calc`):

```gdscript
## Maintain is_drifting and integrate slip_angle. Runs before _velocity_calc so
## velocity picks up the slip this tick. No-op (and slip decays to 0) when not drifting.
func _drift_calc(delta: float):
	# --- entry / exit ---
	if player_entity.is_crashed or not _is_on_floor:
		is_drifting = false
		slip_angle = move_toward(slip_angle, 0.0, DRIFT_RECOVER_RATE * delta)
		return

	if not is_drifting:
		is_drifting = _can_initiate_drift()

	if not is_drifting:
		# Not drifting — make sure any residual slip unwinds.
		slip_angle = move_toward(slip_angle, 0.0, DRIFT_RECOVER_RATE * delta)
		return

	# Sustain check — drift ends once nothing is feeding it and the slide has closed.
	var brake_sustain = input_controller.nfx_rear_brake > DRIFT_BRAKE_HOLD
	var power_sustain = input_controller.nfx_throttle > 0.5 and input_controller.nfx_lean > 0.0
	if not brake_sustain and not power_sustain and absf(slip_angle) < deg_to_rad(2.0):
		is_drifting = false
		slip_angle = 0.0
		return

	# Seed an initial direction from steer when starting near-straight.
	if absf(slip_angle) < deg_to_rad(1.0):
		var seed_dir = signf(input_controller.nfx_steer)
		if seed_dir == 0.0:
			seed_dir = 1.0
		slip_angle = seed_dir * deg_to_rad(1.5)

	var steer = input_controller.nfx_steer
	var slip_sign = signf(slip_angle)
	# Drive = how hard the slide is fed (throttle for power drift, rear brake for brake slide).
	var drive = maxf(input_controller.nfx_throttle, input_controller.nfx_rear_brake)
	# steer_into > 0 when steering the same way the tail is out; < 0 is countersteer.
	var steer_into = steer * slip_sign

	# Outward growth — fed by drive and steering into the slide.
	var kick = DRIFT_KICK_RATE * drive * clampf(0.4 + maxf(steer_into, 0.0), 0.0, 1.0)
	slip_angle += slip_sign * kick * delta

	# Grip recovery toward 0 — suppressed while feeding the slide, boosted by countersteer.
	var recover = DRIFT_RECOVER_RATE * (1.0 - drive * DRIFT_RECOVER_SUPPRESS)
	recover += maxf(-steer_into, 0.0) * DRIFT_COUNTERSTEER_AUTHORITY
	slip_angle = move_toward(slip_angle, 0.0, recover * delta)

	# Clamp just past the spinout angle so CrashController fires before it can wrap.
	slip_angle = clampf(
		slip_angle, -deg_to_rad(DRIFT_MAX_SLIP_ANGLE_DEG), deg_to_rad(DRIFT_MAX_SLIP_ANGLE_DEG)
	)

	# Carve — rotate heading so the powerslide can be aimed.
	player_entity.rotate_y(-steer * DRIFT_YAW_RATE * delta)

	# Speed scrub — sliding sideways bleeds speed.
	speed -= speed * DRIFT_SPEED_SCRUB * absf(slip_angle) * delta

	DebugUtils.DebugMsg(
		"drift: slip=%.1f° drive=%.2f steer_into=%.2f" % [rad_to_deg(slip_angle), drive, steer_into],
		OS.has_feature("debug") and debug_verbose
	)
```

- [ ] **Step 3: Call `_drift_calc` in the tick + suppress normal steering while drifting**

In `on_movement_rollback_tick`, insert `_drift_calc(delta)` immediately before `_steer_calc(delta)` (~line 114):

```gdscript
	_update_surface_alignment(delta)
	_drift_calc(delta)
	_steer_calc(delta)
	_velocity_calc(delta)
```

Then in `_steer_calc`, gate the heading rotation so it doesn't fight the drift carve. Change (~line 299):

```gdscript
	if absf(speed) > 0.5:
```

to:

```gdscript
	if absf(speed) > 0.5 and not is_drifting:
```

(Leave the lean/`roll_angle` and basis-alignment code in `_steer_calc` untouched — only the `rotate_y` turn block is gated.)

- [ ] **Step 4: Verify lint-clean**

`mcp__ide__getDiagnostics` for `movement_controller.gd`. Expected: empty. Fix any issues.

- [ ] **Step 5: Manual play-test — drift feel**

Human, in Free Roam:
1. **Brake slide:** get moving (> ~15 km/h equiv), hold rear brake + steer → tail should step out and follow steer; release rear brake → recovers and rides away.
2. **Power drift:** in a low gear, lean forward + floor throttle (or clutch dump leaning forward) → tail breaks loose.
3. **Countersteer:** while sliding, steering opposite the slide should reduce the angle and hold it; steering into it should deepen it.
4. Confirm lean BACK + throttle still does a **wheelie** (not a drift).

Note feel problems (too twitchy / won't initiate / won't recover) and tune the `DRIFT_*` constants. This is expected iteration.

- [ ] **Step 6: Commit (human runs)**

```bash
git add player/controllers/movement_controller.gd
git commit -m "feat(drift): slip integration, entry methods, countersteer control"
```

---

## Task 3: TrickController reports `Trick.DRIFT`

**Files:**
- Modify: `player/controllers/trick_controller.gd`

- [ ] **Step 1: Add enum value**

In the `Trick` enum (~line 7-18), add `DRIFT,` (append after `TWO_LEFT_FEET,`):

```gdscript
enum Trick {
	NONE,
	WHEELIE_SITTING,
	WHEELIE_MOD,
	STOPPIE,
	BACKFLIP,
	FRONTFLIP,
	THREESIXTY,
	HEEL_CLICKER,
	HIGH_CHAIR,
	TWO_LEFT_FEET,
	DRIFT,
}
```

- [ ] **Step 2: Detect drift in `_detect_current_trick`**

At the top of the on-ground branch, right after `_flip_emitted = false` (~line 60-61), add:

```gdscript
		# Reset flip tracking on landing
		_flip_emitted = false

		if movement_controller.is_drifting:
			return Trick.DRIFT
```

(Placed before the wheelie/stoppie checks — during a drift `pitch_angle` is ~0 so those wouldn't fire anyway, but this keeps DRIFT authoritative.)

- [ ] **Step 3: Add to the string maps**

In `trick_to_str`, add a case before the final `return "NONE"`:

```gdscript
		Trick.DRIFT:
			return "DRIFT"
```

In `str_to_trick`, add before the final `return Trick.NONE`:

```gdscript
		"DRIFT":
			return Trick.DRIFT
```

- [ ] **Step 4: Verify lint-clean**

`mcp__ide__getDiagnostics` for `trick_controller.gd`. Expected: empty.

- [ ] **Step 5: Manual play-test — HUD/trick signal**

Human: initiate a drift; confirm the HUD trick readout shows `DRIFT` (or the localized label) and clears when the drift ends. No crash yet — that's Task 4.

- [ ] **Step 6: Commit (human runs)**

```bash
git add player/controllers/trick_controller.gd
git commit -m "feat(drift): add DRIFT trick state"
```

---

## Task 4: CrashController — spin-out + highside (throttle-chop) crashes

**Files:**
- Modify: `player/controllers/crash_controller.gd`

- [ ] **Step 1: Add tunables + throttle-tracking state**

After the existing `@export` block (~line 20) add:

```gdscript
## Drift over-rotation crash angle (tail came all the way around).
@export var drift_spinout_angle_deg: float = 60.0
## Min |slip| for a highside on grip regain.
@export var drift_highside_angle_deg: float = 40.0
## Min speed for a highside to be dangerous.
@export var drift_highside_min_speed: float = 12.0
## Throttle release rate (per sec) that highsides at drift_highside_angle_deg (forgiving).
@export var highside_chop_forgiving: float = 6.0
## Throttle release rate that highsides near the spinout angle (twitchy — small lift snaps).
@export var highside_chop_twitchy: float = 1.5
## Upward+lateral launch speed applied to a highside crash.
@export var highside_launch_force: float = 14.0
```

And with the other tracking vars (~line 22):

```gdscript
var _prev_throttle: float = 0.0
```

- [ ] **Step 2: Add `_detect_drift_crash()`**

Add this method (call wired in Step 3):

```gdscript
## Drift crashes: spin-out (tail past the limit) or highside (tire hooks up on a
## throttle chop while still slipped). Rolling the throttle off slowly is safe.
func _detect_drift_crash(delta: float):
	var throttle = input_controller.nfx_throttle
	var release_rate = (_prev_throttle - throttle) / delta  # > 0 means letting off
	_prev_throttle = throttle

	if not movement_controller.is_drifting:
		return

	var slip = absf(movement_controller.slip_angle)

	# Spin-out — tail came all the way around.
	if slip > deg_to_rad(drift_spinout_angle_deg):
		DebugUtils.DebugMsg("drift spinout crash (slip=%.1f°)" % rad_to_deg(slip))
		trigger_crash()
		return

	# Highside — fast throttle chop while deep + fast. Chop tolerance shrinks as slip grows.
	if (
		slip > deg_to_rad(drift_highside_angle_deg)
		and movement_controller.speed > drift_highside_min_speed
	):
		var slip_ratio = clampf(
			(
				(slip - deg_to_rad(drift_highside_angle_deg))
				/ deg_to_rad(drift_spinout_angle_deg - drift_highside_angle_deg)
			),
			0.0,
			1.0
		)
		var chop_threshold = lerpf(highside_chop_forgiving, highside_chop_twitchy, slip_ratio)
		if release_rate > chop_threshold:
			# Launch over the high side: up + lateral toward the outside of the slide.
			var slip_sign = signf(movement_controller.slip_angle)
			var right = player_entity.global_transform.basis.x
			var launch = (Vector3.UP - right * slip_sign).normalized() * highside_launch_force
			DebugUtils.DebugMsg("drift HIGHSIDE crash (slip=%.1f° rate=%.1f)" % [rad_to_deg(slip), release_rate])
			trigger_crash(launch)
```

- [ ] **Step 3: Wire it into the tick**

In `on_movement_rollback_tick` (~line 36-45), add the drift check alongside the others:

```gdscript
	_update_brake_grab(delta)
	_detect_air_trick_landing()
	_detect_drift_crash(delta)
	_detect_crash()
```

- [ ] **Step 4: Add launch impulse to `trigger_crash`**

Change `trigger_crash()` (~line 162) to accept an optional launch impulse. Currently:

```gdscript
func trigger_crash():
	player_entity.is_crashed = true
	player_entity.velocity = Vector3.ZERO
	animation_controller.start_ragdoll()
	player_entity.camera_controller.force_tps()
	crashed.emit()
```

becomes:

```gdscript
func trigger_crash(launch_impulse: Vector3 = Vector3.ZERO):
	player_entity.is_crashed = true
	player_entity.velocity = launch_impulse
	animation_controller.start_ragdoll()
	player_entity.camera_controller.force_tps()
	crashed.emit()
```

- [ ] **Step 5: Verify the ragdoll inherits the launch**

Read `player/characters/scripts/ragdoll_controller.gd`. Determine how ragdoll bones get their initial velocity when `animation_controller.start_ragdoll()` runs:
- If `RagdollController` already seeds bone `linear_velocity` from `player_entity.velocity`, Step 4 is sufficient — the highside throw works.
- If it zeroes bone velocity, add a minimal pass-through: have the ragdoll seed bones from `player_entity.velocity` at startup (use the existing bone iteration; set `linear_velocity = player_entity.velocity` on each `PhysicalBone3D`). Keep it to the smallest change that makes the rider get thrown.

Document what you found in the commit message. Do not guess the API — read the file first.

- [ ] **Step 6: Reset `_prev_throttle` in `do_reset`**

In `do_reset()` (~line 171), add:

```gdscript
	_prev_throttle = 0.0
```

- [ ] **Step 7: Verify lint-clean**

`mcp__ide__getDiagnostics` for `crash_controller.gd`. Expected: empty.

- [ ] **Step 8: Manual play-test — both crash modes**

Human:
1. **Spin-out:** hold a deep drift and keep steering into it past ~60° → crash.
2. **Highside:** get a solid slide going at speed (≥ ~40°), then **snap the throttle shut** → highside crash, rider launched up/over.
3. **Safe recovery:** same deep slide, but **roll the throttle off slowly** → no crash, slip unwinds and you ride away.
4. **Shallow:** at a small slip angle (< 40°), chopping throttle should NOT highside.

Tune `highside_chop_*`, `drift_highside_*`, `highside_launch_force` in the inspector until it feels like a skill check.

- [ ] **Step 9: Commit (human runs)**

```bash
git add player/controllers/crash_controller.gd player/characters/scripts/ragdoll_controller.gd
git commit -m "feat(drift): spin-out + highside crashes with throttle-chop skill check"
```

---

## Task 5: Drift animation (FINAL — requires authoring in editor; skip until anim exists)

This task only adds the trick→anim registry row. The drift is fully playable without it; do this once a `drift` IK animation has been authored.

**Files:**
- Modify: `player/controllers/animation_controller.gd`
- Author: `player/player_entity.tscn` → `IKAnimationPlayer` animation library (editor, human)

- [ ] **Step 1: Author the `drift` anim (human, in editor)**

Per `planning_docs/AnimationController.md` → "Creating IK (Polish) Animations": open `player_entity.tscn`, select `IKAnimationPlayer` → Animation > New, name it `drift`. Keyframe a forward-lean / weight-to-the-inside pose on the `IKTargets/*` markers, **keyframing `t=0` as the default**. Use full track paths (no `%` shorthand).

- [ ] **Step 2: Register the entry**

In `_build_trick_entries()` (~line 931), add a row to the array:

```gdscript
		_make_entry(
			TrickController.Trick.DRIFT, "drift", PlayMode.LOOP_WHILE_LATCHED, false
		),
```

- [ ] **Step 3: Verify lint-clean**

`mcp__ide__getDiagnostics` for `animation_controller.gd`. Expected: empty.

- [ ] **Step 4: Manual play-test — anim plays**

Human: initiate a drift; the rider should blend into the drift pose and blend out when it ends. No errors in the output about a missing `drift` animation.

- [ ] **Step 5: Commit (human runs)**

```bash
git add player/controllers/animation_controller.gd player/player_entity.tscn
git commit -m "feat(drift): drift rider animation"
```

---

## Done / Definition of Success

- Two entry methods work: rear-brake-slide (steer + hold rear brake) and power drift (lean forward + floor/clutch-dump).
- Countersteer holds the line; steering into the slide deepens it.
- Wheelie (lean back) is unaffected and clearly distinct from drift (lean forward).
- Spin-out crash at ~60°; highside crash on a fast throttle chop while deep + fast; slow roll-off recovers cleanly.
- Drift survives multiplayer rollback (slip_angle synced; state re-derives from synced inputs).
- All five files lint clean; normal riding/tricks unchanged.

## Known Tuning Levers (expect iteration)

- **Won't break loose:** lower `DRIFT_BREAK_FORCE`, raise `DRIFT_KICK_RATE`.
- **Too twitchy / spins instantly:** lower `DRIFT_KICK_RATE`, raise `DRIFT_RECOVER_RATE`.
- **Can't hold a slide:** raise `DRIFT_RECOVER_SUPPRESS` (drive holds it), raise `DRIFT_COUNTERSTEER_AUTHORITY`.
- **Highside too punishing/lenient:** adjust `highside_chop_forgiving` / `highside_chop_twitchy` and `drift_highside_angle_deg`.
- **Drift drains speed too fast:** lower `DRIFT_SPEED_SCRUB`.
