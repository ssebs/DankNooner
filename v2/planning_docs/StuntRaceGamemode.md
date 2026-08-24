# Stunt Race Gamemode

- [Notes](#notes)
- [MVP](#mvp)
- [Map design](#map-design)
  - [Ramps \& routing (brainstormed)](#ramps--routing-brainstormed)
- [Design direction (brainstormed)](#design-direction-brainstormed)
  - [Core loop](#core-loop)
  - [Scoring (multiple counters, summed and cumulative across legs)](#scoring-multiple-counters-summed-and-cumulative-across-legs)
  - [Fuel × boost (decided)](#fuel--boost-decided)
  - [Items](#items)
  - [Open questions](#open-questions)


## Notes
- want players to explore doing different tricks
- want random pickup items
  - stunt related?
  - mario-kart like?
- lap / time / distance based?
- Super Battle Golf style scoring (multiple counters / multipliers for diff things)
  - Things to track:
    - 1st place medals (count)
    - Highest trick score / Longest/best combo
    - Trick variety %

## MVP



## Map design
- Multi-City layout
  - Plan out before mapping out roads (now that I've got a working terrain+road system)
  - Smol cities w/ freeways & winding roads between, meet ups at gas stations, vista views, lakes, etc.
  - Open world
  -  i want an open world w/ diff map layouts (islands) of cities. so
  theres maybe 9 gas stations so 3 circuits per level
- Ramps & trick-friendly design
- Curvy roads
- Long straightaway
- No shortcuts

### Ramps & routing (brainstormed)

> Core rule: no shortcuts, so a ramp is never a time skip — it's a **style/fuel line that costs
> risk**. Same distance as the ground route, more reward, more danger.

- **Ramps are environmental, not skate-park kickers.** In a city that's broken overpasses,
  collapsed bridge gaps, construction ramps, parking-garage spirals, highway on/off-ramps, hill
  crests. They read as the world, not placed toys — and the terrain+road system gives crest-launches
  for free (long straightaway → crest at the end = natural big air).
- **The air line vs. ground line fork — the fun.** At a corner or gap, two routes of *equal
  distance*: ground line is safe and low-scoring; the ramp line launches you over/across for trick
  time, but risks a crash (voids combo) and an awkward landing. Risk traded for style, not distance.
  This fork is where the risk/reward loop lives in physical space. **Nail this single junction
  first** — if choosing it is fun, ramps are earning their place.
- **Fuel pickups at the apex of the arc.** Makes the air line the *fueled* line, so ramps matter to
  the Efficiency axis too — even a non-trickster wants them, without them being a shortcut. Stylish
  line = fueled line.
- **Chain ramps into combo runs.** Sequence ramp → smooth trickable road → rail → rooftop → next
  ramp so a skilled player keeps the combo alive across gaps (what `COMBO_GRACE_SECS` is for). Road
  *between* ramps must be smooth enough to hold a wheelie or the chain breaks.
- **Telegraph launch and landing.** Every ramp needs a readable, open, on-road landing zone visible
  from takeoff. A ramp you can't see the landing for is a crash trap, not a choice.
- **Density is the difficulty curve.** Early legs: sparse, gentle, optional ramps. Later legs
  (Gauntlet): dense ramp/rail chains where the whole street is trick terrain.

## Design direction (brainstormed)

> High-level loop concept. Not yet scoped for MVP — captures decisions, not implementation.

> **Inspiration:** Super Battle Golf's scoreboard — several parallel scoring counters summed into
> one running total, so a player can lose every race and still win on style or knockouts. That
> multi-axis idea is what we're borrowing; everything below is in DankNooner's own terms.

### Core loop
- A match is a run through **N gas stations**, possibly spanning cities. Each **leg** is a race from
  one station to the next; arriving completes the leg.
- **Fuel** is the central resource. You leave a station with a finite tank and manage it to reach
  the next one.
- Filling up at a station is a short **fill-up minigame** (FPS-style). Do it well → full tank + a
  bonus; do it poorly → start the next leg under-fueled. Item pickups happen at the pump.

### Scoring (multiple counters, summed and cumulative across legs)
Four axes that trade against each other — no dominant strategy:
- **Placement** — finish order each leg.
- **Style** — best combo / trick score en route (feeds off the existing trick loop).
- **Knockouts** — riders you took out.
- **Efficiency** — reached the station with fuel to spare / fewest refuels, plus fill-up skill.
Chasing a big combo burns fuel; hunting knockouts costs speed and fuel; playing efficient means
playing safe and slow.

### Fuel × boost (decided)
- **Boost burns fuel.** Keep the existing trick → combo → boost meter as-is; spending boost now
  drains the fuel tank. A big combo you can't afford to boost is wasted — a second push-your-luck
  knob on top of crash-voids-combo.
- **Run dry → comedic pedal-push.** Rider hops off and pushes the bike (funny fast-push
  animation). Always able to finish — a soft penalty (slow, tanks placement), never a dead-end.
  Also a catch-up lever.
- **Mid-leg fuel must exist** or the smart play is "never boost." Primary source: **on-course fuel
  pickups**, placed on the trick-friendly line (ramps, rooftops) so the stylish line is the fueled
  line.

### Items
Kept small and varied — each targets a different axis:
- **Fuel:**
  - Jerry Can — instant partial refuel (the on-course pickup).
  - Siphon Hose — drain the rider ahead into your tank.
- **Style:**
  - Deployable Ramp — start a combo anywhere.
  - Sticky Tires — tricks hold easier, multiplier climbs faster.
- **Knockout:**
  - Bat — melee; the activate button swings left/right, knock a rider off their line so they almost crash.
  - Shorty Shotgun — blasts the rider directly ahead so they crash, Terminator-style fire animation.
  - Oil Slick — banana peel causes person riding over it to crash
- **Defense:**
  - Armor — absorbs one hit (knockout, shotgun blast, or oil-slick crash), then breaks.
  - Roll Cage — your next crash doesn't void the combo you were building, then breaks.
- **Speed:**
  - Nitrous — boost burst that does *not* burn fuel.

> **Dependency:** knockout items need **fast respawn** — getting hit should bounce you back into
> the leg quickly (short recovery, keep placement stakes without a dead time-out). All items use the
> single activate button, so directional ones (Bat) resolve the direction themselves.

### Open questions
- Match structure: how points are dealt per leg, how the efficiency bonus is set.
- Fill-up minigame shape and how much it should gate the next leg.
- Item acquisition: only at pumps, or pickups on-course too?
- How cross-city travel between stations is authored (level/segment structure).
