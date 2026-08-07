# Navigation Primer

> Theory only. No DankNooner code in here — read this first to switch context, then read
> [TrafficAI.md](./TrafficAI.md) for how our code actually does it, then
> [TrafficAI_TODO.md](./TrafficAI_TODO.md) to build it.

---

## 1. Context switch: what "navigation" even means for cars

If your mental model of game AI navigation is **navmesh + NavigationAgent**, put it down. That
model is built for a pedestrian: a continuous walkable surface, an agent free to move anywhere
on it in any direction, and a solver that finds a polygon corridor and funnels a string-pulled
path through it.

A vehicle breaks all three assumptions:

| Navmesh assumes | A car/bike is |
| --- | --- |
| Any point on the surface is reachable | Constrained to a lane, laterally |
| Direction of travel doesn't matter | One-way. Driving up the oncoming lane is a bug, not a shortcut |
| Any geometric path is a legal path | Cutting the corner across the junction is illegal even though it's walkable |
| Turning is free | Non-holonomic — can't turn in place, needs radius and needs to slow for it |

So nobody builds traffic on navmeshes. Roads come pre-authored as **a directed graph of
curves**: the curve handles the steering (a car following a spline looks correct for free), and
the graph handles the deciding.

### The three questions

The single most useful thing to internalise before you write a line of this: traffic AI is
**three separate questions**, at three different rates, and nearly every bug in a traffic system
is one of them answering a question that belongs to another.

| # | Question | Scope | How often | Name for it |
| --- | --- | --- | --- | --- |
| 1 | Where am I ultimately going? | Whole map | Once per trip | **Routing** (GPS) |
| 2 | Which curve do I follow next? | This junction | Once per junction | **Lane selection** |
| 3 | May I go *now*? | This junction, this second | Every tick while waiting | **Traffic control** |

Keep them in separate objects. Question 1 is a graph search. Question 2 is a table lookup.
Question 3 is a mutual-exclusion problem with a clock. They share data but they are not the
same code, and fusing them is how you end up with a car that recomputes a cross-town route
every frame because a pedestrian stepped in front of it.

---

## 2. Graphs, just enough

A graph is a set of **nodes** (vertices) and **edges** connecting them.

- **Directed**: edges have a direction. `A → B` does not imply `B → A`. Roads are directed —
  this is not optional, it's the whole point.
- **Weighted**: each edge has a cost. Length in metres, or seconds of travel time, or "metres
  but left turns cost an extra 30".

You store it as an **adjacency map**: a dictionary from node to the list of nodes you can
reach from it.

```
successors = {
    A: [B, C],
    B: [D],
    C: [D],
    D: [],
}
```

That's it. That's the data structure. Everything else is a search over it.

### The two ways to model a road network

This is *the* concept to internalise, because picking the wrong one is what makes traffic AI
feel impossible.

**Model 1 — the primal / "GPS" graph.**
Node = an intersection. Edge = the stretch of road between two intersections.

```
     (Elm)────450m────(Main)
       │                 │
     300m              1200m
       │                 │
    (Oak)─────800m────(Park)
```

- Small. A whole city block grid is maybe 20–100 nodes.
- Weights are natural and meaningful: length, or length ÷ speed limit = travel time.
- This is what every real satnav uses.
- **It cannot tell you which lane to be in.** It doesn't know lanes exist.

**Model 2 — the dual / "lane" graph.**
Node = a single lane (one directional curve). Edge = "a vehicle on lane A may legally continue
onto lane B next."

```
    [Elm_F0] ──→ [Junction_ElmToMain_through] ──→ [Main_F0]
        └───────→ [Junction_ElmToOak_left]    ──→ [Oak_F0]
```

- Much bigger — a 4-way junction alone generates a dozen internal lanes.
- Legality is *structural*: if there's no edge from the left lane to the right-turn lane, the
  turn is simply not in the graph. You never write an `if` to forbid it.
- Great for driving. Terrible to A* across a whole city — you'd expand thousands of nodes to
  answer a question the primal graph answers in twenty.

