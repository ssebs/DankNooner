# Stunt Race Gamemode

- [Notes](#notes)
- [MVP](#mvp)
- [Implementation approach (idea)](#implementation-approach-idea)
- [Map design](#map-design)
  - [Ramps \& routing (brainstormed)](#ramps--routing-brainstormed)
- [Design direction](#design-direction)
  - [Core loop](#core-loop)
  - [Scoring (3 axes, summed and cumulative across legs)](#scoring-3-axes-summed-and-cumulative-across-legs)
  - [Boost = fuel (decided)](#boost--fuel-decided)
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

> Goal: get the loop *playable* on a blockout level, humans-only, with the least net-new
> code. Prove the fun before building the big subsystems (full item roster, NPCs, open world,
> city vibe).

- **Legs on the stunt track.** A match is a chain of station-to-station races. Reuse the
  runner-chain pattern from `StreetRaceGameMode` (legs = the sequence of runners) — or drive
  it imperatively (see Implementation approach). The fiddly part is the multiplayer
  crash/respawn/disconnect/results handling, but there are templates for all of it.
- **Boost = fuel**, per the decided section below. Nothing to build — the existing trick →
  combo → boost loop already is this. Fill-up = full bar is a one-liner.
- **Three-axis scoring: Placement + Style + Knockouts**, summed and cumulative across legs.
  Placement (`RaceTask`) and Style (`TrickManager.get_score`) already exist; the net-new work
  is an aggregator that sums the three per leg and carries a running total, plus extending
  `ResultsHUD` to show the columns. Knockouts in the MVP is driven by **ramming** (reuses the
  crash system) plus the Oil Slick item, so the axis is live without the full item roster.
  Needs fast respawn.
- **Item system + minimal starter set.** The item *system* — on-course pickup, hold one item,
  single activate button — is the heaviest net-new MVP piece. Ship it with a small,
  non-directional starter set: **Jerry Can** (boost refill / the apex pickup), **Nitrous**
  (free boost burst), **Oil Slick** (drop-behind hazard). The full roster comes later.
- **Fill-up minigame** as a *bonus* setter (see Implementation approach). Self-contained local
  minigame; can stub to "full bar, no bonus" first and add the skill check after.
- **Minimal blockout level.** Graybox roads and map only — no city vibe yet. Straight/curvy
  road segments, station markers, and one air-line vs. ground-line junction (blockout kickers,
  not environmental ramps yet). A flat void or synthwave-grid aesthetic is fine for now. Reuse
  the existing `graybox` / `kenney_prototype-textures` assets. The Jerry Can pickup sits at the
  ramp apex.

Explicitly OUT of MVP (add after the loop works): the rest of the item roster (Bat, Shorty
Shotgun, Siphon Hose, Deployable Ramp, Sticky Tires, Armor, Roll Cage); NPC racers;
cross-city / open world; and the city aesthetic.


## Implementation approach (idea)

> Code-first, not the half-editor / half-code task-tree.

- **`StuntRaceGameMode` is imperative** — modeled on `FreeRoamGameMode`, not on the
  tutorial/race task-tree. The leg loop, scoring, and leg-completion logic live in code in
  `Enter()` / `Update(delta)` / `Exit()`. A gamemode is just a `State` with those three
  methods.
- **Resolve level objects by group lookup**, the way `FreeRoamGameMode` does with
  `EventCircles` — e.g. `get_tree().get_nodes_in_group("stunt_checkpoints")`,
  `"gas_stations"`, `"ramps"`, `"spawns"`. No `@export` NodePath wiring, no
  `GameModeEventDefinition` resources, no injection layer.
- **Borrow leaf tasks only where they save real work** — `CountdownTask`, `GridSpawnTask`,
  `RaceTask`. Everything else is plain code. Don't lean on the task framework.
- **Spatial props stay in the editor.** Checkpoints, gas-station markers, ramps, spawn
  points are physical positions in the level — placing those in the editor is inherent to a
  3D game. The split is: editor = *where things are*, code = *what the mode does*.
- **Registration is trivial.** `STUNT_RACE` is already reserved in the `Kind` enum. Adding
  the mode = one `@export var stunt_race_mode` + one line in `_gamemode_map`.

**NPC scoping:** delete most of the NPC AI now. Keep only basic lane position/movement +
the racing AI (`npc_race_state` / `npc_race_manager`) — but keep it dormant. Ship the loop
**humans-only first**, re-add racing AI after it works. Don't reimplement NPC AI until the
stunt race is working.

**Fill-up minigame:** local `CanvasLayer`, top-downish angle. Point the mouse at the pump,
nozzle follows the cursor; click & hold to fill, aiming to stop within a target range.
Because it happens while stopped at a station, it runs **outside** the netfox rollback sim —
run it locally and report the result to the server. It sets a **bonus**, not pass/fail:
you always leave with a full bar (per boost = fuel), and nailing the range grants a bonus
(e.g. an extra starting boost segment or a small score bump). Overfilling past the range
forfeits the bonus — never leaves you under-fueled. One chance is fine when the stakes are
"bonus or no bonus."


## Map design

> MVP is blockout-first: build the roads, junctions, and station markers as graybox geometry
> (a flat void / synthwave grid is fine). The city vibe below — buildings, vistas, lakes,
> environmental ramps — is all post-MVP dressing.

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

> Core rule: no shortcuts, so a ramp is never a time skip — it's a **style/boost line that
> costs risk**. Same distance as the ground route, more reward, more danger. (MVP ramps are
> plain blockout kickers; the *environmental* framing below is the post-MVP version.)

- **Ramps are environmental, not skate-park kickers.** In a city that's broken overpasses,
  collapsed bridge gaps, construction ramps, parking-garage spirals, highway on/off-ramps, hill
  crests. They read as the world, not placed toys — and the terrain+road system gives crest-launches
  for free (long straightaway → crest at the end = natural big air).
- **The air line vs. ground line fork — the fun.** At a corner or gap, two routes of *equal
  distance*: ground line is safe and low-scoring; the ramp line launches you over/across for trick
  time, but risks a crash (voids combo) and an awkward landing. Risk traded for style, not distance.
  This fork is where the risk/reward loop lives in physical space. **Nail this single junction
  first** — if choosing it is fun, ramps are earning their place.
- **Boost pickups at the apex of the arc.** Since boost *is* fuel, the air line is the
  boosted line — even a non-trickster wants it, without it being a shortcut. Stylish line =
  boosted line.
- **Chain ramps into combo runs.** Sequence ramp → smooth trickable road → rail → rooftop → next
  ramp so a skilled player keeps the combo alive across gaps (what `COMBO_GRACE_SECS` is for). Road
  *between* ramps must be smooth enough to hold a wheelie or the chain breaks.
- **Telegraph launch and landing.** Every ramp needs a readable, open, on-road landing zone visible
  from takeoff. A ramp you can't see the landing for is a crash trap, not a choice.
- **Density is the difficulty curve.** Early legs: sparse, gentle, optional ramps. Later legs
  (Gauntlet): dense ramp/rail chains where the whole street is trick terrain.


## Design direction

> The full loop concept — the vision beyond MVP. The MVP section above is the subset being
> built first; everything here is what it grows into.

> **Inspiration:** Super Battle Golf's scoreboard — several parallel scoring counters summed into
> one running total, so a player can lose every race and still win on style or knockouts. That
> multi-axis idea is what we're borrowing; everything below is in DankNooner's own terms.

### Core loop
- A match is a run through **N gas stations**, possibly spanning cities. Each **leg** is a race from
  one station to the next; arriving completes the leg.
- **Boost is the central resource — it's also your fuel.** You leave a station with a full
  bar and spend it as you go; you top it back up by doing tricks.
- Filling up at a station is a short **fill-up minigame**. It always tops you off; doing it
  well grants a bonus (it can't leave you under-fueled). Item pickups happen at the pump.

### Scoring (3 axes, summed and cumulative across legs)
Three axes that trade against each other — no dominant strategy:
- **Placement** — finish order each leg. *(already exists: `RaceTask`)*
- **Style** — best combo / trick score en route. *(already exists: `TrickManager.get_score`)*
- **Knockouts** — riders you took out. *(MVP: via ramming + Oil Slick; more knockout items later)*

Chasing a big combo means committing to the risky air lines; hunting knockouts costs speed
and boost you'd rather spend on tricks.

### Boost = fuel (decided)
- **Boost is the only meter, and it doubles as fuel.** Keep the existing trick → combo →
  boost loop exactly as-is. The existing boost meter and its gauge are the whole system —
  nothing separate to add.
- **Earned by tricks, spent by boosting** — both already implemented (`trick_controller`,
  `boost_controller`).
- **You can't run out in a punishing way.** No pedal-push, no dead-ends. Running low just
  means no boost until you trick more or reach a pump. Low boost is a soft state, never a
  fail state.
- **Filling up = full bar** (`boost_amount = BOOST_SEGMENTS`), plus whatever bonus the
  minigame grants.

### Items
The item *system* (pickup + hold one + single activate button) is the heaviest net-new piece;
there's no inventory/pickup system yet and the `entities/pickups/*` folders are empty stubs. A
minimal slice ships in the MVP — the starter set is marked below. Kept small and varied — each
targets a different axis:
- **Boost:**
  - Jerry Can — instant partial boost refill (the on-course pickup). *(MVP starter set)*
  - Siphon Hose — drain the rider ahead's boost into your bar.
- **Style:**
  - Deployable Ramp — start a combo anywhere.
  - Sticky Tires — tricks hold easier, multiplier climbs faster.
- **Knockout:**
  - Oil Slick — banana peel causes person riding over it to crash. *(MVP starter set)*
  - Bat — melee; the activate button swings left/right, knock a rider off their line so they almost crash.
    - > also, ramming into someone has the same effect
    - causes speed wobbles
  - Shorty Shotgun — blasts the rider directly ahead so they crash, Terminator-style fire animation.
  - Call the cops - same as blue shell
- **Defense:**
  - Armor — absorbs one hit (knockout, shotgun blast, or oil-slick crash), then breaks.
  - Roll Cage — your next crash doesn't void the combo you were building, then breaks.
- **Speed:**
  - Nitrous — Maxes out boost meter and uses it now *(MVP starter set)* 

> **Dependency:** knockout items (and ramming) need **fast respawn** — getting hit should bounce
> you back into the leg quickly (short recovery, keep placement stakes without a dead time-out).
> All items use the single activate button, so directional ones (Bat) resolve the direction
> themselves. Needs speed wobbles to be a thing too

### Open questions
- Match structure: how the three axes are dealt per leg, and how they're weighted against each
  other in the running total.
- Fill-up minigame: exact bonus it grants (starting boost vs. score), and the target-range
  tuning.
- Item acquisition: only at pumps, or pickups on-course too?
- How cross-city travel between stations is authored (level/segment structure) for the full
  open-world version.
