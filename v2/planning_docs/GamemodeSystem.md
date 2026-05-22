# Gamemode System

## Class taxonomy

- **`GameModeType`** (`managers/gamemodes/gamemode.gd`) — base class for a gamemode. Subclasses live under `managers/gamemodes/types/` (`FreeRoamGameMode`, `StreetRaceGameMode`, `TutorialGameMode`). The `Kind` enum on this class is the canonical gamemode identifier (`GameModeType.Kind.TUTORIAL`, etc.).
- **`GamemodeManager`** (`managers/gamemodes/gamemode_manager.gd`) — owns the state machine, match state, late-joiner sync. Maps `Kind` → `GameModeType` instance.
- **`GameModeEventDefinition`** (`managers/gamemodes/resources/gamemode_event_definition.gd`) — `Resource`. Metadata about a single event: display name/description, `target_gamemode` (a `Kind`), `event_type` (`SEQUENTIAL` / `CONCURRENT` — flag only, runners enforce the actual semantics).
- **`GameModeTask`** (`managers/gamemodes/tasks/gamemode_task.gd`) — base class for both leaf tasks and runners (composite pattern). Has `eval_when: ALWAYS | ON_ENTER | WHILE_INSIDE` and an optional `trigger: GameModeObject`. Leaf subclasses (`countdown_task`, `speed_above_task`, `wheelie_duration_task`, `stoppie_duration_task`, `change_gear_task`, `checkpoint_task`, `teleport_task`, `close_help_task`) override `on_enter / check / on_exit / get_progress / get_objective_text / get_hint_text`. Holds a `_runner` ref set by the parent runner — leaf tasks reach shared deps via `_runner.spawn_manager` / `_runner.task_hud` rather than downcasting to a specific gamemode.
- **`TaskRunner`** (`managers/gamemodes/runners/task_runner.gd`) — base class for composite runners. Holds the shared deps (`spawn_manager`, `task_hud`, `audio_manager`) and the `respawn_requested` signal so leaf tasks can address them via `_runner.<dep>` regardless of which runner subclass owns them. Don't instantiate directly — use `SequentialTaskRunner` or `ConcurrentTaskRunner`.
- **`SequentialTaskRunner`** (`managers/gamemodes/runners/sequential_task_runner.gd`) — `TaskRunner` that walks its child `GameModeTask`s one at a time per peer. Owns per-peer state, eval_when dispatch, and trigger wiring. Supports nesting: a child that is itself a `TaskRunner` (sequential or concurrent) acts as a gate — peers park at it, runner starts once all non-completed peers reach it, parent advances them past it on `all_completed`.
- **`ConcurrentTaskRunner`** (`managers/gamemodes/runners/concurrent_task_runner.gd`) — `TaskRunner` that runs every child `GameModeTask` in parallel per peer. Each child's `on_enter` fires immediately; each `check()` ticks every frame until it returns true; peer completes when every child reports done. Trigger gating is NOT supported — children must use `eval_when = ALWAYS`. Nest a `SequentialTaskRunner` inside if you need trigger-gated steps. Exposes `@export var objective_text` / `hint_text` for the runner-level HUD line (individual children's `get_objective_text()` is ignored).
- **`PlayerTaskState`** (`managers/gamemodes/runners/player_task_state.gd`) — per-peer runner state (`current_index`, `completed`, `start_time`, `completion_time_ms`, `lesson_state` scratchpad, `prop_event_fired` / `inside_zone` trigger gates).
- **`GameModeObject`** (`managers/gamemodes/gamemodeobjects/gamemode_object.gd`) — base for level-authored props (rings, gates, checkpoints, killboxes, trigger zones). Dumb props — emit signals, `activate`/`deactivate`, never decide completion.
- **`EventStartCircle`** (`managers/gamemodes/gamemodeobjects/event_start_circle.gd`) — level-placed `Area3D` carrying a `GameModeEventDefinition` and one or more `SequentialTaskRunner` children. Entering it raises the confirm HUD in free roam. Exposes `get_runners()`. The initial teleport into the event is handled by a leading `TeleportTask` in the runner — the circle no longer owns a `start_marker`.
- **`GamemodeStateContext`** (`managers/gamemodes/gamemode_state_context.gd`) — `StateContext` subclass carrying `peer_id`, `gamemode_event`, `event_start_circle` across state transitions.

## Folder layout

```
managers/gamemodes/
  gamemode.gd                 # GameModeType + Kind enum
  gamemode_manager.gd
  gamemode_state_context.gd
  types/
    free_roam/free_roam_gamemode.gd
    tutorial/                 # tutorial_gamemode.gd, tutorial_hud.{gd,tscn}
    street_race/street_race_gamemode.gd
  runners/
    task_runner.gd  sequential_task_runner.gd  concurrent_task_runner.gd
    player_task_state.gd
  tasks/
    gamemode_task.gd
    countdown_task.gd  teleport_task.gd  speed_above_task.gd
    change_gear_task.gd  close_help_task.gd  checkpoint_task.gd
    wheelie_duration_task.gd  stoppie_duration_task.gd
  gamemodeobjects/
    gamemode_object.gd  event_start_circle.{gd,tscn}
    checkpoint_marker.{gd,tscn}  killbox.{gd,tscn}  trigger_zone.{gd,tscn}
  resources/
    gamemode_event_definition.gd
  hud/                        # game_mode_event_confirm_hud, results_hud
```

