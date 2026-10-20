# Traffic AI — Design + Build Order

> Ambient traffic driven by a hand-placed, editor-baked traffic network. No road-addon lane
> data, no `Path3D`/`Curve3D` editing. NPC racers are out of scope.

## Intent

- Traffic follows the roads, keeps right, and obeys intersections (lights / stop signs / yield).
- The network is **authored with custom placeable nodes**, not curve handles — the Godot curve
  editor is the thing being avoided.
- Roads will change (new island map, non-addon road meshes), so traffic must not read
  `RoadManager` / `RoadLane` / `RoadIntersection` at all. What counts as road is known via a
  `road` **collision layer**.
- The network is **baked by an editor button** into a `.tres` that ships with the level. Runtime
  only reads the bake.

**Non-goals:** NPC racers, A\*/destinations (riders pick a random legal turn), overtaking,
traffic light props (debug draw only for now), one-way roads.

**Anti-goals:** curve handles in the authoring flow; a bake that silently produces a broken
network (every problem must be visible in the editor); riders that teleport-recover in normal
driving.

---

## How it works

### Authoring nodes (`levels/components/traffic/`)

```
TrafficNetwork (Node3D, @tool)           ← one per level; Bake button; holds the baked .tres
 ├─ TrafficRoad (Node3D, @tool)          ← child order = road path
 │   ├─ TrafficRoadPoint                 ← end: an intersection slot points at this road
 │   ├─ TrafficRoadPoint                 ← middle: shape only
 │   └─ TrafficRoadPoint                 ← end
 └─ TrafficIntersection (Node3D, @tool)
```

**`TrafficRoad`**
- Child `TrafficRoadPoint`s in tree order are the road. Reordering children reorders the road.
- `lane_width` export.
- Never links to anything — intersections link to roads (one source of truth).

**`TrafficRoadPoint`**
- `lane_count` — **total across both directions** (4 = 2 each way). `0` = same as the previous
  point; the first point must set it. Must be even.
- A count change between two points is a merge/split there (see Bake).

**`TrafficIntersection`**
- Four slot exports, `north` / `east` / `south` / `west`: `TrafficRoad` or empty (n/a). Directions
  are in the intersection's own basis (north = -Z, east = +X), so rotating the node works.
- `radius` — the box; road lanes stop here (the stop line), turn lanes live inside it.
- `control`: `enum ControlType { NONE, STOP, LIGHT }` (`Control` shadows the native class).
- `LIGHT` phases: north/south green together, then east/west. Phase is a pure function of
  `NetworkTime.time` (no Timer, no stored index) so every peer agrees with no sync. Green and
  amber durations are exports.
- Which end of a slotted road connects is resolved by proximity (nearest end point).
- **Cul-de-sac / dead end:** an intersection with exactly one linked slot. It's the only case that
  gets U-turn lanes; `control` is ignored there.

**`TrafficNetwork`**
- `@export_tool_button("Bake")` → builds and saves `baked: TrafficNetworkData` to a `.tres` next to
  the level scene.
- `show_in_editor` toggle for the editor drawing.

### Editor visuals

Drawn with the `debug_draw_3d` addon, editor only, nothing saved into the scene. **No per-frame
work:** nodes call `TrafficNetwork.request_redraw()` on transform / export / child-order changes;
the network clears and redraws once (deferred) with long-lived draws, depth test off.

- **Road:** polyline through its points; live preview of the lanes + direction arrows, so you see
  merges as you drag points. No text labels.
- **Intersection:** the `radius` box, an arm per slot — grey stub = empty, green = linked and the
  road's near end is on the slot's side (~45°), red = wrong side. Distance isn't checked; a gap
  just makes a longer turn lane.
- **Road point not over the `road` layer:** red sphere.
- `_get_configuration_warnings()` on all three: road with < 2 points, odd/unset lane count, road
  end not claimed by any intersection, lane count changing on a road's first/last segment, slot
  road whose nearest end is on the wrong side, empty intersection, network with no bake / stale
  bake. **Bake refuses while any of these exist**, and after building rejects lanes clipped away
  or with no successor.

### Bake

