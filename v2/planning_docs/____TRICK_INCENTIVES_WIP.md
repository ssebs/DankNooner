# Trick Incentives (WIP)

High-level design. Nothing here is built yet.

## Problem

Playtesters race from checkpoint to checkpoint and skip tricks. Riding a straight line is faster
than tricking, so the game rewards ignoring its main mechanic. Related notes:

- Racers are too fast. After a crash you can't see anyone and have no way back.
- Score is a reason to trick, but players don't notice it.
- The mini can't start a clutch-up at its higher speeds, so on a straight it has no trick to open a
  combo with.
- Traffic crashes feel unfair during challenges.

## Rule

**The trick line has to beat the straight line.** Tricks should be the fastest way around the
course, and the game should show players that while they ride.

## Goals

- Tricking is faster than riding plain, in races and stunt races.
- Crashed or trailing riders can catch up by tricking.
- Riding plain looks and sounds flatter than tricking.
- Players can see what tricks earned them (time, score, $).
- Traffic is still a risk, but a glancing hit isn't a run-ender.

## Non-goals

- Buffing the mini's `max_speed` / `acceleration`. It stays slow; it only needs to be able to
  trick.
- Changing the wheelie feel of the other bikes.
- Passive rubber-banding (free speed for being behind). Catch-up goes through tricks.

---

## 1. Speed: make tricks the fast line

- **Lower top speed, boost goes past it.** Lower the stock top speed and let boost push past it.
  Riding plain caps lower; boosting is the only way above the cap. Covers "slow racers down but
  make it feel fast".
- **Landing boost.** A clean landing gives an instant speed kick that grows with the trick /
  combo size, so taking a ramp is faster than going around it.
- **Shortcuts through tricks (level design).** Place ramps and rails where they cut corners, so
  the trick is the racing line.

## 2. Catch-up through tricks

- **Slipstream / catch-up boost.** Riders behind the leader fill boost faster from tricks, more
  the further back they are. It never gives free speed: you have to trick to collect it.
- **Respawn with a banked boost segment** when crashing while behind the leader.

## 3. Stunt race scoring

- **Bonus ramps.** Some ramps glow and call out a specific trick ("BACKFLIP HERE 4x"). Landing it
  pays a multiplier. The trick rotates over the race, and the ramp shows on the compass strip.
  Inspired by the CS2 deathmatch bonus weapon.
- **Score gates.** A checkpoint only counts cleanly if you pass through it mid-combo (or above a
  multiplier threshold); otherwise there's a time penalty.

## 4. Make the reward visible

- **Live $ per banked combo** ("+$40") in the bank pop. Check against the pacing targets in
  [Economy](./Economy.md).
- **End-of-race breakdown:** finish time, trick bonus time, $ from tricks.
- **Rival callouts in the trick feed:** "Squid passed you on score."

## 5. Reminders

- **Floating text over trick spots, events only.** Generated from existing ramp / rail nodes (not
  authored). Shows within a range and fades on approach. Names the opportunity, not the input
  ("GAP", "RAIL", "BIG AIR"). Hidden in free roam.
- **Idle-boost tell (SSX Tricky style).** Presentation follows combo state:
  - *Idle* (no combo for a while): muted HUD and quieter music (MusicDuck bus).
  - *In combo*: normal.
  - *High multiplier / full boost*: saturated HUD, music filter opens, boost trail on.
  Riding plain should feel flatter than tricking. The music is the main hook.
- **Clutch-up reminder after respawn.** One line, shown only when boost is below one segment.
  Stops showing once the player has done clutch-ups on their own a few times. Depends on §7.

## 6. Combo multiplier decay

Stops riding plain, and spamming one easy trick, from paying well.

- **Straight riding:** gaps between combos lower the next combo's starting multiplier.
- **Repeated tricks:** each trick has a freshness value. Repeating it within a combo (or within
  the last few tricks) pays less each time; a different trick restores it.
- **Holding one trick:** after a while, holding one easy trick (a long wheelie) still keeps the
  combo alive but stops raising the multiplier. Harder holds (balance point) can run longer
  before they stop paying.
- **Visible:** callouts show a stale repeat as stale (greyed out / reduced multiplier), so it
  doesn't feel like a hidden nerf.
- Lives in `ComboRules.accrue()` (rollback tick); any new state is a RollbackSynchronizer state
  property. See [ComboAndBoost](./ComboAndBoost.md).

## 7. Mini clutch-up

