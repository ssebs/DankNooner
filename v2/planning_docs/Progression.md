# Progression

> **Status 2026-11-13:** see [Built](#built), [Next](#next) and [3D models to make](#3d-models-to-make).
> Gamba wheel is out for now.
>
> **Demo scope.** The full release adds a story on top ([Story](./Story.md)); the big map's plans
> are in TODO's New Large Map. Neither is covered here.

- [Built](#built)
- [Next](#next)
- [3D models to make](#3d-models-to-make)
- [Goal](#goal)
- [The loop](#the-loop)
- [What exists](#what-exists)
- [Economy](#economy)
	- [What's locked](#whats-locked)
- [Bike types and skins](#bike-types-and-skins)
- [Challenges](#challenges)
	- [Bike challenges and mastery](#bike-challenges-and-mastery)
	- [Dailies](#dailies)
	- [Completion](#completion)
- [Stats and achievements](#stats-and-achievements)
- [Challenges menu](#challenges-menu)
- [Save slots](#save-slots)
- [New systems](#new-systems)
- [Avoid](#avoid)
- [Open questions](#open-questions)


## Built

Steps refer to [New systems](#new-systems).

- **Bike type split** (step 1): `BikeTypeDefinition` holds simulation (collision, gearing,
  physics, tricks, surfaces); skins point at their type. See [Skins](./Skins.md#biketypedefinition).
- **Skins:** mini (Grom, scooter), naked (naked, cruiser), sport (sport).
- **Rider-level gate** (steps 2 + 7, bikes only): `BikeSkinDefinition.unlock_level` +
  `SaveManager.is_locked()`. Locked garage rows show "🔒 Lvl N · $price" and still preview. New
  saves start on the mini.
- **Save version 2 + Saves menu** (step 8): old-version saves are kept but grayed out; see
  [Save slots](#save-slots).
- **Economy pass** (step 10): level-ramped payouts, tested and balanced per minute. See
  [Economy](./Economy.md).
- **UI shells, on stub data:** the profile card's Challenges / Career tabs (`profile_card.gd`
  `STUB_CHALLENGES`, `STUB_CAREER`) and the Saves menu's Career and Bike Challenges tabs
  (`saves_menu_state.gd` `_STUB_BIKE_CHALLENGES`).
- **Console:** `dbg_set_money`, `dbg_set_level`, `dbg_unlock_all`.


## Next

In build order:

1. **Stats tracker** (step 3): everything challenges count comes from it.
2. **Challenges** (step 4): per-bike-type lists + mastery, then dailies. Completion pays through
   `SaveManager.earn` and plays the [completion](#completion) juice.
3. **Unlock requirements, the rest of step 2:** mastery level gates mods; a finished list gates a
   type's other skins.
4. **Swap the UI stubs for real data** (step 6), plus the pause menu's challenge progress.
5. **Console commands** (step 9): `add_bike_level <type> <levels>`, `unlock_bike_max <type>`.
6. **Steam stats + achievements** (step 5): full build only.
7. **Level-up callout:** a HUD moment naming what a level just unlocked (see
   [Economy](./Economy.md#later)).

Still open:

- **What mastery unlocks.** Only `ColorMod` exists, so the mod ladder needs content (below)
  before mastery can reward anything. Deciding later.
- **Sport's level gate:** 5 or 6 (see [Economy](./Economy.md#pacing)).
- **Variant audio:** engine sound is per skin already (`engine_sound_id` + pitch/curves); new
  sounds come later.


## 3D models to make

**Bike skins** (unlocked by finishing the type's challenge list):

| Type | Skin | State |
|---|---|---|
| Mini | Bicycle | No model |
| Naked | ADV | No model |
| Sport | Retro sport | No model |
| Sport | Street vendor cart | Model exists (one mesh); needs the split below |

**Bike mods** (the mastery ladder; examples from [Bike challenges](#bike-challenges-and-mastery)):
wheelie bar, exhaust, training wheels. Each needs attach markers on every bike skin, since an
unlocked mod fits any bike. Textures are mods too, but they aren't models.

**Every bike skin needs** (`bike_skin.gd` drives these):

- Separate objects for `FrontWheel`, `RearWheel` and a steering node (`Handlebars` /
  `RotationPoint`) that parents the bars, fork and front wheel. Pivots at the wheel axles and the
  steering head. Matches Grom (`RotationPoint/FrontWheel`, `RearWheel`) and naked
  (`Handlebars/FontWheel`).
- The steering node's origin on the centreline with zero rotation (the game overwrites it).
- The paintable body as its own object or material slot.
- Optional: a separate taillight object, for the brake light and boost trail.

Lessons from the scooter and cruiser: an unscaled or +X-facing glb is fixed on the skin (the
cruiser rotates -90° and scales to 0.14; its wheels spin on +Z), and markers can be copied from a
same-type bike apart from the wheels.


## Goal

Give players something to grind while they ride, Call of Duty camo style: challenges to chase in
free roam and in events, unlocks that show progress, and money to spend on what they want.


## The loop

- **Money buys, levels unlock.** Most things must be unlocked first, then bought with $.
- **Events** pay money + XP (see [Payouts](./Economy.md#payouts)). They're the main income.
- **Challenges** pay money + XP and level up the bike type you did them on. Bike levels unlock
  mods and, at the top, the type's other skins.
- **Dailies** are short challenges that rotate each day, a bonus on top of events.
- **Stats** count everything, lifetime and per bike type. They feed challenges, Steam
  achievements and the Career page.


## What exists

- `PlayerDefinition.money` is spent on garage skins and horns (`SaveManager.purchase`) and on
  priced `FreeRoamActivity`s and fuel-up pumps (`SaveManager.spend`), and earned from event
  [payouts](./Economy.md#payouts) (`SaveManager.earn`).
- `PlayerDefinition.xp` is earned the same way. `level()` derives the rider level shown on the
  riding HUD from `XP_PER_LEVEL`; each level costs more than the last. It gates bikes
  (`unlock_level`).
- `current_save["progression"]` holds per-event time attack PBs and `owned` skin paths.
  `TimeAttackComponent` and `RunnerGameMode.rpc_earn` are the pattern for writing a client's save
  from a server-run event: the server RPCs each client, which writes its own save.
- **Garage shop:** characters, horns and bikes cost money; colors are free. Bikes can also need
  a rider level (`unlock_level`, checked by `SaveManager.is_locked()`). A 0 price
  counts as owned (`SaveManager.is_owned()`). A new save owns only what its default loadout uses.
  The garage (`garage_ui.gd`, free roam `GarageActivity` or the customize menu) lists every skin on
  disk with its price, tinted when unaffordable.
- `RaceChallenge` (mid-race side challenges) and `StuntChallengeGameMode` already use the word
  "challenge". The new challenges are a separate system; code names must not collide.


## Economy

Earning, payouts, rider level and pacing targets are in [Economy](./Economy.md).

### What's locked

| Item | Unlocked by | Then |
|---|---|---|
| Mini bike (Grom) | owned on a new save | — |
| Naked, sport bikes | rider level (sport's is higher) | bought with $ |
| Other skins of a type | finishing that type's challenge list (until challenges exist: cruiser uses a rider level, scooter is price-only) | bought with $ |
| Bike mods | bike-type mastery level | bought with $ (default $200) |
| Characters | nothing | bought with $ |
| Horns | nothing | bought with $ |
| Colors | nothing | free |

Bike textures are mods too (later). Unlocked mods fit any bike, not only the type that unlocked
them; each skin places its own attach markers.


## Bike types and skins

Three types, each with skins that share its stats:

- **Mini:** Grom; scooter, bicycle.
- **Naked:** naked; cruiser, ADV.
- **Sport:** sport; retro sport, street vendor cart.

The first skin is the one you buy; the rest unlock when the type's challenge list is finished.
Skins share their type's stats through `BikeTypeDefinition` ([Built](#built)).


## Challenges

One system serves bike challenges and dailies. A challenge has a goal, a target, an optional
context (which mode it must happen in), and pays money + XP.

Goal shapes seen so far:

- **Count of qualifying events:** 10× 5s wheelies, 10× 3s stoppies, 50 bunny hops, win 5 stunt
  battles, spill no gas 10×.
- **Cumulative total:** 1 minute of total airtime.
- **Single best:** hold a 10s wheelie.
- **In a context:** 10 backflips *in a stunt race*, complete 5 time trials.

Challenges count in single player and multiplayer, free roam and events, each rider into their own
save (same rule as payouts). NPCs never count.

### Bike challenges and mastery

- **One list per bike type,** about 10 challenges, about half unique to the type. All skins of a
  type count toward its list. More tricks are planned, so lists will grow.
- **Mastery:** each finished challenge levels the bike type up by one, to a max of 10. "Mastery"
  is a working name to keep it apart from rider level on screen.
- Mods unlock at mastery levels (e.g. wheelie bar, exhaust, training wheels). The ladder is
  per type and will grow.
- A **capstone** (e.g. the airtime total) is naturally the last one done but isn't locked behind
  the others. Finishing the list (max mastery) unlocks the type's other skins.

### Dailies

Same goal shapes as bike challenges, smaller targets. Three a day, drawn from a pool of templates,
counted on any bike, reset at local midnight, no rerolls.

### Completion

Only on completion, never as a live tracker: a toast with confetti VFX and a party-balloon sfx,
plus the existing `+$N` / `+N XP` pops (`RidingHUDState.pop_earned`). `AudioManager` has a
`CONFETTI_HORN` sfx that may fit. Progress shows in the pause menu and the
[Challenges menu](#challenges-menu).


## Stats and achievements

- **Two scopes:** lifetime totals, and per-bike-type counters. Both saved.
- **Broad set for the Career page,** not only what challenges read: trick counts and times
  (wheelie, stoppie, balance point, airtime, flips, grinds), crashes, wins and finishes by mode,
  plus distance, top speed, near misses and money earned.
- **Save is the source of truth.** The same counters push to Steam stats, which drive Steam
  achievements. Achievements are bragging rights for 100%ing; they unlock nothing in game.
- **The demo ships no Steam achievements,** but the system is built and the demo still saves
  stats; achievements are configured on the full app only.
- Achievement ideas: 5 minutes total wheelie time in the balance point; unlock each bike type;
  win 100 stunt races; win 100 stunt battles; crash 1,000 times.
- "In the balance point" already exists as a HUD check (`trick_popups.gd`); stats must share one
  definition with it, not copy it.


## Challenges menu

A new menu, reachable from the main, play, lobby and pause menus:

- **Career:** lifetime stats, achievement progress, rider level and its unlock track.
- **Daily:** today's three, progress, time to reset.
- **Per-bike:** each type's mastery level, challenge list, mod ladder and the skins it unlocks.

The pause menu also shows challenge progress. The garage must show a lock state with its
requirement next to the price; locked items can't be bought.

**Idea:** the main menu's profile card (`ProfileCard`, top right) could show the dailies or
Career at a glance (e.g. daily progress under the level and money), or open the Career / Daily
pages on click. It opens the Saves menu today, so this needs deciding.


## Save slots

Decided 2026-11-10. Demo and full builds share `user://` (`export.sh` only swaps the app id) and
Steam Cloud syncs `savegame_*.json`, so demo saves are named `savegame_%d_demo.json`: still inside
the cloud pattern, never colliding with a full save. Each build lists only its own saves. See also
"Demo savegame" in TODO's Steam Prep.

- **Saves menu:** the main menu's save card opens a horizontal row of slot cards (scrollbar hidden): one
  per save on disk, then empty cards in the lowest free slots until there are at least 3.
- **Active slot:** saved in `settings.json`, one key per build (`save_slot`, `demo_save_slot`),
  default 1. Its card shows "(active)" in blue at the top.
- **Card:** a still preview of the save's active loadout at the top, a renamable name (stored in
  the save; blank shows "Save N"), rider level, money and save version. Clicking the card asks
  "Load?" and makes it active (not on the active or an old card, which also don't hover); Delete
  asks first. An empty card is a big `+` that starts a new save there and makes it active.
- **Preview:** `SavePreview`, a `SubViewport` posing a `RiderVisual`, drawn once each time the
  menu opens. Never written to disk.
- **Main menu** shows the active save top right (`ProfileCard`, replacing the old greeting):
  the rider in a circle, level and money, the save name small. Clicking it opens the Saves menu.
- **Old versions** (any `version` but `save_version`) are grayed out, show their version, and can
  only be deleted. A migrate button comes later.
- **Boot on an old version:** the old file is kept, and a new save starts in the first free slot
  (4+ if 1–3 are taken), which becomes active. Corrupt files are still replaced in place.
- **Deleting the active save** switches to another current-version save, or a new one if none
  are left.


## New systems

A sketch for whoever builds this, roughly in build order. Calls marked *(builder)* are open to a
better idea; the rest were decided.

1. **Bike type split.** A per-type resource holds everything that affects simulation: the
   Gearing, Physics and Tricks groups, and collision *(builder: collision is simulation, so it
   goes with the type)*. `BikeSkinDefinition` keeps mesh, markers, rider pose, mods and audio,
   and points at its type. The type also carries its challenge list and mod ladder. ~24 scripts
   reference `BikeSkinDefinition` (player, NPC racers, traffic, garage), so read through the
   definition rather than renaming every field read.
2. **Unlock requirements.** Bike skins and mods (not characters) get a
   requirement: rider level, mastery level, or finished list. One check (beside
   `SaveManager.is_owned()`) answers "locked, and why", used by the garage and `purchase()`.
3. **Stats tracker.** Server-side, ticking every rider from synced state like `RaceChallenge`
   does, and listening to `TrickManager.combo_banked` / `combo_voided` and crashes. Server-side
   because `trick_started` / `trick_ended` fire inside the rollback tick and repeat on resim.
   It sends each rider their own increments, batched rather than per frame *(builder: cadence)*,
   and the client writes its save and pushes Steam stats. Saved under
   `current_save["progression"]` as lifetime totals plus per-type counters.
4. **Challenges.** `ChallengeDefinition` resources *(builder: name, any that doesn't collide)*
   with a goal shape, target, optional mode context and reward. Bike lists live on the type
   resource; daily templates in a pool. Progress is fed by the same increments as stats. Saved
   per challenge, plus today's date and picks for dailies. Completion pays through
   `SaveManager.earn` and plays the [completion](#completion) juice.
5. **Steam stats + achievements.** Through `SteamManager` (never a static `Steam.` call).
   Several save slots share one Steam account, so Steam should only ever move up: push a stat
   only when the save's value is higher *(builder)*. The demo app has none configured, so the
   demo build (`UtilsConstants.is_demo_build()`) skips the Steam push; its stats still save.
6. **Challenges menu + pause panel.** A new `MenuState` with Career / Daily / Per-bike sections,
   wired from main, play, lobby and pause.
7. **Garage lock state.** The requirement next to the price; locked rows can't be bought.
8. **Save slot menu + demo file naming.** Only the demo's `save_path` changes (adds `_demo`);
   full saves keep their names (see [Save slots](#save-slots)).
9. **Console commands** for playtesting, beside `dbg_set_money` in `SaveManager`:
   `add_player_xp <amount>`, `add_bike_level <type> <levels>` (completes that many of the
   type's challenges, since mastery comes from challenges, not XP) and `unlock_bike_max <type>`.
   They write the save like normal progress, so the unlocks behave the same as earned ones.
10. **Economy pass.** The level-ramped payout (see [Economy pass](./Economy.md#economy-pass)), bike prices and
   level gates, daily rewards, starting money on `default_player_definition.tres`.

Depends on, but isn't part of this: NPC racer AI difficulty ramping with event difficulty, more
tricks for unique challenges, and the tutorial (which comes before all of this for a new player).


## Avoid

- **Gating tricks:** shrinks the core fun.
- **Bike stat upgrades:** break multiplayer fairness. Skins of a type share stats for the same
  reason.
- **Crew / club systems:** a lobby of friends already is one.


## Open questions

See [Next](#next).

- **Gamba wheel** on level up (in TODO): out for now.
