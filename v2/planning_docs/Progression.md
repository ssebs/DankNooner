# Progression

> Brainstorm, nothing built yet. Parked until NPCs work properly (mission givers depend on them).
> Story beats live in [Story](./Story.md); this doc is the systems side.

- [Goal](#goal)
- [What exists](#what-exists)
- [Decided](#decided)
- [Ideas](#ideas)
	- [Story as the spine](#story-as-the-spine)
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


## Ideas

### Story as the spine

Grow up through the bikes, Simpsons Hit & Run style:

- **Chapter 1, mini bike:** basics missions. Could replace the planned tutorial missions (MSF →
  Stunting 101 → 102 in TODO).
- **Chapter 2, naked bike:** the reward for finishing chapter 1. Street riding, races, first stunt race.
- **Chapter 3, sport bike:** bought, not given, so money has a big goal to save toward.

[Story](./Story.md) has an older version starting on a bicycle and a scooter.

### Hit & Run-style systems

- **NPC mission givers:** an NPC + speech bubble (in-world UI exists) on an existing
  `GameModeEvent` start circle. The story is an ordered list of events; finishing one unlocks the next.
- **Collectibles in trick spots:** rooftops, gaps, past a jump, so exploring through tricks pays.
  A pickup + a saved set of collected ids.
- **In-world shop:** buy skins at a garage or gas station in free roam. The gas station is already
  a hub (fuel-up). The same garage can be the customize menu's background scene.
- **Districts gated per chapter** instead of new maps. Maps are the most expensive content; the
  bridge to the island already gives a natural gate.
- **Gags / destructibles:** knock over light poles, hydrants, signs, so free roam feels alive between missions.

### Unlock cadence

Three bikes is three purchases, then the loop is over. Fill the gaps with cheap, frequent unlocks:

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
- **Bike stat upgrades:** break multiplayer fairness.
- **Dailies / login bonuses:** live-service pattern with no audience here.


## Open questions

- Story as the backbone (chapters gate bikes and districts) vs. a shop backbone (money unlocks
  everything, missions just pay well) vs. shop first, story layered on later.
- **Multiplayer story progress:** each player's lives in their own save. When playing together,
  the host's event runs and everyone gets paid, but whose story advances, and can a player join
  an event they haven't unlocked?
- Payout amounts per mode and placement.


## MVP slice

One map, three chapters of 2–3 missions each, one collectible type, money + bike unlocks. Enough to
prove the loop before adding content.

The money + unlock layer (payouts, save, locked bikes in customize) doesn't depend on NPCs and is
what the story would sit on, so it can be built first.