**Neither is wrong. You want both.** That's hierarchical routing, section 4.

---

## 3. Shortest path

You have a graph and two nodes. Find the cheapest route.

### BFS — wrong, but shows the shape

Breadth-first search explores in rings: all nodes 1 hop away, then all 2 hops away, etc. It
finds the path with the **fewest edges**.

That's wrong for roads, and it's worth understanding *why*: fewest-hops would send a car down
a 5 km motorway to avoid three 200 m residential streets. Hop count is not cost. The moment
edges have weights, BFS is out.

### Dijkstra — correct, but wasteful

Instead of a plain queue, keep a **priority queue** of frontier nodes ordered by
`g(n)` = cheapest known cost from the start to `n`. Repeatedly pop the cheapest, and relax its
neighbours:

```
if g(current) + weight(current, neighbour) < g(neighbour):
    g(neighbour) = g(current) + weight(current, neighbour)
    came_from[neighbour] = current
    push neighbour
```

When you pop the goal, `g(goal)` is optimal, and you rebuild the path by walking `came_from`
backwards.

Dijkstra is correct. Its problem is that it has no idea where the goal is, so it expands a
roughly **circular blob** outward from the start — including a lot of nodes in exactly the
wrong direction.

### A* — Dijkstra that knows which way the goal is

Add a **heuristic** `h(n)`: a guess at the remaining cost from `n` to the goal. Order the
priority queue by

```
f(n) = g(n) + h(n)
      ^^^^   ^^^^
      known  guessed
      so far remaining
```

Same algorithm, one changed sort key. Now the frontier stretches toward the goal instead of
ballooning in all directions.

For a road network, `h(n)` = straight-line distance from `n` to the goal. You always know node
positions, so it's free.

### Admissibility — the rule that makes it correct

> **`h(n)` must never overestimate the true remaining cost.**

A heuristic with this property is **admissible**, and an admissible heuristic guarantees A*
returns the optimal path. Overestimate, and A* will confidently return a route that isn't the
shortest — and it won't error, it'll just be quietly wrong, which is worse.

Straight-line distance is admissible when cost is distance, because no road is ever shorter
than the straight line between its ends.

**The classic bug, and you will hit it the moment you add speed limits:** if you switch edge
weight from *metres* to *seconds* (`length / speed_limit`), your heuristic must switch units
too. And it must divide by the **fastest speed anywhere in the network**, not the local road's
speed:

```
h(n) = distance_to_goal(n) / max_speed_in_whole_network   # admissible ✓
h(n) = distance_to_goal(n) / this_road_speed              # NOT admissible ✗
```

Because a slow road might feed onto a motorway, and estimating the rest of the trip at
residential speed would overestimate wildly.

Two more terms you'll see:

- **Consistent / monotonic**: `h(n) ≤ weight(n, m) + h(m)` for every edge. Stronger than
  admissible. Straight-line distance is consistent. If your heuristic is consistent you never
  need to re-open a node you've already closed — which lets you keep a simple `closed` set.
- `h(n) = 0` turns A* back into Dijkstra exactly. Useful sanity check: if your A* is broken,
  zero the heuristic. If it starts working, the bug is in `h`, not the search.

### Worked example — verify your implementation by hand

Weights on edges, `h` = straight-line to `D`. Start `A`, goal `D`.

```
        4          3
   A ───────→ B ───────→ D
   │                     ↑
   │ 2                   │ 6
   ↓          1          │
   C ───────────────────→┘

   h(A)=6   h(B)=3   h(C)=5   h(D)=0
```

| Step | Pop | g | h | f | Frontier after (node: g, f) |
| --- | --- | --- | --- | --- | --- |
| 1 | A | 0 | 6 | 6 | B: 4, f=7 · C: 2, f=7 |
| 2 | B *(tie, took B)* | 4 | 3 | 7 | C: 2, f=7 · D: 7, f=7 |
| 3 | C | 2 | 5 | 7 | D: 7, f=7 *(via C = 2+6 = 8, worse, not relaxed)* |
| 4 | D | 7 | 0 | 7 | — goal popped, done |

