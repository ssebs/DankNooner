# Testing
---

PASTE TO CLAUDE


Build the automated regression test harness specified in planning_docs/Testing.md. Read that doc
first, then CLAUDE.md and planning_docs/GamemodeSystem.md. Testing.md is the spec; if the code
contradicts it, stop and ask me rather than improvising.

Scope for this session: Build order step 1 only (wrapper scene, Python orchestrator, error
capture, host/join through the real menu UI, invariants). Stop after step 1 and report. Steps 2-4
come in later sessions.

Before writing code, verify the doc's "Open questions / verify before building" items that affect
step 1, and report what you find:
- Does Godot 4.7 have Logger / OS.add_logger for in-process error capture? If not, fall back to
  log parsing in run.py.
- Does MainGame._apply_window_mode override --position / --resolution? A per-peer settings file
  set to windowed should avoid that; confirm by reading settings_manager.gd + main_game.gd.
- Can the wrapper set SaveManager.save_slot and SettingsManager.settings_path before they load?
  Check _ready / deferred_init ordering in save_manager.gd and settings_manager.gd.

Hard constraints:
- Near-zero changes to existing game code. Drive the real UI: play menu host_mode_opt +
  host_btn, code_entry + join_btn, the lobby's start. Find nodes through existing groups, unique
  names and exports. If you need a game-code change (a getter, a group), ask first and say why.
- Everything test-only lives in v2/tests/. Add "tests/*" to exclude_filter in all 4 presets in
  export_presets.cfg. Nothing test-related may ship.
- Inputs go in-game via Input.parse_input_event / Input.action_press. No external input
  injection.
- run.py: Python stdlib only. Godot exe path is in .vscode/settings.json.
- Director (host) / driver (every peer) split, communicating via RPCs on a TestRunner at the same
  path on every peer. Read the doc for why.
- Invariants for step 1: no errors logged; all peers agree on player count + current gamemode;
  riding HUD present (HUDManager.state_machine current state + visible UI). Countdown, stuck and
  movement invariants need the drive bot, so they belong to step 2; stub their shape only if it
  falls out naturally.
- Success criteria for step 1: `python tests/run.py` launches host + client windows tiled side by
  side; they connect via 127.0.0.1 through the menus; they enter free roam in an existing level;
  invariants run for a short window; both quit; a summary table prints; per-peer logs land in
  tests/out/. Deliberately break something (e.g. hide the riding HUD) and confirm the run fails
  with a clear message, then revert.

Process:
- Use superpowers:writing-plans to plan step 1 before coding, and show me the plan before
  implementing.
- Follow CLAUDE.md: lint with .gdlintrc, run the headless editor parse check, follow existing
  patterns, terse comments, no git/gh commands, fail loudly (no silent null guards).
- I'm granting an exception to "only the human runs the project": you may run
  `python tests/run.py` to verify the harness.
- Don't edit planning_docs/TODO.md. Update Testing.md only where the verified facts or the build
  differ from the spec (no concrete tunable values in docs).


TO HERE

---

> **Status: spec, not built.** Automated regression run before every Steam upload. Follows the
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
`SettingsManager.settings_path` at per-peer test files. Why: peers on one machine would otherwise
share (and the garage step would mutate) the real save, and a per-peer settings file is how each
window is forced windowed.

Nothing in the game uses `current_scene` or `/root/` paths, so nesting `main_game` is safe.

### Orchestrator (`tests/run.py`)

Python (stdlib only). Launches the peer processes, tiles their windows (`--position` /
`--resolution`), enforces the overall timeout, collects per-peer logs and screenshots into
`tests/out/`, and prints the summary table. Headed by default; `--headless` where the step allows
it.

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

### Drive bot

Drives, not teleports, so handling and stuck-on-geometry regressions are caught.

- **Waypoints:** a race's `EventRoute.get_checkpoints()` in tree order; otherwise the current
  task's `trigger` position.
- **Steering:** steer toward the waypoint, throttle, brake on sharp heading error. Input goes
  through `Input.parse_input_event` / `Input.action_press`, which `InputController._gather()` picks up and
  netfox records like a human's input.
- **Recipes:** tasks with no destination (wheelie, stoppie, tricks, speed) use an input recipe
  keyed by task class. **A task class with no recipe or waypoint fails loudly**, so adding a new
  task type forces adding its solver.
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

### Gym level

A normal `LevelDefinition` registered the usual way (see CLAUDE.md, Level System). Compact, wide,
flat courses, so a stuck bot means a regression, not hard terrain. It holds:

- an `EventStartCircle` per gamemode (including each race `race_type` and a `fuel_up_first`
  event);
- every `FreeRoamActivity` (gas station, garage);
- pickup spawners on the drive paths.

**Coverage check:** at startup the director compares `GameModeType.Kind`, the race types and the
`GameModeTask` / `FreeRoamActivity` subclasses in use against what's placed in the gym. Anything
missing fails the run, so the gym can't silently fall behind the game.

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

## Build order

1. Wrapper scene, orchestrator, error capture, host/join through the UI, invariants.
2. Drive bot and the task solver registry.
3. Gym level and coverage check.
4. Free-roam activities, then late join / rejoin.

## Open questions / verify before building

- **Error capture:** Godot 4.5+ `Logger` / `OS.add_logger` may allow failing on `push_error` in
  process instead of grepping logs. Check it exists on 4.7.
- **Window placement:** `MainGame._apply_window_mode` may override `--position` / `--resolution`.
- **Budget:** the cost of process launch + level load is unmeasured; if it eats the budget, the
  gym gets smaller, not the invariants fewer.
- **Optional `--all-levels`:** load each shipped level, spawn, drive briefly. Off by default;
  depends on load times.
- **NPCs are being reworked:** until then, invariants only check that NPCs produce no errors, not
  how they behave.
