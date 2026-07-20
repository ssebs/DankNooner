# Combo & Boost

> Tricks build a combo, the combo fills a boost meter, boost is spent for speed.

## Player-facing loop

1. Hold any trick (wheelie, stoppie, drift, air tricks) — the combo timer runs and the boost meter fills.
2. Unbroken trick time raises the **combo multiplier**, which fills boost faster.
3. Drop every trick and a **grace window** starts — re-enter a trick in time and the combo survives, so wheelie → stoppie → wheelie chains keep their multiplier.
4. **Tap the boost button** to spend. It is a *tap, not a hold*: the press commits a burn that releasing cannot cancel.
   - One or more full segments banked → burns a single segment.
   - Meter completely full → the whole meter burns as one longer boost.
   - Under one full segment → press is rejected, gauge blinks.
5. **Crashing voids the run** — that combo's score is discarded, not partially credited, and the boost it earned is taken back. Boost banked by *earlier completed* combos survives (see `combo_boost_earned` below).
6. While boosting, the **automatic transmission is forced on** regardless of the `auto_transmission` setting — a boost spent bouncing off the rev limiter in the wrong gear is a wasted boost.

## Where the logic lives (and why it's split)

The split is **not** stylistic — it's forced by netfox.

| Concern | Location | Runs on |
| --- | --- | --- |
| Combo timer, multiplier, boost fill | `TrickController._accrue_combo()` | Rollback tick, every peer |
| Boost spend / drain | `MovementController._boost_calc()` | Rollback tick, every peer |
| Score banking | `TrickManager._track_combo()` | Server `_process()` |
| Gauge + counter UI | `HUDController._process()` → `BoostGauge` / `ComboCounter` | Local client |
| Camera FX | `CameraController._update_juice_fx()` | Local client |

### The rule that bit us

`combo_time`, `combo_grace`, `combo_boost_earned`, `combo_multiplier`, `boost_amount`, `boost_burn_target`, `boost_burn_rate`, `boost_prev_held` and `is_boosting` are all **netfox state properties** on `PlayerEntity`.

`RollbackSynchronizer._before_tick()` calls `apply_state(tick)`, which re-applies *every* state property from recorded history on *every* network tick. **A manager writing these from `_process()` is overwritten before anything can accumulate.** The first version of this system did exactly that and the boost meter silently never filled.

So: anything that mutates those vars must run inside `_rollback_tick()`. `TrickManager` therefore only *observes* them and banks a score on the combo-end edge — which also means resimulation can't double-count the score.

Related: the rollback tick bails early on `is_crashed`, so a crash freezes combo state rather than clearing it; it's the respawn's `do_reset()` that actually zeroes it. `TrickManager` checks `is_crashed` **before** its `combo_time` test for this reason — in the other order a crashed run would bank on the way down like a clean finish.

### `combo_boost_earned` — why a crash doesn't wipe the whole meter

A crash should cost you the combo you were in the middle of, not boost you already banked and were saving. `combo_boost_earned` tracks how much of the current meter the *in-progress* combo contributed, and is maintained in three places:

- **Earning** (`TrickController._accrue_combo()`) — incremented by the actual post-cap delta, so topping out a full meter doesn't inflate the claim.
- **Clean combo end** (grace window expires) — reset to zero. That boost is permanent now.
- **Spending** (`MovementController._boost_calc()`) — drawn down alongside `boost_amount`. Without this, spending would leave a claim larger than the meter, and the next crash would eat previously banked boost too.

`PlayerEntity._apply_respawn_state()` then subtracts `combo_boost_earned` from `boost_amount` (clamped at zero). It must run **before** the `do_reset()` loop in that same function, which clears the combo state it depends on.

## Tunables

> Values live in the source — this lists what each knob *does*, not what it's currently set to.

### Earning — `player/controllers/trick_controller.gd`

Consts, deliberately **not** `@export`: this code runs inside the rollback tick on every peer and must be byte-identical, or client prediction diverges from the server.

| Const | Effect |
| --- | --- |
| `BOOST_PER_SEC` | Boost segments earned per second of trick, before the multiplier. **The main "how fast does this feel" knob.** |
| `COMBO_GRACE_SECS` | How long you can be trickless before the combo breaks. Higher = more forgiving chaining. |
| `COMBO_MULT_THRESHOLDS` | Seconds of unbroken trick time per multiplier step, ascending. Add entries for higher tiers. |

**Keep `COMBO_MULT_THRESHOLDS` in the same ballpark as the meter fill time implied by `BOOST_PER_SEC`.** The gauge is the only feedback the player can see, so a multiplier that steps far behind it reads as broken. Changing one without re-checking the other has already caused a false bug report once.

Any trick counts toward the combo — there is no per-trick rate table. If you want a stoppie worth more than a wheelie, that's a change to `_accrue_combo()`, not a constant.

### Spending — `player/controllers/movement_controller.gd`

