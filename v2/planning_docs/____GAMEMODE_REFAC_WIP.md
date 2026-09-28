# Gamemode Refactor (WIP)

> Plan agreed 2026-09-27. Goal: collapse the duplicated race gamemodes into one component-based
> `RaceGameMode`, support multiple events per `EventStartCircle`, then add Time Attack, suggested
> tricks, and a time-ranked `StuntChallengeGameMode`. Lint clean after every phase. Human
> playtests at 3 stops: after the refactor (1–3), after Time Attack (4), after challenges (5–7).
> Delete this file once folded into `GamemodeSystem.md`.

## Why

- `RoadRaceGameMode` / `StreetRaceGameMode` are ~95% identical (diff = traffic start/stop).
- `StuntRaceGameMode` is the same skeleton + trick scoring, challenges, leaderboard, pickups.
- All 5 runner modes (Tutorial, Challenge, Road, Street, Stunt) re-implement runner chaining,
  dep injection, crash respawn, late-join, disconnect, input reset, return-to-free-roam.
- `EventStartCircle` holds one `gamemode_event` (TODO: select multiple events).

## Target design

### Gamemode classes

- **`RunnerGameMode extends GameModeType`** — the shared runner plumbing listed above.
  Tutorial, StuntChallenge, and Race subclass it.
- **`RaceGameMode extends RunnerGameMode`** — replaces Road/Street/Stunt.
  `@export var race_type: RaceType { RACE, STUNT_RACE, TIME_ATTACK }`; `main_game.tscn` has one
  instance per type. `@tool` — `_get_configuration_warnings()` requires component exports
  per `race_type` (optional for others).
- **`StuntChallengeGameMode`** (rename of `ChallengeGameMode`) — see Phase 6.
- **`Kind`**: `FREE_ROAM, RACE, STUNT_RACE, TIME_ATTACK, TUTORIAL, STUNT_CHALLENGE`. Stored as ints
  in level scenes → remap `stunt_track_01`, `racetrack_level_01`, `test_city_01`.

### Components (PlayerEntity pattern)

Child nodes of each `RaceGameMode` instance in `main_game.tscn`. Parent holds
`@export var <component>`, component holds `@export var race_mode: RaceGameMode` + its own manager
exports. Parent calls hooks in a fixed, explicit order (like `_rollback_tick`):
`race_start()`, `tick(delta)`, `racer_finished(peer_id)`, `race_end()`, plus
leaderboard/results column + cell builders.

| Component | RACE | STUNT_RACE | TIME_ATTACK |
|---|---|---|---|
| NPCRacers | optional (event flag) | optional (event flag) | — |
| Traffic | optional (event flag) | optional (event flag) | — |
| StyleScoring | — | ✓ | — |
| FinishBonus | — | ✓ | — |
| KnockoutScoring (later) | — | ✓ | — |
| Challenges | — | ✓ | — |
| Pickups | — | ✓ | ✓ |
| TimeAttack | — | — | ✓ |
| Leaderboard | ✓ | ✓ | ✓ |

### Place vs standing

- **Race position** (P2/6, finish order) — `RaceTask` is the single source of truth
  (`get_progress_key`, completion time), humans + NPCs. Leaderboard column in every type.
- **Standing** (final 1st/2nd/3rd) — fixed by `race_type`, no extra knob:
  - `RACE` → race position.
  - `STUNT_RACE` → sum of every active scoring component's `score(peer_id)`.
  - `TIME_ATTACK` → best lap (best run for point-to-point).
- **Scoring components** implement `score(peer_id) -> float` + their cells:
  - `StyleScoring` — `TrickManager.get_score` (suggested tricks already doubled there).
  - `FinishBonus` — `placement_points[finish place]`, reads `RaceTask` finish order.
  - `KnockoutScoring` — per-knockout points; needs the aggressor id threaded through the crash
    (see StuntRaceGamemode.md M2).
- Axis weighting = each component's own points tunable. Scores are per-peer across the whole
  event, so multi-runner legs are cumulative for free.

### Level scene shape

```
EventStartCircle                       picker lists its GameModeEvent children
├── EventRoute "IslandLoop"  (Node3D)   grid markers, CheckPointMarkers, arrow walls, ramps, PickupSpawners
├── GameModeEvent "Island Race"         @export route -> IslandLoop, @export definition (kind=RACE, traffic, npcs, challenges)
│   └── SequentialTaskRunner -> GridSpawnTask -> CountdownTask -> RaceTask
└── GameModeEvent "Island Time Attack"  @export route -> IslandLoop, definition (kind=TIME_ATTACK)
    └── SequentialTaskRunner -> GridSpawnTask -> CountdownTask -> RaceTask
```

- **`EventRoute`** (Node3D) — holds the route's physical stuff so several events share one route.
  Show/hide = `visible` + collision toggle; replaces the `in_task` graybox special case in
  `EventStartCircle._set_game_objects_active`.