1. **Snap heights.** Ray down from each road point against the `road` collision layer
   (`TrafficRoadPoint.road_hit_at`, editor world's direct space state). A miss is a bake warning,
   not a crash. On Bake only (not the editor preview, to keep redraws cheap) every sampled lane
   point is snapped too (`_snap_lanes`), since traffic rides at the baked height; a sample miss
   keeps its height silently. The user will also snap points to the ground while editing.
2. **Road lanes.** For each `TrafficRoad`, offset the point chain right of travel by
   `lane_width` per lane, once per direction, so each direction keeps right. Round corners
   (sampled, not exposed as curves). Clip both ends at the attached intersection's `radius`.
3. **Merges.** Where `lane_count` drops between two points, the outer lane(s) of the wider side
   taper into the adjacent remaining lane and become its predecessor; a rise splits the same way.
4. **Turn lanes.** Per intersection, every incoming lane gets connections to each other
   non-empty slot (no U-turns): right turn from the rightmost lane → rightmost exit lane, left
   from leftmost → leftmost, through lane *i* → exit lane *i* (clamped when counts differ).
   A 1-slot cul-de-sac instead gets U-turns only: incoming lane *i* → outgoing lane *i*.
   An approach with a single exit (L-bend, cul-de-sac) pairs every lane with it, lane-for-lane.
   Geometry is a sampled bezier from the stop line to the exit lane start. Each turn lane
   records its intersection, entry slot, and `TurnDir { LEFT, THROUGH, RIGHT, U_TURN }`. A turn
   lane's first point is the stop line, its last point the exit lane's start.
5. **Conflicts.** Per intersection, mark every pair of turn lanes whose sampled paths come within
   a vehicle width of each other horizontally, **except** pairs sharing an entry lane (same
   queue). Done once at bake.
6. **Save** `TrafficNetworkData`: sub-resources `TrafficLaneData` (points, successor indices,
   intersection index or -1, entry slot, turn dir, conflicting lane indices) and
   `TrafficJunctionData` (position, control, phase timing). References are plain ints.

### Runtime

Server-only simulation: clients get `sync_transform` via the existing `MultiplayerSynchronizer`.
**Traffic rides on rails with no physics** — the state decides a target speed, the follower
advances along the lane by it, and the rider is placed there. (Changed from the original
steer + `move_and_slide` design: at 96 riders `move_and_slide` was most of the traffic cost, and
traffic must scale to more riders on a basic PC.)

**`NPCTrafficManager`** (`managers/npc_traffic_manager.gd`)
- `start_traffic()` finds the level's `TrafficNetwork` node; no node or no bake = no traffic.
  Linked into free roam only (`main_game.tscn`); race `TrafficComponent`s are deliberately
  unlinked.
- Builds one `JunctionState` per baked junction and hands the shared array to every rider's
  state alongside its follower.
- Spawns round-robin on random points along **road** lanes (never turn lanes — they cluster),
  parented under the `TrafficNetwork` node.
- `rpc_spawn_npc` zeroes the rider's `collision_layer` / `collision_mask` **on every peer** — a
  predicting client would otherwise bump into a body the server rides through.
- `_on_npc_crashed` crashes the rider once (a wreck keeps reporting contacts) and crashes a
  `PlayerEntity` victim via `spawn_manager.crash_player`. Recovery (`_place_on_lane`) advances
  the follower and teleports, else a random clear road lane. No stuck recovery — riders on rails
  can't wedge.
- No lane-occupancy table (dropped from the original spec — see exit-clear below).

**`TrafficLaneFollower`** (`entities/npc/traffic_lane_follower.gd`, `RefCounted`)
- Current lane + offset; **authoritative** for traffic position. `advance(dist)` moves along and
  across successors. `point_ahead(dist)` / `get_transform()` sample without moving.
- Turn choice is latched per lane in `_choices` until the rider leaves that lane, so the gate
  re-asks about the same turn every tick without re-rolling it.
- `next_turn_lane()` — next turn lane on the latched path (past the current one if inside a
  junction). `dist_to_junction()` — distance along the path to its stop line.
- Builds a runtime `Curve3D` per lane (in `TrafficNetworkData.lane_curve`) for sampling only.

**`NPCRiderEntity`** helpers used by traffic
- `lane_speed()` — corner speed (shared with race). `stop_line_speed(dist)` —
  `sqrt(2 · braking · (dist − STOP_LINE_BUFFER))`, 0 inside the buffer / past the point.
  `STOP_LINE_BUFFER` ≈ a car's half length, measured from the rider's centre.
- `ramp_speed()` (accel / braking toward a target), `ride_to(pos, dir, delta)` — places the
  rider, sets `velocity = dir · current_speed` (blockers and contact read it), faces velocity,
  writes `sync_transform`.
- `nearest_racer_ahead(range, angle, slower_only)` — race passes `true` (only racers worth
  passing); traffic passes `false` (any racer not oncoming), so a queue stays held once speeds
  match. Throttled per rider and O(n²) over the Racers group.
- `ContactArea` (`Area3D` child in `npc_rider_entity.tscn`, mask + layer `crash_collision`, off
  by default; shape copied from the body in `_init_collision_shape`). Only the traffic state turns
  it on (server). Race bots keep their body, `move_and_slide`, and stuck check.

**`NPCTrafficState` — per tick** (`entities/npc/states/npc_traffic_state.gd`)
```
if crashed: leave junction, stand still
release claimed junction once its turn lane is neither under us nor next ahead
target_speed = lane_speed                                         # corners
             min blocker_speed + stop_line_speed(gap − buffer)   # queue: stop a gap behind
             min _gate(...)                                       # stop line until let in
ramp_speed; follower.advance(current_speed · delta); ride_to(lane point + line_offset)
```

- **Junction gate** (`_gate`):
  - Only asks once the stop line actually slows the rider (checked after the blocker cap), so
    riders far away or queued behind someone never claim.
  - **Claims on grant** (`JunctionState.enter` the same tick `may_enter` says yes), so two
    riders can't both see an empty junction — the server ticks riders sequentially.
  - Clauses, in order:
    1. Waited longer than `junction_timeout` → go. Wait time is per rider in the state, and
       only counts while the light (if any) is green: a red always holds.
    2. `LIGHT`: turn's entry slot isn't green (amber included) → wait. Phase from
       `TrafficJunctionData.light(slot, NetworkTime.time)`.
    3. `STOP`: rider hasn't fully stopped, or isn't head of `JunctionState`'s arrival queue →
       wait. A rider joins on its first stopped ask; `enter()` / `leave()` take it out, and a
       crash leaves via `_leave_junction`.
    - `TrafficNetworkData.control(turn)` gives a turn's control; cul-de-sac U-turns get `NONE`.
    4. A conflicting turn lane is occupied (`JunctionState.may_enter`) → wait.
    5. Exit not clear (`_exit_clear`): a stopped racer within `EXIT_CLEARANCE` of the turn
       lane's last point, along the exit direction and within a vehicle width of its line →
       wait. Spatial check instead of lane occupancy.
  - The original clause 6 (`NONE` tie-break, turning yields to through) was **dropped** — claim
    on grant already prevents simultaneous entry.
  - `leave()` happens when the claimed lane is behind the rider, when it's crashed, and in
    `Exit()`. The manager never calls it.
- **Contact** (`_on_contact`, from `ContactArea.body_entered` + `area_entered`; another traffic
  rider's `ContactArea` stands in for its body):
  - Both sides of a hit see it; each rider only crashes itself (`crashed.emit(racer)`).
  - A player has no body to bump off, so **any touch from a player crashes both**, wrecks
    included. Rider-to-rider contact needs relative velocity ≥ `contact_min_speed_delta` so
    queued riders brushing don't wipe out.
- **Player in front:** the blocker cap brakes for a player and stops behind a stopped one.
  No go-around (dropped 2026-10-19: doesn't fit rails).

### Kept as-is

`NPCRaceManager`, `NPCRaceState`, `TrafficRouteGraph`, and the rider's `RoadLaneAgent` stay for
racers, including their physics body, `move_and_slide`, stuck check and `report_hit`. The rider
only creates its `lane_agent` when `road_manager` is set (race spawns); traffic spawns don't set
it.

---

## LOD + network culling

**Intent:** rider count scales on a basic PC **and online** (Steam). The server keeps the whole
city moving; each peer only draws, and only receives updates for, the riders near its own
player. Triggered by v0.0.151's Steam lag: 64 riders syncing a full `Transform3D` every
rendered frame flooded the link (fixed for now with `replication_interval` on the rider's
`MultiplayerSynchronizer`).

**Non-goals:** racers (`NPCRaceManager` riders keep today's path, apart from the pose change
below), the `nearest_racer_ahead` O(n²) fix, hysteresis at the radius edge (add only if
flicker shows up in play).

**Anti-goals:** far traffic that freezes or teleports (the city keeps moving); stale "ghost"
riders on a client where a rider used to be; per-frame, per-peer visibility callbacks.

### One radius

`near_radius` (export on `NPCTrafficManager`) is the single line for everything: a rider within
it of **any** player is *near* — full-rate tick, `ContactArea` on. A rider is only synced to and
drawn by the peers whose player is within it. Pop-in at the edge is accepted; there's no fog to
hide it on current maps, so tune it in play.

### Pose: position + yaw

Riders only ever rotate around Y (`_face_velocity`, `Basis.looking_at` on a flattened dir), so
`sync_transform: Transform3D` becomes `sync_position: Vector3` + `sync_yaw: float`, both
`ALWAYS` in the synchronizer. Applies to racers too — same entity, same synchronizer.
`NPCRaceManager._respawn_npc` teleports to a checkpoint's `global_transform`, which may be
tilted; `teleport_to` flattens it to yaw so server and clients agree.

### One write per tick

`ride_to` keeps yaw in a var (same `lerp_angle` as `_face_velocity`) and writes
`global_transform` once, instead of restore → `global_position` → `rotation.y`. Traffic skips
`NPCRiderEntity._physics_process`'s restore — the follower, not the node, is traffic's
authoritative position. `ride_to` also takes over setting `_phys_prev` (the pose before this
write) for the host's render smoothing. Traffic's reads of other racers' `global_position` may
see the server's render-smoothed pose (≤ 1 tick behind); accepted, they're already throttled
scans.

### Batched tick (server)

`NPCTrafficManager._physics_process` loops its riders and calls
`npc.state_machine.current_state.Physics_Update(dt)` — through the state machine, so a rider
still in idle before its deferred transition is handled. Traffic riders' own `StateMachine` and
`NPCRiderEntity` physics processing are switched off at spawn (server branch of
`rpc_spawn_npc`). Clients already have the state machine off.

### Server LOD

A LOD pass on a fixed interval (not every tick) measures each rider against every
`PlayerEntity` in the Racers group (peer id = node name) and records which peers it's near.
Distance is from the player, not the camera. A player respawning onto a far rider can go
untouched by it for up to one pass interval; accepted.

- **Near:** ticks every physics tick.
- **Far** (near nobody): ticks every `far_tick_interval`-th tick with the time accumulated
  since its own last tick. Far riders are bucketed round-robin so 1 / `far_tick_interval` of
  them tick per frame. A far rider that turns near ticks next frame with its accumulated time.
- `ContactArea` `monitoring` / `monitorable` on only while near (still only in
  `NPCTrafficState`).
- Rails make the big step safe: `advance(speed · dt)` doesn't care. The gate and blocker just
  react later. A far rider can overshoot a stop line by one coarse step — unseen, and it settles
  once near.
- **Lights (step 6):** far riders still run `_gate` on their coarse ticks and read the light
  phase from `NetworkTime.time` at that tick, so they obey lights unseen. Nothing here changes
  how `_gate` is built.

### Network visibility

- Traffic riders' synchronizer: `public_visibility = false`,
  `visibility_update_mode = NONE`, set on the server at spawn. Racers keep the defaults.
- The LOD pass calls `set_visibility_for(peer, near)` only when a peer's near set changes. The
  host (peer 1) is skipped — it's local.
- Every peer still **spawns every rider** (`rpc_spawn_npc` / `request_traffic_sync`
  unchanged). Only the sync stream is culled.
- `npc_state` (`ON_CHANGE`) must arrive correct when a rider becomes visible again. Godot
  resets a peer's delta baseline when visibility drops, which should resend it; **verify** (see
  L4).

### Drawing

Hidden = root `visible = false`, `set_process(false)` (client smoothing), and the
`NPCAnimationController`'s physics off. Showing snaps `global_transform` to the synced pose
instead of lerping from a stale one.

- **Host:** shown when near its own player — straight from the LOD pass.
- **Client:** spawns hidden; shown when its last sync arrived recently. The `sync_position` setter records the
  time and shows a hidden rider. `NPCTrafficManager` sweeps its riders on an interval and hides
  stale ones. No client distance math, and nothing can render at a position the server stopped
  updating.

### Tunables

| Export (`NPCTrafficManager`) | Effect |
| --- | --- |
| `near_radius` | Full tick, contact, sync and drawing inside it. Bigger = less pop-in, more cost and bandwidth |
| `far_tick_interval` | Far riders tick once per this many physics ticks. Bigger = cheaper, coarser far behavior |

The LOD pass interval and the client stale timeout stay constants. The stale timeout must cover
several missed packets at the synchronizer's `replication_interval`, or riders blink on lossy
links.

---

## Build order

Each step lints clean + headless-loads before the next. The user runs the game and checks each
step in-game; stop after each one.

- [x] **0. Road layer.** `3d_physics/layer_7="road"`, on stunttrack01's `RoadManager`.
- [x] **1. Authoring nodes + editor visuals.**
- [x] **2. Bake.**
- [x] **3. Follow lanes.**
- [x] **4. Stop line.** `stop_line_speed()` + queue braking behind the rider ahead.
- [x] **5. `JunctionState` + gate.** Clauses 1, 4, 5; claim on grant. Verified on a 4-way in
      stunttrack01. Followed by the rails + `ContactArea` rework (verified: better FPS, player
      contact crashes both).
> L1–L4 and 6 were built together on 2026-10-19 and none is verified yet. Check them in order.

- [ ] **L1. Pose + one write.** `sync_position` / `sync_yaw`, flattened `teleport_to`, single
      `global_transform` write in `ride_to`. **Verify:** solo + 2 peers, traffic and race bots
      look the same as before.
- [ ] **L2. Batched tick.** **Verify:** traffic behaves the same solo; the per-rider
      `StateMachine._physics_process` dispatch is gone from the profiler.
- [ ] **L3. Server LOD + host drawing.** **Verify:** solo, drive across the map — riders appear
      within `near_radius` already moving along the lanes, with no visible stutter near the player.
- [ ] **L4. Network visibility + client drawing.** **Verify:** 2 peers far apart each see only
      their local traffic; ping stays at LAN levels over Steam; crash a rider, drive away and back
      — the other peer sees the wreck state correctly.
- [ ] **6. Lights + stop signs.** Gate clauses 2 + 3. Light phase is a **pure function of
      `NetworkTime.time`** (no Timer, no stored index) so every peer agrees with no sync; N/S
      green together, then E/W, using the junction's `green_duration` / `amber_duration`.
      `STOP`: full stop + arrival queue. Cul-de-sacs ignore control. Runtime debug draw of each
      slot's light state, behind a `dbg_traffic` console command (`LevelManager` registers it,
      `TrafficNetwork.show_lights` draws a sphere over each lit turn lane's stop line). The light
      state matters on the server for the gate and on every peer for the debug draw.
      **Verify:** two peers show the same light at the same moment; riders hold at red past
      `junction_timeout`; a STOP junction lets riders go one at a time in arrival order.
- [ ] **8. Docs.** Fold the final shape into `Architecture.md` (NPC / traffic section), then
      delete this file.

## Handoff notes

- Follow `CLAUDE.md` strictly: no git/gh, don't edit `planning_docs/TODO.md`, read before
  deciding, ask before choosing how something should work, terse comments, prefer deleting.
- Before reporting any `.gd` change done: `python -m gdtoolkit.linter <paths>` clean, and the
  headless editor load from `CLAUDE.md` prints nothing. Logic can be tested headless with an
  `extends SceneTree` script in the scratchpad via `--script` (autoloads don't load there).
- Editor `@tool` code must never do per-frame work; `TrafficNetwork` redraws only on change via
  `TrafficNetwork.request_redraw(node)`.
- Known open bug, leave unless asked: the editor preview (DebugDraw3D long-duration draws)
  disappears whenever nothing is moving.
- Pending request, **confirm with the user before building:** auto-rebake when the bake goes
  stale after a committed edit (gizmo release, inspector change) — connect
  `EditorInterface.get_editor_undo_redo()`'s `history_changed` / `version_changed`, looking
  `EditorInterface` up via `Engine.get_singleton("EditorInterface")`; skip silently while config
  warnings exist.
- Traffic no longer kills animals: animals only listen for `body_entered`, and traffic has no
  body. Fix is connecting the animal's `area_entered` too — not done, ask first.
- Next perf bottleneck past ~100 riders: `nearest_racer_ahead` (O(n²)). Fix idea: rider ahead
  from per-lane order, players checked separately.
- Turn lanes passing between `VEHICLE_WIDTH` and roughly a car width + line-offset wander apart
  aren't marked conflicting; if cars clip mid-junction, raise the baker's `VEHICLE_WIDTH` and
  rebake.

## Later

- Traffic light props from `levels/assets/props/Traffic Light.glb`, reading the same clock phase.
- Route-driven traffic (destinations + A\* over intersections).
- NPC racers on the new network.
- Overpasses: the height snap is a single down-ray, so stacked roads need a closer start height.
