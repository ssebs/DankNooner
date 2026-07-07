# AI NPC Race Riders — Plan

> Plan for the next agent. Design brainstormed + approved by Seb. Read
> [GamemodeSystem.md](./GamemodeSystem.md) and [StreetRaceMode.md](./StreetRaceMode.md)
> first — this feature plugs into the existing gamemode/race system, it does not
> replace it. Also skim [AnimationController.md](./AnimationController.md) before
> touching the lite rider animation (Phase 4).

## User's goals (retain these)

- Add **racing AI** to the game as a **new, separate entity** — `NPCRiderEntity`
  (`entities/npc/npc_rider_entity.tscn`, already created by Seb).
- NPCs are **kinematic**: they just **move and collide**. No netfox rollback, no
  `nfx_*` input simulation, no real bike physics. They have plain **functions** to
  `crash()` / `wheelie()` / etc. that are **cosmetic only**.
- **Navigation = navmesh** (`NavigationRegion3D` + `NavigationAgent3D`), NOT the
  road-generator `RoadLane` splines. Rationale (Seb): splines are too coupled to
  the road-generator addon impl; navmesh is Godot-native and works regardless of
  how a track was built.
- **For now, the only behavior is: go to the next checkpoint in a race**, driven
  ("called down") from the **gamemode system**. Passing / difficulty / trick
  variety are explicitly deferred.
- NPCs are **multiplayer-synced** (server simulates, clients see them).
- NPCs are **first-class racers**: they register laps/checkpoints and appear in the
  results HUD alongside human peers.
- NPC needs a **lite AnimationController** that snaps the IK targets / uses the IK
  system the same way `player/player_entity.tscn` does, but stripped down.

## Approved design decisions

- **A — Identity & detection.** NPC nodes are named with **negative integer ids**
  (`"-1"`, `"-2"`, …) so `int(node.name)` slots into all existing race code
  without colliding with peer ids (always positive). Checkpoints must detect NPCs:
  broaden `GameModeObject` body detection to a shared **`"Racers"` group** (add to
  `utils/constants.gd`) instead of the current hard `body is PlayerEntity` check,
  and emit the body as `Node3D`. Both `PlayerEntity` and `NPCRiderEntity` join the
  `Racers` group.
- **B — MP sync.** Plain Godot **`MultiplayerSynchronizer`** on `NPCRiderEntity`
  syncing `global_transform` + a small `state` enum (RIDING / WHEELIE / CRASHED /
  FINISHED). **Server is authority; clients are passive.** NOT netfox
  `RollbackSynchronizer` (NPCs take no input, need no client prediction). Add
  netfox `TickInterpolator` only if motion looks choppy.
- **C — Scoring.** `RaceTask` becomes the **single source of truth for all racers**
  (human + NPC), keyed by racer id. Results are built from `RaceTask` progress, not
  from `runner._player_states` alone. Runner completion still gates on **humans
  only** — the race ends when all human peers finish; NPC placements are read from
  RaceTask at that moment.
- **v1 behavior cut.** Racing (navigate checkpoint→checkpoint at a target speed)
  + cosmetic crash/recover. Deferred: rubber-banding, difficulty tiers, deliberate
  overtake AI, wheelie/trick variety (keep `wheelie()` as a stub cosmetic hook).

## Unifying insight

Checkpoints are already **ordered waypoints**. If an NPC navigates
**checkpoint → next checkpoint**, the *same* `CheckPointMarker.entered` crossing
drives BOTH navigation retargeting AND lap scoring, and keeps the bot on a sane
route (mitigating navmesh corner-cutting, since it's pulled through each gate
rather than beelining the finish line). One event, two jobs.

---

## Architecture

