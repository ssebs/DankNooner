# Traffic AI — Build Order

> Ten steps, each one buildable and verifiable on its own. Concepts are in
> [Navigation.md](./Navigation.md); how the existing code is put together is in
> [TrafficAI.md](./TrafficAI.md).

**How this doc is meant to be used.** Each step gives you the **contract** (names and signatures,
so what you write plugs into the existing code), the **questions you need to answer yourself**,
and a **verify** you can run before the next step exists. The implementation is the exercise.

Where an algorithm is genuinely the thing being learned, a worked solution sits behind a
collapsed block:

<details>
<summary>Like this — open only after you've had a real go</summary>

Timebox it. An hour stuck on A\* teaches you more than five minutes reading someone else's
version, but three hours stuck teaches you nothing. Write your own first, then open these to
compare — the interesting part is usually *where you differ*, not whether you match.
</details>

Notes that are **facts about our codebase** — addon quirks, which method already exists, what
`RoadLane` already tracks for you — are never hidden. You can't derive those from first
principles and there's nothing to learn by rediscovering them.

Do the verify steps. They're the whole reason this is a ten-step list instead of one big task,
and working solo they're the only thing standing between you and a bug you find four steps later.

---

## Step 0 — Debug draw harness

You cannot debug a graph you cannot see. Build this first; you'll use it in every later step.

