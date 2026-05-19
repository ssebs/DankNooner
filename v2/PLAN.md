# Gamemode Decoupling Plan

Goal: split `TutorialGameMode` (440 lines doing too much) and remove `_gamemode as TutorialGameMode` downcast from tasks. Composition over inheritance — runners nest inside `EventStartCircle`, and runners can themselves nest under other runners.

## Target shape

Tutorial today (one runner):
```
EventStartCircle
└── SequentialTaskRunner          (spawn_manager, task_hud wired here)
    ├── CountdownTask
    ├── SpeedAboveTask
    ├── TeleportTask
    └── ...
```

Future race (heterogeneous, nested):
```
EventStartCircle
└── SequentialTaskRunner
    ├── (intro tasks)
    ├── ConcurrentTaskRunner       ← a runner is itself a task, lives inside another runner
    │   └── (race tasks)
    └── (outro tasks)
```

## Class contract

- `GameModeTask` (existing) becomes the shared base. Both leaf tasks and runners extend it.
  - Adds: `start(peer_ids: Array)`, `update(delta: float)`, `stop()`, signals `player_completed(peer_id)`, `all_completed`. Default impls are no-ops — leaf tasks ignore them; runners override.
  - Replaces `_gamemode: GameModeType` with `_runner: SequentialTaskRunner` (set on `start`).
  - Adds a doc-comment on the `state: Dictionary` arg explaining: per-peer scratchpad, runner owns it, cleared on advance + on crash, tasks store whatever they need (e.g. `state["t"]` for stoppie timer).
- `SequentialTaskRunner extends GameModeTask`. Owns per-peer walk:
  - `@export spawn_manager: SpawnManager`, `@export task_hud: TutorialHUD`.
  - `_player_states: Dictionary[int, PlayerTaskState]`, `_tasks` (child GameModeTasks in tree order).
  - `start(peer_ids)`: builds states, wires triggers, calls `on_enter` of first task per peer.
  - `update(delta)`: per-peer eval_when dispatch.
  - `stop()`: unwires triggers.
  - For a child that is itself a `SequentialTaskRunner` (nested): calls `child.start(peers)`, awaits `all_completed`. Future ConcurrentTaskRunner follows same protocol.
  - `notify_crashed(peer_id)`, `notify_disconnected(peer_id)`, `mark_state(peer_id, key, value)`, `set_respawn_marker(peer_id, marker)`.
  - Emits `respawn_requested(peer_id, marker)` — the gamemode handles the actual respawn timer.
- `PlayerTaskState` (renamed from `TutorialPlayerState`, moved to `runners/`). Unchanged shape.
- `EventStartCircle`:
  - `get_runners() -> Array[SequentialTaskRunner]` replaces `get_tasks()`.
  - No longer owns trigger wiring (runner does).
- `TutorialGameMode`:
  - Walks `start_circle.get_runners()` sequentially; chains via `all_completed`.
  - Handles results, crash respawn (listens to `respawn_requested`), latejoin, disconnects.
  - Drops: `_player_states`, `_tasks`, `_respawn_overrides`, `_wired_callables`, trigger handlers, `_update_player_tutorial`, advance/complete logic — all moved to runner.

## Task → runner reference

Tasks that need shared deps reach via the runner (`get_parent() as SequentialTaskRunner`):
- `CountdownTask` → `runner.task_hud`
- `TeleportTask` → `runner.spawn_manager`, `runner.set_respawn_marker(...)`
- `CloseHelpTask` → `runner.spawn_manager`, `runner.mark_state(...)` for ack
- `CloseHelpTask` also `@export`s its tutorial-specific deps: `input_state_manager`, `menu_manager`, `help_menu_state`. Wired in the task node in the tutorial level scene.

Leaf tasks with no current `_gamemode` use are unchanged: `SpeedAboveTask`, `ChangeGearTask`, `WheelieDurationTask`, `StoppieDurationTask`, `CheckpointTask`.

## Files

New:
- `managers/gamemodes/runners/sequential_task_runner.gd`
- `managers/gamemodes/runners/player_task_state.gd` (moved/renamed)

Edited:
- `managers/gamemodes/tasks/gamemode_task.gd` — base API + state dict doc
- `managers/gamemodes/tasks/countdown_task.gd` — runner ref
- `managers/gamemodes/tasks/teleport_task.gd` — runner ref
- `managers/gamemodes/tasks/close_help_task.gd` — runner ref + @exports
- `managers/gamemodes/gamemodeobjects/event_start_circle.gd` — `get_runners`
- `managers/gamemodes/types/tutorial/tutorial_gamemode.gd` — slim
- Tutorial event `.tscn` — insert SequentialTaskRunner, reparent tasks, wire @exports

Deleted:
- `managers/gamemodes/types/tutorial/tutorial_player_state.gd`

## Order

1. `GameModeTask` base + `PlayerTaskState` rename
2. `SequentialTaskRunner`
3. `EventStartCircle.get_runners()`
4. Migrate task subclasses
5. Shrink `TutorialGameMode`
6. Update tutorial `.tscn`