```
GamemodeManager (state machine of gamemodes)
└── StreetRaceGameMode (Enter/Update/Exit)      # already exists
     ├── spawns/despawns NPCs via NPCRaceManager
     ├── registers NPCs into RaceTask
     └── merges NPC rows into ResultsHUD

NPCRaceManager (new BaseManager, under ManagerManager)
     ├── server-only AI tick per NPC
     ├── spawn/despawn RPCs (mirror SpawnManager pattern)
     └── owns negative-id counter + roster

NPCRiderEntity (CharacterBody3D, entities/npc/)   # scene exists; needs script + nodes
     ├── NavigationAgent3D          (ADD — target = current checkpoint)
     ├── MultiplayerSynchronizer    (ADD — transform + state, server authority)
     ├── VisualRoot / BikeSkin / CharacterSkin / IKTargets / NameLabel  (exist)
     └── NPCAnimationController      (new lite controller — Phase 4)

RaceTask (existing) — gains register_npc()/unregister_npc(), records
     completion_time per racer id (human + NPC). Checkpoint handler already keys
     by id — works for NPC ids once detection (A) passes them through.
```

---

## Implementation phases

Build in this order so each phase is independently testable. Phases 1–2 need no
MP and no gamemode — verify a bot drives a track locally first.

### Phase 1 — `NPCRiderEntity` moves on a navmesh (local, no race)

**Goal:** a bot follows a navmesh to a target Node3D and collides with the world.

1. Author navmesh on a test racetrack: add a **statically-baked**
   `NavigationRegion3D` over the track collision + Terrain3D geometry. Bake once in
   the editor (use `terrain.generate_nav_mesh_source_geometry(aabb, false)` — see
   `terrain3d_demo/src/RuntimeNavigationBaker.gd:127` for the Terrain3D call, but do
   NOT use the runtime streaming baker; a bounded track is a one-time static bake).
   → verify: navmesh visible in editor debug, covers the drivable surface.
2. Add `NavigationAgent3D` child to `npc_rider_entity.tscn`.
3. Write `entities/npc/npc_rider_entity.gd` (`class_name NPCRiderEntity extends
   CharacterBody3D`). Model movement on `terrain3d_demo/src/Enemy.gd`:
   throttled `set_target_position` (RETARGET_COOLDOWN ~1s — retargeting every frame
   is an expensive A* search), `get_next_path_position()` → velocity → gravity →
   `move_and_slide()`. Orient the body to face velocity (`look_at`), tuned
   `move_speed`.
   → verify: drop the NPC + a target marker in a test scene, it drives to the
   target over the navmesh and stops.

**Files:** `entities/npc/npc_rider_entity.{tscn,gd}`, one test racetrack scene.

### Phase 2 — Checkpoint targeting + `NPCRaceManager` (still local)

**Goal:** an NPC drives a lap by chasing ordered checkpoints, spawned/owned by a
manager.

1. Add `"Racers"` group key to `utils/constants.gd`. Add both `PlayerEntity` and
   `NPCRiderEntity` to it (in `_ready`, via the constants key).
2. Broaden `managers/gamemodes/gamemodeobjects/gamemode_object.gd`:
   `_on_area_body_entered/_exited` gate on the `Racers` group instead of
   `body is PlayerEntity`; change `entered/exited/hit` signal param type to
   `Node3D`. (Consumers only call `int(body.name)` and `.global_*` — safe.)
   → verify existing race still works with a human first (regression check).
3. New `managers/npc_race_manager.gd` (`class_name NPCRaceManager extends
   BaseManager`). Responsibilities:
   - Owns the negative-id counter and the NPC roster (`id -> NPCRiderEntity`).
   - `spawn_npc(...)` / `despawn_npc(id)` — local instantiate/free (Phase 3 adds the
     RPC broadcast). Names the node `str(neg_id)`, sets skins from a definition,
     adds to the level (mirror `SpawnManager.add_player_locally`).
   - Server-only `_physics_process`/tick: for each NPC, set its NavigationAgent
     target to the checkpoint it's currently chasing. The NPC's current target
     checkpoint is told to it by the race integration (Phase 3) — for now, hardcode
     an ordered checkpoint array to prove driving.
   - Wire under `ManagerManager` in `main_game.tscn`; add `@export`s + config
     warnings following existing managers.
   → verify: manager spawns 1 NPC that drives start→cp→cp→…→finish on the test
   track by itself.

