# Street Race Mode

Lap-based race built on the gamemode system ([GamemodeSystem](./GamemodeSystem.md)).

## Relevant files

- `managers/gamemodes/types/street_race/street_race_gamemode.gd` — the gamemode
- `managers/gamemodes/tasks/race_task.gd` — lap/checkpoint state machine
- `managers/gamemodes/tasks/maintain_trick_task.gd` — `MaintainTrickTask` constraint (wheelie-race variant)
- `managers/gamemodes/gamemodeobjects/checkpoint_marker.gd` — `CheckPointMarker` (gate, signals `entered`)
- `managers/gamemodes/runners/sequential_task_runner.gd` — runner that hosts `RaceTask`
- `managers/gamemodes/tasks/grid_spawn_task.gd` — leading task that assigns each peer a grid slot and sets the race-start respawn
- `managers/spawn_manager.gd` — `set_respawn_point` / `respawn_player_at` / `respawn_player` RPCs
- `managers/gamemodes/types/tutorial/tutorial_hud.gd` + `.tscn` — shared HUD (`rpc_show_step`, `rpc_update_progress`, `rpc_hide_step_label`)
- `managers/gamemodes/hud/results_hud.gd` — end-of-race results panel
- `managers/gamemodes/gamemode_manager.gd` — match state, `change_gamemode`, late-join sync
- `managers/gamemodes/gamemodeobjects/event_start_circle.gd` — owns the runners, carries `GameModeEventDefinition`
- `levels/test_levels/test_city_01/test_city_01.tscn` — `RaceTestEventStartCircle` reference wiring
- `localization/localization.csv` — `RACE_*` keys
- `planning_docs/GamemodeSystem.md` — base taxonomy / flow that this mode plugs into
Mirrors `TutorialGameMode`: an `EventStartCircle` owns one or more `TaskRunner`s;
the gamemode walks them, listens for completion, shows results, returns to free roam.

## Key pieces

- **`StreetRaceGameMode`** (`managers/gamemodes/types/street_race/street_race_gamemode.gd`) —
  near-copy of `TutorialGameMode` without help-menu wiring. Runner chain, crash
  respawn forwarding, results HUD, return-to-free-roam.
- **`RaceTask`** (`managers/gamemodes/tasks/race_task.gd`) — leaf `GameModeTask`
  that runs the lap loop. Sits inside a `SequentialTaskRunner` as the race body.
- **`CheckPointMarker`** — existing `GameModeObject`. Race uses its `entered`
  signal directly. The marker's `global_transform` doubles as the respawn point.

## RaceTask flow

Exports: `start_checkpoint`, `lap_checkpoints: Array[CheckPointMarker]` (ordered),
`end_checkpoint` (may equal start), `total_laps`, `objective_key`.

Per-lap sequence: `start → lap_checkpoints[0..N] → end`. If `end == start`, one
crossing both finishes a lap and starts the next.

