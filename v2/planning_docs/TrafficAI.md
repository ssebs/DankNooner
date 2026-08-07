# Traffic AI — Reference

> How NPC road navigation works in DankNooner, file by file, and what each file's job becomes
> once traffic rules land.
>
> Read [NavigationPrimer.md](./NavigationPrimer.md) first for the theory — this doc assumes the
> vocabulary from it (primal vs dual graph, movement, conflict set, admissible heuristic).
> Build order lives in [TrafficAI_TODO.md](./TrafficAI_TODO.md).

---

## 0. The short version

**Today:** there is no pathfinding. NPC traffic does a *random walk* over a lane-adjacency
table. Intersections do not exist as objects to the AI — they've been dissolved into a handful
of short overlapping lane curves that get stitched together by proximity. There are no weights,
no destinations, and no rules.

**Target:** add the primal (routing) graph above the existing dual (lane) graph, and a control
layer that gates junction entry. Ambient traffic keeps wandering; A* becomes available to
anything that wants it.

```
                                     ┌──────────────────────┐
   NEW                               │ RoutingGraph         │  intersections + weighted roads
                                     │ A* lives here        │  (primal graph)
                                     └──────────┬───────────┘
                                                │ built by walking ↓
   EXISTS  ┌─────────────────┐       ┌──────────▼───────────┐
           │ RoadLane curves │──────▶│ TrafficRouteGraph    │  lane → [legal next lanes]
           │ (addon)         │       │                      │  (dual graph)
           └─────────────────┘       └──────────┬───────────┘
                                                │
   NEW                               ┌──────────▼───────────┐
                                     │ JunctionControl      │  may I enter, right now?
                                     │ + conflict sets      │
                                     └──────────────────────┘
```

---

## PART A — What exists today

### A1. `addons/road-generator/nodes/road_lane.gd` — the node of the dual graph

`RoadLane extends Path3D`. One directional lane, one `Curve3D`. This is the atom of the whole
system.

The four connection fields are the addon's own idea of a graph:

| Field | Meaning |
| --- | --- |
| `lane_next: NodePath` | the single lane that follows this one |
| `lane_prior: NodePath` | the single lane that precedes it |
| `lane_left` / `lane_right` | the adjacent lanes, for lane changes |
| `lane_next_tag` / `lane_prior_tag` | strings like `F0`, `R1` used to auto-wire the above |

Note what that is: `lane_next` is **one** NodePath. That's a linked list, not a graph. It can
express "this lane continues into that one" and cannot express "this lane may go three
different ways." That single limitation is why `TrafficRouteGraph` exists.

Also useful and already maintained for you:

- `get_lane_start()` / `get_lane_end()` — world-space endpoints.
- `register_vehicle()` / `unregister_vehicle()` / `get_vehicles()` — **per-lane occupancy**,
  kept up to date automatically by `RoadLaneAgent.assign_lane`. Free input for congestion
  weights later.

### A2. `addons/road-generator/nodes/road_lane_agent.gd` — the follower

A helper node parented to a vehicle. Holds `current_lane` and converts "move me 12 m forward"
into a world position on the curve.

The methods that matter:

| Method | What it does |
| --- | --- |
| `assign_lane(lane)` | switch to a lane, handling register/unregister |
| `assign_nearest_lane()` | brute-force scan of *every* lane in the level, 50 m cutoff |
| `move_along_lane(d)` | position `d` metres ahead, **advancing `current_lane`** across `lane_next` |
| `test_move_along_lane(d)` | same, without advancing — used for lookahead sampling |
| `close_to_lane_end(prox, dir)` | true if within `prox` of the end **and `lane_next` is empty** |

Two things to know:

- `assign_nearest_lane()` is expensive — a `Curve3D.get_closest_point` per lane in the level.
  `npc_traffic_state.gd` deliberately throttles it behind a randomised 2–5 s retry timer
  (see the comment at `relatch_retry_delay_min`). Don't call it per tick.
- `close_to_lane_end()` returns false whenever `lane_next` is set. So it only ever fires on
  lanes with no successor — which, conveniently, is exactly the lanes that feed a junction.
  This is load-bearing behaviour that the current junction code relies on.