- [ ] `entities/road/traffic_debug_draw.gd` — a `Node3D` that draws lines/labels on demand
- [ ] Toggle it from the console (see `level_manager`'s console cmd — same place `dbg_gym` lives)
- [ ] Server-only, and off by default

Start with one method: draw every lane, and an arrow from each lane's end to each of its
successors. `TrafficRouteGraph` already exposes `lanes` and `next_lanes()`, so this needs no new
data — it's purely a view onto what already exists.

Use `ImmediateMesh` — `road_lane.gd:_draw_shark_fins()` is a working example of building one in
this codebase, copy its material setup.

**Verify:** load a map with roads. You should see every lane and every successor link. Look hard
at the intersections — you should see the 6 m proximity snapping fan out into multiple arrows
from each incoming lane. If a junction has *no* outgoing arrows, `TrafficRouteGraph`'s snap
distance or heading tolerance is wrong for that geometry, and everything downstream will be
broken. Fix it here.

---

## Step 1 — `JunctionGraph`: turns and conflicts

File: `entities/road/junction_graph.gd`, `class_name JunctionGraph extends RefCounted`.

This is the "who clashes with whom" table from [Navigation.md](./Navigation.md). Static,
geometric, built once per level load.

- [ ] `enum TurnDir { LEFT, THROUGH, RIGHT }`
- [ ] `is_junction_lane(lane) -> bool`
- [ ] `intersection_of(lane) -> RoadIntersection`
- [ ] `turn_direction(lane) -> TurnDir`
- [ ] `build(lane_graph)` → conflict sets
- [ ] `movements_conflict(a, b) -> bool`
- [ ] Debug draw: colour junction lanes by turn direction

**Codebase facts you'd otherwise waste time on:**

- A turn *is* a lane parented to a `RoadIntersection` (see `intersection_ngon.gd`). You don't
  need a new type — the first two methods are one line each.
- Test the parent with `has_method("is_road_intersection")`, **not** `is RoadIntersection`. That
  matches the addon's own cyclic-typing workaround; see `road_intersection.gd:143`.
- `traffic_route_graph.gd` already has heading-at-start and heading-at-end maths. Reuse it.

**Work out yourself:**

1. **Turn direction from geometry.** You have the lane's entry heading, its exit heading, and the
   junction's up vector. What do you compute, and how do you decide where THROUGH ends and a turn
   begins? Don't parse the node name — `_tagged_lane_name()` bakes a suffix in, but it's a
   display detail that collides-and-numbers on duplicates.
2. **Do two curves clash?** You need a yes/no from two `Curve3D`s. What's the cheapest test that
   isn't wrong? Think about what "conflict" means physically before you pick a threshold.
3. **The one exception.** Two turns starting from the *same* entry lane must never count as
   conflicting — same queue, they can't be in the junction simultaneously. How do you detect
   that, and can you do it without an O(n) search per pair?
4. **Cost check.** Roughly how many pairs is this per junction, and does it matter that it's
   O(pairs × samples²)? Work out the number before you optimise anything.

<details>
<summary>Solution — conflict building</summary>

```
enum TurnDir { LEFT, THROUGH, RIGHT }

is_junction_lane(lane):
    parent = lane.get_parent()
    return parent != null and parent.has_method("is_road_intersection")

turn_direction(lane):
    junction = intersection_of(lane)
    up       = junction.global_transform.basis.y
    entry    = heading at lane curve start
    exit     = heading at lane curve end
    angle    = signed_angle(entry, exit, up)
    if abs(angle) < THROUGH_TOLERANCE:  return THROUGH
    return RIGHT if angle > 0 else LEFT
    # sanity-check the sign against the debug draw once, then trust it

build(lane_graph):
    for each junction in all intersections:
        movements = junction children that are RoadLane
        for each unordered pair (a, b) in movements:
            if share_entry_lane(a, b):  continue
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

`share_entry_lane(a, b)` — two turns share an entry if some lane in the graph lists both as
successors. Precompute a reverse index once rather than searching per pair.

A 4-way with two lanes per approach is ~16 turns → 120 pairs, once, at load. If it ever does get
slow, coarsen `SAMPLE_STEP` before you get clever.
</details>

**Verify:** draw junction lanes red/green/blue by turn direction. At a 4-way, each approach
should show exactly one THROUGH and turns to the others. Then draw a line between every
conflicting pair: opposing through movements must **not** be linked; every crossing pair must be.
Eyeball one intersection carefully — this table is the foundation for all three rule types, and a
wrong entry here shows up much later as an inexplicable collision.

---

## Step 2 — `RoutingGraph`: build the small map

File: `entities/road/routing_graph.gd`, `class_name RoutingGraph extends RefCounted`.

The intersection-level map from [Navigation.md](./Navigation.md), "Two maps, not one". Graph
only — no search yet.

- [ ] `RouteEdge` inner class: `to`, `cost`, `entry_lane`
- [ ] `build(tree, road_manager, lane_graph, junction_graph)`
- [ ] `random_intersection()` — mirror `TrafficRouteGraph.random_lane()`'s stale-pruning
- [ ] Debug draw: a line per edge, labelled with its cost

**Codebase facts:**

- Intersections come from `road_manager.get_containers()`, filtering each container's children.
- `curve.get_baked_length()` is your edge cost, accumulated as you walk.
- Build and rebuild off the existing hooks in `npc_traffic_manager.gd` — `start_traffic()` and
  the coalesced `_rebuild_route_graph()`. Don't invent new lifecycle.

**Work out yourself:**

1. **The walk.** You're at a junction exit. How do you find which junction it leads to, and what
   it costs to get there? Write this before you write anything else — it's the whole of `build`.
2. **Branching.** Partway down a road, `next_lanes()` may return more than one successor. Does it
   matter which you follow? Justify your answer — and if you convince yourself it doesn't, assert
   the assumption rather than leaving it implicit.
3. **Termination.** What happens to your walk on a ring road with no intersections on it? On a
   graph caught mid-rebuild? Both of these hang the level load if you get it wrong, and both are
   real cases on real maps.

<details>
<summary>Solution — build and walk</summary>

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
        next = succs[0]                                # see note below
        if junction_graph.is_junction_lane(next):
            return RouteEdge.new(junction_graph.intersection_of(next), cost, start_movement)
        lane = next
        hops += 1
    return null                                        # ring road / mid-rebuild, bail
```

- `succs[0]` is fine **only** because between two junctions the successors are parallel lanes of
  the same road, which all arrive at the same place. If a map ever branches without an
  intersection node, this assumption breaks — assert on it rather than discovering it later.
- `MAX_HOPS` is not optional. A closed loop with no intersections hangs the level load
  otherwise, and so does a graph caught mid-rebuild.
</details>

**Verify:** draw the primal graph as thick lines between intersection origins with cost labels.
Count the nodes — it should be the number of intersections you placed, not thousands. Walk one
edge by eye and check its cost against the actual road length. Then check the graph is
**connected**: from any node you should be able to reach every other.

---

## Step 3 — A\* ⭐

Still in `routing_graph.gd`. **This is the step worth taking your time on**, and the one where
opening the solution early costs you the most.

Before you start: re-read [Navigation.md — "Finding a route"](./Navigation.md) and trace the
four-node example on paper. Not in your head — on paper, with the table. If you can't produce
`A → B → D` by hand, writing it in GDScript will not go well.

- [ ] `find_route(from, to) -> Array[RoadIntersection]`
- [ ] `_heuristic(a, b) -> float`
- [ ] `_reconstruct(came_from, current) -> Array`
- [ ] Debug: click two intersections, draw the route

**Codebase facts:**

- No priority queue in GDScript. A sorted `Array` is fine at this graph size — twenty nodes.
- Return an empty array for "unreachable". That's a real answer, not an error condition.

**Work out yourself:**

1. **What do you track per node, and where does it live?** You need cost-so-far, and you need
   enough to rebuild the path at the end. Three dictionaries and an array is one shape; there are
   others.
2. **The relax step.** You've popped a node and you're looking at a neighbour. Under exactly what
   condition do you update it? This is rule 2 from Navigation.md and it's the line people get
   wrong — write it out in words before you write it in code.
3. **When do you stop?** On popping the goal, or on first seeing it? One of those is wrong. Work
   out which, and why.
4. **The heuristic.** One line. But state to yourself *why* it satisfies rule 1 before you move
   on, because the day you switch cost to seconds is the day it stops being true.

<details>
<summary>Solution — A\*</summary>

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

    return []                        # unreachable

_heuristic(a, b):
    return a.global_position.distance_to(b.global_position)
    # never overestimates while cost is metres. If cost ever becomes seconds,
    # divide by the network-wide max speed. See Navigation.md, "Finding a route".

_reconstruct(came_from, current):
    path = [current]
    while current in came_from:
        current = came_from[current]
        path.push_front(current)
    return path
```
</details>

**Verify — do all four:**

1. **Hand-check.** Run the hand-traced example from Navigation.md through your code (fake a
   4-node graph in a test scene). Same path, same cost.
2. **Zero the heuristic.** `_heuristic` returns `0.0` → it's now Dijkstra. It must return the
   **same path** at the **same cost**, just slower. If the path changes, your heuristic
   overestimates somewhere.
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

**Codebase facts:**

- It goes next to `lane_speed()`, in the **body**, not the state. Same kind of question, same
  place. See TrafficAI.md on the brain/body split.
- `target_speed` in `Physics_Update` is already a minimum of independent caps (corner speed,
  blocker speed). A stop line is one more cap on the same number, not a new mechanism.
- The stop line already exists geometrically: a junction lane's `get_lane_start()` *is* the point
  where that branch meets the intersection (`intersection_ngon.gd:_lane_stop_position`).

**Work out yourself:**

1. Given a distance `d` to the line and a deceleration `braking`, what's the fastest you can be
   going and still stop in time? This is one line of high-school kinematics — derive it from
   `v² = u² + 2as` rather than looking it up.
2. What should it return when you're already past the line?
3. Why a small buffer, and which way does the error go if it's too big vs too small?

<details>
<summary>Solution — stopping distance and blending</summary>

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
</details>

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

This is the mutable half. `JunctionGraph` (Step 1) is static geometry shared by everything;
`JunctionState` is one object per intersection holding what's happening *right now* — who's
inside, who's waiting, since when. Server-only.

**Codebase facts:**

- `RoadLane` already tracks its own occupancy via `register_vehicle()` / `get_vehicles()`, kept
  up to date by `RoadLaneAgent.assign_lane`. You do not need to build exit-lane counting.
- The player never calls `enter()` — it has no `lane_agent` and no turn. Occupancy has to
  tolerate a body it never registered.

**Work out yourself:**

1. **Write down `may_enter`'s clauses before you code any of them.** Navigation.md gives you
   three; this step adds a fourth (a tie-break when two waiting riders both have a legal move)
   and a fifth (the deadlock escape). What order do they go in, and does the order matter?
2. **The tie-break.** With no lights and no signs, who wins? Pick the simplest rule that isn't
   obviously wrong and can be evaluated from what you have in Step 1. "Yield to the right" needs
   `edge_points`' clockwise ordering — you *can* do it, but consider whether something simpler
   gets you 90% there first.
3. **The timeout.** Where does "waiting since" get recorded and cleared? Getting the clear wrong
   is how you end up with riders that think they've been waiting for six minutes.

<details>
<summary>Solution — the gate</summary>

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
    if junction_graph.turn_direction(movement) == THROUGH:  return false
    return any other waiting vehicle has a THROUGH movement

enter(vehicle, movement):  occupants[vehicle] = movement; waiting_since.erase(vehicle)
leave(vehicle):            occupants.erase(vehicle)
```
</details>

⚠️ **Latching is not optional, and it isn't obvious.** When a rider is refused, it must remember
*which* turn it was refused for and re-ask about that same one next tick. If you re-roll
`pick_random()` every tick while queued, the rider flips between "waiting to turn left" and
"waiting to go straight" every frame, the conflict checks evaluate a different turn each time,
and you get riders darting into the junction on whichever frame their re-roll happens to come up
non-conflicting. It looks like a conflict-detection bug and it isn't.

**Verify:** raise `traffic_count` and watch a 4-way. Riders should interleave rather than
colliding. Then deliberately break it: comment out the deadlock timeout and confirm you *can*
produce a permanent 4-way standoff. Seeing the deadlock once is worth more than trusting the fix.

---

## Step 6 — Traffic lights

- [ ] `resources/traffic/junction_control.gd` — base `Resource`, `SignalState` enum
- [ ] `resources/traffic/traffic_light_control.gd`
- [ ] Addon patch: `@export var junction_control` on `RoadIntersection`
- [ ] Author one `.tres` and assign it to a test intersection
- [ ] `JunctionState.may_enter` consults it first

**Codebase facts:**

- `NetworkTime.time` (netfox) is your shared clock.
- Mark the addon edit `## PATCHED (DankNooner, traffic AI): ...` — the convention is in
  `road_lane_agent.gd:238`.
- It's a `Resource`, so it's shared and immutable and holds **no** per-junction state. That's
  precisely why `JunctionState` exists as a separate object.

**Work out yourself:**

1. **Phase from clock, with no stored state.** Given a list of phases with green and amber
   durations and the current time in seconds, which phase are we in and is it amber? Re-read
   Navigation.md's "why lights should be maths" if this doesn't feel motivated yet — then write
   it with no `Timer`, no stored index, and no member that changes.
2. **Where in `may_enter` does the light check go, and what does it *not* replace?** If you find
   yourself deleting a clause from Step 5, stop and re-read the "green isn't permission" box.
3. **Authoring.** How do you express "these turns are green together" in a `.tres` a human can
   fill in without going mad? This is the genuinely fiddly part — start with two phases
   (north-south, then east-west) and only add protected lefts once that works.

<details>
<summary>Solution — phase from clock</summary>

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

At the top of `may_enter`:

```
if control != null and control.movement_state(movement, self) != GREEN:  return false
```

Note the ordering: the light is checked **first**, but the conflict and exit checks still run
after it. A green light is one third of permission, never all of it.
</details>

**Verify:** debug-draw each branch's current state as a coloured bar above the intersection.
Watch one full cycle with traffic running. Then **start a second peer** — both must show the
same colour at the same moment with no networking involved. If they drift, something in the
phase calc isn't purely a function of `NetworkTime.time`.

---

## Step 7 — Stop signs

- [ ] `resources/traffic/stop_sign_control.gd`
- [ ] `requires_full_stop()` on the base returns false, true here
- [ ] Arrival queue in `JunctionState`

**Work out yourself:**

1. A stop sign needs an *actual* stop, not a slow roll. How do you detect one, and where does
   that check live? (The speed cap from Step 4 is already holding the rider at the line — you're
   detecting, not braking.)
2. When does a rider join the queue, and when does it leave it? List every way a rider can vanish
   mid-queue before you write it.

<details>
<summary>Solution — full stop and queue</summary>

```
# npc_traffic_state.gd
if control.requires_full_stop() and not _has_fully_stopped:
    if npc.current_speed < FULL_STOP_SPEED:
        _has_fully_stopped = true
        state.join_queue(npc)
    return                       # speed cap from Step 4 keeps holding it at the line

# stop_sign_control.gd
movement_state(movement, junction_state):
    return GREEN if junction_state.queue_head() == vehicle else RED
```
</details>

⚠️ Clear `_has_fully_stopped` when the rider leaves the junction, and drop vehicles from the
queue in `leave()` — *and* on crash and despawn. Otherwise a wiped-out rider holds the queue head
forever and the junction locks until the deadlock timeout bails everyone out one at a time.

**Verify:** an all-way stop with four approaches. Riders come to a genuine halt, then go in
arrival order. Crash one at the line on purpose and confirm the junction recovers.

---

## Step 8 — Traffic light props (your scene)

- [ ] Build the scene from `levels/assets/City Pack.undefined-glb/Traffic Light.glb`
- [ ] Script it with the interface below
- [ ] Place per branch, wire the two exports

The interface is fixed because it's what Step 6 exposes; the scene and the materials are yours.

```gdscript
@export var intersection: RoadIntersection
@export var branch: RoadPoint

func _process(_delta: float) -> void:
    set_signal_state(intersection.junction_control.branch_state(branch))

func set_signal_state(state: JunctionControl.SignalState) -> void:
    pass  # yours: emission material / lamp mesh visibility
```

You'll need to add `branch_state(branch)` to `TrafficLightControl`: reduce that branch's several
turns to the one state a physical lamp can display. Decide what that reduction is — a branch
whose through movement is green but whose left turn is red is one lamp, not two.

Runs on **every peer**, needs no server and no sync — the clock does it. Guard for
`junction_control == null` so an uncontrolled junction with a prop on it doesn't crash.

**Verify:** lights match the debug bars from Step 6, and match across two peers.

---

## Step 9 — Defensive yield to the player

- [ ] Player proximity check in `may_enter`
- [ ] Throttled, not per tick per rider

**Work out yourself:** what makes a rider decide the player is *coming at* the junction rather
than merely near it? Two quantities, and one of them is a dot product.

<details>
<summary>Solution — approach test</summary>

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
</details>

The player enters the box without ever calling `enter()`, so occupancy never sees them. That's
fine — the yield check covers approach and physical collision covers the rest. Just make sure
`occupants` tolerates a body it never registered.

**Verify:** ride at a junction where traffic has green. They should hesitate. Then ride up slowly
— they should ignore you and go. Tune `YIELD_RADIUS` until it feels like being seen rather than
like traffic that's afraid of you.

---

## Step 10 — Route-driven traffic (stretch)

Everything above works with the random walk. This is where A\* finally drives something.

- [ ] Give each rider `_destination: RoadIntersection` and `_route: Array[RoadIntersection]`
- [ ] On spawn and on arrival: pick a new destination, `find_route` to it
- [ ] `_choose_successor` prefers the successor heading toward the next hop
- [ ] Fall back to random if the route is empty or stale

**Work out yourself:**

1. You're at a junction with a list of legal successor lanes and a route that says the next
   intersection is `X`. How do you pick the lane? (Look at what you put in `RouteEdge`.)
2. **When do you reroute?** Get this wrong and you've built the exact failure Navigation.md warns
   about in "Three questions, three speeds" — name the three triggers that *are* legitimate
   before you write any of it.

<details>
<summary>Solution — successor choice</summary>

```
_choose_successor(successors):
    if _route.size() < 2:  return successors.pick_random()
    next_hop = _route[1]
    for s in successors:
        if routing_graph.edge_from(s) leads to next_hop:  return s
    return successors.pick_random()          # route went stale (road rebuild) — reroute later
```

Reroute lazily: on arrival, or when the fallback fires. **Never** per tick.
</details>

**Verify:** debug-draw one rider's route. It should follow it and pick a fresh one on arrival.
Watch the road rebuild case (drive around while a container regenerates) and confirm it falls
back to random instead of stalling.

---

## Cross-cutting — do these throughout

- [ ] **Rebuild hygiene.** `RoadContainer.rebuild_segments` frees every `RoadLane`. Every new
      structure keyed by `RoadLane` or `RoadIntersection` must rebuild in place off the existing
      coalesced `_rebuild_route_graph()` hook, and must survive holding freed instances.
      This is `TrafficAI.md`'s "What breaks" item 1, and it will bite you if you defer it.
- [ ] **Throttle every sweep.** Follow the randomised-interval pattern already in
      `nearest_racer_ahead()` and the re-latch timer, so riders never sync onto one tick.
- [ ] **Server-only.** Nothing here is client-side except the light visual, which derives from
      `NetworkTime.time`. No new RPCs, no new synced state.
- [ ] **Lint.** `.gdlintrc`, especially `class-definitions-order`.
- [ ] **Test on a two-peer session** at Steps 6 and 8, not at the end.
