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
- `control`: `enum Control { NONE, STOP, LIGHT }`.
- `LIGHT` phases: north/south green together, then east/west. Phase is a pure function of
  `NetworkTime.time` (no Timer, no stored index) so every peer agrees with no sync. Green and
  amber durations are exports.
- Which end of a slotted road connects is resolved by proximity (nearest end point).

**`TrafficNetwork`**
- `@export_tool_button("Bake")` → builds and saves `baked: TrafficNetworkData` to a `.tres` next to
  the level scene.
- `show_in_editor` toggle for the editor drawing.

### Editor visuals

Drawn with the `debug_draw_3d` addon in `_process` under `Engine.is_editor_hint()` only — nothing
is saved into the scene.

- **Road:** polyline through its points; live preview of the lanes + direction arrows, so you see
  merges as you drag points; lane count label per point.
- **Intersection:** the `radius` box, an arm per slot — grey stub = empty, green = linked and the
  road's near end is within reach, red = linked but too far / wrong side. `Label3D` for `control`.
- **Road point not over the `road` layer:** red sphere.
- `_get_configuration_warnings()` on all three: road with < 2 points, odd/unset lane count, road
  end not claimed by any intersection, slot road whose nearest end is on the wrong side, empty
  intersection, network with no bake / stale bake.

### Bake

1. **Snap heights.** Ray down from each road point against the `road` collision layer
   (`PhysicsDirectSpaceState3D` from the editor world). A miss is a bake warning, not a crash.
2. **Road lanes.** For each `TrafficRoad`, offset the point chain right of travel by
   `lane_width` per lane, once per direction, so each direction keeps right. Round corners
   (sampled, not exposed as curves). Clip both ends at the attached intersection's `radius`.
3. **Merges.** Where `lane_count` drops between two points, the outer lane(s) of the wider side
   taper into the adjacent remaining lane and become its predecessor; a rise splits the same way.
4. **Turn lanes.** Per intersection, every incoming lane gets connections to each other
   non-empty slot (no U-turns): right turn from the rightmost lane → rightmost exit lane, left
   from leftmost → leftmost, through lane *i* → exit lane *i* (clamped when counts differ).
   Geometry is a sampled bezier from the stop line to the exit lane start. Each turn lane
   records its intersection, entry slot, and `TurnDir { LEFT, THROUGH, RIGHT }`.
5. **Conflicts.** Per intersection, mark every pair of turn lanes whose sampled paths come within
   a vehicle width of each other horizontally, **except** pairs sharing an entry lane (same
   queue). Done once at bake.
6. **Save** `TrafficNetworkData`: sub-resources `TrafficLaneData` (points, successor indices,
   intersection index or -1, entry slot, turn dir, conflicting lane indices) and
   `TrafficJunctionData` (position, control, phase timing). References are plain ints.

### Runtime

Server-only, as today: clients get `sync_transform` via the existing `MultiplayerSynchronizer`.
Brain/body split stays — **the state decides target point + target speed, the rider turns them
into velocity.**

**`NPCTrafficManager`**
- `start_traffic()` finds the level's `TrafficNetwork` node (replaces `_find_road_manager()`); no
  node or no bake = no traffic, same as maps without roads today.
- Builds one `JunctionState` (`entities/npc/junction_state.gd`, `RefCounted`) per intersection.
- Spawns on random points along random **road** lanes (never turn lanes — they cluster).
- `_place_on_lane()` recovery rewritten against the network (nearest lane point ahead, else a
  random lane point). Spawn/sync RPCs unchanged.
- Holds lane occupancy (`lane index → riders`), updated when a rider changes lane — used for the
  exit-clear check.

**`TrafficLaneFollower`** (`entities/npc/traffic_lane_follower.gd`, `RefCounted`)
- Current lane index + distance along it. `point_ahead(dist)` walks across successors, using a
  turn choice latched once per junction approach. Builds a runtime `Curve3D` per lane for
  sampling only — never edited.

**`NPCTrafficState` — per tick**
```
target       = follower.point_ahead(lookahead)
target_speed = corner speed                      # existing lane_speed math, not duplicated
             min stop_line_speed(stop line)      # only while gated at a junction
             min blocker speed                   # existing nearest_racer_ahead cap
if go-around active: target = detour waypoint
steer_toward; apply_gravity_and_move; _check_contact; _check_stuck
```

