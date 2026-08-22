# Traffic AI — how our code works

> Where ambient traffic lives in the codebase, what each file is responsible for, and the traps
> already hit once.
>
> Concepts (A\*, right-of-way, why lights are maths) are in [Navigation.md](./Navigation.md).
> The build order for what's missing is in [TrafficAI_TODO.md](./TrafficAI_TODO.md).

## Where it stands

Traffic riders drive around the road network forever without hitting things. That part works.

What they don't do is **navigate**. At every junction the rider asks for the lanes it could
continue onto and calls `pick_random()` on the result. There are no destinations, no costs, and
no rules — intersections don't exist to the AI at all, they've been dissolved into a handful of
short overlapping lane curves stitched together by proximity.

So: the "which lane next" question from [Navigation.md](./Navigation.md) is answered badly, and
the other two questions ("where am I going", "can I go now") aren't asked yet.

## Architecture — who owns what

Traffic follows the project's usual Manager + State Machine pattern. Nothing here is special;
it's the same shape as `NPCRaceManager`.

```
ManagerManager
 └─ NPCTrafficManager  (BaseManager)        ← owns everything below, server only
      │  started by FreeRoamGameMode / StreetRaceGameMode on Enter
      │  holds  _route_graph : TrafficRouteGraph
      │
      └─ spawns NPCRiderEntity  (CharacterBody3D, ids counting down from -1000)
           ├─ StateMachine
           │    ├─ NPCIdleState
           │    ├─ NPCTrafficState   ← the brain: decides where to go, how fast
           │    └─ NPCRaceState
           ├─ RoadLaneAgent (addon)  ← follows one lane curve, created in _ready
           └─ MultiplayerSynchronizer on `sync_transform`
```

Read it as three jobs:

| Layer | File | Job |
| --- | --- | --- |
| **Lifecycle** | `managers/npc_traffic_manager.gd` | build the map, spawn riders, recover crashes |
| **Brain** | `entities/npc/states/npc_traffic_state.gd` | per tick: where next, how fast |
| **Body** | `entities/npc/npc_rider_entity.gd` | steering, speed ramping, collision, the mesh |
| **Map** | `entities/npc/traffic_route_graph.gd` | lane → the lanes you may continue onto |

The split that matters: **the brain never touches the transform and the body never makes a
decision.** `NPCTrafficState` picks a target point and a target speed; `NPCRiderEntity` turns
those into velocity. Anything new goes on the side of that line it belongs to — a stop-line
speed is a body question, a "may I enter" is a brain question.

### Server-only, and why that's a gift

All AI runs on the server. `NPCRiderEntity._ready` calls `state_machine.set_physics_process(false)`
on every non-server peer, so clients never simulate a rider — they just receive `sync_transform`
over a plain `MultiplayerSynchronizer` and ease toward it in `_process`.

That means anything you add to the decision-making needs **no networking at all**. No RPCs, no
rollback, no prediction. The one exception is traffic light *visuals*, which have to render on
every peer — and that's exactly why the phase should be calculated from the clock (see
[Navigation.md](./Navigation.md), "why lights should be maths"). Clock maths costs nothing to
replicate because there's nothing to replicate.

### How a level's road data gets in

`start_traffic()` finds the level's `RoadManager`, gathers every AI lane, and builds the
`TrafficRouteGraph`. Then it connects each container's `on_road_updated` so the graph gets
rebuilt whenever the road generator regenerates its lanes.

Those are the two hooks. **Anything new that's derived from the road network hangs off exactly
these two places**: built in `start_traffic()`, rebuilt in `_rebuild_route_graph()`, handed to
riders in `rpc_spawn_npc()` next to `traffic_state.route_graph = _route_graph`, and nulled in
`stop_traffic()`.

---

## File by file

### `entities/npc/traffic_route_graph.gd` — the map (121 lines)

A `RefCounted` holding `lanes` and `_successors: Dictionary[RoadLane, Array]`. This is the lane
lookup from [Navigation.md](./Navigation.md), and it is the entire current navigation system.

