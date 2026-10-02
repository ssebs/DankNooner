# Stunt Race Gamemode

- [Notes](#notes)
- [How it works](#how-it-works)
- [Fuel-up](#fuel-up)
- [Not built yet](#not-built-yet)
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


## How it works

> Updated 2026-09-28. The original plan (a standalone imperative `StuntRaceGameMode`, milestones
> M0–M4) was dropped: the stunt race runs on the shared race loop instead.

The stunt race is `RaceGameMode` with `race_type = STUNT_RACE`: the shared race loop plus
`RaceComponent` children. See [GamemodeSystem — Races](./GamemodeSystem.md#races).

- **A leg is one event.** A `GameModeEvent` with `target_gamemode = STUNT_RACE` under an
  `EventStartCircle`, running its `EventRoute` (point-to-point checkpoints, grid slots,
  `PickupSpawner`s, props) through `RaceTask`. Legs run station to station. NPC racers, traffic and
  fuel-up are per-event flags on the definition.
- **Standing = sum of the scoring components, frozen at the finish line:**
  - Style: `StyleScoringComponent`, banked trick points (`TrickManager.get_score`).
  - Placement: `FinishBonusComponent`, `placement_points` by finish place among humans.
  - Knockouts: `KnockoutScoringComponent`, `points_per_knockout` each.
  - Fuel-up: `FuelUpBonusComponent`, the clean-fill bonus from a `fuel_up_first` event's fuel-up.
- **Knockouts** go through `SpawnManager.knock_out(victim, aggressor)`: ramming (`CrashController`),
  Oil Slick, Shotgun. Human victims only; Bat wobbles aren't attributed, and a rider's own slick
  doesn't count.
- **Items** (`PickupItem` / `PickupSpawner` / `PickupItemDefinition`, server-auth via `ItemManager`)
  spawn during races (`PickupsComponent`) and in free roam (`PickupSpawnManager`). Gas Can applies
  instantly (boost refill); the rest fill the rider's single held slot, used with double-tap trick or
  `use_item`. Built: Gas Can, Bat, Oil Slick, Ramp, Shotgun.
- **Challenges:** `RaceChallenge` resources in the definition's `race_challenges`
  (`LongestWheelieChallenge`, `BestComboChallenge`, `SuggestedTricksChallenge`), run by
  `ChallengesComponent`. Suggested tricks score double in `TrickManager`.
- **Leaderboard:** `LeaderboardComponent` feeds the riding HUD's live board and the results table.

## Fuel-up

Events with `fuel_up_first` run `FuelUpGameMode` before the race, which hands the same event to
its `target_gamemode` once every rider has finished. This is the boost = fuel top-off.

**Free roam:** each pump is also a `FreeRoamActivity` (see
[GamemodeSystem](./GamemodeSystem.md)) with its own small `%PlayerStartCircle`. Its `server_start`
teleports and freezes the rider; its `server_end` sets boost to the higher of the meter and the
reported fill (`SpawnManager.set_boost_player`), then unfreezes. Cancelling partway keeps the
partial fill.

- **Pumps** are `gas_pump.tscn` (`FuelUpMinigame`) instances in `gas_station.tscn`; the circle's
  `gas_station` export picks the station. Riders get pumps in tree order by sorted peer id, so every
  peer agrees without an RPC, and a station needs one pump per rider. Extra pumps sit under a
  `GameModeObject` (`HIDE_CTRL`) so they only exist during fuel-up.
- **Each rider** is teleported to their pump's `BikeSpot` and frozen. Their own client then plays
  locally, outside the rollback sim: pump camera, rider hidden, `IN_MINIGAME` input state (hand
  cursor; the left stick steers it on gamepad), and `FuelUpHUDState` (boost gauge + step prompt).
  The pump owns all of that: gamemodes call `FuelUpMinigame.begin()` / `end()` and listen for
  `finished`.
- **Play** (one button, `use_item` / A): click the handle to pick it up; it follows the cursor by
  `HandleMarkerClick`. Nearing the cap, it swings toward the `GasCapMarkerTip` pose and rides at cap
  height. Hold to spray (holding on past the pick-up click sprays too, so riders learn to let go); it fills while
  `HandleMarkerTip` is inside `GasCapArea`. The `GLUG_GLUG` sfx plays only while filling, pausing in
  place so it plays once across the whole fill. Carry the grip back to its spot on the pump to hang
  it up, then click `%EndBtn` to finish whenever. The tank starts at the rider's boost.
- **Recoil and spill:** spraying pushes the cursor itself upward via `warp_mouse` (growing with
  spray time, plus random kicks) and the rider pulls against it. Web ignores `warp_mouse`, so it
  has no recoil. Spray not going into an unfull tank, off the cap or overfilling, counts as
  `spilled`, with `%SpillParticles` spraying from the tip, the looping `WATER_FLOWING` sfx, and a
  spilling prompt.
- **Payout differs by mode.** Free roam ignores spill (see above). Pre-race starts every tank at
  most `FULL_TANK_DRAIN_SEGMENTS` below full so full riders still play; finishing reports fill and
  `spilled`, the server sets boost to fill minus spill, and a full tank banks a bonus scaling from
  `MAX_BONUS` down to zero at `SPILL_FOR_NO_BONUS`, read by `FuelUpBonusComponent` in the stunt
  race.
- **The cap target is per bike:** `BikeSkinDefinition.gas_cap_position`, authored with
  PlayerEntity's `gas_cap_marker`.
- **Why the minigame starts on `respawned`, not `Enter`:** the teleport's `do_respawn` flips the HUD
  back to riding. The pump camera is re-asserted every frame because respawn resims reset the
  camera.

## Not built yet

- **Rest of the item roster:** Nitrous, Siphon Hose, Sticky Tires, Armor, Roll Cage, Rally Up,
  Call the cops (see Items).
- **Cross-city / open world:** islands, several stations and circuits per level.
- **City aesthetic:** environmental ramps, buildings, vistas, lakes.
- **Known gaps:**
  - A combo still running at the finish isn't banked, so it doesn't count.
  - Wobble-on-ram fires too rarely.
  - The Oil Slick mesh is a placeholder.
  - Late joiners don't see deployables already down (or a held shotgun).
  - Pump handle movement is local, so other riders see everyone's handles still hanging.


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
  - Rally Up - "lightning" item - swaps everyone to mini bike + the astronaut skin
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
