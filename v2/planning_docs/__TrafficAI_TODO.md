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
    1. Waited longer than `junction_timeout` → go. Wait time is per rider in the state.
    2. `LIGHT`: turn's entry slot isn't green → wait. **(step 6, not built)**
    3. `STOP`: rider hasn't fully stopped, or isn't head of the arrival queue → wait.
       **(step 6, not built)**
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
- **Player in front (step 7, needs re-design):** the blocker cap already brakes for a player and
  stops behind a stopped one. The original plan (detour waypoint via `NPCNavRegion` +
  steering) doesn't fit rails — a go-around on rails would be a temporary lateral offset off the
  lane. Decide with the user before building.

### Kept as-is

`NPCRaceManager`, `NPCRaceState`, `TrafficRouteGraph`, and the rider's `RoadLaneAgent` stay for
racers, including their physics body, `move_and_slide`, stuck check and `report_hit`. The rider
only creates its `lane_agent` when `road_manager` is set (race spawns); traffic spawns don't set
it.

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
- [ ] **6. Lights + stop signs.** Gate clauses 2 + 3. Light phase is a **pure function of
      `NetworkTime.time`** (no Timer, no stored index) so every peer agrees with no sync; N/S
      green together, then E/W, using the junction's `green_duration` / `amber_duration`.
      `STOP`: full stop + arrival queue. Cul-de-sacs ignore control. Runtime debug draw of each
      slot's light state, behind a `dbg_traffic` console command next to the other level console
      commands in `managers/level_manager.gd` (check how those are registered first). The light
      state matters on the server for the gate and on every peer for the debug draw.
      **Verify:** two peers show the same light at the same moment.
- [ ] **7. Go-around.** Needs re-design for rails (see Runtime). **Verify:** stop on a lane in
      front of traffic — they stop, wait, go around, rejoin.
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
