# Speed Wobbles — implementation plan

Handoff plan for the next agent. Design is agreed; code is not written yet. Read
`CLAUDE.md` (Patterns, Multiplayer, Fail Loudly) and `Architecture.md#player-entity` before
starting. Verify every file:line below against the current code — treat them as pointers, not gospel.

## Intent (user's words, verbatim)

> my drift (rear brake) makes it too easy to steer at high speed. it allows me to steer super
> easily. i want to keep the existing drift physics, but when only using the rear brake to slide,
> i want to place the player into a speed wobble state. i want to use this in other times too, e.g.
> landing a huge jump not flush to the ground +- some degrees, hitting a player while moving
> (instead of simply crashing, have some max speed/impact that will cause a crash but default to
> speed wobbles, and a new bat item)

On the bat:

> for the bat - give me a function that i can call, dupe the gas tank item but in the code leave a
> big TODO and print to console when item is picked up with todo text, since i need to animate and
> add hitboxes later.

On the brake-slide trigger (why there are two variants below):

> im not sure what would be better, initial thought is how long they hold the drift for can cause
> it, and what angle they release the drift at. your idea could work too, ideally i can try diff
> versions out, so add both but separate into diff functions for the diff types that i can mix &
> match when playtesting.

## The wobble state

A damped tank-slapper: the bike's heading oscillates left/right and each swing is smaller than the
last (the natural envelope of a damped harmonic oscillator — matches the user's "1st wobble full,
2nd half, taper off"). Recovery: **countersteer** (steer opposite the current swing) damps it fast;
**off-gas + any steer** is a slower universal save. Feeding it (steering into the swing) grows it.
A peak past a limit crashes via `crash_controller.trigger_crash()`. Steering authority is cut hard
while wobbling — that is the loss of control.

Lives entirely in `MovementController` (user's call — one file for now). It reads/writes `speed`,
`roll_angle`, heading (`rotate_y`), `is_drifting`, `_is_on_floor` and input, same as `_drift_calc`.

### State
Two **synced** vars, modeled on `slip_angle` (movement_controller.gd:77) — register them on the
`RollbackSynchronizer` in `player_entity.tscn` alongside it. They perturb heading, so per CLAUDE.md
(Multiplayer) they MUST be state properties or resim can't rewind them.
- `wobble_angle` — signed current yaw perturbation (rad)
- `wobble_vel` — its angular velocity (rad/s)

`is_wobbling` is **derived** locally each tick (like `is_drifting`, movement_controller.gd:78), not
synced: true while `|wobble_angle|`/`|wobble_vel|` exceed a small epsilon.

Zero all three in `do_reset()` (movement_controller.gd:855).

### Core function
Add `_wobble_calc(delta)` to `on_movement_rollback_tick` (movement_controller.gd:170). Order
matters (see the ORDER MATTERS note there and in player_entity.gd:212) — it carves heading via
`rotate_y`, so slot it with `_drift_calc`/`_steer_calc` and confirm slip + wobble don't fight over
`rotate_y` in the same tick. While wobbling, suppress drift and trick initiation (you can't wheelie
mid-tank-slapper). All feel numbers (spring, damping, countersteer bonus, off-gas bonus, crash
limit) are `@export`s on MovementController — no magic numbers.

## Triggers (each just injects amplitude into `wobble_vel`)

**1. Rear-brake slide — TWO independent variants, each its own function + its own `@export bool`
toggle so they can be mixed & matched in playtesting.** Both leave the existing drift physics
(`_can_initiate_drift` power/clutch/burnout paths, movement_controller.gd:691) intact.
- **1a. Release-based** (user's first instinct): keep the normal brake-slide drift, but track how
  long it's held and the `slip_angle` at the moment the rear brake releases; a long hold and/or a
  large release angle injects a wobble on release. Track hold-time as new state; reset it in
  `do_reset()`.
- **1b. High-speed entry** (the alternative): the brake-slide entry (movement_controller.gd:711),
  above a speed-fraction threshold, injects a wobble and does NOT start a drift. Below it, normal
  brake-slide drift as today.

**2. Bad jump landing.** In the landing branch (`if not _was_on_floor:`, movement_controller.gd:133):
if the bike's yaw/roll misalignment to the landing surface exceeds a `@export` angle window, inject
a wobble scaled by how far off it is. Landing flush stays clean.

**3. Player-to-player hit.** Mirror `_crash_rammed_racer` (crash_controller.gd:217, called from
`_detect_crash` at :207). Server compares impact speed to a `@export` threshold: below → wobble
BOTH riders (rammer + victim); at/above → existing hard crash (`crash_player`). This replaces the
current always-crash ram at crash_controller.gd:197-209.

**4. Bat item.** See below.

## Netcode

Discrete external triggers (player-hit, bat) use the `rb_*` pattern (CLAUDE.md → Netfox + RPC):
add `rb_do_wobble: bool` + `_wobble_strength: float` on `PlayerEntity`, consumed in `_rollback_tick`
(mirror `rb_do_crash`, player_entity.gd:194-196), injecting into the synced `wobble_vel`. Reached
via a new **server-only** `SpawnManager.wobble_player(peer_id, strength)` RPC — mirror `crash_player`
(spawn_manager.gd:88-92), reject non-server senders. This is the callable the bat (and anything
else) uses.

Because amplitude is synced state, a resim re-applies it for free — no boost-grant-style tick memo
needed (contrast player_entity.gd:138-141). In-sim triggers (1, 2) are deterministic from synced
inputs, so every peer detects them locally; no RPC.

## HUD

Reuse `BalanceBar`. In `RidingHUDState.Physics_Update` (riding_hud_state.gd:105), when `is_wobbling`,
drive `current_val = rad_to_deg(wobble_angle)` on a symmetric ±max range with warn bands at the
crash edges; wobble takes the bar over from the trick display (tricks show/hide it via signals at
:196-215) while active. Local display only — never write sim state from here.

## Bat item (stubbed — hitboxes/animation come later)

- Add `BAT` to `PickupItemType` (pickup_item_definition.gd:4).
- Dupe `gas_can_pickup_definition.tres` → `bat_pickup_definition.tres`; reuse the gas_can `.glb`
  mesh as a placeholder with a `# TODO` to swap it.
- In `pickup_spawner._apply_effect` (pickup_spawner.gd:105) add the `BAT` case: a big `# TODO`
  block noting hitboxes/animation are unbuilt, a `DebugUtils.DebugMsg("BAT PICKED UP — TODO ...")`,
  and a call to `wobble_player`.
- To actually spawn it, add the new definition to a `PickupSpawner.items` array in a level scene
  (note for the user — level authoring is theirs).

## Conventions (CLAUDE.md)

- Fail loudly — no silent null-return guards (see the Fail Loudly section).
- `DebugUtils.DebugMsg()` for all prints; tunables as `@export`, grouped; terse "why"-only comments.
- Reuse before adding; new methods/exports are a last resort.
- Do NOT edit `TODO.md` (user owns it). Lint `.gd` files clean against `.gdlintrc` before done.
- This doc names tunables by behavior, not value — keep concrete numbers in the inspector.
