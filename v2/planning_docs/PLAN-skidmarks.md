# Skidmarks (drift trails)

Local-only VFX that draws a ribbon mesh on the ground behind a drifting bike.

## Why local, not server-spawned

`slip_angle` is already network-synced (RollbackSynchronizer `state_properties`)
and `is_drifting` is re-derived each tick on every peer from synced inputs +
slip. So every client already knows when any player is drifting — no RPC or
server spawning needed. Same pattern as the spark particles (local nodes driven
by synced state). "Sync as little as possible."

## Component

`SkidmarkController` (`player/controllers/skidmark_controller.gd`), a child of
`AnimationController` in `player_entity.tscn`. Purely visual:

- Runs in `_process`, **not** the rollback tick (rollback re-simulates ticks and
  would duplicate/corrupt geometry).
- Reads `movement_controller.is_drifting` and `player_entity.rear_raycast`
  (ground contact point + normal). Both valid on every peer for every player.
- Not gated on `is_local_client` — we want to see other players' marks too.

## Geometry

- A ribbon = one continuous drift. While `is_drifting`, each frame appends a
  point pair at the rear-wheel ground contact (once it has moved
  `min_segment_dist`), offset slightly along the floor normal to avoid
  z-fighting. Built as a `PRIMITIVE_TRIANGLE_STRIP` in an `ImmediateMesh`.
- The `MeshInstance3D` is `top_level` (vertices authored in world space) and
  parented to the level (`player_entity.get_parent()`), so marks stay put and
  clear on level reload.
- Drift ends → ribbon is finalized; the next drift starts a fresh ribbon.

## Lifetime — fade + cap

- Finalized ribbons fade alpha over `fade_time` (shader `fade` uniform), then
  free.
- Per-player `max_ribbons` budget recycles the oldest ribbon. Bounds memory
  (total = players × max_ribbons).

## Material

A `ShaderMaterial` (one per ribbon, for independent fade). The shader maps
texture luminance → alpha (black ink opaque, white background transparent) so it
works whether or not `skidmarktex.png` carries an alpha channel.

## Not done here

- Tire-screech SFX (separate TODO item).
- Stationary burnout marks (no movement → no segments; out of scope).