Same rollback-determinism reason for being consts.

| Const | Effect |
| --- | --- |
| `BOOST_SEGMENTS` | Meter capacity in segments. Changing this needs a matching cell count in `boost_gauge.tscn`. |
| `BOOST_SEGMENT_SECS` | Duration of a single-segment burn. |
| `BOOST_FULL_BURN_SECS` | Duration when a full meter is committed in one press — the reward for banking the whole thing. |
| `BOOST_ACCEL_MULT` | Engine drive multiplier while boosting. |
| `BOOST_SPEED_MULT` | Raises both the gear cap and the `bd.max_speed` ceiling while boosting. |

### Scoring — `managers/trick_manager.gd`

`@export`, safe to tweak in the inspector (server-only, outside rollback).

| Export | Effect |
| --- | --- |
| `points_per_second` | Base points per second of combo time. Final score = `duration × points_per_second × peak_multiplier`. |

Signals for gamemodes:

- `combo_banked(peer_id, points, duration, multiplier)` — combo ended cleanly, score added.
- `combo_voided(peer_id, lost_duration, lost_points)` — crash discarded the run.

API: `get_score(peer_id)`, `reset_peer(peer_id)`. Call `reset_peer()` when a run starts.

### Camera FX — `player/controllers/camera_controller.gd`

`@export`, per-player, safe to tweak.

| Export | Effect |
| --- | --- |
| `boost_fov_add` | Extra FOV degrees while boosting, on top of the speed-driven widen. |
| `boost_blend_speed` | How fast the tint / FOV punch ramps in and out. |

Shader uniforms in `resources/shaders/radial_blur.gdshader` (shared with the speed blur):

| Uniform | Effect |
| --- | --- |
| `boost_color` | The wash color. |
| `boost_tint_amount` | How strongly the tint pushes at full boost + screen edge. |
| `boost_clear_radius` | How far inward the tint reaches. Lower = more full-screen. Reaches further in than the blur's `clear_radius` on purpose. |

> Hook for flame VFX later: `PlayerEntity.is_boosting` is synced, so remote players' flames work off the same bool.

### UI — `player/hud_elements/`

Both live bottom-left in a `BoostCluster` VBox (counter above gauge). Consts in their scripts.

**`boost_gauge.gd`** — three readable states, because a press under one segment is silently rejected and that needs to be obvious *before* the player tries:

| State | Look | Consts |
| --- | --- | --- |
| Under 1 segment | Muted, no pulse | `COLOR_DIM` |
| 1+ segments (ready) | Bright, slow glow | `COLOR_READY`, `READY_PULSE_HZ`, `READY_GLOW_AMOUNT` |
| All full | Faster / stronger shimmer | `FULL_PULSE_HZ`, `FULL_GLOW_AMOUNT` |
| Spending | Extra brighten | `SPENDING_BRIGHTEN` |
| Rejected press | Strobe | `COLOR_REJECT`, `BLINK_SECS`, `BLINK_PERIOD` |

Cell tint **snaps** during a blink instead of easing — at a short blink period the normal smoothing averages the on/off frames into a muddy constant.

**`combo_counter.gd`** — escalates with the tier (`tier = multiplier - 1`):

| Const | Effect |
| --- | --- |
| `TIER_COLORS` | Tint per tier; last entry reused past the end. |
| `SCALE_PER_TIER` | Base size added per tier, so higher tiers read bigger. |
| `PUNCH_SCALE` / `PUNCH_DECAY` | Size spike on step-up and how fast it settles. |
| `PUNCH_TRAUMA` / `TRAUMA_PER_TIER` / `TRAUMA_DECAY` | Shake spike on step-up, the constant floor held per tier, decay rate. |
| `SHAKE_MAX_PX` | Shake displacement at full trauma. |
| `THROB_HZ` / `THROB_PER_TIER` | Idle throb so a high combo never sits still. |
| `FADE_SPEED` | Fade in/out rate. |

Visibility keys off `combo_time > 0`, **not** the multiplier — an earlier version gated on `multiplier > 1` and so showed nothing until the first multiplier step, which read as broken.

## Input

`boost` action in `project.godot` (keyboard + gamepad). Gathered as `nfx_boost_held` in `InputController._gather()`, synced as a netfox input property.

The rising edge is detected off the **synced** `boost_prev_held` in `_boost_calc()` so it survives resimulation. `HUDController` keeps its own separate `_prev_boost_held` for the rejection blink — deliberately not reusing the synced var, since the HUD must not perturb rollback state for a cosmetic effect.

`InputController._process()` forces `_auto_shift()` while `is_boosting`, independent of the `auto_transmission` setting — see [PlayerController.md](./PlayerController.md) for why auto-shift lives in `InputController` rather than `GearingController`.

## Related

- [PlayerController.md](./PlayerController.md) — controller order, netcode, synced state list
- [Architecture.md](./Architecture.md) — TrickManager in the manager taxonomy