There is one local patch in this file, at `_move_along_lane` (~line 238), marked
`PATCHED (DankNooner, perf)` — it removed a duplicated closest-point search that profiled at
17 ms/frame with 128 agents. **That comment convention is how we mark addon edits.** Follow it.

### A3. `addons/road-generator/nodes/road_intersection.gd` — the node of the primal graph (unused)

`RoadIntersection extends RoadGraphNode`, a child of a `RoadContainer`. It holds
`edge_points: Array[RoadPoint]` — its branches — **sorted clockwise** by
`_sort_edges_clockwise()`.

This is already a perfectly good primal-graph node: it knows where it is, it knows its
branches, and it knows their angular order (which is what you need to say "the next branch
clockwise from the one I came in on" = a right turn).

**The traffic AI never touches it.** That's the single biggest missed opportunity in the
current system.

Also carries `@export var settings: IntersectionSettings` — the resource that generates its
geometry and lanes. The new `junction_control` export sits alongside it.

### A4. `addons/road-generator/procgen/intersection_ngon.gd` — where movements are born

`generate_lanes()` (line 59) is the important one. For each branch of an intersection it emits:

- **through lanes** — every entering lane routed across to the branch's "primary" opposite
  (surplus lanes merge onto the outermost exit lane),
- **turn lanes** — one per remaining branch, sourced from the outer entering lane for a
  clockwise turn and the inner one for a counter-clockwise turn (`_turn_is_clockwise`, line 120).

Three consequences you will build directly on top of:

1. **One `RoadLane` per movement.** You do not need to invent a movement type. A movement *is*
   an intersection-child lane.
2. **They are children of the `RoadIntersection` node** (`intersection.add_child(lane)` in
   `_get_or_create_lane`). So `lane.get_parent() is RoadIntersection` is a complete, zero-cost
   test for "this lane is inside a junction."
3. **`_lane_stop_position(edge, intersection, index)` (line 209) is the stop line.** It returns
   the world point where a given lane of a given branch meets the intersection — and it's used
   as the *start point* of every intersection lane. The geometry you need for "where do I stop"
   already exists.

One trap: `_tagged_lane_name()` (line 425) bakes turn info into the node name as a suffix —
`a` for a turn lane, `r` for a merged lane. **Don't parse it.** It's a display detail and it
collides-and-numbers on duplicates (`..._a2`). Derive turn direction from geometry instead.

### A5. `entities/npc/traffic_route_graph.gd` — the dual graph we actually use

~120 lines, `RefCounted`, and the entire current navigation system.

```gdscript
var lanes: Array[RoadLane] = []
var _successors: Dictionary[RoadLane, Array] = {}
```

`_find_successors(lane)` (line 91) is the whole idea:

1. If `lane.lane_next` resolves, that's the only successor. Done.
2. Otherwise, **snap geometrically**: any other lane whose `get_lane_start()` is within
   `_snap_distance` (6 m) of this lane's `get_lane_end()`, *and* whose start heading dots
   > `_heading_tolerance` (0.3) with this lane's end heading.

Step 2 is the patch for A3/A4: the addon never sets `lane_next` on intersection lanes, so
without this nothing can drive through a junction at all.

The rest is bookkeeping you should preserve:

- `gather_lanes(tree, road_manager)` — static; sweeps the manager's `ai_lane_group` *and* every
  container's own override group, because containers may each define their own.
- `rebuild(road_lanes)` — re-derives in place, so riders holding a reference survive it.
  Necessary because `RoadContainer.rebuild_segments` **frees and regenerates every lane**, and
  it defers that on `_ready`. Every cached `RoadLane` is potentially a freed instance; hence
  `is_instance_valid` checks throughout.
- `lane_transform_at(lane, t)` — a pose at fraction `t` along a lane. Used for spawning.
  Spawning everyone at `t = 0` piles them into intersections, because junction lanes all start
  within a few metres of each other.

**What it does not have:** weights, costs, destinations, any notion of an intersection, or any
search. `next_lanes()` returns an unordered array and the caller picks at random.

### A6. `entities/npc/states/npc_traffic_state.gd` — the driver

The behaviour state. `Physics_Update` each tick:

```
if no lane under us      -> throttled re-latch attempt, coast
_pick_next_lane_at_junction()
target      = lane_point_ahead(steer_lookahead())
target_speed= lane_speed()
blocker     = nearest_racer_ahead(...)  -> if found, cap speed to theirs (queue, don't overtake)
steer_toward(target, target_speed, delta)
apply_gravity_and_move(delta)
_check_contact(); _check_stuck(delta)
```

And the routing "brain" in full — `_pick_next_lane_at_junction()`, line 103:

```gdscript
if !npc.lane_agent.close_to_lane_end(junction_proximity, RoadLaneAgent.MoveDir.FORWARD):
    return
var successors := route_graph.next_lanes(npc.lane_agent.current_lane)
if successors.is_empty():
    npc.lane_agent.assign_nearest_lane()   # dead end the graph didn't cover
    return
npc.lane_agent.assign_lane(successors.pick_random())
```

Five lines. `pick_random()` is the navigation. **This function is where the new layers plug
in** — it's the only place a routing decision is made.

Two signals go up to the manager, which owns recovery: `crashed(victim)` and `stuck`.

### A7. `entities/npc/npc_rider_entity.gd` — the body

`CharacterBody3D`. Relevant to navigation:

| Member | Notes |
| --- | --- |
| `lane_agent: RoadLaneAgent` | created at runtime, needs `road_manager` set before `_ready` |
| `lane_point_ahead(dist)` | steering target, nudged sideways by this rider's `line_offset` |
| `cruise_speed()` | `move_speed × _speed_scale` (per-rider variance) |
| `lane_speed()` | **corner-aware** target speed — samples the curve's bend over `turn_lookahead` and eases toward `min_turn_speed`. Throttled behind a randomised timer. |
| `steer_toward(target, target_speed, delta)` | ramps `current_speed` by `acceleration`/`braking`, points horizontal velocity at target |
| `coast_to_stop(delta)` | decays velocity by `braking` |
| `nearest_racer_ahead(range, angle)` | slower racer in a forward cone. Throttled — it sweeps the whole `Racers` group, O(n²) across the pack otherwise |
| `apply_gravity_and_move(delta)` | the one place `sync_transform` is written |

Note `lane_speed()` is already the "how fast should I be going" hook and it already
*decelerates ahead of time* by looking down the curve. Stopping at a stop line is the same
shape of problem, and belongs next to it — not bolted into the state machine.

Clients never simulate: `_ready` disables the behaviour state machine's physics on non-server
peers, and the pose arrives via a plain `MultiplayerSynchronizer` on `sync_transform`. **All AI
decisions are server-only**, which simplifies the control layer enormously.

### A8. `managers/npc_traffic_manager.gd` — lifecycle and ownership

Server authority. Owns `_route_graph`, spawns riders on negative ids from `-1000`, handles crash
and stuck recovery, and manages the client accept-gate / resync dance for spawn broadcasts.

The parts that matter here:

- `start_traffic(for_race)` builds the graph, connects `container.on_road_updated` →
  `_on_road_updated` → deferred `_rebuild_route_graph()`. Rebuilds are **coalesced to one per
  frame** because the signal fires per container per pass.
- `rpc_spawn_npc` hands each new rider `traffic_state.route_graph = _route_graph`.
- `_find_road_manager()` — `level_manager.current_level.find_children("*", "RoadManager", ...)`,
  null on maps with no roads (the stunt map simply gets no traffic).

Anything new that needs building at level load, and handing to riders at spawn, follows these
exact two hooks.

### A9. `road_demos/navigation/astar_lane_graph.gd` — the demo you're not using

A standalone demo: click to set start/end, it A*s over the lanes. Worth reading once, and worth
understanding why we're **not** copying it.

It builds an `AStar3D` by dropping a point every `astar_point_interval` (10 m) along every lane
and connecting them one-way. A modest city becomes thousands of points. It does that because
`AStar3D` models nodes as positions (see NavigationPrimer §3) — so a "lane" has to be shredded
into position-sized pieces to fit.

It also carries `get_path_cost()` using `get_point_weight_scale()`, which is a real hint at
where weights would go — but at 10 m granularity, per point, not per road.

**Take the idea, not the implementation.** The routing graph should be ~20 nodes, not ~2000.

---

## PART B — What you're building

Naming, style and placement all follow the existing files. GDScript order matters for
`.gdlintrc` (`class-definitions-order`): `@tool` → `class_name`/`extends` → docstring → signals
→ enums → consts → `@export` → public vars → private vars → `@onready` → static methods →
built-in callbacks → public methods → private methods.

### B1. `entities/road/routing_graph.gd` — NEW — the primal graph + A*

`class_name RoutingGraph extends RefCounted`. Sits next to `TrafficRouteGraph` conceptually;
built from it.

**Data**

```
nodes:      Array[RoadIntersection]
edges:      Dictionary[RoadIntersection, Array[RouteEdge]]

RouteEdge:  to: RoadIntersection
            cost: float                 # summed baked length of the run
            entry_lane: RoadLane        # the lane that starts this run
```

**Contract**

| Method | Purpose |
| --- | --- |
| `build(tree, road_manager, lane_graph) -> void` | discover intersections, walk lanes to find edges |
| `find_route(from, to) -> Array[RoadIntersection]` | A*. Empty array if unreachable |
| `next_hop(from, to) -> RoadIntersection` | convenience: first step of the route |
| `random_intersection() -> RoadIntersection` | destination picking, mirrors `TrafficRouteGraph.random_lane()` |

**How `build` works.** Intersections come from `road_manager.get_containers()`, each container's
children filtered by `has_method("is_road_intersection")` (the addon's own cyclic-typing
workaround — see `road_intersection.gd:143`; use it rather than `is RoadIntersection` to stay
consistent with the addon).

For each intersection, for each of its child lanes (= each movement), walk forward through
`lane_graph.next_lanes()`, accumulating `curve.get_baked_length()`, until you land on a lane
whose parent is a *different* `RoadIntersection`. That destination is the edge's `to`, and the
accumulated length is its `cost`.

Guard the walk with a hop limit. A ring road with no intersections is an infinite loop
otherwise, and so is a graph mid-rebuild.

**Heuristic.** `h(a, b) = a.global_position.distance_to(b.global_position)`. Admissible while
cost is metres. If you later switch cost to seconds, re-read NavigationPrimer §3 — the
heuristic must divide by the *network-wide* max speed.

**Rebuild.** Same lifecycle as `TrafficRouteGraph`: rebuild in place whenever the lane graph
rebuilds, off the same coalesced `_rebuild_route_graph()` hook in the manager.

### B2. `entities/road/junction_graph.gd` — NEW — movements and conflicts

`class_name JunctionGraph extends RefCounted`. Static, geometric, built once per level load.

Answers three questions:

| Method | Purpose |
| --- | --- |
| `is_junction_lane(lane) -> bool` | `lane.get_parent()` has `is_road_intersection()` |
| `movements_conflict(a: RoadLane, b: RoadLane) -> bool` | precomputed lookup |
| `turn_direction(lane) -> TurnDir` | `LEFT` / `THROUGH` / `RIGHT`, from geometry |

**Conflict computation.** For each intersection, for each unordered pair of its child lanes:
sample both curves at a fixed interval and take the minimum distance between sample pairs. Below
a threshold (roughly a vehicle width) → conflicting. Store as
`Dictionary[RoadLane, Dictionary[RoadLane, bool]]` or a set of sorted pairs.

Cost is `O(movements² × samples²)` per intersection, once, at load. A 4-way with two lanes per
approach is ~16 movements → 120 pairs. Fine. If it ever isn't, coarsen the sample interval
before you get clever.

Two pairs that need thought and are worth handling explicitly:

- Movements **sharing an entry lane** never conflict — same queue, they can't be simultaneous.
- Movements **sharing an exit lane** conflict even if their curves only touch at the very end
  (a merge). The distance test catches this naturally; don't special-case it away.

**Turn direction.** Signed angle from the lane's start heading to its end heading, about the
intersection's `global_transform.basis.y`. Within ±~30° → `THROUGH`; positive → one way,
negative → the other. Derive it, don't parse `_tagged_lane_name`'s suffix (see A4).

### B3. `resources/traffic/junction_control.gd` (+ subclasses) — NEW — the rules

Base `class_name JunctionControl extends Resource`. Assigned per intersection (B6), shared and
immutable — **it holds no per-junction runtime state**, which is exactly why B4 exists.

```
enum SignalState { GREEN, AMBER, RED }

func movement_state(movement: RoadLane, junction: JunctionState) -> SignalState
func requires_full_stop() -> bool
```

**`traffic_light_control.gd`** — `TrafficLightControl extends JunctionControl`.

```
class Phase:  movements_by_branch: Array[...]   # authored per intersection
              green_secs: float
              amber_secs: float
```

`movement_state()` computes the current phase as a **pure function of `NetworkTime.time`**:

```
cycle_len = sum of (green + amber) over all phases
t         = fmod(NetworkTime.time, cycle_len)
```

…then walks phases accumulating until `t` lands. No `Timer`, no stored index, no RPC — see
NavigationPrimer §6. Every peer computes the same answer, which is what makes the visuals free.

**`stop_sign_control.gd`** — `StopSignControl extends JunctionControl`. `requires_full_stop()`
returns true; `movement_state()` returns `GREEN` only when this movement's vehicle is at the
head of the junction's arrival queue (which lives in B4, passed in).

**Uncontrolled** is `null` — no resource. Gate falls through to conflicts + priority alone.

### B4. `entities/road/junction_state.gd` — NEW — per-junction runtime state

`class_name JunctionState extends RefCounted`. One per `RoadIntersection`, server-only, owned by
the traffic manager. This is where the mutable state the Resource can't hold goes:

| Member | Purpose |
| --- | --- |
| `occupants: Dictionary[Node3D, RoadLane]` | who is in the box, and on which movement |
| `arrival_queue: Array[Node3D]` | stop-sign FIFO |
| `waiting_since: Dictionary[Node3D, float]` | for the deadlock timeout |

**The gate.** One function, and it's the heart of the whole feature:

```
may_enter(vehicle, movement) -> bool:
    if waited longer than DEADLOCK_TIMEOUT:  return true        # NavigationPrimer §5
    if control and control.movement_state(movement, self) != GREEN:  return false
    for each occupant, their_movement in occupants:
        if junction_graph.movements_conflict(movement, their_movement): return false
    if exit lane of movement is full:  return false             # anti-gridlock
    if a player is approaching the box fast:  return false       # defensive yield
    return true
```

Every clause is mandatory. Dropping the occupancy check makes green lights meaningless;
dropping the exit check produces real gridlock; dropping the timeout produces permanent
deadlock at 4-way stops.

Call `enter(vehicle, movement)` when a rider is assigned a junction lane and
`leave(vehicle)` when it's assigned a lane outside the junction.

**The defensive-yield clause** is the "NPCs see the player" behaviour: sweep the `Racers` group
for a `PlayerEntity` within a radius of the intersection origin, closing on it above a speed
threshold. Reuse the throttling pattern from `nearest_racer_ahead` — do not sweep per tick per
rider.

### B5. `entities/npc/states/npc_traffic_state.gd` — MODIFIED

`_pick_next_lane_at_junction()` grows from "pick random" to "pick, then ask permission":

```
if not close_to_lane_end(...):  return
successors = route_graph.next_lanes(current_lane)
if successors.is_empty():  assign_nearest_lane(); return

chosen = _choose_successor(successors)      # random today; route-driven later
if junction_graph.is_junction_lane(chosen):
    if not junction_state_for(chosen).may_enter(npc, chosen):
        _waiting_for = chosen               # remember it, don't re-roll each tick
        return                              # ← speed handling below
junction bookkeeping: leave(old) / enter(new)
assign_lane(chosen)
```

**The part that isn't obvious:** returning early is not enough. The rider is still being steered
by `lane_point_ahead()` toward a point beyond the end of its curve, so it will drive straight
through the stop line and off the road. Refusing the transition must be paired with a target
speed that reaches zero *at* the line — B7.

Also: latch `_waiting_for` once. Re-rolling `pick_random()` every tick while queued makes a
rider flick between "waiting to turn left" and "waiting to go straight", and the conflict checks
become nonsense.

### B6. `addons/road-generator/nodes/road_intersection.gd` — ADDON PATCH

One export, next to the existing `settings`:

```gdscript
## PATCHED (DankNooner, traffic AI): rules this junction runs under. Null = uncontrolled.
@export var junction_control: JunctionControl = null
```

Follow the `PATCHED (DankNooner, ...)` comment convention from `road_lane_agent.gd:238` so the
edit survives an addon update review.

### B7. `entities/npc/npc_rider_entity.gd` — MODIFIED

One new method, sitting beside `lane_speed()` because it's the same kind of question:

```
stop_line_speed(stop_point: Vector3) -> float:
    d = horizontal distance to stop_point, minus a small buffer
    if d <= 0: return 0.0
    return sqrt(2 * braking * d)          # fastest speed that still stops in d
```

The caller takes `min(lane_speed(), stop_line_speed(...))` and hands that to `steer_toward`. It
composes cleanly with the existing corner-aware speed and with the follow-the-blocker cap — all
three are just upper bounds on the same target.

Stop point comes from the chosen movement's `get_lane_start()` (which, per A4, *is* the stop
line).