Per-peer state lives in `RaceTask._peer_progress` (a dict on the task — not the
runner's scratchpad, because signal callbacks have no scratchpad context):

```
peer_id → { laps_done, next_lap_idx, waiting_for, start_ms }
```

`waiting_for` ∈ `{ START, LAP_CP, END }` — what the player must cross next.

### Driving the state machine

- `_init` sets `eval_when = ALWAYS` — RaceTask owns its own triggering.
- First `on_enter` connects every unique checkpoint's `entered` signal once
  (`_signals_wired` guard). Subsequent `on_enter`s just init that peer's row.
- `_on_checkpoint_entered(player, ckpt)`:
  - Looks up the peer in `_peer_progress`. Unknown peers (spectators, finished
    racers) are ignored.
  - If `ckpt` matches the expected checkpoint → call `_advance`.
  - Otherwise → log via `DebugUtils.DebugMsg` and ignore (strict in-order).
- `_advance` updates the persistent respawn point and steps the state. On
  hitting `end_checkpoint` it increments `laps_done` and resets `next_lap_idx`.
- `check()` pushes the lap/timer HUD every frame, returns true once
  `laps_done >= total_laps`. The `SequentialTaskRunner` then marks the peer
  done and emits `all_completed` when every peer finishes.

### Crash respawn

Every accepted crossing calls
`spawn_manager.set_respawn_point.rpc(peer_id, ckpt.global_position, ckpt.global_basis)`
which updates the player's persistent `rb_respawn_transform` **without**
teleporting them (distinct from `respawn_player_at`, which both sets and
teleports — `TeleportTask` uses that variant at the start of the runner).

On crash:
1. `StreetRaceGameMode._on_player_crashed` → `runner.notify_crashed(peer_id)`.
2. Runner clears the scratchpad (we don't use it) and emits `respawn_requested`.
3. Gamemode schedules `spawn_manager.respawn_player.rpc(peer_id)` after
   `_respawn_delay`, which honours the player's persistent respawn transform.

Result: crash → respawn at the last checkpoint passed. Before any checkpoint
is hit, the leading `GridSpawnTask` already set the respawn to that peer's
grid slot.

## HUD

Uses the shared `TutorialHUD`. Race-specific behaviour:
- Step counter is hidden — race is a single runner step (`rpc_hide_step_label`,
  deferred from `on_enter` so it runs after the runner's `rpc_show_step`).
- `get_hint_text()` returns `""` so the initial hint paint is blank.
- `check()` pushes lap + timer text each frame via `rpc_update_progress`:
  `Lap X/Y  -  M:SS.ms` (formatted from `Time.get_ticks_msec() - start_ms`).
- Results HUD shows username + completion time, sorted ascending, using
  `tr("RACE_COMPLETE")` as the header.

## Scene shape

```
EventStartCircle  (target_gamemode = STREET_RACE)
└── SequentialTaskRunner
    ├── GridSpawnTask        (grid_markers = [GridSlot01, GridSlot02, ...])
    ├── ConcurrentTaskRunner (countdown + sfx)
    └── RaceTask
        ├── start_checkpoint = CheckpointMarker01
        ├── lap_checkpoints  = [CheckpointMarker02, 03, 04, 05]
        ├── end_checkpoint   = CheckpointMarker01   (same as start)
        └── total_laps       = 3
```

`GridSpawnTask` assigns each entering peer the next slot from its `grid_markers`
array, teleports them there via `SpawnManager.respawn_player_at` (also stores
the transform as the persistent respawn point), then auto-advances. Peers
beyond `grid_markers.size()` stack on the last marker — collision avoidance
handles separation.

Markers can live anywhere in the level — RaceTask references them by NodePath
exports, so their parent doesn't matter.

## Wheelie Race variant

A race where you must hold a wheelie the whole way — drop the wheelie for more
than a grace window and you restart at your last checkpoint. Built entirely from
existing pieces plus one reusable constraint task; `RaceTask` and
`StreetRaceGameMode` are unchanged.

- **`MaintainTrickTask`** (`managers/gamemodes/tasks/maintain_trick_task.gd`) —
  a constraint `GameModeTask` (`is_constraint = true`). Exports
  `required_tricks: Array[int]` (TrickController.Trick enum ints, default the two
  wheelie variants), `grace` (default 2.0s), `warn_key`. Each frame: in a required
  trick → reset its timer; otherwise accumulate, and once past `grace` call
  `spawn_manager.respawn_player.rpc(peer_id)` (returns the player to the persistent
  respawn point `RaceTask` keeps updated at each checkpoint) and reset. `get_progress`
  is blank while the trick is held (so `RaceTask` owns the HUD line) and shows a
  `WHEELIE! X.Xs` countdown while the player is slipping.
- Reusable for other tricks/events: change `required_tricks`/`grace` in the inspector
  (e.g. a stoppie race). See `is_constraint` in [GamemodeSystem](./GamemodeSystem.md).

Scene shape — wrap the race body in a `ConcurrentTaskRunner` so the objective and
the constraint run in parallel:

```
EventStartCircle  (target_gamemode = STREET_RACE)
└── SequentialTaskRunner
    ├── GridSpawnTask
    ├── ConcurrentTaskRunner   (countdown + sfx)
    └── ConcurrentTaskRunner   (race body)
        ├── RaceTask           (objective — total_laps = 1, objective_key = RACE_WHEELIE_OBJECTIVE)
        └── MaintainTrickTask  (constraint — wheelie, grace 2.0)
```

Live example: the `WheelieRace` `EventStartCircle` in
`levels/racetracks/racetrack_level_01.tscn` (references the same checkpoint/grid
markers as a normal race — only one event runs at a time, so sharing is safe).

## Localization keys

- `RACE_OBJECTIVE` — static objective line (`Complete the laps`)
- `RACE_LAP` — `Lap {current}/{total}  -  {time}` (dynamic, per frame)
- `RACE_COMPLETE` — results header
- `RACE_HINT` — unused by RaceTask, kept for future variants
- `RACE_WHEELIE_OBJECTIVE` — wheelie-race objective line (`Hold a wheelie the whole lap!`)
- `RACE_WHEELIE_WARN` — `MaintainTrickTask` countdown warning (`WHEELIE! {time}s`)

## Future work / extension points

- **Multiple spawn slots per checkpoint** — add `spawn_markers: Array[Marker3D]`
  on `CheckPointMarker` and pick by player slot index when calling
  `set_respawn_point`. RaceTask shape stays the same.
- **AI racers** — RaceTask's signal handler only looks up `peer_id` from
  `player.name`. AI bots driving a `PlayerEntity` with an integer name will
  participate automatically.
- **Shared base** for `StreetRaceGameMode` and `TutorialGameMode` once a third
  runner-driven mode arrives. Until then the ~50 lines of duplication is the
  simpler call.
