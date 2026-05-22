# Race Gamemode Plan

## RaceTask — leaf `GameModeTask` (`managers/gamemodes/tasks/race_task.gd`)

Single task node that tracks per-peer lap+checkpoint progress. Lives inside a
`SequentialTaskRunner` as the race body. Connects directly to checkpoint
`entered` signals — it does NOT use the runner's single-`trigger` system,
since it watches many markers.

### Exports
- `start_checkpoint: CheckPointMarker`
- `lap_checkpoints: Array[CheckPointMarker]` (in order)
- `end_checkpoint: CheckPointMarker` (may equal `start_checkpoint`)
- `total_laps: int = 3`
- `objective_key: String = "RACE_OBJECTIVE"`
- `hint_key: String = "RACE_HINT"`

### Internal state
RaceTask owns its own per-peer dict (not the runner scratchpad — signal
callbacks have no scratchpad context):

```
_peer_progress: Dictionary[int, Dictionary]
  # peer_id -> { laps_done: int, next_lap_idx: int, waiting_for: int }
_signals_wired: bool
```

`waiting_for` enum: `WAIT_START`, `WAIT_LAP_CP`, `WAIT_END`.

### Per-lap sequence
`start → lap_checkpoints[0..N] → end`. If `end == start`, crossing it counts
as both "lap complete" and (when more laps remain) "next lap started" in one
event.

### Flow
- `_init()`: `eval_when = ALWAYS` (we own our own triggering)
- `on_enter(player, _state)`:
  - if `!_signals_wired`: connect every unique checkpoint's `entered` signal once, set flag
  - init `_peer_progress[peer_id] = {laps_done: 0, next_lap_idx: 0, waiting_for: WAIT_START}`
- `_on_checkpoint_entered(player, ckpt)`:
  - `peer_id = int(player.name)`; skip if not in `_peer_progress`
  - match `waiting_for` against the expected checkpoint
  - if it matches: advance state, update persistent respawn via
    `spawn_manager.respawn_player_at.rpc(peer_id, ckpt.global_position, ckpt.global_basis)`,
    push lap HUD via `_runner.task_hud.rpc_update_progress.rpc_id(peer_id, "Lap X/Y")`
  - if it does NOT match: `DebugUtils.DebugMsg("out-of-order checkpoint hit")` and ignore
- `check(player, _delta, _state)`: return `_peer_progress[peer_id].laps_done >= total_laps`
- `on_exit(player, _state)`: erase peer entry. Signal connections persist
  (handler is a no-op for unknown peers).
- `get_objective_text() / get_hint_text()`: `tr(objective_key) / tr(hint_key)`
- `get_progress()` returns `""` — we push lap text directly from the signal
  handler since `get_progress(state)` has no peer context.

### Crash respawn
Nothing extra needed. The player's persistent `rb_respawn_transform` was set
at the last checkpoint crossing via `respawn_player_at` (same pattern as
`TeleportTask`). Existing `SpawnManager.respawn_player` flow handles it.

Default before any checkpoint hit: the leading `TeleportTask` in the runner
already sets respawn to `RaceStartMarker01`. ✓

Runner's `notify_crashed` clears the scratchpad — we don't use it, so race
progress is preserved across crashes. ✓

### Multi-player spawn array (deferred)
For now: use the marker's own `global_transform` for respawn. When you want
spread spawns later, add `spawn_markers: Array[Marker3D]` on `CheckPointMarker`
and pick by player slot index. RaceTask shape stays the same.

## StreetRaceGameMode (`managers/gamemodes/types/street_race/street_race_gamemode.gd`)

Near-copy of `TutorialGameMode`. Same `@export` deps (drop `help_menu_state`),
same runner-chain loop, same crash respawn forwarding, same results HUD.

Differences:
- `current_game_mode = GameModeType.Kind.STREET_RACE`
- No `CloseHelpTask` injection in `_inject_task_deps`
- Results header uses `tr("RACE_COMPLETE")`
- Reuses `TutorialHUD` (typed on `TaskRunner.task_hud`)

~50 lines of duplication from `TutorialGameMode`. Extract a shared base later
when a third runner-driven mode lands.

## Scene wiring (`levels/test_levels/test_city_01/test_city_01.tscn`)

Replace the inner `ConcurrentTaskRunner` (with 5 `CheckpointTask` children)
with a single `RaceTask`. Outer `SequentialTaskRunner` + leading
`TeleportTask` + countdown `ConcurrentTaskRunner` unchanged.

```
RaceTestEventStartCircle
└── SequentialTaskRunner
    ├── TeleportTask (RaceStartMarker01)
    ├── ConcurrentTaskRunner (countdown + sfx)
    └── RaceTask
        ├── start_checkpoint = Race01CheckpointMarker01
        ├── lap_checkpoints = [02, 03, 04, 05]
        ├── end_checkpoint = Race01CheckpointMarker01  (same as start)
        └── total_laps = 3
```

Reparent the 5 `Race01CheckpointMarker0X` nodes under the `RaceTask` (or
anywhere in the level — global_transform is what matters). The old
`CheckpointTask` wrappers go away.

## Localization (`localization/localization.csv`)

Add keys:
- `RACE_OBJECTIVE` — "Complete the laps"
- `RACE_HINT` — "Pass each checkpoint in order"
- `RACE_COMPLETE` — "Race Complete!"
- `RACE_WAITING_FOR_OTHERS` — (optional, reuse `TUT_WAITING_FOR_OTHERS`)

## main_game.tscn wiring

`StreetRaceGameMode` node already exists on the `GamemodeManager`'s state
machine (referenced via `street_race_mode` export). Wire its `@export` deps
the same way as `TutorialGameMode`:
- `tutorial_hud` (shared HUD)
- `results_hud`
- `input_state_manager`
- `lobby_manager`
- `menu_manager`
- `audio_manager`

## Files touched
- **New**: `managers/gamemodes/tasks/race_task.gd`
- **Edit**: `managers/gamemodes/types/street_race/street_race_gamemode.gd`
- **Edit**: `levels/test_levels/test_city_01/test_city_01.tscn` (user wires in editor)
- **Edit**: `localization/localization.csv`
- **Wire**: `main_game.tscn` (user wires exports in editor)

## Confirmed decisions
1. Spawn marker source: `CheckPointMarker.global_transform` directly — no per-checkpoint Marker3D array yet.
2. Checkpoint order: strict in-order. Out-of-order passes are logged (`DebugUtils.DebugMsg`) and ignored.
3. Race finish: per-peer; runner completes when all peers done.
4. Gamemode reuse: mirror `TutorialGameMode` now, extract base later.
5. HUD: simple per-peer "Lap X/Y" pushed via existing `rpc_update_progress`.
6. Race time: use existing `PlayerTaskState.completion_time_ms`.
7. Crash respawn: last checkpoint hit, default to start (handled by leading `TeleportTask`).
