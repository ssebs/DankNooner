# Gamemode System

> How events are authored, launched and run. Follows the [Architecture](./Architecture.md#how-to-write-in-this-doc)
> rule: grep for rosters (the `Kind` enum, task list, component list); this doc holds the shape and
> the reasons.

## Class taxonomy

### Gamemodes (`managers/gamemodes/types/`)

- **`GameModeType`** (`gamemode.gd`) — base `State`. Its `Kind` enum is the canonical gamemode id.
  `Kind` values are stored as **ints** in level scenes (`GameModeEventDefinition.target_gamemode`),
  so reordering or inserting entries silently retargets every authored event — append only, or
  remap the level scenes.
- **`GamemodeManager`** — owns the state machine, match state and late-join sync; maps each `Kind`
  to its state node in `main_game.tscn`.
- **`FreeRoamGameMode`** — the hub. Event circles open the event picker from here. Also hosts
  `FreeRoamActivity`s (below) per rider, without leaving free roam.
- **`FuelUpGameMode`** — not a runner mode: a pre-race step for events flagged `fuel_up_first`.
  Every rider plays the gas pump minigame locally, then it hands the same event to its
  `target_gamemode`. See [StuntRaceGamemode — Fuel-up](./StuntRaceGamemode.md#fuel-up).
- **`RunnerGameMode`** (`runner_gamemode.gd`) — base for every mode that runs a `GameModeEvent`'s
  task runners: runner chaining, dep injection, crash respawn, late-join, disconnect, input reset,
  the results countdown and the return to free roam. Subclasses call `super()` from
  `Enter`/`Update`/`Exit` and override the `_on_*` hooks plus `shows_event_props()` /
  `shows_step_count()`.
  - **`TutorialGameMode`** — step-by-step lessons; injects the menu deps `CloseHelpTask` needs.
    Results by completion time.
  - **`StuntChallengeGameMode`** — a trick-sequence race (see [Stunt challenge](#stunt-challenge)).
  - **`LongJumpGameMode`** — timed trick attempts off one jump (see [Long jump](#long-jump)).
  - **`RaceGameMode`** — every checkpoint race (see [Races](#races)). `main_game.tscn` holds one
    instance per `race_type`.

Why one `RunnerGameMode` base: the five runner modes this replaced re-implemented the same
plumbing, and Road/Street race differed only in traffic start/stop.

### Events and props (`managers/gamemodes/gamemodeobjects/`)

- **`EventStartCircle`** — level-placed `Area3D`; its `GameModeEvent` children are the events the
  picker lists. `set_active_event()` owns show/hide of the events' props. `gas_station` picks the
  station whose pumps its fuel-up events use.
- **`GameModeEvent`** — one selectable event: `@export definition`, `@export route`, and the
  `TaskRunner` children the target mode runs **in tree order**.
- **`GameModeEventDefinition`** (`resources/`) — name/description, `target_gamemode`, forced bike,
  and the race flags (`enable_npcs`, `enable_traffic`, `race_challenges`, `fuel_up_first`). Authored as an embedded
  sub-resource on the event.
- **`EventRoute`** — `Node3D` holding a route's physical stuff: grid `Marker3D`s, `CheckPointMarker`s
  and `PickupSpawner`s as direct children (each group in tree order), plus props (arrow walls,
  ramps). Several events on a circle can share one route. `set_active()` toggles `visible`, every
  `GameModeObject` and every `CollisionShape3D` — a hidden ramp mustn't be an invisible wall.
  `top_level`, so it sits in world space whatever the circle's transform.
- **`GameModeObject`** — base for dumb props (checkpoints, trigger zones, speech bubbles): emit signals, `is_active` toggles visibility + collision, never decide completion.
- **`FreeRoamActivity`** — abstract, level-placed, per-rider event that `FreeRoamGameMode` hosts
  without a gamemode change (`FuelUpMinigame` is one). Entering its `%PlayerStartCircle` opens the
  same picker, for any rider. On submit the server takes a one-rider lock (`_running`), sends
  `begin()` to that client, *then* runs `server_start()`, so the client is already listening for
  whatever `server_start` triggers. The client reports `get_result()` on `finished` or on pause →
  Cancel Event (shown via `GameModeType.can_cancel_event`), and the server runs `server_end()`.
  Free roam's Exit ends every running activity with result 0. Props must stay identical on every
  peer (rollback needs the same bodies everywhere), so an activity's local-only state is visuals
  and input.

### Tasks and runners (`managers/gamemodes/tasks/`, `runners/`)

- **`GameModeTask`** — base for leaf tasks **and** runners (composite). Leaf hooks:
  `on_enter / check / on_exit / get_progress / get_objective_text / get_hint_text`. `eval_when`
  (`ALWAYS | ON_ENTER | WHILE_INSIDE`) + optional `trigger: GameModeObject`. See the file header for
  the full contract.
- **Constraint tasks** (`is_constraint = true`) — run alongside the objective for a whole step but
  never gate completion; they enforce their own fail-condition each frame (`MaintainTrickTask`).
  Place one as a sibling of the objective inside a `ConcurrentTaskRunner`.
- **`TaskRunner`** — base for runners. Holds the shared deps leaf tasks reach via `_runner.<dep>`
  (`spawn_manager`, `riding_hud`, `audio_manager`, `route`, `show_step_count`) and the
  `respawn_requested` signal.
- **`SequentialTaskRunner`** — walks its children one at a time **per peer**. A child that is
  itself a `TaskRunner` is a **gate**: peers park there, and it starts only once every unfinished
  peer has arrived. Gates put everyone in lockstep — don't nest runners in anything players should
  race through.
- **`ConcurrentTaskRunner`** — runs every child in parallel per peer; done when every
  non-constraint child is. No trigger gating (children use `ALWAYS`); its own
  `objective_text` / `hint_text` replace the children's.
- **`PlayerTaskState`** (`resources/`) — per-peer runner state: `current_index`, `completed`,
  `start_time`, `completion_time_ms`, the `lesson_state` scratchpad, trigger gates.

## Level scene shape

```
EventStartCircle                       picker lists its GameModeEvent children
├── EventRoute "IslandLoop"            grid markers, CheckPointMarkers, PickupSpawners, props
├── GameModeEvent "Island Race"        definition (kind=RACE, flags), route -> IslandLoop
│   └── SequentialTaskRunner -> GridSpawnTask -> ConcurrentTaskRunner(Countdown, SFX) -> RaceTask
└── GameModeEvent "Island Time Attack" definition (kind=TIME_ATTACK), route -> IslandLoop
    └── SequentialTaskRunner -> GridSpawnTask -> ...
```

- Tasks read markers from `_runner.route`, never from `@export` NodePath arrays. `GridSpawnTask`
  takes `route.get_grid_markers()`; `RaceTask` takes `route.get_checkpoints()` — a first checkpoint
  named ending in `StartStop1` makes it a lap circuit (start = finish), anything else is
  point-to-point. `GameModeEvent` / `EventRoute` configuration warnings flag a missing route, too
  few checkpoints, and first children not named ending in `1` (tree order is the sequence).
- Events without a route (tutorials) leave `route` empty.
- Any other `GameModeObject` under the circle (not in a route) belongs to every event on it.

## Flow

1. **Pick:** entering a circle in free roam opens `GamemodeEventHUDState`'s picker over
   `circle.get_events()` (host only). Submit → `GamemodeManager.change_gamemode(kind, peer_id,
   event_path)`, with `kind = FUEL_UP` when the event has `fuel_up_first`.
2. **Transition:** `change_gamemode()` is the single entry point (guards: server only; a
   non-late-joinable mode only accepts a return to `FREE_ROAM`, except fuel-up handing its own
   event on to the race). It broadcasts
   `_rpc_transition_gamemode`; every peer resolves the **event node path** against its own copy of
   the level — node refs can't cross RPC boundaries, the path is the sync mechanism. The
   `GamemodeStateContext` carries the event, `peer_id` and `skip_spawn_redistribute`.
3. **Enter (`RunnerGameMode`):** shows the event's props (unless `shows_event_props()` is false —
   modes whose tasks reveal their own props), sets the event pane title, injects runner deps
   (every peer — see below), and the server starts the first runner.
4. **Runner walk:** `start(peer_ids)` builds a `PlayerTaskState` per peer; `update()` evaluates the
   current task per `eval_when`, advancing on `check() == true`. Progress pauses while a peer is
   crashed (a frozen `current_trick` would otherwise keep a hold timer running through the respawn).
5. **Crash respawn:** `player_crashed` → `runner.notify_crashed` clears the peer's scratchpad and
   emits `respawn_requested`; the gamemode owns the delay, then respawns at the player's persistent
   `rb_respawn_transform` (set by the last `TeleportTask` / grid slot / checkpoint), or where they
   crashed if the current task has `respawn_in_place` (free-driving steps that set no checkpoint).
   A crash after the runner finished requests nothing.
6. **Chain + results:** each runner's `all_completed` starts the next. On the last one,
   `_on_last_runner_completed(runner)` fires **before** `runner.stop()` (which clears the per-peer
   state results read). `_show_results(data)` opens `ResultsHUDState` with a countdown; skip or
   timeout returns to free roam. Exiting a mode restores `IN_GAME` input and hides results.

## Dependency injection

Runners and tasks live in level scenes; their deps live in `main_game.tscn`. Cross-scene `@export`
NodePaths are fragile, so runners declare plain `var`s and `RunnerGameMode._inject_runner_deps()`
sets them, then `wire_task_refs()` sets every child's `_runner` and recurses into nested runners.

It runs on **every peer**, not just the server: `start()` is server-only, and tasks whose `_rpc_*`
bodies execute on clients (e.g. `SFXTask`) dereference `_runner.<dep>` there. Mode-specific deps are
injected by overriding `_inject_runner_deps()` (Tutorial → `CloseHelpTask`'s menu managers).

Level-local inputs (durations, text keys, triggers) stay `@export` on the task node.

## Per-peer scratchpad

Each leaf hook receives that peer's `PlayerTaskState.lesson_state` — cleared on advance and on
crash, untyped so each task picks its own keys (`PerformTrickTask` accumulates `state["t"]`).

## Event pane (riding HUD)

Every runner event's text lives in `RidingHUDState`'s event pane (top-right, under the minimap):
title, step count (`shows_step_count()`; races hide it), objective, a progress line (hint / lap
clock / countdown / status), a flashing warning line, then the live leaderboard. Runners and tasks
call `riding_hud.push_event_*` server-side; the text is pre-localized there, so the client doesn't
`tr()` again. Label visibility is set in code at `_ready` — the editor kept flipping it in the scene.

## Races

`RaceGameMode` runs every checkpoint race. `race_type` (`RACE`, `STUNT_RACE`, `TIME_ATTACK`) picks
the standing and which components are required; everything beyond the shared race loop lives in
**components**.

### Components (PlayerEntity controller pattern)

`RaceComponent` children of each `RaceGameMode` node, wired both ways by `@export`. The mode calls
their hooks server-side in a fixed, explicit order (`_components` in `Enter`) — traffic before NPCs
(the route graph must exist first), scoring before the leaderboard reads it:
`race_start()`, `tick(delta)`, `racer_finished(peer_id)`, `race_end()`, plus `score(peer_id)` and the
`column_headers()` / `column_cells()` leaderboard builders. `REQUIRED_COMPONENTS` (and the `@tool`
configuration warnings) list what each `race_type` needs; the rest are optional.

| Component | RACE | STUNT_RACE | TIME_ATTACK |
|---|---|---|---|
| NPCRacers | event flag | event flag | — |
| Traffic | event flag | event flag | — |
| StyleScoring | — | ✓ | — |
| FinishBonus | — | ✓ | — |
| KnockoutScoring | — | ✓ | — |
| Challenges | — | ✓ | — |
| Pickups | — | ✓ | ✓ |
| TimeAttack | — | — | ✓ |
| Leaderboard | ✓ | ✓ | ✓ |

### Place vs standing

- **Race position** (P2/6, finish order) — `RaceTask` is the single source of truth for humans and
  NPCs (`get_race_position`, completion time). Shown in every race type.
- **Standing** (the final ranking) is fixed by `race_type`, no extra knob:
  - `RACE` → race position.
  - `STUNT_RACE` → `RaceGameMode.score()`: every component's `score(peer_id)` summed.
    `StyleScoring` = banked trick points, `FinishBonus` = points by finish place among humans,
    `KnockoutScoring` = points per knockout credited via `SpawnManager.player_knocked_out`. All
    freeze at the finish line. Axis weighting = each component's own points tunable.
  - `TIME_ATTACK` → session best lap.

### Race challenges

`RaceChallenge` resources in `GameModeEventDefinition.race_challenges`, run by
`ChallengesComponent`: ticked from synced player state, fed TrickManager's `combo_banked` /
`combo_voided` (so a crash voids a combo's challenge stats too), one leaderboard column each.
`hint_tricks()` reach the riding HUD through `push_leaderboard` and show as trick rows under the
player's pinned tricks.

- **Suggested tricks** (`SuggestedTricksChallenge`) — rolls `pick_count` tricks from `trick_pool`
  each race. `bonus_tricks()` → `TrickManager.set_bonus_tricks()`, which attributes each frame's
  `combo_score` growth to the trick being held and counts a bonus trick's growth twice, so
  `get_score` already includes it. Observe-only: no rollback change. No leaderboard column (empty
  `title_key`). The HUD's live combo points and the banked score pop turn `TrickPopups.BONUS_COLOR`.
  Known limitation: the client tints for **any** challenge hint trick (e.g. the longest-wheelie
  hint), not just the 2x ones, and the live number doesn't include the 2x until it banks.

### Time attack

- `RaceTask.endless` never completes: circuits lap forever; point-to-point parks the rider at the
  finish. The host ends the session via pause → Cancel Event.
- A full respawn (hold-R / pause Respawn) after the race body started restarts the run
  (`RaceGameMode.handle_full_respawn` → `TimeAttackComponent.restart_run` → `RaceTask.restart_run`):
  back to the grid slot, frozen through a countdown, fresh clock, boost refilled.
- `TimeAttackComponent` keeps session times per event per peer on the host (Best / PB / Last / Lap
  columns). The server sends each lap to its rider; the client saves a new PB under
  `progression.time_attack["<level>/<circle>/<event>"]` (the circle is in the key because event
  names repeat across circles). PBs are client-reported — display only.
- Point-to-point finish → a per-rider run-finished prompt: Run Again, plus Wait for Host (clients)
  or End Event (host).
- `SaveManager.save_changed` means "whole save loaded/reset" only. A PB write used to emit it, which
  re-pushed player metadata → lobby resync → every rider's skin rebuilt mid-race. Per-key writes go
  through `save_item_updated`.

## Stunt challenge

`StuntChallengeGameMode` races players through a fixed trick sequence.

- **Event shape:** runner 1 = `GridSpawnTask` + countdown; runner 2 = a flat
  `SequentialTaskRunner` of `PerformTrickTask`s (trick and hold time picked per task in the
  inspector, tree order = sequence). Keep runner 2 flat — a nested runner is a gate and would put
  everyone back in lockstep.
- **Ranking:** runner 2's `completion_time_ms`, which starts when runner 2 does (after the
  countdown). Live leaderboard by progress (tricks done, then time); results by completion time,
  fastest first. The event ends when everyone finishes (or the host cancels).

## Long jump

`LongJumpGameMode`: repeated attempts off a level's jump, each scored by its trick points.

- **Event shape:** runner 1 = `GridSpawnTask` + countdown; runner 2 = one `LongJumpTask`.
- **Start gate:** the task's `trigger` is a route `CheckPointMarker`. The runner sets
  `trigger_entered` in the scratchpad for `ALWAYS` tasks, and nothing scores until it's set.
  Nothing sets a checkpoint respawn in this mode, so respawns stay on the grid slot.
- **Attempt:** once through the gate, `LongJumpTask` resets the peer's `TrickManager` score, waits for a landing after
  real airtime, then `reset_delay` on the ground and the combo banking. It reports the score and
  respawns the rider at their grid slot. A crash clears the scratchpad, so the attempt is void
  and the next one starts after the normal crash respawn. The task never completes.
- **Session:** the mode's `duration_secs` clock starts with runner 2. The time left shows on the
  progress line, and the leaderboard shows Best / Last. Results rank by best attempt. The host's
  pause → Cancel Event ends it early with results (`GameModeType.handle_cancel_event`). Before
  runner 2 starts, or while results are up, Cancel Event goes straight to free roam.

## Gamemode refactor (2026-09) — why it looks like this

- `RoadRaceGameMode` / `StreetRaceGameMode` were ~95% identical, and `StuntRaceGameMode` was the same
  skeleton plus scoring → one component-based `RaceGameMode`. `StuntRaceTask` folded into `RaceTask`
  (it collects the route's `PickupSpawner`s; lap text only when `total_laps > 1`).
- `EventStartCircle` held one event → `GameModeEvent` children + a shared `EventRoute`, so one route
  serves a race and a time attack. This also replaced the circle's graybox `in_task` special case.
- `TutorialHUDState` is gone — every event's text is in the riding HUD's event pane.
- `KnockoutScoring` landed later (2026-09-28), once `SpawnManager.knock_out` carried the aggressor id.