- **`GameModeEvent`** (Node) — `@export var definition: GameModeEventDefinition`,
  `@export var route: EventRoute`, runner children. The runner propagates `route` to tasks like
  `spawn_manager`; `RaceTask` / `GridSpawnTask` read markers from `_runner.route`.
- `gamemode_event` + `enable_npcs` move off `EventStartCircle` onto the event/definition.
- Transition sends the **event node path** (circle = its parent). Same NodePath sync as today.
- Confirm HUD becomes a picker over the circle's events.

## Phases

### 1 — `RunnerGameMode` extraction (pure refactor)

- [x] Create `RunnerGameMode`; move shared plumbing out of the 5 runner modes.
- [x] Port Tutorial, Challenge, Road, Street, Stunt onto it. No behavior change.
- **Verify:** lint; human plays each mode (tutorial, challenge, road, street, stunt race).

### 2 — `RaceGameMode` + components

- [x] `RaceGameMode` with `race_type` + per-type configuration warnings.
- [x] Components per the table (KnockoutScoring deferred).
- [x] Fold `StuntRaceTask` into `RaceTask`: collect `PickupSpawner`s, lap text only when
  `total_laps > 1`. Delete `StuntRaceTask`.
- [x] Delete Road/Street/Stunt gamemodes; update `GamemodeManager` map + `main_game.tscn`.
- [x] Remap `Kind` ints in the 3 level scenes.
- [x] `camera_controller._is_street_racing()` → `RACE`/`STUNT_RACE` with traffic enabled.
- [x] `NPCRaceManager` / traffic docstrings that name the deleted classes.
- **Verify:** lint; road race, traffic race, stunt race all play as before.

### 3 — `EventRoute` + `GameModeEvent` + picker

- [x] `EventRoute`, `GameModeEvent`, runner `route` propagation, tasks read from route.
- [x] `EventStartCircle` lists events; drop the graybox `in_task` hack.
- [x] Confirm HUD picker; `change_gamemode` / `_rpc_transition_gamemode` take the event path.
- [x] Migrate circles: `stunt_track_01` (5), `racetrack_level_01`, `test_city_01` (incl. tutorial).
- **Verify:** lint; each circle's events selectable + playable; props show/hide per event.

### 4 — Time Attack

- [x] `RaceTask` emits `lap_completed(racer_id, lap_ms)`; `endless` export — never completes.
  Circuits lap forever; point-to-point parks the rider at the finish until `restart_run()` (also hold-R /
  pause Respawn via `GameModeType.handle_full_respawn`: back to the grid, 3-2-1, fresh clock). The host
  ends the session via pause → Cancel Event.
- [x] `TimeAttackComponent`:
  - `race_start` sets `player.rb_do_max_boost = true` per rider (existing rollback path).
  - Host keeps session times per peer per event → Leaderboard columns best / last / current lap
    (everyone in lobby runs together, own clocks, no NPCs). Standing = best lap.
  - Server RPCs each lap time to the owning peer; the client compares against its PB and saves.
  - Point-to-point finish → per-rider `ResultsHUDState` prompt: Run Again (`request_retry`) or
    Wait for Host.
- [x] `SaveManager`: add a `progression` field to the save JSON —
  `{"time_attack": {"<level_name>/<circle>/<event node name>": {best_lap_ms}}}`.
  (Future: skins / $ / unlocks go in the same field.)
- **Verify:** lint; laps + p2p time attack, session leaderboard, PB persists across restarts.

### 5 — Suggested tricks (2x + color)

- [ ] `SuggestedTricksChallenge extends RaceChallenge` — `trick_pool: Array[TrickController.Trick]`
  + `pick_count`; server rolls on `reset()`. Authored as an embedded sub-resource per event.
  Picks reach clients via the existing `push_leaderboard(..., tricks)`.
- [ ] `TrickManager.set_bonus_tricks(peer_id, tricks)` — while a combo runs, attribute each frame's
  `combo_score` growth to `current_trick`; bonus tricks count 2x. Observe-only, no rollback change.
- [ ] `push_score_popup` gets a `bonus` flag → distinct color.
- [ ] Live combo HUD tints client-side while `current_trick` is a suggested trick (already synced;
  no RPC).
- **Verify:** lint; suggested tricks bank 2x, popup + live tint visible.

### 6 — `StuntChallengeGameMode`

- [ ] Rename `ChallengeGameMode` → `StuntChallengeGameMode`, `Kind.CHALLENGE` → `STUNT_CHALLENGE`.
- [ ] Event runner = sequence of `PerformTrickTask`s (trick picked per task in the inspector, tree
  order = sequence). Runner's `completion_time_ms` is the ranking.
- [ ] Live leaderboard by progress (tricks done, then time); results by completion time; first to
  finish wins.
- **Verify:** lint; multi-player run, correct ranking.

### 7 — Docs

- [ ] Fold this into `GamemodeSystem.md`; update `StuntRaceGamemode.md` As-built; `Architecture.md`
  gamemode section. Don't touch `TODO.md`.
