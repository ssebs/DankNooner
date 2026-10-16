# Testing
---


> **Status: steps 1–4 written, not yet green; being verified run by run.** Solo runs now get
> through both fuel-up pumps. Every step still has to be seen working (solo, then two peers, then
> late join) before this is done; see [Next session](#next-session). Automated regression run before every Steam upload. Follows the
> [Architecture](./Architecture.md#how-to-write-in-this-doc) rule: rosters live in code, this doc
> holds the shape and the reasons.

## Goal

One command, run locally before a Steam upload, that answers "did anything regress?" in a
**2–3 minute budget**. No manual input: a bot plays the game through its real code paths while
the peer windows tile side by side so a human can watch. Not run on CI.

Out of scope: unit tests (features churn too much to pay for them), CI, perf budgets.

## Constraints

- **Near-zero changes to existing game code.** The runner drives the real UI and reads state
  through existing groups, unique names and public APIs. Any new getter a solver needs is a
  deliberate, flagged change.
- **The gym level ships; the orchestration doesn't.** Everything test-only lives in `tests/`,
  which is added to every preset's `exclude_filter` in `export_presets.cfg`.
- **Tests come from authored content, not hand-written scenarios.** What the bot does is derived
  from the gamemode task trees in the gym level, so new events are covered for free.

## Pieces

### Wrapper scene (`tests/test_main.tscn`)

Launched as `godot --path . res://tests/test_main.tscn -- <test args>`. The scene path overrides
the main scene, so `main_game.tscn` is untouched. It instances `main_game` plus a `TestRunner`.

Before `main_game` enters the tree, the wrapper points `SaveManager.save_slot` and
`SettingsManager.settings_path` at per-peer test files (both load in `deferred_init`, so that's
early enough), and resets them every run. Why: peers on one machine would otherwise share (and the
garage step would mutate) the real save, and a per-peer settings file is how each window is forced
windowed. The project boots maximized, which ignores `--position` / `--resolution`; Godot keeps
that rect as the windowed one, so `MainGame._apply_window_mode` switching to the file's
`windowed` is what lands each window on its tile.

Nothing in the game uses `current_scene` or `/root/` paths, so nesting `main_game` is safe.

### Orchestrator (`tests/run.py`)

Python (stdlib only). Launches the peer processes, tiles their windows (`--position` /
`--resolution`), enforces the overall timeout, collects per-peer logs and screenshots into
`tests/out/`, and prints the summary table. Always headed: fuel-up needs a real cursor. Audio runs
on Godot's dummy driver: the audio code still executes, nothing plays.

`--peers 1` runs the host alone; `--late-join` adds the late joiner (off by default, so the late
join and rejoin steps are skipped). Windows are always sized as if three peers were running, so a
solo window stays small.

The host launches first; clients launch once the director drops a ready marker in `tests/out/`,
since they join through the menu and need a listening host; a host that never listens is killed
rather than left to the overall timeout. The late joiner launches when the director drops a second
marker (start of free roam). Each peer gets its own `--log-file`
(they would otherwise share `user://` logs) and writes a result JSON (errors, violations) on quit;
the summary is built from those plus exit codes, so a hung or crashed peer shows as `timeout` /
`NO RESULT`. The result also carries warnings (untested coverage), printed without failing.
`tests/out/` carries a `.gdignore` so the editor never imports it.

**Compile check:** the headless editor load misses parse errors in `tests/` (nothing references
those scripts). Boot the wrapper headless with `--quit-after` for a few frames instead, and grep
for `SCRIPT ERROR`.

**Error capture:** a `Logger` registered with `OS.add_logger` when the wrapper loads. `push_error`,
script and shader errors and `printerr` (so `DebugUtils.DebugErrMsg`) all fail the run; warnings
don't. Errors from before the wrapper loads (autoload init) only reach the log.

Files: `test_runner.gd` (timeline, RPCs), `menu_flows.gd` (every UI path), `task_solvers.gd`,
`drive_bot.gd` + `trick_recipes.gd`, `invariants.gd`, `coverage.gd`, `activity_players.gd`.
No `class_name` in `tests/` (keeps them out of the shipped class cache); the helpers take the
runner untyped, since a cyclic `preload` won't resolve.

Input is **not** injected from Python (pyautogui, Playwright etc.). OS-level input only reaches
the focused window, so it can't drive tiled peers at once, and the bot needs in-game state
(waypoints, current task) to steer anyway. Playwright would mean testing the web export, which
isn't the Steam build. Inputs go through `Input.parse_input_event` in-game instead: the same path
as a real key press, with no dependence on window focus.

### Director and drivers

Each process runs a `TestRunner`; the host's acts as **director**, the rest as **drivers**.

- **Director (host only):** reads each peer's current task
  (`SequentialTaskRunner.get_current_task`), picks a solver, issues teleports/respawns, and
  judges the invariants.
- **Drivers (every peer, host included):** press inputs for their own rider on the director's
  orders.

Why the split: netfox only accepts input from the rider's authority peer, and host-side
`SpawnManager` effects are the only teleports that stick (see `DebugTeleporter`'s header). The
director talks to drivers over RPCs on the `TestRunner` node, which sits at the same path on every
peer.

Invariant sampling runs for the whole session: the director orders a snapshot, every peer reports
its own, and the director judges the set one interval later (a missing report is itself a
violation). Agreement isn't judged for a moment after a join, leave or gamemode change. A peer
that late-joins a running non-late-joinable event is **benched**: expected in free roam until the
event ends. At the end the director tells the drivers to quit and quits last, so no driver is
dropped into the server-disconnected flow.

**Orders:** a control loop on the director turns each rider's current task into an order
(`idle` / `hold` throttle / `go` toward a target, with an optional trick and gear tap) and sends
it when it changes; the host's own bot gets it directly. The active runner and current task are
read through public state only (`player_states`, `get_current_task`), no new getters.

**Mouse token:** fuel-up warps the one OS cursor, so peers queue for it on the director and play
pumps one at a time, including the simultaneous pre-race fuel-up. While the token is out the
director keeps a marker in `tests/out/`; `run.py` beeps and shows a red "hands off" banner under
the tiled windows, and a green one when the mouse is free. A fresh grant waits a moment after the
banner goes up. Moving the mouse or alt-tabbing during a pump breaks it.

**Pump play:** the cursor carries the grip, not the nozzle, and the handle swings as it nears the
cap, so the bot steers by the tip's on-screen error to the cap. It waits for the gas cap to stop
moving before grabbing: the pump measures the cap at the grab, and the bike is still easing out of
its lean when the session starts (grabbing that early made hang-up impossible; possibly a real game
bug, unconfirmed).

**Pickers:** both activities and events check the open picker's title before submitting, since a
neighbouring circle's picker can still be up when an order lands.

### Drive bot

Drives, not teleports, so handling and stuck-on-geometry regressions are caught.

- **Waypoints:** a race's next checkpoint from `RaceTask.get_target_checkpoint` (the call NPC
  racers use, so a missed checkpoint is re-targeted); otherwise the current task's `trigger`
  position. Getting to event circles and activities is a host-side teleport onto the circle.
- **Steering:** steer toward the waypoint, throttle, brake on sharp heading error. Input goes
  through `Input.parse_input_event` / `Input.action_press`, which `InputController._gather()` picks up and
  netfox records like a human's input.
- **Solvers** are keyed by task class (`task_solvers.gd`). **A task class with no solver fails
  loudly**, so adding a new task type forces adding one. A concurrent runner solves its first child
  with somewhere to go, plus any constraint's trick.
- **Trick recipes** are closed-loop on the local rider. Stick tricks are derived from
  `TrickController.BINDINGS` (easiest state first), so a new binding needs no recipe; physics
  tricks (wheelie, stoppie, drift, burnout, bunny hop, flips) are hand-written. Air tricks aim at
  the task's `success_zone` / `trigger` ramp, and a rider who overshoots is respawned for another
  run-up. `WHEELIE_MOD` and `THREESIXTY` have no detection path in `TrickController`, so nothing
  can perform them; a task requiring one fails loudly.
- **Endless modes** (time attack, long jump, trick battle) are cancelled through the pause menu
  after a solve window. Results are skipped through their own button.
- **No progress toward the waypoint for too long** = failure: screenshot, respawn, continue.

### Invariants

Checked on every peer for the whole run, independent of the step:

| Invariant                                                                            | Catches                               |
| ------------------------------------------------------------------------------------ | ------------------------------------- |
| No error / crash logged                                                              | null refs, broken RPCs, missing nodes |
| `movement_locked` and stationary during a countdown                                  | moving before the race starts         |
| Unlocked and moving after the countdown while throttle is held                       | riders stuck at the start             |
| Not crashed, not locked, no movement while throttle is held                          | stuck riders mid-event                |
| Riding → `HUDManager.state_machine` is in the expected HUD state with its UI visible | missing HUD                           |
| Every peer agrees on the player count and current gamemode                           | desyncs, missing spawns               |

Steps only put the game into a situation; the invariants judge it. That is what keeps per-mode
test code near zero.

Sampling starts once each peer is in free roam with the riding HUD entered: that HUD enters on the
local player's first respawn, a few ticks after spawn, not at spawn. "Expected HUD" is the riding
HUD (or the picker / results over it), plus the activity HUDs while that peer runs an activity;
skipped while a menu is open. The expected player count is the host's lobby.

### Gym level

`TEST_LEVEL_01`, reused rather than a new level (`GYM_LEVEL` in `test_runner.gd`; the host picks it
in the lobby's level dropdown). Compact, wide, flat courses, so a stuck bot means a regression,
not hard terrain. It holds:

- an `EventStartCircle` per gamemode (including each race `race_type` and a `fuel_up_first`
  event);
- every `FreeRoamActivity` (gas station, garage);
- pickup spawners on the drive paths.

**Coverage check:** at startup the director compares every `GameModeType.Kind` and every global
`GameModeTask` / `FreeRoamActivity` subclass against what's placed in the gym. Anything missing
fails the run, so the gym can't silently fall behind the game. Exceptions, listed in
`coverage.gd`: the tutorial (and its tutorial-only tasks) is left out, and a short optional list
(kinds and tasks the gym skips by choice) only warns "untested".

## Timeline

One continuous session, not a launch per case. Process launches are the expensive part of the
budget.

1. Host and client launch. The host hosts via the play menu (IP_PORT selected in
   `host_mode_opt`). The client types `127.0.0.1` into `code_entry`; `_auto_detect_connection_mode`
   switches it to IP_PORT, then it emits `join_btn.pressed`. The menu and lobby flow are tested on
   the way in.
2. **Free roam:** both drive to the gas station and play fuel-up (cursor placed via the camera's
   `unproject_position` + mouse warp, holding `use_item`), then the garage (a purchase lands in the
   test save slot). **Late joiner** joins mid-activity.
3. **Race:** lobby start, countdown, both drive the route. The late joiner leaves and rejoins
   mid-race. That covers mid-race late join and rejoin: per `is_late_joinable()`, races sync the
   joiner into the fallback mode, and they must be able to move, see a HUD, and not disturb the
   race.
4. Every remaining event in the gym, in sequence.
5. Quit and print the summary.

**On failure:** screenshot every peer, then force a return to free roam and continue; abort only
if that recovery fails. The summary lists every violation, not just the first.

## Running

`tests/run.py` before exporting for Steam. The exported build can also be boot-checked with no
test code inside it: run it with Godot's `--quit-after` and fail on any logged error.

Once built, Claude may run `tests/run.py` to verify changes (an exception to "only the human runs
the project").

**Abort:** Esc twice from any window, Alt+F4 on any peer, or Ctrl+C in the terminal stops every
peer. A peer that exits without a result also stops the run.

## Build order

1. Wrapper scene, orchestrator, error capture, host/join through the UI, invariants.
2. Drive bot and the task solver registry.
3. Gym level and coverage check.
4. Free-roam activities, then late join / rejoin.

## Next session

Testing in progress: the user is running it step by step, and nothing counts as done until each
step has been seen working. Order: `run.py --peers 1`, then `--peers 2`, then `--late-join`.

Verified so far (solo):

- Host through the menus into free roam; abort hotkeys; mouse banners.
- Free-roam and pre-race fuel-up pumps fill and hang up with no spill.

Fixed but not yet seen working:

- Activity and event pickers matched by title (the bot used to submit whatever picker was open,
  so it entered the garage instead of the pump and the race).
- Garage always leaves, even after a failure.
- Drive bot cruise speed cap (it overshot turns); the gym's race checkpoints are being spaced out.

Still open:

1. **Garage:** every bike skin is free, so there is nothing to buy and the step fails. The test save
   starts with a fixed balance (`TEST_MONEY`); a skin needs a price within it.
2. **Drive bot / trick recipes:** tuning once a solo run gets through the events.
3. **Two peers:** check the mouse token hands off cleanly between pumps, then remove the TEMP
   cursor diagnostics (`_diag`, DIAG lines) in `activity_players.gd`.
4. **Late join (real game bugs, reported, not fixed):** the late joiner logs `Node not found:
   …/PlayerSpawn/<id>/RollbackSynchronizer/Node` and "Invalid packet received"; a client logs
   `up_direction can't be equal to Vector3.ZERO` from a netfox snapshot apply at the join. Also
   seen: "Cancel Event isn't offered in FuelUpGameMode" during recovery, and `Unable to send packet
   on channel 0` on the host.
5. **Timeouts:** a stuck event waits out the event timeout before moving on; consider shortening
   it and the warmup-sized default wait for steps after boot.
6. Measure the budget once a full run passes.

## Open questions / verify before building

- **Budget:** the cost of process launch + level load is unmeasured; if it eats the budget, the
  gym gets smaller, not the invariants fewer.
- **Optional `--all-levels`:** load each shipped level, spawn, drive briefly. Off by default;
  depends on load times.
- **NPCs are being reworked:** until then, invariants only check that NPCs produce no errors, not
  how they behave.