- **Stop line:** `stop_line_speed(stop_point)` on the rider next to `lane_speed()` —
  `sqrt(2 · braking · d)` with a small buffer, 0 past the line. A refused gate alone isn't enough;
  the rider is steering past the line, so the speed cap is what stops it.
- **Junction gate** (`JunctionState.may_enter(rider, turn_lane)`), in order:
  1. Waited longer than the deadlock timeout → go (mandatory, ships in the first commit).
  2. `LIGHT`: turn's entry slot isn't green → wait.
  3. `STOP`: rider hasn't fully stopped, or isn't head of the arrival queue → wait.
  4. A conflicting turn is occupied → wait.
  5. Exit lane full → wait (anti-gridlock).
  6. `NONE` tie-break: turning traffic yields to through traffic already waiting.

  `enter()` on entry, `leave()` on exiting the box **and** on crash / despawn, or a wiped-out
  rider holds the junction until the timeout. The latched turn is re-asked every tick — never
  re-rolled while waiting.
- **Player in front:** the existing blocker cap already slows to the player and stops behind a
  stopped one. If the blocker is a `PlayerEntity` and the rider has been stopped behind it for
  `go_around_delay` (user wants 3 s), it drives around: a detour waypoint beside the player on the
  side with more room, projected onto `NPCNavRegion` with
  `NavigationServer3D.map_get_closest_point`, then rejoin the lane a few metres past them. Not
  triggered by junction waits or by queuing behind NPCs.
- **Stuck check** suppressed while gated or blocked by a player — waiting is correct behavior.

### Kept as-is

`NPCRaceManager`, `NPCRaceState`, `TrafficRouteGraph`, and the rider's `RoadLaneAgent` stay for
racers. The rider only creates its `lane_agent` when `road_manager` is set (race spawns); traffic
spawns don't set it.

---

## Build order

Each step lints clean + headless-loads before the next.

- [ ] **0. Road layer.** `3d_physics/layer_7="road"` in `project.godot`. Add it to stunttrack01's
      `RoadManager.collision_layer` (keep layer 1 — the player still drives on it).
- [ ] **1. Authoring nodes + editor visuals.** `TrafficNetwork`, `TrafficRoad`,
      `TrafficRoadPoint`, `TrafficIntersection` scenes + scripts, drawing, config warnings.
      **Verify (user):** place a 3-way in stunttrack01; empty/linked/broken arms read correctly.
- [ ] **2. Bake.** Data resources + bake steps 1–6, lane preview in the editor reuses the bake's
      lane-offset code. **Verify:** bake stunttrack01's 3-way; lanes keep right, a merge tapers,
      each approach has one THROUGH, opposing throughs aren't marked conflicting, crossings are.
- [ ] **3. Follow lanes.** `TrafficLaneFollower`, manager reads the bake, remove the
      `# HACK - DISABLE TMP` return in `NPCTrafficState`, random turns, no gating yet; recovery
      rewritten. Rider `lane_agent` made race-only. **Verify:** riders loop the network on the
      right; stuck/crash recovery lands them back on a lane.
- [ ] **4. Stop line.** `stop_line_speed()`, temporarily refuse every entry. **Verify:** riders
      stop at the line without overshoot or creep.
- [ ] **5. `JunctionState` + gate.** All six clauses, occupancy, latching, stuck suppression.
      **Verify:** a busy intersection interleaves; with the timeout disabled a standoff is
      reproducible.
- [ ] **6. Lights + stop signs.** Clock-driven phases, full-stop + arrival queue. Runtime debug
      draw of each slot's light state, behind a `dbg_traffic` console command (same place as the
      other level console cmds in `level_manager.gd`). **Verify:** two peers show the same light
      at the same moment.
- [ ] **7. Go-around.** Player-blocker timer + detour via `NPCNavRegion`. **Verify:** stop on a
      lane in front of traffic — they stop, wait, go around, rejoin.
- [ ] **8. Docs.** Fold the final shape into `Architecture.md` (NPC / traffic section), then
      delete this file.

## Later

- Traffic light props from `levels/assets/props/Traffic Light.glb`, reading the same clock phase.
- Route-driven traffic (destinations + A\* over intersections).
- NPC racers on the new network.
- Overpasses: the height snap is a single down-ray, so stacked roads need a closer start height.