## Scene shape

An `EventStartCircle` owns one or more `SequentialTaskRunner` children. Each runner owns its `GameModeTask` children (leaves or nested runners). Tutorial today uses a single runner:

```
EventStartCircle
└── SequentialTaskRunner
    ├── CountdownTask
    ├── CloseHelpTask
    ├── SpeedAboveTask
    └── ...
```

A future race can mix runners — outer sequential with a concurrent body:

```
EventStartCircle
└── SequentialTaskRunner            (race overall)
    ├── TeleportTask                (intro)
    ├── CountdownTask
    ├── ConcurrentTaskRunner        (race body — all children run in parallel)
    │   ├── CheckLapsTask
    │   ├── CheckPlaceTask
    │   └── OutOfBoundsTask
    ├── PlayFinishAnimTask          (outro)
    └── ShowResultsTask
```

## Flow

1. **Free roam → event:** player enters an `EventStartCircle`. `FreeRoamGameMode` shows the confirm HUD. On submit it calls `GamemodeManager.change_gamemode(definition.target_gamemode, peer_id)`.
2. **Transition:** `GamemodeManager` stashes the `GameModeEventDefinition` + `EventStartCircle` on `pending_*` fields and broadcasts `_rpc_transition_gamemode`. Every peer's state machine transitions to the matching `GameModeType` with a populated `GamemodeStateContext`.
3. **Gamemode enter:** `TutorialGameMode.Enter()` reads `_start_circle.get_runners()`, injects runtime deps (`spawn_manager`, `tutorial_hud` onto each runner; tutorial-specific managers onto `CloseHelpTask` instances — see "Dependency injection" below), and starts the first runner. The runner's first child is expected to be a `TeleportTask` that moves all peers to the event start.
4. **Runner walk:** `SequentialTaskRunner.start(peer_ids)` builds `PlayerTaskState` per peer, wires triggers from its leaf children, calls `on_enter` of the first leaf. `Update(delta)` runs `_update_player` per peer: `eval_when` selects continuous (`ALWAYS`), one-shot (`ON_ENTER`), or zone-gated (`WHILE_INSIDE`) evaluation; on `check() == true` the peer advances. Peer completion → `player_completed`; all complete → `all_completed`.
5. **Nesting gate:** if a leaf advance lands a peer on a child that is itself a `SequentialTaskRunner`, the peer parks. Once all non-completed peers are parked at the same gate index, the parent starts the nested runner with those peers and forwards its `update`/`crash`/`disconnect` calls. On `all_completed` the parent advances every parked peer past the gate.
6. **Crash respawn:** `TutorialGameMode` listens to `gamemode_manager.player_crashed` and forwards to `runner.notify_crashed(peer_id)`. The runner clears scratchpad, gating, and emits `respawn_requested(peer_id)`. The gamemode owns the respawn delay timer and calls `spawn_manager.respawn_player.rpc(peer_id)`, which uses the player's persistent `rb_respawn_transform` (set by the most recent `TeleportTask` via `SpawnManager.respawn_player_at`). `FreeRoamGameMode.Enter()` calls `reset_respawn_point.rpc()` on transition so subsequent free-roam crashes fall back to `player_spawn_pos`.
7. **Runner chain & results:** `TutorialGameMode` listens for `all_completed` on the active runner; on signal it advances to the next runner under the circle. On the last runner's completion it builds the `ResultsData` from `runner._player_states`, shows `ResultsHUD`, runs a skip-or-timeout countdown, then transitions back to `FreeRoamGameMode`.

## Per-peer scratchpad: `state: Dictionary`

Each leaf-task hook (`on_enter / check / on_exit / get_progress`) receives a `Dictionary` arg — that peer's `PlayerTaskState.lesson_state`. The runner owns it: cleared on advance to next task and on crash. Tasks pick their own keys; e.g. `StoppieDurationTask` uses `state["t"]` to accumulate elapsed hold time, `ChangeGearTask` uses `state["initial"]` to record the entry gear. Untyped on purpose so each task chooses its own shape.

See the `GameModeTask` file header for the full contract.

## Dependency injection

`SequentialTaskRunner` and tutorial-specific tasks (`CloseHelpTask`) live in level scenes; their dependencies (`SpawnManager`, `TutorialHUD`, `MenuManager`, `HelpMenuState`, `InputStateManager`) live in `main_game.tscn`. Cross-scene `@export` NodePaths are fragile, so:

- Runners and `CloseHelpTask` declare plain `var` (not `@export`) fields.
- `TutorialGameMode.Enter()` calls `_inject_runner_deps()` which walks every runner (recursively into nested runners) and sets:
  - `runner.spawn_manager`, `runner.task_hud`, `runner.audio_manager` on each runner.
  - `task.input_state_manager`, `task.menu_manager`, `task.help_menu_state` on each `CloseHelpTask`.
- Nested runners receive the same deps from their parent runner inside `SequentialTaskRunner.start()` — they propagate automatically once the outermost runner is wired.

Things that *are* level-scene-local (markers, triggers, durations, text keys) stay as `@export` on the task node — wired directly inside the level scene.
