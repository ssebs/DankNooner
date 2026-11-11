# Progression

> **WIP 2026-11-10: bike type split + skin variants.** Working on [New systems](#new-systems)
> step 1 only. Gamba wheel is out for now.
>
> **Built (scooter ridden and working 2026-11-10; the other types not re-checked):**
> - `BikeTypeDefinition` (`resources/bikes/bike_type_definition.gd`) holds the Collision,
>   Gearing, Physics, Tricks and Surfaces groups. The mini, naked and sport `.tres` files in
>   `resources/bikes/types/` carry the old per-bike values. Documented in
>   [Skins](./Skins.md#biketypedefinition).
> - `BikeSkinDefinition.bike_type` plus read-only forwarders, so callers didn't change.
>   `to_dict`/`from_dict` didn't change either: the type comes with the base def.
> - **Scooter** (mini type): `player/bikes/scenes/scooter_bike.tscn` and
>   `resources/bikes/skins/scooter_skin_definition.tres`. Mesh scale, offset and wheel markers
>   were computed from the glb. Markers placed by hand. `Top`'s origin must sit on the centreline
>   with zero rotation, because the game overwrites its rotation to steer.
>
> - **Cruiser** (naked type): `cruiser_bike.tscn` + `cruiser_skin_definition.tres`, built
>   and working 2026-11-10. The glb faces +X and is unscaled, so the skin rotates it -90° and
>   scales it to 0.14; its wheels spin on +Z. Paint is its own material (surface 2) on the
>   body and `Top`; the textured surface 0 stays as is. Markers other than the wheels are copied from the naked bike.
>
> - **Rider-level gate** (steps 2 + 7, bikes only), built 2026-11-10, untested.
>   `BikeSkinDefinition.unlock_level` + `SaveManager.is_locked()`. Locked garage rows are
>   disabled, show "🔒 Lvl N · $price", and still preview. Mini is free; naked and sport are
>   gated, sport higher. `BikeMod.price` has a default (`ColorMod` is 0). New saves start on the
>   mini (`default_player_definition.tres`). Deferred to step 4: the finished-list requirement for variants and mastery gates for mods.
> - **Save version 2** (`SaveManager.save_version`): a save with another version isn't loaded,
>   so pre-gate saves don't keep bikes they never bought. It stays on disk, grayed out in the
>   [Saves menu](#save-slots); boot starts a new save in a free slot. Settings
>   (`settings.json`) are untouched.
> - **Saves menu** ([Save slots](#save-slots), step 8): built 2026-11-10, untested.
>
> **Next:** the retro sport bike (Street Vendor Cart stand-in), once the model is split in Blender.
>
> **Blender edits needed** for the stand-in (it's one mesh; `bike_skin.gd`
> needs a steering node for the handlebar IK proxy, and wheel nodes for spin):
> - Split out separate objects for `FrontWheel`, `RearWheel` and a `Handlebars`/`RotationPoint`
>   that parents the bars, fork and front wheel. Pivots go at the wheel axles and the steering
>   head. This matches Grom (`RotationPoint/FrontWheel`, `RearWheel`) and naked (`Handlebars/FontWheel`).
> - Split the paintable body into its own object or material slot.
> - Optional: a separate taillight object, for the brake light and boost trail.
> - Steering node: origin on the centreline, zero rotation (the game overwrites it).
>
> **Open questions:**
> - **Variant audio:** engine sound is per skin already (`engine_sound_id` + pitch/curves); new
>   sounds come later. Traffic rolls every skin, which is fine.
> - Answered 2026-11-10: characters are price-only; naked and sport both need a rider level;
>   Claude drafts the challenge lists for the user to edit; stats cover a broad Career page.
> - Still open: the actual level numbers for naked and sport (economy pass).

> **Demo scope.** The full release adds a story on top ([Story](./Story.md)); the big map's plans
> are in TODO's New Large Map. Neither is covered here.
> Built: [payouts](#payouts), the garage shop, money + XP. Everything else is the plan.

- [Goal](#goal)
- [The loop](#the-loop)
- [What exists](#what-exists)
- [Economy](#economy)
	- [Pacing](#pacing)
	- [What's locked](#whats-locked)
- [Bike types and skins](#bike-types-and-skins)
- [Challenges](#challenges)
	- [Bike challenges and mastery](#bike-challenges-and-mastery)
	- [Dailies](#dailies)
	- [Completion](#completion)
- [Stats and achievements](#stats-and-achievements)
- [Challenges menu](#challenges-menu)
- [Save slots](#save-slots)
- [Payouts](#payouts)
- [New systems](#new-systems)
- [Avoid](#avoid)
- [Open questions](#open-questions)


## Goal

Give players something to grind while they ride, Call of Duty camo style: challenges to chase in
free roam and in events, unlocks that show progress, and money to spend on what they want.


## The loop

- **Money buys, levels unlock.** Most things must be unlocked first, then bought with $.
- **Events** pay money + XP (see [Payouts](#payouts)). They're the main income.
- **Challenges** pay money + XP and level up the bike type you did them on. Bike levels unlock
  mods and, at the top, the type's other skins.
- **Dailies** are short challenges that rotate each day, a bonus on top of events.
- **Stats** count everything, lifetime and per bike type. They feed challenges, Steam
  achievements and the Career page.


## What exists

- `PlayerDefinition.money` is spent on garage skins and horns (`SaveManager.purchase`) and on
  priced `FreeRoamActivity`s and fuel-up pumps (`SaveManager.spend`), and earned from event
  [payouts](#payouts) (`SaveManager.earn`).
- `PlayerDefinition.xp` is earned the same way. `level()` derives the rider level shown on the
  riding HUD from `XP_PER_LEVEL`; each level costs more than the last. It gates nothing yet.
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

### XP and money today

- **Where it comes from:** only event [payouts](#payouts) and time attack laps. Free roam,
  challenges and dailies pay nothing yet. No event overrides the `payout_money` / `payout_xp`
  defaults on `GameModeEventDefinition`, so every event pays the same base.
- **Rider level** is derived from total XP (`PlayerDefinition.level()`, `XP_PER_LEVEL`); each level
  costs more XP than the last. Reaching a level pays nothing and plays nothing; it only lifts
  bike `unlock_level` gates and shows on the riding HUD.
- **Money** starts at the default definition's amount and is spent in the garage, on priced free
  roam activities and on fuel-ups.
- **Off target:** with flat payouts, the gated bikes take far longer to afford than
  [Pacing](#pacing) wants.

**Next:**
1. [Economy pass](#economy-pass): payouts that ramp with rider level, sized to the pacing
   targets. Planned, not built.
2. Challenges and dailies as a second income (steps 3 and 4), which also unlock variants and mods.
3. A level-up moment: a HUD callout when a level is crossed, naming anything it just unlocked.
   Not designed yet.

### Economy pass

Decided 2026-11-10, not built.

- **Raise payouts, don't cut prices.** Bikes stay well above cosmetics.
- **No difficulty tiers.** Every event shares one base payout; it ramps with the rider's
  **level** instead: `(event base × place multiplier + score × rate) × level multiplier`. This
  changes the [payout](#payouts) formula. The level multiplier also offsets each level costing
  more XP than the last, so levels don't slow to a crawl.
- **Demo scope:** only Stunt City ships, so the demo's events are its stunt races, track race,
  time attacks, trick battle and crash launch. One event runs about 30 s to 2 min.
- **Tutorial** keeps its existing one-off payout.

Open, to settle before building:

- **Score magnitudes:** the user reads score and earned columns off a few stunt race and trick
  battle results screens. The score rates are tuned so the score adds to the base without
  swamping it.
- **Multiplier shape:** linear per level (simplest), capped or not.
- **Where the server gets the level:** payouts are computed on the server, so it needs each
  rider's level. Check whether the lobby's synced player data carries `xp` before adding
  anything.
- **The numbers:** event base money and XP, the level multiplier, and starting money, sized
  against [Pacing](#pacing) with a quick simulation of a grinder and a 100%er.

### Pacing

Targets to tune toward. Prices, levels and payout bases are set on the definitions.

- A new save owns the mini bike, at rider level 1, with starting money that buys neither of the
  other bikes.
- The naked bike is a short save-up plus a low rider level.
- A player grinding toward the sport bike gets it in about **30 minutes** of events.
- A 100%er (every bike, variant, mod and challenge) takes about **an hour**; challenges and mods
  add to the run beyond events.
- Payouts ramp with rider level (see [Economy pass](#economy-pass)), not with event difficulty.
- Three dailies are worth about ten races of XP.
- Cosmetics are cheap next to bikes, so buying one doesn't wreck the bike savings.

### What's locked

| Item | Unlocked by | Then |
|---|---|---|
| Mini bike (Grom) | owned on a new save | — |
| Naked, sport bikes | rider level (sport's is higher) | bought with $ |
| Other skins of a type | finishing that type's challenge list | bought with $ |
| Bike mods | bike-type mastery level | bought with $ (default $200) |
| Characters | nothing | bought with $ |
| Horns | nothing | bought with $ |
| Colors | nothing | free |

Bike textures are mods too (later). Unlocked mods fit any bike, not only the type that unlocked
them; each skin places its own attach markers.


## Bike types and skins

Three types, each with skins that share its stats:

- **Mini:** Grom; bicycle.
- **Naked:** naked; cruiser, ADV.
- **Sport:** sport; retro sport.

The first skin is the one you buy; the rest unlock when the type's challenge list is finished.
Today `BikeSkinDefinition` holds both the look and the stats, so the stats move to a shared
per-type resource (see [New systems](#new-systems)).


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


## Save slots

Decided 2026-11-10. Demo and full builds share `user://` (`export.sh` only swaps the app id) and
Steam Cloud syncs `savegame_*.json`, so demo saves are named `savegame_%d_demo.json`: still inside
the cloud pattern, never colliding with a full save. Each build lists only its own saves. See also
"Demo savegame" in TODO's Steam Prep.

- **Saves menu:** a main menu button opens a horizontal row of slot cards (scrollbar hidden): one
  per save on disk, then empty cards in the lowest free slots until there are at least 3.
- **Active slot:** saved in `settings.json`, one key per build (`save_slot`, `demo_save_slot`),
  default 1. Its card shows a gray "(active)" under the name.
- **Card:** a still preview of the save's active loadout at the top, a renamable name (stored in
  the save; blank shows "Save N"), rider level, money and save version. Clicking the card asks
  "Load?" and makes it active (not on the active or an old card, which also don't hover); Delete
  asks first. An empty card is a big `+` that starts a new save there and makes it active.
- **Preview:** `SavePreview`, a `SubViewport` posing a `RiderVisual`, drawn once each time the
  menu opens. Never written to disk.
- **Main menu** shows the active save in place of the old greeting (`CurrentSaveCard`): the rider
  in a circle, level and money, the save name small. Display only; the Saves button opens the
  menu.
- **Old versions** (any `version` but `save_version`) are grayed out, show their version, and can
  only be deleted. A migrate button comes later.
- **Boot on an old version:** the old file is kept, and a new save starts in the first free slot
  (4+ if 1–3 are taken), which becomes active. Corrupt files are still replaced in place.
- **Deleting the active save** switches to another current-version save, or a new one if none
  are left.


## Payouts

Built.

- **Formula:** `event base × place multiplier + score × rate`, computed separately for money and
  XP. Place multipliers fall off from 1st, with a floor for everyone below the podium. Score
  only applies in score modes (stunt race, trick battle, long jump); pure races and stunt
  challenges pay on placement alone. In score modes a rider who scored 0 gets the floor whatever
  their row, so idling never pays 1st.
- **Tunables:** the base money and XP are per event, on `GameModeEventDefinition`. Place
  multipliers, score rates and the time attack lap fraction are shared constants.
- **Placement** is the rider's row on the results screen they see, NPCs included, so beating
  bots counts.
- **Where:** the server computes it in `RunnerGameMode._show_results()`, which every
  results-showing mode goes through. It RPCs each rider, whose client writes its own save via
  `RunnerGameMode.rpc_earn`, which also pops `+$N` and `+N XP` off the riding HUD. The results
  screen shows the earned money and XP columns. Modes add score through the `_payout_score`
  override (`TimedScoreGameMode`, stunt races).
- **Time attack** never reaches the results screen: every lap pays a fraction of the base, and a
  lap that beats the rider's saved PB pays the full base on top. Laps pay through
  `RunnerGameMode.earn`, so the point-to-point run screen shows the event's earnings so far.
- **Doesn't pay:** free roam, fuel-up, and events the host cancels without results. Late joiners
  who never raced aren't in the results, so they get nothing. (Challenges finished in free roam
  still pay their own reward.)


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
10. **Economy pass.** The level-ramped payout (see [Economy pass](#economy-pass)), bike prices and
   level gates, daily rewards, starting money on `default_player_definition.tres`.

Depends on, but isn't part of this: NPC racer AI difficulty ramping with event difficulty, more
tricks for unique challenges, and the tutorial (which comes before all of this for a new player).


## Avoid

- **Gating tricks:** shrinks the core fun.
- **Bike stat upgrades:** break multiplayer fairness. Skins of a type share stats for the same
  reason.
- **Crew / club systems:** a lobby of friends already is one.


## Open questions

- **Bike level gates:** the rider levels for naked and sport (economy pass).
- **Gamba wheel** on level up (in TODO): out for now.