**Files:** `managers/npc_race_manager.gd`, `utils/constants.gd`,
`managers/gamemodes/gamemodeobjects/gamemode_object.gd`, `main_game.tscn`,
`entities/npc/npc_rider_entity.gd`.

### Phase 3 — Race integration (scoring + gamemode ownership)

**Goal:** NPCs are first-class racers in `StreetRaceGameMode`, appearing in results.

1. `RaceTask` (`managers/gamemodes/tasks/race_task.gd`):
   - Add `register_npc(npc_id: int)` / `unregister_npc(npc_id: int)` that add/remove
     a row in `_peer_progress` with its own `start_ms` (same shape as the human row
     built in `on_enter`). The existing `_on_checkpoint_entered` handler already
     advances any id in `_peer_progress` — NPC ids flow through unchanged once
     detection (A) is in.
   - Record `completion_time_ms` into each `_peer_progress` row when
     `laps_done >= total_laps` (for humans too — makes RaceTask the single scoring
     source of truth per decision C).
   - Expose the per-racer progress/time so results can read it (getter or make the
     dict readable). NPC "next target checkpoint" for navigation = the
     `_expected_checkpoint(p)` for that id — expose a helper
     `get_target_checkpoint(id) -> CheckPointMarker` so `NPCRaceManager` can set the
     NavigationAgent target from RaceTask (closes the "one event, two jobs" loop).
2. `StreetRaceGameMode` (`managers/gamemodes/types/street_race/street_race_gamemode.gd`):
   - In `Enter()` (server): decide NPC count (export on the gamemode or the
     `EventStartCircle`), call `npc_race_manager.spawn_npc(...)` for each at grid
     slots (reuse the `GridSpawnTask` grid markers / spawn logic), then
     `race_task.register_npc(id)` for each.
   - `NPCRaceManager` sets each NPC's nav target each tick from
     `race_task.get_target_checkpoint(npc_id)`.
   - In `Exit()`: despawn all NPCs, unregister them from RaceTask.
   - Crash respawn: NPC `crash()` → after `_respawn_delay`, teleport it to its
     persistent respawn point (RaceTask already updates `set_respawn_point` per
     checkpoint; for NPCs, keep the last-passed checkpoint transform in the manager
     or reuse the same mechanism).
3. Results: `_show_results` merges human rows (from `runner._player_states`) with
   NPC rows (from `RaceTask` progress). Human usernames via `lobby_manager`; NPC
   display names from the NPC definition. Sort by completion time; NPCs that didn't
   finish get a DNF/partial row. Runner completion still gates on humans only.
   → verify: 1 human + N NPCs; NPCs complete laps, results panel lists everyone by
   time.

**Files:** `race_task.gd`, `street_race_gamemode.gd`,
`managers/gamemodes/hud/results_hud.gd` (only if row/DNF formatting needs it),
`localization/localization.csv` (NPC name / DNF keys if needed).

### Phase 4 — Lite rider animation (IK)

**Goal:** the NPC looks like a rider (seated pose via IK + lean/wheelie), not a
floating capsule. "Lite" = no trick anims, no input/trick controllers, no netfox.

Reference the full system in [AnimationController.md](./AnimationController.md) and
`player/controllers/animation_controller.gd`. Reuse, don't reinvent:

- The `CharacterSkin` instance already carries an `IKController` (FABRIK). Call
  `ik_controller.set_targets(...)` with the NPC's 11 `VisualRoot/IKTargets/*`
  markers, then `_create_ik()` + `enable_ik()` — same sequence as
  `AnimationController._editor_init_ik_from_bike()` (`animation_controller.gd:744`).
- Snap the hand/foot/chest/head/butt/magnet markers from the NPC's
  `BikeSkinDefinition` using the same pattern as `_sync_targets_from_bike()` /
  `_editor_init_ik_from_bike()` (positions/rotations live on the definition).
- Cosmetic dynamics: write `VisualRoot.rotation.z` for **lean** (from turn rate /
  steering direction) and `VisualRoot.rotation.x` for **wheelie pitch** (driven by
  the cosmetic `wheelie()` hook). Per Seb's memory: `visual_root.rotation.x` = pitch,
  `visual_root.rotation.z` = lean — do NOT rotate `bike_skin` for these.