The clutch-pop gate in `MovementController._can_initiate_wheelie()` is capped by speed
(`CLUTCH_POP_MAX_SPEED_FRAC`) and by the wheel force a power wheelie needs
(`POWER_WHEELIE_MIN_FORCE`). In its upper gears the mini never reaches that force, and above the
speed cap a clutch-up is blocked outright.

- Let a clutch-up loft the mini across its whole speed range. A clutch dump is already a torque
  spike, so it shouldn't need the force a power wheelie does.
- Power wheelies and the other bikes' feel stay as they are.
- Update the comments that say the mini is meant to stay planted.
- Open: how high a clutch-up pops at speed versus at low speed.

## 8. Traffic

- **Glancing traffic hits wobble, not crash.** Today any traffic touch crashes the player
  (`NPCTrafficState`, "any touch crashes them"); the glancing-angle wobble only covers walls and
  riders (`CrashController`). Route glancing traffic hits through the same wobble + reflect +
  speed-loss path. Head-on / high-speed hits still crash.
  - A glance **ends the combo but banks its score**, like a clean combo end. Only a real crash
    voids the combo.
- **Honks.** Traffic honks when a player is close and closing fast. Doubles as a warning cue.
  Reuses the positional horn audio.
- **Yield earlier.** Traffic slows for riders ahead too late. Likely cause: the detection range
  (`follow_detect_range`) is a fixed distance, while players close in much faster than traffic.
  Candidate: a time-based lookahead scaled by closing speed, like the race bots'
  `avoid_lookahead_time`. Needs verifying.

## 9. Explaining the rules: Tips tab

Players can't trade straight-line speed for tricks if they don't know the rules. Add a **Tips**
tab to the tricks menu (`TricksMenuState`, opened from the main and pause menus). It's one more
`_add_tab()` next to the existing per-state and how-to tabs.

- One short rule per row: a title plus one line, no walls of text. Localized as `TIP_*` keys (no
  em dashes in `localization.csv`).
- Grouped by system. Each tip ships with its system, so the tab never describes a rule that
  doesn't exist yet.
- The same strings can feed the in-game reminders (§5) and loading-screen tips, so the rules are
  written once.

Draft rules (✓ = system exists today):

| Group   | Rule                                                                                          | Source        |
| ------- | --------------------------------------------------------------------------------------------- | ------------- |
| Combo   | ✓ Hold any trick to start a combo. Keep chaining to raise the multiplier.                     | ComboAndBoost |
| Combo   | ✓ Drop a trick and you have a moment to start the next one before the combo ends.             | grace window  |
| Combo   | ✓ Crashing loses the combo you're in. Boost from earlier combos is safe.                      | crash void    |
| Combo   | Repeating the same trick pays less. Mix it up.                                                | §6            |
| Combo   | Holding one easy trick keeps the combo alive but stops raising the multiplier.                | §6            |
| Boost   | ✓ Tricks fill boost. Tap to burn a segment, double-tap to burn it all.                        | ComboAndBoost |
| Boost   | Boost is the only way past your bike's top speed.                                             | §1            |
| Boost   | Land clean for a speed kick.                                                                  | §1            |
| Boost   | Behind the leader? Tricks fill boost faster.                                                  | §2            |
| Boost   | Clutch-up (hold clutch, rev, release) to pop a wheelie at any speed.                          | §7            |
| Traffic | ✓ Pass close to traffic for near-miss points.                                                 | near misses   |
| Traffic | Clipping traffic at an angle ends your combo but keeps its score. Hitting it head-on crashes. | §8            |
| Events  | Glowing ramps ask for a trick. Land it for a big multiplier.                                  | §3            |
| Events  | Hit checkpoints mid-combo or lose time.                                                       | §3            |
| Events  | Score cuts time off your finish.                                                              | §3            |

Open: the tab's name ("Tips", "Rules", "How to Score").

---

## Suggested order

1. Mini clutch-up (§7). Small, and §5's reminder depends on it.
2. Traffic glance wobble + earlier yield (§8). Fixes the unfun crashes during challenges.
3. Boost past the top-speed cap (§1). Root fix for the incentive.
4. Catch-up boost (§2).
5. Combo decay (§6) + idle-boost tell (§5).
6. Stunt race scoring (§3), reward visibility (§4), floating text (§5).

## Playtest check

A mini rider who tricks well should finish level with a sport bike rider who only races. If the
sport bike wins easily, tricks still aren't paying enough.