`_find_successors(lane)` is the whole idea:

1. If the addon set `lane.lane_next`, that's the only successor. Done.
2. Otherwise **snap geometrically** — any lane whose start is within 6 m of this lane's end and
   points roughly the same way (heading dot > 0.3).

Step 2 exists because the addon never links intersection lanes at all (see the next section).
Without it, nothing could drive through a junction.

Worth preserving when you extend it: `rebuild()` re-derives **in place**, so riders holding a
reference survive a road rebuild; `gather_lanes()` is static and checks both the manager's lane
group and each container's own override; `lane_transform_at(lane, t)` gives a pose partway along
a lane, which is what stops everything spawning on top of each other.

What it doesn't have: costs, destinations, any concept of an intersection, or any search.

### `entities/npc/states/npc_traffic_state.gd` — the brain (151 lines)

`Physics_Update` in order:

```
no lane under us?     → throttled re-latch attempt, coast, return
_pick_next_lane_at_junction()
target       = lane_point_ahead(steer_lookahead())
target_speed = lane_speed()
blocker ahead and slower? → cap target_speed to theirs   (queue, never overtake)
steer_toward(target, target_speed, delta)
apply_gravity_and_move(delta)
_check_contact() ; _check_stuck(delta)
```

Note that `target_speed` is already built by taking the **minimum of independent caps**. That's
the pattern to follow — a stop line is just one more upper bound on the same number, not a new
mechanism.

And the entire routing brain, `_pick_next_lane_at_junction()`:

```gdscript
if !npc.lane_agent.close_to_lane_end(junction_proximity, RoadLaneAgent.MoveDir.FORWARD):
    return
var successors := route_graph.next_lanes(npc.lane_agent.current_lane)
if successors.is_empty():
    npc.lane_agent.assign_nearest_lane()   # dead end the graph didn't cover
    return
npc.lane_agent.assign_lane(successors.pick_random())
```

Five lines, and `pick_random()` is the navigation. **This is the only place a routing decision
is made**, so it's where every new layer plugs in.

Two signals go up to the manager, which owns recovery: `crashed(victim)` and `stuck`.

### `entities/npc/npc_rider_entity.gd` — the body (513 lines)

The parts navigation touches:

| Member | Notes |
| --- | --- |
| `lane_agent` | created in `_ready`; needs `road_manager` set before that |
| `lane_point_ahead(dist)` | steering target, nudged sideways by this rider's `line_offset` |
| `cruise_speed()` | `move_speed × _speed_scale` (per-rider variance) |
| `lane_speed()` | **corner-aware** target speed — see below |
| `steer_toward(target, speed, delta)` | ramps `current_speed`, points horizontal velocity |
| `coast_to_stop(delta)` | decays velocity by `braking` |
| `nearest_racer_ahead(range, angle)` | slower racer in a forward cone. Throttled |
| `apply_gravity_and_move(delta)` | the one place `sync_transform` is written |

`lane_speed()` is the file's most useful precedent. It samples the lane's bend over the next
`turn_lookahead` metres, compares the near half's heading against the far half's, and eases
toward `min_turn_speed` when they diverge — so the rider **brakes before the corner** rather
than at it. Stopping at a stop line is the same shape of problem and belongs beside it, in the
body, not bolted into the state machine.

### `managers/npc_traffic_manager.gd` — lifecycle (369 lines)

Server authority. Beyond the two hooks described above:

- Riders spawn on negative ids from `-1000` (race NPCs count down from `-1`, so the two can
  never collide under the level's spawn node).
- Spawn is a broadcast RPC with a client-side accept gate (`_accept_spawns`) plus a
  `request_traffic_sync()` pull, because a broadcast can beat a peer's level load.
- Crash and stuck recovery both land in `_place_on_lane()`, which drops the rider a few metres
  ahead of where it went wrong, or onto a random point along a random lane if that spot is taken.

### Addon files you'll be reading

| File | What it gives you |
| --- | --- |
| `road_lane.gd` | one directional lane + `Curve3D`. Also `get_lane_start/end()` and per-lane vehicle registration, already maintained for free |
| `road_lane_agent.gd` | follows a lane. `move_along_lane` advances across `lane_next`; `test_move_along_lane` doesn't (that's what lookahead uses) |
| `road_intersection.gd` | knows its branches, **sorted clockwise**. The traffic AI never touches it — the single biggest missed opportunity in the current system |
| `intersection_ngon.gd` | `generate_lanes()` emits one `RoadLane` per turn, parented to the `RoadIntersection` |

