# Navigation — the ideas

> The concepts behind road navigation, in plain terms. No DankNooner code in here.
> For our code see [TrafficAI.md](./TrafficAI.md), for the build order see
> [TrafficAI_TODO.md](./TrafficAI_TODO.md).

## Roads aren't navmeshes

Navmesh + `NavigationAgent` is built for someone on foot: a walkable floor, free to move in any
direction, and a solver that finds a way across it.

A bike on a road breaks every part of that. It has to stay in a lane. Lanes point one way —
driving up the oncoming lane is a bug, not a shortcut. Cutting the corner across a junction is
perfectly walkable and completely illegal. And it can't turn in place, so it has to slow down
for corners.

So nobody builds traffic on navmeshes. Roads get authored as curves instead, one curve per lane,
each pointing one way. Following a curve makes the bike look right for free, which leaves only
one decision to make: **which curve is next?** And that's a list, not geometry:

```
next_lanes = {
    lane_A: [lane_B, lane_C],
    lane_B: [lane_D],
    ...
}
```

A lookup from a lane to the lanes you may legally continue onto. That's the entire data
structure. Everything else in this doc is a search over it.

## Three questions, three speeds

Nearly every traffic bug is one part answering a question that belongs to another part. There
are three, and they run at completely different rates:

| Question | How wide | How often |
| --- | --- | --- |
| Where am I ultimately going? | the whole map | once per trip |
| Which lane do I take next? | this junction | once per junction |
| Can I go *right now*? | this second | every tick while waiting |

The human version is exact: the satnav says "turn right at Main Street". You work out which lane
that means. Your foot decides whether to go now or wait for the green. Three systems, one rider.

Fuse them and you get a bike that recalculates a cross-town route every frame because someone
stepped in front of it.

## Two maps, not one

The lane lookup above is great for driving and useless for planning. One 4-way junction is a
dozen little lanes; a city is thousands. Searching that to answer "how do I get across town" is
enormous, and most of the work is spent on detail that doesn't affect the answer.

So you keep a second, much smaller map on top of it:

```
   (Elm)────450m────(Main)
     │                 │
   300m             1200m
     │                 │
   (Oak)────800m────(Park)
```

Points are intersections, links are the roads between them, each with a length. A whole city
block grid is maybe twenty points. Plan the trip on this one, then drop back down to lanes to
actually drive it.

You never author this map by hand. You build it by walking the lane lookup: start at a junction
exit, follow lanes until you reach another junction, add up the curve lengths along the way, and
that total is the link's cost.

## Finding a route: A\*

You have that small map and two points on it. Find the cheapest way between them.

Keep a sorted list of places worth trying next. Repeatedly take the most promising one and look
at its neighbours. For each neighbour, if you just found a cheaper way to reach it than the one
you already knew about, write down the new cost and remember where you came from. When you reach
the goal, walk those "came from" notes backwards to get the route.

The only real question is what *most promising* means:

- Sort by **cost so far**, and the search spreads in a circle outward from the start — including
  a lot of ground in exactly the wrong direction. That's Dijkstra. Correct, wasteful.
- Sort by **cost so far + a guess at what's left**, and the search stretches toward the goal
  instead. That's A\*. Same algorithm, one different sort key.

```
score = cost_to_get_here + guess_at_whats_left
```

For a road map, the guess is just straight-line distance to the goal. You know where every point
is, so it's free.

Three rules and you're done:

1. **The guess must never be too big.** Overestimate and A\* will confidently hand you a route
   that isn't the shortest — and it won't error, it'll just be quietly wrong, which is worse.
   Straight-line distance is always safe when you're measuring distance, because no road is ever
   shorter than the straight line between its ends.
2. **Keep the cheaper one.** When you find a second way to somewhere you've already reached,
   compare and keep the better one. Don't blindly overwrite. This is the line people get wrong.
3. **A guess of zero turns A\* back into Dijkstra**, which is a great debugging trick. If your
   A\* returns nonsense, zero the guess. If it starts working, the bug is in the guess, not the
   search.

The trap you'll hit the moment you add speed limits: if you switch cost from metres to seconds
(`length / speed_limit`), the guess has to switch units too — and it has to divide by the
**fastest speed anywhere on the map**, not the local road's. A slow street can feed onto a
motorway, so estimating the rest of the trip at residential speed would overestimate wildly, and
you're back to breaking rule 1.

