# Progression

> Brainstorm, nothing built yet. Parked until NPCs work properly (mission givers depend on them).
> Story beats live in [Story](./Story.md); this doc is the systems side.

- [Goal](#goal)
- [What exists](#what-exists)
- [Decided](#decided)
- [Ideas](#ideas)
	- [Story as the spine](#story-as-the-spine)
	- [World layout](#world-layout)
	- [Hit \& Run-style systems](#hit--run-style-systems)
	- [Unlock cadence](#unlock-cadence)
	- [Avoid](#avoid)
- [Open questions](#open-questions)
- [MVP slice](#mvp-slice)


## Goal

Make points mean something: players should want to unlock something, and replay events to get it.


## What exists

- `PlayerDefinition.money` is saved/loaded but nothing reads or writes it.
- `current_save["progression"]` holds per-event time attack PBs. `TimeAttackComponent` is the
  pattern for writing a client's save from a server-run event: the server RPCs each client, which
  writes its own save.
- `LeaderboardComponent.build_results()` has every rider's final standing at the end of a race.
- Everything is unlocked today: `SaveManager` seeds one loadout per bike on first run, and the
  customize menu lists every skin it finds on disk.


## Decided

- **Every gamemode pays out** currency at its results screen. Winning a race pays more.
- **Multiplayer events follow the host's progress.** Anyone can join the host's events, locked in
  their own save or not, and earns money/XP toward their own level and unlocks. Finishing also
  marks the event completed in their own save.


## Ideas

### Story as the spine

Grow up through the bikes, Simpsons Hit & Run style. Each chapter moves you to the next district
(see [World layout](#world-layout)):

- **Chapter 1, bad side, mini bike:** learn tricks. Could replace the planned tutorial missions
  (MSF → Stunting 101 → 102 in TODO). Save up to buy the naked bike for the area's final race,
  so money has a goal from the start.
- **Chapter 2, big city, naked bike:** stunt races, time trials, stunt battles. Sport bike and more
  customization unlock here.
- **Chapter 3, calm side:** the ending. Beach town, farms, island track; dirt bike on the beach.

Outside the story, **classic mode** is the road trip: touring bike, an endless loop like the
original game. The cruiser unlock fits here. Beats are in [Story](./Story.md).

### World layout

One map grown from stunt track 01, not a map per chapter (Hit & Run's approach). Maps are the most
expensive content.

- **Calm side:** the current map. About 2/3 of it (farms, suburbs, lighthouse coast, island track)
  becomes the beach/farm/track vibe; the rest is the mountains and city. Its neon gets toned down
  so the big city stands out.
- **Interstate:** a loop, not a connector. A coastal ring road plus a mountain pass or two (Test
  Drive Unlimited's Oahu as the template) linking the calm side, city and bad side, so friends can
  cruise without dead ends. The same loop is classic mode's road trip. It needs real length to feel
  fast at sport-bike speed, which grows the world several times over. The road generator already
  has 2x2 containers.
- **Big city:** lots of neon, the nicer streets.
- **Bad side:** across the railroad tracks from the city. Old and worn: orange sodium streetlights,
  a few flickering neon signs, chain-link fences, boarded windows. The style stays the same; only
  the lighting and props change.

**The world is never gated** (Forza Horizon 5 style). The map starts under fog of war that clears
as you ride. Story events you reach early show as locked; collectibles, gas stations and garages
always work.

**No level streaming** (Godot has none). Keep everything loaded and cull with visibility ranges
(unused in levels today) and occlusion (stunt track 01 already has it). The risk is long interstate
sightlines to the city skyline. Hand-roll district streaming only if profiling demands it, and
even then the host must keep collision loaded wherever any player is. The full map renders the
live world (`Minimap`), so zoomed out it would show culled terrain; it needs a baked top-down
image, which is also what the fog of war draws over.

### Hit & Run-style systems

- **NPC mission givers:** an NPC + speech bubble (in-world UI exists) on an existing
  `GameModeEvent` start circle. The story is an ordered list of events; finishing one unlocks the next.
  Animal Crossing-style dialog: text plus gibberish voice blips.
- **Collectibles in trick spots:** rooftops, gaps, past a jump, so exploring through tricks pays.
  A pickup + a saved set of collected ids.
- **In-world shop:** buy skins at a garage or gas station in free roam. The gas station is already
  a hub (fuel-up). The same garage can be the customize menu's background scene.
- **Gags / destructibles:** knock over light poles, hydrants, signs, so free roam feels alive between missions.

### Unlock cadence

A handful of bikes is a handful of purchases, then the loop is over. Fill the gaps with cheap, frequent unlocks:

- **Color mods and character skins** as small purchases.
- **Medals per event** (bronze / silver / gold targets on time, score, or place). Extends the
  saved time attack PBs and gives a reason to replay.
- **Money buys, medals gate:** money is the grind (cosmetics), medals are skill (e.g. a bike needs
  N golds). Grinding can't skip skill; skill alone doesn't empty the shop.
- **First-clear bonus:** one-time payout per event, so players try every event once.
- **Challenge payouts:** completing a `RaceChallenge` pays a small bonus.
- **Stats page:** total wheelies, races won, best combo (already a TODO).
- **Visible locks:** locked bikes show in the customize grid with a padlock and their price or requirement.

### Avoid

- **Gating tricks:** shrinks the core fun.
- **Gating the world:** lock events, never roads or districts.
- **Crew / club systems:** a lobby of friends already is one.
- **Bike stat upgrades:** break multiplayer fairness.
- **Dailies / login bonuses:** live-service pattern with no audience here.


## Open questions

- Story as the backbone (chapters gate bikes and events) vs. a shop backbone (money unlocks
  everything, missions just pay well) vs. shop first, story layered on later.
- **Bike per chapter:** locked to the chapter's bike, or free choice once unlocked? In multiplayer,
  does everyone ride the host's chapter bike?
- The two skyscrapers sit next to the island, in the middle of the calm side. Move them to the big city?
- Payout amounts per mode and placement.


## MVP slice

One map, three chapters of 2–3 missions each, one collectible type, money + bike unlocks. Enough to
prove the loop before adding content.

The money + unlock layer (payouts, save, locked bikes in customize) doesn't depend on NPCs and is
what the story would sit on, so it can be built first. It doesn't need the world expansion either.
