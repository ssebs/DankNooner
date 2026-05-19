# Gamemode System

## Class taxonomy

- **`GameModeType`** (`managers/gamemodes/gamemode.gd`) — base class for a gamemode. Subclasses live under `managers/gamemodes/types/` (`FreeRoamGameMode`, `StreetRaceGameMode`, `TutorialGameMode`). The `Kind` enum on this class is the canonical gamemode identifier (`GameModeType.Kind.TUTORIAL`, etc.).
- **`GamemodeManager`** (`managers/gamemodes/gamemode_manager.gd`) — owns the state machine, match state, late-joiner sync. Maps `Kind` → `GameModeType` instance.
- **`GameModeEventDefinition`** (`managers/gamemodes/resources/gamemode_event_definition.gd`) — `Resource`. Metadata about a single event: display name/description, `target_gamemode` (a `Kind`), `event_type` (`SEQUENTIAL` / `CONCURRENT` — concurrent traversal is not yet implemented).
- **`GameModeTask`** (`managers/gamemodes/tasks/gamemode_task.gd`) — one step in a gamemode course. Subclasses under `tasks/` cover both *checks* (reach speed, change gear, hold wheelie) and *actions* (teleport, countdown, open help). Has `eval_when: ALWAYS | ON_ENTER | WHILE_INSIDE` and an optional `trigger: GameModeObject`.
- **`GameModeObject`** (`managers/gamemodes/gamemodeobjects/gamemode_object.gd`) — base for level-authored props (rings, gates, checkpoints, killboxes, trigger zones). Dumb props — emit signals, `activate`/`deactivate`, never decide completion.
- **`EventStartCircle`** (`managers/gamemodes/gamemodeobjects/event_start_circle.gd`) — level-placed `Area3D` carrying a `GameModeEventDefinition`, a `start_marker`, and `GameModeTask` children (tree order = task order). Entering it raises the confirm HUD in free roam.
- **`GamemodeStateContext`** (`managers/gamemodes/state_context.gd`) — `StateContext` subclass carrying `peer_id`, `gamemode_event`, `event_start_circle` across state transitions.

## Folder layout

```
managers/gamemodes/
  gamemode.gd                 # GameModeType + Kind enum
  gamemode_manager.gd
  state_context.gd            # GamemodeStateContext
  types/
    free_roam/free_roam_gamemode.gd
    tutorial/                 # tutorial_gamemode.gd, tutorial_hud.{gd,tscn}, tutorial_player_state.gd
    street_race/street_race_gamemode.gd
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

## Flow

1. Free roam: player enters an `EventStartCircle`. `FreeRoamGameMode` shows the confirm HUD. On submit it calls `GamemodeManager.change_gamemode(definition.target_gamemode, peer_id)`.
2. `GamemodeManager` stashes the `GameModeEventDefinition` + `EventStartCircle` on `pending_*` fields and broadcasts `_rpc_transition_gamemode`. Every peer's state machine transitions to the matching `GameModeType` with a populated `GamemodeStateContext`.
3. `TutorialGameMode.Enter()` reads `_start_circle.get_tasks()` (children of the circle), walks them per-peer via `current_index`. Each task implements `on_enter / check / on_exit / get_progress / get_objective_text / get_hint_text`. `eval_when` selects continuous, body-entered, or while-inside evaluation; the gamemode wires the `GameModeObject` triggers once and routes per-peer.
4. On all peers complete, the gamemode shows results and transitions back to `FreeRoamGameMode`.
