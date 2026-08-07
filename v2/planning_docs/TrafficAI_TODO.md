# Traffic AI — Build Order

> Pseudocode and checkboxes. Theory is in [NavigationPrimer.md](./NavigationPrimer.md); what the
> existing files do is in [TrafficAI.md](./TrafficAI.md).
>
> **Pseudocode here is deliberately not GDScript.** Types, names and shapes are given so it
> plugs into the existing code; the implementation is yours.

Every step ends with a **Verify** you can run without the next step existing. Do not skip them —
each one is the last point where a bug is still cheap to find.

---

## Step 0 — Debug draw harness

You cannot debug a graph you cannot see. Build this first; you'll use it in every later step.

- [ ] `entities/road/traffic_debug_draw.gd` — a `Node3D` that draws lines/labels on demand
- [ ] Toggle it from the console (see `level_manager`'s console cmd — same place `dbg_gym` lives)
- [ ] Server-only, and off by default

```
draw_lane_graph():
    for each lane in lane_graph.lanes:
        line from lane.get_lane_start() to lane.get_lane_end()   # white
        for each succ in lane_graph.next_lanes(lane):
            arrow from lane.get_lane_end() to succ.get_lane_start()   # cyan
```

Use `ImmediateMesh` — `road_lane.gd:_draw_shark_fins()` is a working example of building one in
this codebase, copy its material setup.

**Verify:** load a map with roads. You should see every lane and every successor link. Look hard
at the intersections — you should see the 6 m proximity snapping fan out into multiple arrows
from each incoming lane. If a junction has *no* outgoing arrows, `TrafficRouteGraph`'s snap
distance or heading tolerance is wrong for that geometry, and everything downstream will be
broken. Fix it here.

---

## Step 1 — `JunctionGraph`: movements, turns, conflicts

File: `entities/road/junction_graph.gd`, `class_name JunctionGraph extends RefCounted`.

- [ ] `is_junction_lane(lane) -> bool`
- [ ] `intersection_of(lane) -> RoadIntersection`
- [ ] `turn_direction(lane) -> TurnDir`
- [ ] `build(lane_graph)` → conflict sets
- [ ] `movements_conflict(a, b) -> bool`
- [ ] Debug draw: colour junction lanes by turn direction

```
enum TurnDir { LEFT, THROUGH, RIGHT }

is_junction_lane(lane):
    parent = lane.get_parent()
    return parent != null and parent.has_method("is_road_intersection")
    # has_method, not `is RoadIntersection` — matches the addon's own cyclic-typing workaround
```

```
turn_direction(lane):
    junction = intersection_of(lane)
    up       = junction.global_transform.basis.y
    entry    = heading at lane curve start      # reuse the math in traffic_route_graph.gd
    exit     = heading at lane curve end
    angle    = signed_angle(entry, exit, up)
    if abs(angle) < THROUGH_TOLERANCE:  return THROUGH
    return RIGHT if angle > 0 else LEFT
    # sanity-check the sign against the debug draw once, then trust it
```

```
build(lane_graph):
    for each junction in all intersections:
        movements = junction children that are RoadLane
        for each unordered pair (a, b) in movements:
            if share_entry_lane(a, b):  continue      # same queue, never simultaneous
            if curves_come_within(a, b, CONFLICT_RADIUS):
                mark a and b conflicting

curves_come_within(a, b, r):
    for ta in 0..1 step SAMPLE_STEP:
        pa = a.to_global(a.curve.sample_baked(ta * a.curve.get_baked_length()))
        for tb in 0..1 step SAMPLE_STEP:
            pb = b.to_global(b.curve.sample_baked(tb * b.curve.get_baked_length()))
            if horizontal_distance(pa, pb) < r:  return true
    return false
```

`share_entry_lane(a, b)` — two movements share an entry if some lane in the graph lists both as
successors. Precompute a reverse index once rather than searching per pair.

**Verify:** draw junction lanes red/green/blue by turn direction. At a 4-way, each approach
should show exactly one THROUGH and turns to the others. Then draw a line between every
conflicting pair: opposing through movements must **not** be linked; every crossing pair must be.
Eyeball one intersection carefully — this table is the foundation for all three rule types, and a
wrong entry here shows up much later as an inexplicable collision.

---

## Step 2 — `RoutingGraph`: build the primal graph

File: `entities/road/routing_graph.gd`, `class_name RoutingGraph extends RefCounted`.

Graph only. No search yet.

- [ ] `RouteEdge` inner class: `to`, `cost`, `entry_lane`
- [ ] `build(tree, road_manager, lane_graph, junction_graph)`
- [ ] `random_intersection()` — mirror `TrafficRouteGraph.random_lane()`'s stale-pruning
- [ ] Debug draw: a line per edge, labelled with its cost

```
build(...):
    nodes = every intersection found under road_manager.get_containers()
    edges = {}
    for junction in nodes:
        for movement in junction's child lanes:
            edge = walk_to_next_junction(movement, lane_graph, junction_graph)
            if edge != null:  edges[junction].append(edge)

walk_to_next_junction(start_movement, ...):
    cost  = 0.0
    lane  = start_movement
    hops  = 0
    while hops < MAX_HOPS:
        cost += lane.curve.get_baked_length()
        succs = lane_graph.next_lanes(lane)
        if succs.is_empty():  return null              # dead end, no edge
        next = succs[0]                                # ANY successor reaches the same junction
        if junction_graph.is_junction_lane(next):
            return RouteEdge.new(junction_graph.intersection_of(next), cost, start_movement)
        lane = next
        hops += 1
    return null                                        # ring road / mid-rebuild, bail
```

Two notes on that walk:

- `succs[0]` is fine **only** because between two junctions the successors are parallel lanes of
  the same road, which all arrive at the same place. If a map ever branches without an
  intersection node, this assumption breaks — assert on it rather than discovering it later.
- `MAX_HOPS` is not optional. A closed loop with no intersections hangs the level load
  otherwise, and so does a graph caught mid-rebuild.

**Verify:** draw the primal graph as thick lines between intersection origins with cost labels.
Count the nodes — it should be the number of intersections you placed, not thousands. Walk one
edge by eye and check its cost against the actual road length. Then check the graph is
**connected**: from any node you should be able to reach every other.

---

## Step 3 — A\* ⭐ the learning step

Still in `routing_graph.gd`. This is the part worth taking your time on. Read
[NavigationPrimer §3](./NavigationPrimer.md) again first, and do the worked example by hand.

- [ ] `find_route(from, to) -> Array[RoadIntersection]`
- [ ] `_heuristic(a, b) -> float`
- [ ] `_reconstruct(came_from, current) -> Array`
- [ ] Debug: click two intersections, draw the route

```
find_route(start, goal):
    if start == goal:  return [start]

    open      = [start]              # sorted array is fine at this graph size
    came_from = {}
    g         = { start: 0.0 }
    f         = { start: _heuristic(start, goal) }

    while open is not empty:
        current = pop the entry in open with the lowest f
        if current == goal:  return _reconstruct(came_from, current)

        for edge in edges[current]:
            tentative = g[current] + edge.cost
            if edge.to not in g or tentative < g[edge.to]:      # ← the line people get wrong
                came_from[edge.to] = current
                g[edge.to] = tentative
                f[edge.to] = tentative + _heuristic(edge.to, goal)
                if edge.to not in open:  open.append(edge.to)

    return []                        # unreachable — a real answer, not an error

_heuristic(a, b):
    return a.global_position.distance_to(b.global_position)
    # admissible while cost is metres. If cost ever becomes seconds,
    # divide by the network-wide max speed. See NavigationPrimer §3.

_reconstruct(came_from, current):
    path = [current]
    while current in came_from:
        current = came_from[current]
        path.push_front(current)
    return path
```

**Verify — do all four:**

1. **Hand-check.** Run the worked example table from NavigationPrimer §3 through your code
   (fake a 4-node graph in a test scene). Same path, same cost.
2. **Zero the heuristic.** `_heuristic` returns `0.0` → it's now Dijkstra. It must return the
   **same path** at the **same cost**, just slower. If the path changes, your heuristic isn't
   admissible.
3. **Symmetry.** `find_route(a, b)` and `find_route(b, a)` should cost the same on a two-way
   network. Different costs means one direction's edges are missing.
4. **Unreachable.** Point it at an isolated intersection. Empty array, no crash, no hang.

Only move on when all four pass. Everything after this trusts the router.

---

## Step 4 — Stop at the line

No rules yet — just make a rider physically stop where it should. This is a physics step, and
doing it before the rules means you debug one thing at a time.

- [ ] `npc_rider_entity.gd`: add `stop_line_speed(stop_point) -> float`
- [ ] `npc_traffic_state.gd`: temporarily refuse **every** junction entry
- [ ] Blend the speed caps

```
# npc_rider_entity.gd, next to lane_speed()
stop_line_speed(stop_point):
    d = horizontal_distance(global_position, stop_point) - STOP_BUFFER
    if d <= 0.0:  return 0.0
    return sqrt(2.0 * braking * d)      # fastest speed that still stops within d
```

```
# npc_traffic_state.gd Physics_Update — the speed is a MINIMUM of independent caps
target_speed = npc.lane_speed()                                  # corner-aware
if _waiting_for != null:
    target_speed = min(target_speed, npc.stop_line_speed(_waiting_for.get_lane_start()))
if blocker != null:
    target_speed = min(target_speed, npc.horizontal_speed(blocker))
npc.steer_toward(target, target_speed, delta)
```

**Verify:** with entry hard-refused, every rider should roll up to a junction and stop *at the
stop line* — not past it, not 20 m short, and without oscillating. If they overshoot, `braking`
and `STOP_BUFFER` need tuning; if they creep, the buffer is too large. Get this feeling right
now, because once the rules land you won't be able to tell a stopping bug from a rules bug.

⚠️ `_check_stuck()` will fire `stuck` on every stopped rider and the manager will teleport them
away. Suppress the stuck check while `_waiting_for` is set — and keep that suppression, it's
correct behaviour permanently.

---

## Step 5 — `JunctionState` + uncontrolled right-of-way

Now they take turns. Still no lights, no signs.

- [ ] `entities/road/junction_state.gd`, `class_name JunctionState extends RefCounted`
- [ ] `may_enter`, `enter`, `leave`
- [ ] Manager builds one per intersection in `start_traffic()`
- [ ] `npc_traffic_state.gd` calls the gate

```
may_enter(vehicle, movement):
    if _waited_too_long(vehicle):  return true             # deadlock escape, mandatory

    for occupant, their_movement in occupants:
        if occupant == vehicle:  continue
        if junction_graph.movements_conflict(movement, their_movement):
            return false

    if not _exit_is_clear(movement):  return false          # anti-gridlock

    if _yields_to(vehicle, movement):  return false         # priority tie-break

    return true

_waited_too_long(vehicle):
    return waiting_since.has(vehicle)
       and now - waiting_since[vehicle] > DEADLOCK_TIMEOUT

_exit_is_clear(movement):
    exit = lane_graph.next_lanes(movement)[0]
    return exit.get_vehicles().size() < EXIT_CAPACITY       # RoadLane already tracks this

_yields_to(vehicle, movement):
    # v1: turning traffic yields to through traffic already waiting.
    # "Yield to the right" needs edge_points' clockwise order — later.
    if junction_graph.turn_direction(movement) == THROUGH:  return false
    return any other waiting vehicle has a THROUGH movement
```

```
enter(vehicle, movement):  occupants[vehicle] = movement; waiting_since.erase(vehicle)
leave(vehicle):            occupants.erase(vehicle)
```

Wire into `_pick_next_lane_at_junction()`:

```
chosen = successors.pick_random()      unless _waiting_for is already set  ← latch it!
if junction_graph.is_junction_lane(chosen):
    state = junction_states[junction_graph.intersection_of(chosen)]
    if not state.may_enter(npc, chosen):
        _waiting_for = chosen
        state.note_waiting(npc)
        return
    state.enter(npc, chosen)
    _waiting_for = null
else if we were in a junction:
    previous_state.leave(npc)
assign_lane(chosen)
```

**Latching `_waiting_for` is not optional.** Re-rolling `pick_random()` each tick makes a rider
flip between "waiting to turn left" and "waiting to go straight" every frame, and the conflict
checks evaluate against a different movement each time — you get riders that dart into the
junction on the frame their re-roll happens to be non-conflicting.

**Verify:** raise `traffic_count` and watch a 4-way. Riders should interleave rather than
colliding. Then deliberately break it: comment out the deadlock timeout and confirm you *can*
produce a permanent 4-way standoff. Seeing the deadlock once is worth more than trusting the
fix.

---

## Step 6 — Traffic lights

- [ ] `resources/traffic/junction_control.gd` — base `Resource`, `SignalState` enum
- [ ] `resources/traffic/traffic_light_control.gd`
- [ ] Addon patch: `@export var junction_control` on `RoadIntersection`
- [ ] Author one `.tres` and assign it to a test intersection
- [ ] `JunctionState.may_enter` consults it first

```
# traffic_light_control.gd — phase is a PURE FUNCTION of the clock. No Timer. No stored index.
current_phase(now_secs):
    cycle = sum over phases of (green_secs + amber_secs)
    t     = fmod(now_secs, cycle)
    for i, phase in phases:
        span = phase.green_secs + phase.amber_secs
        if t < span:
            return { index: i, amber: t >= phase.green_secs }
        t -= span

movement_state(movement, _junction_state):
    p = current_phase(NetworkTime.time)
    if movement not in phases[p.index].movements:  return RED
    return AMBER if p.amber else GREEN
```

Add to the top of `may_enter`:

```
if control != null and control.movement_state(movement, self) != GREEN:  return false
```

Note the ordering: the light is checked **first**, but the conflict and exit checks still run
after it. A green light is half of permission, never all of it — see NavigationPrimer §5.

Authoring the phase sets is the fiddly part. Start with two phases (north-south, then east-west)
and only add protected lefts once that works.

**Verify:** debug-draw each branch's current state as a coloured bar above the intersection.
Watch one full cycle with traffic running. Then **start a second peer** — both must show the
same colour at the same moment with no networking involved. If they drift, something in the
phase calc isn't purely a function of `NetworkTime.time`.

---

## Step 7 — Stop signs

- [ ] `resources/traffic/stop_sign_control.gd`
- [ ] `requires_full_stop()` on the base returns false, true here
- [ ] Arrival queue in `JunctionState`

```
# npc_traffic_state.gd — a stop sign needs an actual stop, not a slow roll
if control.requires_full_stop() and not _has_fully_stopped:
    if npc.current_speed < FULL_STOP_SPEED:
        _has_fully_stopped = true
        state.join_queue(npc)
    return                       # speed cap from Step 4 keeps holding it at the line

# stop_sign_control.gd
movement_state(movement, junction_state):
    return GREEN if junction_state.queue_head() == vehicle else RED
```

Clear `_has_fully_stopped` when the rider leaves the junction, and drop vehicles from the queue
in `leave()` — *and* on crash/despawn, or a wiped-out rider holds the queue head forever and
the junction locks until the deadlock timeout bails everyone out one by one.

**Verify:** an all-way stop with four approaches. Riders come to a genuine halt, then go in
arrival order. Crash one at the line on purpose and confirm the junction recovers.

---

## Step 8 — Traffic light props (your scene)

- [ ] Build the scene from `levels/assets/City Pack.undefined-glb/Traffic Light.glb`
- [ ] Script it with the interface below
- [ ] Place per branch, wire the two exports

```gdscript
@export var intersection: RoadIntersection
@export var branch: RoadPoint

func _process(_delta: float) -> void:
    set_signal_state(intersection.junction_control.branch_state(branch))

func set_signal_state(state: JunctionControl.SignalState) -> void:
    pass  # yours: emission material / lamp mesh visibility
```

Add `branch_state(branch)` to `TrafficLightControl`: reduce that branch's movements to one
displayable state (green if the branch's through movement is green).

Runs on **every peer**, needs no server and no sync — the clock does it. Guard for
`junction_control == null` so an uncontrolled junction with a prop on it doesn't crash.

**Verify:** lights match the debug bars from Step 6, and match across two peers.

---

## Step 9 — Defensive yield to the player

- [ ] Player proximity check in `may_enter`
- [ ] Throttled, not per tick per rider

```
_player_approaching():
    # throttle: reuse the randomised-interval pattern from nearest_racer_ahead()
    for racer in group("Racers"):
        if not racer is PlayerEntity:  continue
        to_box = junction_origin - racer.global_position
        if to_box.length() > YIELD_RADIUS:  continue
        if racer.velocity.dot(to_box.normalized()) < YIELD_CLOSING_SPEED:  continue
        return true
    return false
```

Also: the player enters the box without ever calling `enter()`, so occupancy never sees them.
That's fine — the yield check covers approach, and physical collision covers the rest. Just make
sure `occupants` tolerates a body it never registered.

**Verify:** ride at a junction where traffic has green. They should hesitate. Then ride up
slowly — they should ignore you and go. Tune `YIELD_RADIUS` until it feels like being seen
rather than like traffic that's afraid of you.

---

## Step 10 — Route-driven traffic (stretch)

Everything above works with the random walk. This is where A\* finally drives something.

- [ ] Give each rider `_destination: RoadIntersection` and `_route: Array[RoadIntersection]`
- [ ] On spawn and on arrival: pick a new destination, `find_route` to it
- [ ] `_choose_successor` prefers the successor whose `RouteEdge.to` is the next hop
- [ ] Fall back to random if the route is empty or stale

```
_choose_successor(successors):
    if _route.size() < 2:  return successors.pick_random()
    next_hop = _route[1]
    for s in successors:
        if routing_graph.edge_from(s) leads to next_hop:  return s
    return successors.pick_random()          # route went stale (road rebuild) — reroute later
```

Reroute lazily: on arrival, or when the fallback fires — **never** per tick. A rider that
recomputes a cross-town route every frame is the exact failure NavigationPrimer §1 warns about.

**Verify:** debug-draw one rider's route. It should follow it and pick a fresh one on arrival.
Watch the road rebuild case (drive around while a container regenerates) and confirm it falls
back to random instead of stalling.

---

## Cross-cutting — do these throughout

- [ ] **Rebuild hygiene.** `RoadContainer.rebuild_segments` frees every `RoadLane`. Every new
      structure keyed by `RoadLane` or `RoadIntersection` must rebuild in place off the existing
      coalesced `_rebuild_route_graph()` hook, and must survive holding freed instances.
      This is `TrafficAI.md` Part C item 1, and it will bite you if you defer it.
- [ ] **Throttle every sweep.** Follow the randomised-interval pattern already in
      `nearest_racer_ahead()` and the re-latch timer, so riders never sync onto one tick.
- [ ] **Server-only.** Nothing here is client-side except the light visual, which derives from
      `NetworkTime.time`. No new RPCs, no new synced state.
- [ ] **Lint.** `.gdlintrc`, especially `class-definitions-order`.
- [ ] **Test on a two-peer session** at Steps 6 and 8, not at the end.
