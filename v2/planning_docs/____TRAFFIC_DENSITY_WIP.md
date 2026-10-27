# Traffic Density Near Players (WIP, not started)

Goal: free-roam traffic feels dense around players without raising `traffic_count`, and busy
roads carry more traffic than side streets. Builds on [NPC Traffic Manager](./Architecture.md#npc-traffic-manager).

## Decisions

- **Ambient fill stays.** Only enough riders are pulled toward players to meet a per-player
  target; the rest keep driving wherever they are.
- **Per-road density weight.** A road between intersections can be marked busier; it gets
  proportionally more spawns and recycles.
- **No visible pop-in.** Recycled riders land *outside* `near_radius` of every player, where
  they're already undrawn on every peer (host: `set_drawn`; clients: no sync stream). They
  become visible by driving in, which is the existing edge pop-in.
- **Multiplayer:** each recycle serves the player with the fewest riders near them
  (interpreted from "yes"; confirm before implementing).
- **Free roam only.** Races (`_for_race`) keep today's even spread.
- **Recycled riders keep cruise speed**, since they'll drive into view. `teleport_to` zeroes
  `current_speed`, so set it to `cruise_speed()` after.

## Plan

1. **Road weight** → verify: rebake, weight survives in the `.tres`.
   - `TrafficRoad`: `traffic_weight` export (redraw setter like `lane_width`).
   - `TrafficLaneData`: `weight`, set in `TrafficNetworkBaker._build_direction` from the road.
     Turn lanes don't need it (never spawn targets).
   - Add the weight to `TrafficNetworkBaker.source_hash`, or changing it won't flag the bake stale.
2. **Weighted initial spawn** → verify: busy roads visibly fuller on start.
   - `start_traffic`: replace the shuffled round-robin with a weight-proportional lane pick.
     Keep the "skip if no clear spot" behavior.
3. **Spawn candidates** → verify: count logged once per start.
   - In `start_traffic`, build a flat list of road-lane spots from `TrafficLaneData.points`
     (lane, offset via `lane_curve().get_closest_offset`, position, travel direction).
     Every point is denser than needed; stride it.
4. **Recycle in `_update_lod`** (server, free roam only, capped per pass) → verify: drive
   around solo, traffic keeps appearing ahead; no rider ever appears inside the radius.
   - Per-player near count falls out of the `_near_peers` pass already running there.
   - Pick the player furthest under target; pick a random rider whose `_near_peers` is empty.
   - Candidate spot filter: within a band just outside `near_radius` of the target player,
     outside `near_radius` of *every* player, lane heading toward the target player
     (direction · to-player > 0, or it drives away and gets recycled again), weighted by
     lane weight, `_is_spot_clear`.
   - Move it the way `_place_on_lane` does: set `traffic_state.follower` (moves its
     `_lane_riders` entry), `teleport_to`, then restore cruise speed.
5. **Docs** → `Architecture.md` NPC Traffic Manager + Traffic Network authoring sections,
   then delete this file.

## New tunables (names only)

- `TrafficRoad.traffic_weight` — relative spawn/recycle share for that road.
- `TrafficSettings` — riders targeted near each player; the band width beyond
  `near_radius` that recycles land in.

## Open / noted

- Crash recovery's random-lane fallback in `_place_on_lane` can already drop a rider inside a
  player's view. Out of scope, but it could reuse step 4's spot filter.
- Candidate filtering is a linear scan per recycle. Fine at the per-pass cap; swap for a grid
  if a map's network gets large.
- No one-way roads exist in the baker today (lane count is split evenly per direction), so
  "1-way roads are quieter" is expressed only through weight for now.