### B8. Traffic light visual — YOURS

You're authoring the scene and mesh. `levels/assets/City Pack.undefined-glb/Traffic Light.glb`
already exists in the project.

What the docs commit to is only the interface. Script it as a `Node3D` with:

```gdscript
@export var intersection: RoadIntersection
@export var branch: RoadPoint            # which approach this light faces

func _process(_delta: float) -> void:
    # runs on EVERY peer — see NavigationPrimer §6
    var state := intersection.junction_control.branch_state(branch)
    set_signal_state(state)

func set_signal_state(state: JunctionControl.SignalState) -> void:
    # yours: swap emission materials / toggle lamp meshes
```

`branch_state(branch)` is a small helper on `TrafficLightControl` that reduces the branch's
movements to one displayable state (green if any of its through movements are green).

No sync, no server dependency, no manager wiring — the clock does it. That's the payoff of the
pure-function formulation in B3.

### B9. `managers/npc_traffic_manager.gd` — MODIFIED

Follows its two existing hooks exactly:

- In `start_traffic()`, after `_route_graph` is built: build `_junction_graph`,
  `_routing_graph`, and one `JunctionState` per intersection.
- In `_rebuild_route_graph()`: rebuild all three together, since they all derive from the lanes
  that just got freed and regenerated.
- In `rpc_spawn_npc()`, in the existing server-only block next to
  `traffic_state.route_graph = _route_graph`: hand over the junction graph and a way to reach
  the junction states.