- **Structural gotcha:** in `npc_rider_entity.tscn`, `IKTargets` is a child of
  `VisualRoot` (the player keeps it as a sibling). So NPC markers rotate WITH
  `VisualRoot`. Confirm the lite controller commits marker *local* transforms in the
  right space and that lean/pitch on `VisualRoot` doesn't double-transform the IK
  targets. Verify visually before wiring anything else.

Build a `NPCAnimationController` (new, `entities/npc/`) — a stripped pose committer:
seat the rider from the definition once, then each frame set `VisualRoot.rotation.z`
(lean) and `.x` (wheelie) via `move_toward`/`lerp`. No `_RiderPose` pipeline, no
`CustomAnimPlayer`, no trick registry needed for v1. Runs **locally on every peer**
(cosmetic — animation is not synced; it derives from synced transform + state).

`crash()` cosmetic: simplest v1 is toggle to a knocked-over visual (rotate
`VisualRoot`, stop the bot) rather than a full ragdoll; wire real ragdoll later if
desired.

→ verify: NPC drives a lap with a seated rider that leans into corners; `wheelie()`
pitches it up; `crash()` reads as a wipeout.

---

## Cross-cutting / gotchas

- **Follow "fail loudly"** (CLAUDE.md + memory): don't add silent null-return
  guards unless null is genuinely valid (comment why). The existing "player may not
  be spawned during late-join" guards are the sanctioned exceptions.
- **Reuse before adding** (CLAUDE.md): SpawnManager/RaceTask/GridSpawnTask patterns
  already do most of what NPC spawning/respawn needs — mirror them.
- **Lint clean** against `.gdlintrc` via VS Code LSP (`mcp__ide__getDiagnostics`),
  not shell. Watch `class-definitions-order`.
- **Only the human runs the project** — hand off runtime verification to Seb.
- **Editor scripts** that touch the scene tree at edit-time need `@tool` +
  `Engine.is_editor_hint()` guards, matching the existing entities.
- **Signal type change** in `gamemode_object.gd` (`PlayerEntity` → `Node3D`) is the
  one change with the widest blast radius — grep every `entered`/`exited`/`hit`
  consumer and confirm each only uses `Node3D`-safe members (`.name`, `.global_*`).
  Handlers to check: `race_task.gd:_on_checkpoint_entered`,
  `sequential_task_runner.gd:_on_trigger_entered/_exited`, tutorial checkpoint tasks.

## Open questions to confirm with Seb before/while building

- NPC roster/skins source: a fixed list of `PlayerDefinition`-like NPC defs, or
  random skins? (Affects `NPCRaceManager` spawn API.)
- NPC count per race: fixed export, per-`EventStartCircle`, or difficulty-driven?
- Does a static per-level navmesh bake fit all current racetracks, or do any need
  runtime baking? (Assume static for v1.)

## Key code references

- Navmesh follower template: `terrain3d_demo/src/Enemy.gd`
- Terrain3D nav source geometry: `terrain3d_demo/src/RuntimeNavigationBaker.gd:120`
- Player spawn/respawn pattern to mirror: `managers/spawn_manager.gd`
- Race state machine + per-racer progress: `managers/gamemodes/tasks/race_task.gd`
- Checkpoint prop + body detection: `managers/gamemodes/gamemodeobjects/{gamemode_object,checkpoint_marker}.gd`
- Runner walk (humans only) + results source: `managers/gamemodes/runners/sequential_task_runner.gd`
- Gamemode Enter/Exit/results host: `managers/gamemodes/types/street_race/street_race_gamemode.gd`
- IK setup + marker-from-definition snapping: `player/controllers/animation_controller.gd` (`_editor_init_ik_from_bike`, `_sync_targets_from_bike`), `player/characters/scripts/ik_controller.gd`
- Rider animation full docs: `planning_docs/AnimationController.md`
- NPC scene (created, needs script/nodes): `entities/npc/npc_rider_entity.tscn`