Result: `A → B → D`, cost 7. Note step 3: the path through `C` reaches `D` at cost 8, so the
existing 7 stands and `came_from[D]` is not overwritten. **That comparison is the single line
people get wrong** — you must compare and keep the better one, not blindly overwrite.

### Priority queues in Godot

GDScript has no binary heap. Your options:

1. **Sorted `Array`** — `push` then `sort_custom` by `f`, pop index 0. O(n log n) per push, but
   for a graph of 20–100 nodes searched a few times a second, this is genuinely fine. Start here.
2. **`AStar3D`** — Godot's built-in. It handles the queue *and* the search for you.

On option 2, know the tradeoff before you reach for it: `AStar3D` models nodes as **3D
positions** and derives its heuristic from them. That's a fine fit for a point cloud, and a
poor fit for "node = an intersection, edge = a 450 m road with a length" — you don't get to
express the edge cost independently of the node positions without overriding
`_compute_cost` / `_estimate_cost` in a subclass.

It's also why the addon's own demo scene samples a point every 10 m along every lane and wires
thousands of points together: that's the workaround for AStar3D's position-centric model, not
the natural way to represent a road graph.

**Recommendation for learning:** hand-write A* over an adjacency map with a sorted array. It's
about 40 lines, the routing graph is small enough that performance is irrelevant, and writing
it is the entire point of the exercise. Reach for `AStar3D` later if profiling says so.

---

## 4. Hierarchical routing — using both graphs

The two models from section 2 compose:

```
  ┌─────────────────────────────────────────┐
  │  ROUTING LAYER   (primal graph)         │
  │  nodes = intersections                  │
  │  edges = roads, weighted by length/time │
  │  A* runs here.  Small, rare, global.    │
  └───────────────────┬─────────────────────┘
                      │  "at Main St, exit toward Oak"
                      ▼
  ┌─────────────────────────────────────────┐
  │  LANE LAYER      (dual graph)           │
  │  nodes = lane curves                    │
  │  edges = legal continuations            │
  │  Table lookup. Per junction, local.     │
  └───────────────────┬─────────────────────┘
                      │  "follow this specific curve"
                      ▼
  ┌─────────────────────────────────────────┐
  │  CONTROL LAYER                          │
  │  may I enter the junction right now?    │
  │  Per tick while waiting.                │
  └─────────────────────────────────────────┘
```

The human analogy is exact: the satnav says *"turn right at Main Street"* (routing). You work
out that this means getting into the right-hand lane (lane selection). Your foot decides
whether to go now or wait for the green (control). Three systems, one driver.

The routing layer is built **by walking** the lane layer: start at an intersection exit, follow
lane successors until you arrive at another intersection, and the total curve length you
accumulated is that edge's weight. You never author the routing graph by hand.

---

## 5. Traffic control theory

Routing tells a car *where*. Control tells it *when*. This is a completely different kind of
problem — it's mutual exclusion, the same shape as a lock in concurrent programming.

### Movements

A **movement** is an ordered pair: *(incoming branch, outgoing branch)*. At a 4-way where every
approach can go left / straight / right, that's 4 × 3 = **12 movements**.

Movements are the unit everything else is expressed in. Not "the intersection is red" — *this
movement* is red. North-to-south can be green while north-to-west is red.

### Conflicts

Two movements **conflict** if their paths cross, merge, or diverge in a way that would put two
vehicles in the same space.

```
        N                 N→S  and  S→N     do NOT conflict (parallel)
        │                 N→S  and  E→W     DO conflict (cross)
   W ───┼─── E            N→W  and  S→N     DO conflict (left turn across oncoming)
        │                 N→E  and  W→E     DO conflict (merge into same exit)
        S
```

Store this as a **conflict set** or a symmetric boolean matrix, computed **once** when the map
loads. For each pair of movements, do their paths come within a car's width of each other? If
yes, they conflict.

This is the foundation. All three control disciplines below are just different policies for
deciding who gets to go when two movements conflict.