### Trace it by hand once

Worth doing on paper before you trust your code. Start `A`, goal `D`, numbers on the links are
costs, and the guess for each point is its straight-line distance to `D`:

```
        4          3
   A ───────→ B ───────→ D
   │                     ↑
   │ 2                   │ 6
   ↓          1          │
   C ───────────────────→┘

   guess: A=6   B=3   C=5   D=0
```

| Take | cost so far | guess | score | list afterwards |
| --- | --- | --- | --- | --- |
| A | 0 | 6 | 6 | B (cost 4, score 7) · C (cost 2, score 7) |
| B | 4 | 3 | 7 | C (cost 2, score 7) · D (cost 7, score 7) |
| C | 2 | 5 | 7 | D (cost 7, score 7) — via C it'd be 2+6=8, worse, so leave it |
| D | 7 | 0 | 7 | goal reached, done |

Answer: `A → B → D`, cost 7. Watch the third row — that's rule 2 doing its job. Reaching `D`
through `C` costs 8, the 7 you already had is better, so you keep it and don't overwrite where
`D` came from.

One practical note: GDScript has no priority queue. Sort an `Array` by score and take index 0.
For twenty points searched a few times a second, that is genuinely fine. Godot's built-in
`AStar3D` exists, but it wants every node to *be* a 3D position, which doesn't fit "point = an
intersection, link = a 450 m road with a length" — you'd have to shred every road into a string
of points to use it. Writing the search yourself is about forty lines.

## Who goes first

Routing tells a rider *where*. This tells it *when*, and it's a completely different kind of
problem: several vehicles want the same patch of tarmac, and only some of them can have it.

A **turn** is one way through a junction — which branch you came in on, which one you leave by.
"North to west." A 4-way where every approach can go left, straight or right has twelve of them.
Everything below is expressed in turns rather than whole junctions, because north-to-south can
be green while north-to-west is red.

Two turns **clash** if their paths cross, merge, or otherwise put two vehicles in the same place:

```
        N          N→S vs S→N    fine, parallel
        │          N→S vs E→W    clash, they cross
   W ───┼─── E     N→W vs S→N    clash, left turn across oncoming
        │          N→E vs W→E    clash, merging into one exit
        S
```

Work this out once, when the map loads — sample both curves and check whether they ever come
within a vehicle's width of each other — and store the answer. After that, the three ways of
running a junction are just different policies for who wins a clash:

- **Traffic lights** — group the turns that don't clash into phases, cycle the phases on a schedule.
- **All-way stop** — everyone stops, joins a queue, goes in arrival order.
- **Uncontrolled** — a fixed rule breaks the tie, like "yield to the right".

### The two that bite everyone

**A green light isn't permission. It's a third of permission.**

```
can I go  =  my turn is allowed        (light / queue / yield rule)
        AND  the junction is empty     (nobody I'd clash with is in there)
        AND  I have somewhere to land  (my exit isn't backed up)
```

Drop that third clause and you get real gridlock: vehicles enter on green, can't leave because
the far side is full, and now they're parked across the traffic that has the green.

**Deadlock is not hypothetical.** Four vehicles reach a 4-way stop together, each yielding to
the one on its right. Nobody moves. Ever. Real drivers break it by someone getting impatient, so
give yours the same escape hatch: if you've been waiting longer than N seconds, go anyway. That
isn't a hack, it's the standard fix, and it's the difference between a traffic system and a car
park.

## Why lights should be maths, not a Timer

This one matters because the game is server-authoritative.

Anything you can calculate purely from a clock needs no networking at all. Every machine works
it out independently and they all agree, forever, for free:

```
cycle_length = total of all phase durations
t            = fmod(shared_clock, cycle_length)
phase        = whichever phase t lands inside
```

No stored state, no RPC, no drift. A `Timer` node is the exact opposite — it starts whenever
*that particular machine* loaded the level, so two players would see different lights.

Anything that accumulates state as it goes — a stop-sign queue, who's currently inside the
junction — can't be done this way. That has to live in one place and be owned by the server.

**Rule of thumb: calculate it from the clock where you can, own it on the server where you can't.**

## Further reading

- Red Blob Games, *Introduction to A\** — the best explanation of this that exists, with
  interactive diagrams you can drag around.
- SUMO's docs on junction logic and right-of-way, if you ever want the full traffic-engineering
  version of the "who goes first" section.
