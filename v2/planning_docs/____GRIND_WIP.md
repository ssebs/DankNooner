# Grinding (WIP spec)

Skate 3 style rail grinds. Delete this file once the feature is playtested and folded into
PlayerController.md / ComboAndBoost.md.

## Intent

Catch air, land on a rail, and ride it as a held trick. What you hold sets the pose, and the pose
is the grind. Shifting lean or steer mid-grind changes the grind; holding a shift too far in one
direction bails.

## Goals / non-goals

- Goals: rail entry from a real jump, live pose → grind classification, bail limits that reuse
  existing crash rules, stick tricks layered on top, scored through the normal combo path.
- Non-goals (v1): curved rails, new rider anims per grind, race bots grinding, early hop-off
  mid-rail.
- Anti-goal: a new balance meter or a parallel crash system. Limits are pitch (existing bike
  limits) and yaw.

## Rails

- Collision layer 9 `grind` (mask `GRIND_LAYER_MASK`). Rails must be `BoxShape3D` colliders,
  e.g. `levels/assets/props/grind_rail.tscn`. Rails also stay on layer 1 so the bike collides
  with them normally.
- The rail runs along the box's longer horizontal axis (x or z); the bike rides its top face.
  Sloped rails work (the box can be rotated); curved ones don't.

## Entry

- In `MovementController`, any tick of a real jump (`air_time >= AIR_TRICK_MIN_AIRTIME`) while
  descending, the bike snaps to the nearest `grind`-layer rail within `GRIND_SNAP_RADIUS`
  (a shape query, not slide contacts, so it needn't land squarely on a thin box). It can be up
  to `GRIND_SNAP_BELOW` under the rail's top and still snap (fell past it this tick).
- Travel direction along the rail is whichever end the velocity points toward. Speed along the
  rail must be at least `GRIND_MIN_SPEED`, else it's a normal (non-grind) landing.
- Initial `grind_yaw` = heading vs rail direction, so landing crooked starts crooked.
- Landing checks are the existing ones: mid air-trick, upside down, and pitch past the bike's
  limits all crash. Landing past the yaw limit crashes too.

## On the rail

- Kinematic: position is snapped to the rail's top line each tick (no `move_and_slide`),
  velocity = rail direction × speed, `is_on_floor` reads true.
- Lean drives `pitch_angle` at `bd.rotation_speed` (same as the balance-lock lean). No input =
  the pose holds.
- Steer drives `grind_yaw` at `GRIND_YAW_RATE`. Heading = rail direction turned by `grind_yaw`
  (the body turns, like a drift's slip).
- Speed: eases up toward the bike's `max_speed` at `GRIND_ACCEL` (down to it if entering faster),
  plus slope gravity (`SLOPE_GRAVITY`) along the rail.
  Throttle does nothing.
- Roll eases to level.

## Grind classification (TrickController)

Pitch zone uses the existing wheelie / stoppie thresholds. Yaw zones: straight, angled
(`GRIND_ANGLED_YAW_DEG`), sideways (`GRIND_SIDEWAYS_YAW_DEG`). Positive yaw = turned left.

| pitch \ yaw | straight | angled | sideways |
|---|---|---|---|
| front (stoppie side) | nosegrind | crooked | noseslide |
| level | 50-50 | 50-50 | boardslide (left) / lipslide (right) |
| back (wheelie side) | 5-0 | feeble (left) / salad (right) | tailslide |

- A held right-stick trick overrides the grind as `current_trick` (e.g. knee knocker), via a
  `TrickState.GRIND` row in `BINDINGS`. No trick button needed on the rail.
- Each grind is a held trick in `ComboRules.HELD_TRICK_SCORE`; switching grinds keeps the combo.

## Exit

- Rail end: pops off with `HOP_VELOCITY` up, keeps rail-direction momentum, back to normal air.
- Bail (crash, existing `trigger_crash`): pitch past `max_wheelie_angle_deg` /
  `max_stoppie_angle_deg` (existing checks), `|grind_yaw|` past `GRIND_MAX_YAW_DEG`, or speed
  under `GRIND_MIN_SPEED`.
- Respawn clears grind state (`do_reset`).

## FX

`BikeWreck`'s sparks + `CRASH_GRIND` loop play at the wheels while `is_grinding` (its
`_process` frozen branch), so remote riders grind audibly too.

## Netcode

New `MovementController` state properties: `is_grinding`, `grind_from`, `grind_to`,
`grind_yaw`. Entry is detected inside the rollback tick from slide collisions, so resims
reproduce it.

## Calls made without the user (check these)

- Rail-end exit pops (robustly leaves the rail top instead of riding it as floor).
- Running out of speed on the rail bails rather than dropping you off.
- No early hop-off: the trick button drives the KBM trick stick, so it can't double as hop.
  Needs an input decision.
- Grinds listed under a new Grind tab in the tricks menu.

## Follow-ups

- Early hop-off input.
- Per-grind rider anims.
- HUD balance meter (reuse the wheelie balance HUD) if bails feel unfair.
