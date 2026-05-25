# PLAN — `animation_controller.gd` Trick Refactor (Sprint Phase 2)

Narrow refactor. Goal: adding a new trick animation is **one edit**, not five.

## Problem

Today, adding a new trick (e.g. `HEEL_CLICKER`, `HIGH_CHAIR`, `TWO_LEFT_FEET`) requires editing `player/controllers/animation_controller.gd` in 5+ places:

1. Declare `_<trick>_anim: Animation` + `_<trick>_layer: CustomAnimPlayer.Layer` (lines ~114-118)
2. In `initialize()`: `if ik_anim_player.has_animation("<name>"): _<trick>_anim = ...; _fixup_anim_paths(...)` (lines ~498-512)
3. In `_on_trick_started()`: enum branch with play logic — `play_one_shot` vs `play(loop)`, hold_at_end, etc. (lines ~531-553)
4. In `_on_trick_ended()`: optional reverse-out logic (lines ~556-563)
5. In `start_ragdoll()`: clear the layer reference (lines ~626-631)
6. In `do_reset()`: clear the layer reference (lines ~652-656)

Every new trick = 5 diffs in one file, plus the easy-to-forget cleanup spots in 5/6.

## Goal

Adding a new trick = **one** entry in a data table. The table drives init, started/ended dispatch, and cleanup.

## Out of scope

- Reverse-anim system (`_update_reverse_anim`) — leave alone, it's not a "trick"
- Idle animation (`_idle_anim`) — leave alone, it's state-driven not trick-driven
- `_fixup_anim_paths` mechanics — keep as-is, just call it from the new loop
- Pose pipeline, IK, ragdoll, procedural code — untouched
- `TrickController` itself (no enum or detection changes)
- Adding any *new* tricks — that's Phase 3+. This refactor is structural only.

## Design

### TrickAnimEntry

A simple data class (inner class or `.gd` resource — TBD during impl, inner class is fine):

```gdscript
class _TrickAnimEntry:
    var trick: TrickController.Trick
    var anim_name: String          # key in ik_anim_player's library
    var play_mode: PlayMode        # ONE_SHOT, LOOP, HOLD_WHILE_LATCHED
    var reverse_on_end: bool       # if true, reverse-play to t=0 on trick_ended
    # populated at init:
    var anim: Animation = null
    var layer: CustomAnimPlayer.Layer = null
```

`PlayMode` enum captures the three current behaviors:
- `ONE_SHOT` (heel_clicker) — `play(anim, 1.0, false)`, no end handling
- `LOOP_WHILE_LATCHED` (two_left_feet) — `play(anim, 1.0, false)` on start, nothing on end (auto-fades)
- `HOLD_WHILE_LATCHED` (high_chair) — `play_one_shot`, on re-entry flip speed back to +1, on end reverse to 0

If high_chair's behavior turns out to be one-of-a-kind, it can stay as a special `reverse_on_end: true` flag and the dispatcher branches once. Don't over-engineer.

### Registry

```gdscript
var _trick_entries: Array[_TrickAnimEntry] = [
    _make_entry(TrickController.Trick.HEEL_CLICKER,   "heel_clicker",   ONE_SHOT,           false),
    _make_entry(TrickController.Trick.HIGH_CHAIR,     "high_chair",     HOLD_WHILE_LATCHED, true),
    _make_entry(TrickController.Trick.TWO_LEFT_FEET,  "two_left_feet",  LOOP_WHILE_LATCHED, false),
]
var _trick_by_enum: Dictionary  # Trick → _TrickAnimEntry, built in initialize()
```

Lookup by enum is O(1) and replaces the if/elif chains.

### Touched functions

- **`initialize()`**: loop over `_trick_entries`, resolve `anim_name` against `ik_anim_player`, call `_fixup_anim_paths`, populate `_trick_by_enum`. The current per-trick `if has_animation(...)` blocks collapse to one loop.
- **`_on_trick_started(trick)`**: lookup `_trick_by_enum[trick]`, dispatch on `play_mode`. Three small branches instead of three full if/elif blocks.
- **`_on_trick_ended(trick)`**: lookup; if `reverse_on_end`, do the reverse-and-fade pattern.
- **`start_ragdoll()`**: loop `_trick_entries` and clear `entry.layer`. Idle/back_up layers stay handled inline (they're not in the registry).
- **`do_reset()`**: same loop as `start_ragdoll`.

### What stays the same

- `CustomAnimPlayer` API is untouched.
- Animation authoring workflow (drop `.anim` into `ik_anim_player`, name it) is unchanged.
- `_POSE_PIPELINE_PATHS` allowlist unchanged.
- `_RiderPose`, pose pipeline, IK targeting, magnets — all unchanged.

## After the refactor — adding a new trick

1. Add the enum value to `TrickController.Trick`
2. Author the animation in `ik_anim_player` with a name (e.g. `superman`)
3. Add one line to `_trick_entries`:
   `_make_entry(Trick.SUPERMAN, "superman", ONE_SHOT, false),`

That's it. No layer var, no init branch, no ragdoll cleanup, no reset cleanup.

## Verification

- All three existing tricks (`heel_clicker`, `high_chair`, `two_left_feet`) behave **identically** to pre-refactor:
  - heel_clicker plays through once, auto-fades.
  - high_chair settles in, holds while button held, unwinds on release, handles re-entry mid-unwind.
  - two_left_feet plays once on activation.
- Crashing mid-trick still cleanly resets the rider (no baked-in pose drift on respawn).
- No regressions in idle/reverse animations (those weren't touched).
- Manual test: ride, do each trick, crash mid-trick, respawn, verify rider returns to default pose.

## Risks

- `high_chair` re-entry logic is subtle (lines ~543-548) — port it carefully. Add a comment explaining the case.
- `heel_clicker` uses `play(...)` not `play_one_shot(...)` despite being one-shot in behavior (line ~537). Confirm this is intentional before "fixing" it — likely the difference is whether the layer is held or auto-cleared.
- The two play primitives (`play` vs `play_one_shot`) differ in cleanup behavior. The registry's `play_mode` enum needs to capture which is used; double-check by reading `CustomAnimPlayer` if uncertain.

## Sequencing

1. Build the `_TrickAnimEntry` class + `PlayMode` enum.
2. Build registry and `_trick_by_enum` lookup, populated in `initialize()`.
3. Migrate one trick at a time (heel_clicker → high_chair → two_left_feet), verifying each against pre-refactor behavior before moving on.
4. Once all three pass, delete the old per-trick vars and branches.