### The three disciplines

**Signalised (traffic lights) — time-division multiplexing.**

Partition the movements into **phases**, where every movement inside a phase is mutually
non-conflicting. Cycle the phases on a fixed schedule.

```
Phase 0  (8s green, 2s amber):  N→S, S→N, N→E, S→W      [north-south through + rights]
Phase 1  (8s green, 2s amber):  E→W, W→E, E→S, W→N      [east-west through + rights]
Phase 2  (5s green, 2s amber):  N→W, S→E                [protected lefts]
```

The beautiful property: **if phase = f(clock), the controller holds no state at all.** Given
the same clock, every machine computes the same light independently. No synchronisation, no
network messages. That matters enormously for multiplayer — see §6.

**Stop-controlled (all-way stop) — a fair lock with a FIFO queue.**

No schedule. Each vehicle must come to a **full stop** at the line, join an arrival queue, and
may proceed when it's at the head of the queue and no conflicting movement is still occupying
the box. This one *does* need state — the queue — which means it can't live in a shared,
immutable resource. It needs a per-junction runtime object.

**Uncontrolled / priority — a static tie-break rule.**

No schedule, no queue. When two conflicting movements arrive together, a fixed rule decides:
"yield to the right", or "turning traffic yields to through traffic". Cheapest to evaluate,
and the most deadlock-prone.

### Two things that bite everyone

**1. A green light is not permission — it's half of permission.**

```
may_enter  =  movement_is_legal      (light / queue / priority rule)
          AND box_is_clear           (no conflicting vehicle currently inside)
          AND exit_is_clear          (somewhere to actually go once through)
```

Drop the third clause and you get real gridlock: cars enter on green, can't leave because the
far side is backed up, and now they're blocking the cross traffic that has the green. Every
term above is mandatory, including on green.

**2. Deadlock is not hypothetical.**

Four cars arrive simultaneously at a 4-way stop, each yielding to the one on its right — a
perfect cycle, nobody moves, forever. Real drivers break it by someone being impatient.

Your AI needs the same escape hatch: **a timeout**. If a vehicle has been waiting longer than
N seconds, it takes priority regardless of the rule. This is not a hack — it's the standard
solution, and it's the difference between a traffic system and a parking lot.

---

## 6. Determinism and multiplayer

A short but load-bearing note, since this game is server-authoritative.

Anything that is a **pure function of a shared clock** needs no synchronisation whatsoever.
Every peer computes it independently and they all agree, forever, for free.

```
phase_index = f(shared_clock_seconds)        # no state, no RPC, no drift
```

Traffic lights are the textbook case, which is exactly why the "phase = f(clock)" formulation
in §5 is worth the small awkwardness of expressing a schedule as arithmetic instead of a
`Timer`. A `Timer` node is *not* a pure function of the clock — it starts whenever that peer
loaded the level, so two players would see different lights.

Anything holding **accumulated state** — a stop-sign queue, who's currently in the box — is the
opposite: it must live on one authority and be either replicated or kept entirely
server-side. In our case NPC decisions are already server-only, so "entirely server-side" is
the cheap answer, and only the *visual* needs to reach clients — which the clock gives you for
free.

Rule of thumb: **derive from the clock where you can, own it on the server where you can't.**

---

## 7. Where to go next

- [TrafficAI.md](./TrafficAI.md) — how DankNooner does this today, file by file, and what each
  file's job becomes.
- [TrafficAI_TODO.md](./TrafficAI_TODO.md) — the build order, with pseudocode.

### If you want to read further

- *Amit Patel's A\* pages* (Red Blob Games) — the best explanation of A\* and heuristics that
  exists. Read the "Introduction to A\*" and "Heuristics" pages.
- The distinction in §2 is formally the **primal vs. dual graph** of a road network; searching
  for "lane graph" or "turn-expanded graph" will find the traffic-engineering literature.
- **SUMO** (Simulation of Urban MObility) is the open-source reference traffic simulator; its
  docs on *connections*, *junction logic* and *right-of-way* describe exactly the model in §5.
