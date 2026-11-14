# Economy

> **Status 2026-11-13:** [Payouts](#payouts) and the [economy pass](#economy-pass) are built
> and played; pacing is checked by the [tests](#tests). Unlocks, challenges and what money buys are in [Progression](./Progression.md).

- [Today](#today)
- [Payouts](#payouts)
- [Economy pass](#economy-pass)
- [Pacing](#pacing)
- [Later](#later)


## Today

- **Where it comes from:** only event [payouts](#payouts) and time attack laps. Free roam,
  challenges and dailies pay nothing yet. No event overrides the `payout_money` / `payout_xp`
  defaults on `GameModeEventDefinition`, so every event pays the same base.
- **Rider level** is derived from total XP (`PlayerDefinition.level()`, `XP_PER_LEVEL`):
  `1 + sqrt(xp / 100)`, so level *n* → *n+1* costs `100 × (2n − 1)` XP. Reaching a level pays
  nothing and plays nothing; it only lifts bike `unlock_level` gates and shows on the riding HUD.
- **Money** starts at $5,000 (`default_player_definition.tres`) and is spent in the garage, on
  priced free roam activities and on fuel-ups.
- **Off target:** flat payouts ($100 / 50 XP for a win, the score adding ~$5) put the sport bike
  ~70 wins away.

| Bike | Price | Rider level |
|---|---|---|
| Scooter (mini) | $4,200 | — |
| Naked | $7,000 | 2 |
| Cruiser (naked) | $9,000 | 2 |
| Sport | $12,000 | 5 |


## Payouts

Built.

- **Formula:** `event base × place multiplier + score × rate`, computed separately for money and
  XP. Place multipliers fall off from 1st, with a floor for everyone below the podium. Score
  only applies in score modes (stunt race, trick battle, long jump, crash launch); pure races and stunt
  challenges pay on placement alone. In score modes a rider who scored 0 gets the floor whatever
  their row, so idling never pays 1st.
- **Tunables:** the base money and XP are per event, on `GameModeEventDefinition`. Place
  multipliers, score rates and the time attack lap fraction are shared constants
  (`UtilsConstants.PAYOUT_*`).
- **Placement** is the rider's row on the results screen they see, NPCs included, so beating
  bots counts.
- **Where:** the server computes it in `RunnerGameMode._pay_out()`, called from
  `_show_results()`, which every results-showing mode goes through. It pays each rider through `RunnerGameMode.earn()`, which RPCs them; their
  client writes its own save via `rpc_earn`, which also pops `+$N` and `+N XP` off the riding
  HUD. The results screen shows the earned money and XP columns. Modes add score through the
  `_payout_score` override (`TimedScoreGameMode` for trick battle and long jump, stunt races,
  crash launch).
- **Time attack** never reaches the results screen: every lap pays a fraction of the base, and a
  lap that beats the rider's saved PB pays the full base on top. Laps pay through
  `RunnerGameMode.earn`, so the point-to-point run screen shows the event's earnings so far.
- **Doesn't pay:** free roam, fuel-up, and events the host cancels without results. Late joiners
  who never raced aren't in the results, so they get nothing. (Challenges finished in free roam
  still pay their own reward.)


## Economy pass

Built and played 2026-11-13. [Today](#today) describes the game before it.

- **Raise payouts, don't cut prices.** Bikes stay well above cosmetics. Starting money and
  prices don't change.
- **No difficulty tiers.** Every event shares the default base (except crash launch, below);
  payouts ramp with rider **level** instead:
  `(event base × place mult + score × rate) × level mult`.
- **Level mult:** `1 + 0.5 × (level − 1)`, linear, no cap. It nearly cancels each level costing
  more XP than the last, so each level settles at ~6 wins instead of slowing to a crawl.
- **Applied once, on the server, in `RunnerGameMode.earn()`,** so results payouts and time
  attack laps both get it and the results columns show what was actually paid.
- **Server's view of the level:** `lobby_manager.lobby_players[peer_id].level()`. `xp` is in the
  synced `PlayerDefinition`, but `SaveManager.earn()` deliberately doesn't re-push metadata
  mid-race, so the server's copy goes stale. `earn()` also adds the XP to the server's
  `lobby_players[peer_id]` so the next payout uses the new level. The next real metadata push
  overwrites it with the save's value.
- **Mode balance:** all modes pay about the same; stunt race pays the most, through score
  (more tricks = more money); crash launch pays the least. Crash launch's score runs ~10× the
  others, so its `_payout_score` scales it down rather than adding a per-mode rate.
- **Balanced per minute, not per event.** Crash launch runs ~37 s against ~70 s for the others,
  so at the shared base it paid ~2× per minute. Its event definition in `stunt_city.tscn`
  overrides the base to $110 / 28 XP.
- **Tutorial** keeps its existing one-off payout.

**Numbers:**

| Tunable | Now | Pass |
|---|---|---|
| `payout_money` default | $100 | $200 |
| `payout_xp` default | 50 | 50 |
| `PAYOUT_SCORE_MONEY_RATE` | 0.01 | 0.08 |
| `PAYOUT_SCORE_XP_RATE` | 0.02 | 0.02 |
| Level mult step (new constant) | — | 0.5 |
| Crash launch `_payout_score` | `_score` | `_score × PAYOUT_SCORE_SCALE` (0.05) |
| Crash launch event base (`stunt_city.tscn`) | $100 / 50 XP | $110 / 28 XP |

**A level 1 win** (scores read off real results screens):

| Mode | Score | Now | Pass |
|---|---|---|---|
| Stunt race, trick heavy | ~1,500 | — | ~$320 / 80 XP |
| Stunt race | 770 | $107 / 65 XP | $262 / 65 XP |
| Trick battle | 425 | $104 / 58 XP | $234 / 58 XP |
| Crash launch | 4,517 | $145 / 140 XP | $128 / 32 XP |

Multiply by the level mult: ×1.5 at level 2, ×3 at level 5.


## Pacing

Targets to tune toward. Prices, levels and payout bases are set on the definitions.

- A new save owns the mini bike, at rider level 1, with starting money that buys neither of the
  other bikes.
- The naked bike is a short save-up plus a low rider level.
- A player grinding toward the sport bike gets it in about **30 minutes** of events.
- A 100%er (every bike, variant, mod and challenge) takes about **an hour**; challenges and mods
  add to the run beyond events.
- Payouts ramp with rider level, not with event difficulty.
- Three dailies are worth about ten races of XP.
- Cosmetics are cheap next to bikes, so buying one doesn't wreck the bike savings.

**The pass against the targets**, for the "regular" profile in `test_economy_pacing.gd` (rerun
it for current numbers):

- Naked at ~8 min; level 6 after 30 min.
- Sport: ~32 min if naked was bought first (on target); ~20 min if the rider saves straight for
  it (faster than target; raising sport's `unlock_level` from 5 to 6 is the likely fix).
- The 100%er hour can't be sized until challenges, variants and mods pay and cost something.


## Tests

GUT (`addons/gut`, excluded from exports), in `tests/unit/`:

```
<godot> --headless --path . -s addons/gut/gut_cmdln.gd
```

- `test_payouts.gd`: the formula's shape (`RunnerGameMode.place_payout` / `level_payout`).
- `test_economy_pacing.gd`: beginner / regular / pro **profiles** (what they ride in each mode,
  where they place) play the demo's events through the real payout, `ComboRules` and level code,
  then shop for bikes from a new save. It prints a table of payouts per mode and per minute and
  minutes until each bike, and asserts the [Pacing](#pacing) targets. "regular" is calibrated to
  real results screens. Scoring tunables are read from `main_game.tscn`, event payouts from
  `stunt_city.tscn`, prices and starting money from the `.tres` files. To rebalance: change the
  numbers, rerun, read the table.
- **Event timing:** `RunnerGameMode` logs `[economy]` lines (start, results, earn, restart, end,
  with seconds from `DebugUtils.TimerStart` / `TimerSecs`) to `user://godot*.log`. The sim's
  per-mode minutes come from them; replay events and update `MODES` when events change length.


## Later

- Challenges and dailies as a second income ([Progression](./Progression.md#challenges)).
- A level-up moment: a HUD callout when a level is crossed, naming anything it just unlocked.
  Not designed yet.