Three facts from `intersection_ngon.gd` that a lot of the future work rests on:

1. **One `RoadLane` per turn.** You don't need to invent a "turn" type — a turn *is* an
   intersection-child lane.
2. **They're children of the `RoadIntersection`**, so `lane.get_parent()` is a free, exact test
   for "is this lane inside a junction".
3. **`_lane_stop_position()` is already the stop line.** It returns where a branch's lane meets
   the intersection, and it's used as the *start point* of every intersection lane. The geometry
   for "where do I stop" already exists.

One trap: `_tagged_lane_name()` bakes turn info into the node name as a suffix. **Don't parse
it** — it's a display detail and it collides-and-numbers on duplicates. Derive turn direction
from geometry.

Local addon edits are marked `PATCHED (DankNooner, <reason>)` — there's one in
`road_lane_agent.gd:238` that removed a duplicated closest-point search profiling at 17 ms/frame
with 128 agents. Follow that convention for any new one.

### `road_demos/navigation/astar_lane_graph.gd` — read it, don't copy it

A standalone demo that A\*s over the lanes. It works by dropping a point every 10 m along every
lane and wiring thousands of them into an `AStar3D` — because `AStar3D` needs nodes to be
positions. That's the workaround, not the design. Take the idea, not the implementation: the
routing map should be ~20 points, not ~2000.

---

## What breaks

All of these are real bugs that were already hit once.

1. **Lanes get freed and regenerated wholesale.** `RoadContainer.rebuild_segments` frees every
   `RoadLane` and rebuilds them, and it defers that on `_ready`. Any cached `RoadLane` may be a
   freed instance. Anything new keyed by `RoadLane` needs the same `is_instance_valid` hygiene
   and the same in-place `rebuild()` that `TrafficRouteGraph` has.

2. **Don't scan per tick.** `assign_nearest_lane()` walks every lane in the level;
   `nearest_racer_ahead()` walks the whole `Racers` group. Both are already throttled behind
   *randomised* timers, so riders don't sync up onto one big scan tick. Any new sweep needs the
   same treatment.

3. **Spawn points cluster at junctions.** Junction lanes all start within a few metres of each
   other, so anything picking "the start of a random lane" piles vehicles into intersections and
   leaves the roads empty. `lane_transform_at(lane, randf())` exists for this reason.

4. **`close_to_lane_end()` lies by design.** It returns false whenever `lane_next` is set, so it
   only ever fires on lanes with no successor — which happens to be exactly the lanes feeding a
   junction. Convenient, and load-bearing, but don't read it as "near the end of the curve".

5. **Refusing to enter a junction isn't enough to stop.** The rider is still being steered toward
   a point beyond the end of its curve, so it'll drive straight through the line and off the
   road. Any gate has to be paired with a target speed that reaches zero *at* the line.

6. **The player is not an NPC.** It's in the `Racers` group and it's a `CharacterBody3D` with
   `velocity`, so `horizontal_speed()` works on it — but it has no `lane_agent`, no lane, and
   will never ask permission for anything. Occupancy tracking has to tolerate a body that
   entered the junction without asking.

7. **Deadlock is guaranteed without a timeout.** Build it in from the first commit, not after
   you see four riders staring at each other.

8. **Lint before you call it done.** `.gdlintrc`'s `class-definitions-order` in particular:
   `@tool` → `class_name`/`extends` → docstring → signals → enums → consts → `@export` → public
   vars → private vars → `@onready` → static → built-in callbacks → public → private.