- In `stop_traffic()`: null them out alongside `_route_graph`.

Nothing new goes over the wire. Nothing new is client-side.

---

## PART C — Things that will bite you

Collected from the existing code's own hard-won comments. These are all real bugs that were
already hit once.

1. **Lanes are freed and regenerated wholesale.** `RoadContainer.rebuild_segments` frees every
   `RoadLane` and rebuilds, and it defers that on `_ready`. Any cached `RoadLane` may be a freed
   instance. Every new dictionary keyed by `RoadLane` needs the same `is_instance_valid` hygiene
   and the same in-place `rebuild()` that `TrafficRouteGraph` has — *including your conflict
   sets and junction states*.

2. **Don't scan per tick.** `assign_nearest_lane()` walks every lane in the level;
   `nearest_racer_ahead()` walks the whole `Racers` group. Both are already throttled behind
   randomised timers so riders don't sync up onto the same tick. Any new sweep (defensive yield,
   exit-lane occupancy) needs the same treatment.

3. **Spawn positions cluster at junctions.** Junction lanes all start within a few metres of
   each other, so anything that picks "the start of a random lane" piles vehicles into
   intersections. `lane_transform_at(lane, randf())` exists for this reason.

4. **`close_to_lane_end()` lies by design.** It returns false whenever `lane_next` is set, so it
   only fires at junctions and road narrowings. Convenient, but don't assume it means "near the
   end of the curve" in general.

5. **Deadlock is guaranteed without a timeout.** Four vehicles, a 4-way stop, each yielding to
   the right. Build the timeout in from the first commit, not after you see it.

6. **The player is not an NPC.** It's in the `Racers` group and it's a `CharacterBody3D` with
   `velocity`, so `horizontal_speed()` works on it — but it has no `lane_agent`, no movement, and
   will never call `may_enter`. Occupancy tracking must tolerate a body that entered the box
   without ever asking.

7. **Verify against `.gdlintrc` before you call it done.** `class-definitions-order` in
   particular — see the ordering at the top of Part B.
