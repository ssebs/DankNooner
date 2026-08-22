# Architecture / Design

> How the game works under the hood

## How to write in this doc

**If a grep would answer it, link the grep. Write down only what the code can't say about itself.**

Enumerations rot on every commit — a copied enum, a list of RPCs, a roster of exports, a file
path next to a class name. All of it is already in the code, machine-readable and correct there.
Point at the authoritative location instead, then write the part that isn't in the code: why a
surprising member is on the list, why an obvious one is absent, what breaks if you change it.

Decisions and constraints are what survive. They only go stale when someone deliberately
revisits the design — and to revisit it they have to read the rationale first, which is exactly
the moment to update it.

Same rule as tunables: name and behavior, never current values.

## High Level

### Tips for me:

- [ ] Think about how to use composition in game, like x has a y. Think golang struct has a struct. I.e. dog has age/walk anim/collider handler/etc components. When something spawns in, it has a popanim component that plays,
- [ ] I don't have to write code the godot way, e.g. load/save my own files without nodes. Use until funcs
- [ ] hand write the code & plan structure. Don't import moto-poc, but re-create it using better systems
- Use spatial comments (debug notes in the level itself)

#### Debug levels

- Nothing is registered today. `level_manager.gd` has one commented-out `Console.add_command`
  (`dbg_gym`, marked broken — its handler no longer exists). Re-add a command there to load a
  level straight from the main menu (\` opens the console).

### Stuff to plan out:

- Filesystem / folder structure
- Gameplay Loop w/ Flowcharts
- Code Structure
  - Signal Buses
- different systems that are needed
- How different systems work together
- Save system (use my own json instead of following godot's recursive way like G&L)
- NPC AI (traffic)
- multiplayer
- MORE

### Features to plan out:

- Tutorials via challenges
  - Teach how to shift, do tricks, and physics of braking via examples.
  - Speed up to 60 then take this corner at the apex, brake progressively

## Nitty-Gritty

### Godot groups

- `utils/constants.gd` has a map of Group name to group name. This should be used whenever accessing a group name so we're sure it exists.

### Translation / Localization

- Source for strings is `localization/localization.csv`
  - This CSV is auto-imported to .translation files
- Using in UI:
  - Use the key_name from the csv, it should auto-swap.
- Using in code:
  - `DebugUtils.DebugMsg(tr("<key_name>"))`

### Editor Validation

- Click "Run Validation" on the `MainGame` node inspector to check for common wiring bugs
- Validates: null `@export` objects, missing `@onready %UniqueNode` references, `@onready` Buttons without `_on_<name>_pressed()` handlers, LevelManager enum/dict sync
- Comment out `@onready` declarations to skip validation on WIP features
- See `utils/validation/auto_validator.gd` for implementation

### Managers

- Managers extend `BaseManager` and are in the "**Managers**" group. _See constants.gd_
- How to use:
  - Create Node under `ManagerManager` Node, rename to class name of the manager. e.g. `MenuManager` node uses `menu_manager.gd` which is `MenuManager` `class_name`

### State Machine

- Managers can have a State Machine, this will transition between different states
  - e.g. MenuManager can be in MainMenuState, or SettingsMenuState, etc.
- How to use:
  - Create Node, attach StateMachine script
  - Children of this Node that are States will automatically be registered
  - Transitioning of states happens via State.transitioned() signal, or request_state_change() func
  - New States can be registered / deregistered to be managed by the state machine
  - States can receive data via `StateContext` - a base class for passing typed data between states
    - Create a subclass with properties and static factory methods (see `lobby_state_context.gd`)
    - Pass context when emitting: `transitioned.emit(target_state, MyContext.NewSomething(...))`
    - Receive in `Enter(state_context: StateContext)` and cast to your type
  - States get a `state_machine_ref` property set on registration

#### Menu State Machine System

Menus use the state machine pattern where each screen is a `MenuState` extending `State`.

##### Creating a New Menu State

> Follow other files for example.

- Create new scene > `MenuState` type
  - Name it `<TYPE>MenuState`, save to `menus/...` as `<type>_menu_state.tscn`
- Create script with `<type>_menu_state.gd` as the name
  - Give it the `class_name` `<TYPE>MenuState` extends `MenuState`
- Add a `Control` node, name it `%UI`

- `@export var menu_manager: MenuManager` + target states. (see other files)
  - In `Enter()`: call `ui.show()`, connect button signals
  - In `Exit()`: call `ui.hide()`, disconnect button signals
  - Transition via `transitioned.emit(target_state)` or `transitioned.emit(target_state, context)`
- Add this new scene in the state machine
  - Add as a child of the StateMachine node
  - Wire up the exports in inspector (menu_manager, navigation targets)

#### Key Rules

- All MenuStates **must** have a `%UI` Control node (unique name)
- Set `initial_state` on StateMachine to define the default menu
- Connect signals in `Enter()`, disconnect in `Exit()` to avoid duplicate connections

### Level Manager

Levels are managed via `LevelManager` and selected through the `LobbyMenuState` MenuState. Levels are PackedScenes that are loaded & configured in `level_manager.gd`

#### Components

A level is identified by a `LevelName` enum value that must appear in **three** places in
`level_manager.gd` — the enum, `possible_levels` (→ `PackedScene`) and `level_name_map`
(→ localization key). Nothing enforces this at compile time, which is why the editor validator
checks enum/dict sync (see [Editor Validation](#editor-validation)); a missing dict entry shows up
as a level that lists but won't load.

`LevelName` idx 0 is a sentinel, not a level — it's the "select a level" placeholder the
`LobbyMenuState` dropdown shows by default. Anything iterating levels has to skip it.

#### Adding a New Level

1. Create level scene extending `LevelDefinition` (no need to wire `level_manager` export - it's set automatically on spawn)
2. Add entry to `LevelName` enum in `level_manager.gd`
3. Add entry to `level_name_map` (enum -> localization key)
4. Add entry to `possible_levels` (enum -> `preload("res://path/to/level.tscn")`)

### Input System

The `InputStateManager` (`managers/input_state_manager.gd`) is a centralized input handler that routes input based on the current game context.

#### Input Routing

`_unhandled_input()` dispatches on `current_input_state` — read the `InputState` enum and the
match in `input_state_manager.gd` for the current set.

The design points behind it:

- **The same physical "pause" press means different things per state**, resolved here rather than
  by the presser. IN_GAME emits `pause_requested`; IN_GAME_PAUSED emits `unpause_requested`.
  Nothing downstream has to know which is appropriate.
- **Menu cancel delegates rather than dispatches** — IN_MENU routes `ui_cancel` to the current
  MenuState's `on_cancel_key_pressed()`, so back-navigation lives with the screen that knows where
  "back" goes.
- **Mouse capture is derived from input state, never set ad hoc.** Menu and paused states show the
  cursor; in-game and disabled capture it. Setting `mouse_mode` anywhere else will fight this.

### Player Entity

`PlayerEntity` is a `CharacterBody3D` using composition. Most components are `@export` node
references wired in `player_entity.tscn`; `HUDController` is an `@onready %HUDController` and
`SkidmarkController` hangs under `AnimationController` rather than off the entity.

The five **simulation** controllers are called sequentially from `_rollback_tick()` via their
`on_movement_rollback_tick()` methods (order matters — see the comment there). The rest are
local/visual and run off `_process()`.

For detailed design docs see:

- [PlayerController.md](./PlayerController.md) - movement, gearing, tricks, crash subsystems
- [AnimationController.md](./AnimationController.md) - procedural animation, IK, ragdoll
- [ComboAndBoost.md](./ComboAndBoost.md) - trick combos, boost economy, scoring, tunables

#### Component Controllers

The roster lives in `player/controllers/` and is wired in `player_entity.tscn` — read it there.
The split that matters, and that the file layout does **not** show:

- **Simulation controllers** implement `on_movement_rollback_tick()` and are called from
  `PlayerEntity._rollback_tick()`. Grep that method for the current set and order. **Order is
  load-bearing** — boost runs first and is the only one evaluated while crashed, so a crash
  mid-boost cancels the burn and its camera FX instead of latching them until respawn.
- **Everything else is local/visual** and runs off `_process()` — camera, animation, HUD,
  skidmarks, minimap. None of it may write simulation state.

`IKController` (FABRIK solver) and `RagdollController` (PhysicalBone3D skeleton) live under
`player/characters/scripts/`, not with the controllers, because they're driven by
`AnimationController` rather than by the entity.

#### Synced State (via RollbackSynchronizer)

The authoritative list is `state_properties` / `input_properties` on the RollbackSynchronizer in
`player_entity.tscn`. Read it there — it's one line each, and it is never wrong.

**The rule that generates that list**: every var mutated inside the rollback tick that affects
simulation must be a state property. Resimulation can't rewind what netfox doesn't record. Adding
a var to the tick without registering it is the single most common way to introduce a desync
here, and it always presents as rubberbanding rather than as an obvious error.

State is registered as `%Controller:var` and lives on the controller owning the domain — netfox
constrains *when* a var may be written, not where it lives. Only root properties and the discrete
actions below sit on `PlayerEntity` itself.

What the list can't tell you:

- **`is_rev_limited`** looks like a cosmetic flag but gates power output. Unsynced, it rubberbanded
  gear shifts — the auto box shifts just under the limiter cut, so the flag flaps exactly then.
- **`up_direction`** looks like a constant but isn't: `MovementController` slerps it toward the
  surface normal for ramp/loop riding, and it drives `is_on_floor()` and the bike's basis.
- **`is_drifting` is deliberately absent.** It's re-derived each tick from synced inputs plus
  `slip_angle`, so syncing it would be redundant state that can disagree with its own inputs.

**Discrete actions** (the `rb_` pattern — external systems set the flag, `_rollback_tick()` runs the handler and clears it):

- `rb_do_respawn` → `do_respawn()`, and `rb_do_crash` → `on_crash()`
- `rb_respawn_transform` (persistent point) / `rb_respawn_transform_oneshot` (consumed on use) carry the target; `_pick_respawn_target()` prefers the one-shot.
- The respawn tick is remembered in `_respawn_tick` so a **resimulation** of it re-applies the synced-state half via `_apply_respawn_state()`, skipping one-time cosmetics (mesh/IK/audio). Without that, the resim undoes the teleport — the flag was already consumed on the first pass.
- Gear shifts sync `nfx_target_gear` (absolute requested gear) as netfox input — never edge-triggered flags, which drop/double-apply under stale-input reuse on the server.

#### GearingController

- Tracks clutch engagement (0-1), blends between throttle-driven and wheel-driven RPM
- Gear shifts applied from `input_controller.nfx_target_gear` each rollback tick
- **Automatic transmission** (`auto_transmission` setting) is a client-side input assist in `InputController._auto_shift()`, NOT a GearingController feature — `nfx_target_gear` is a netfox *input* property owned by the local client, so the server must never write it. Upshift/downshift RPM ratios and the between-shift cooldown are consts on `InputController`; the upshift threshold sits just under the rev-limiter cut so the auto box shifts instead of bouncing off it. Forced on while `BoostController.is_boosting`, whatever the setting says.
- Power output = throttle x power_curve x torque_multiplier x engagement
- Gear ratios, max_rpm, idle_rpm, stall_rpm are defined in `BikeSkinDefinition`

#### TrickController

The trick roster is the `Trick` enum in `trick_controller.gd`.

- **Detection only** — it reads `MovementController.pitch_angle` and classifies. It does not
  drive the bike: the wheelie/stoppie/drift physics (including the clutch-dump kick window,
  `CLUTCH_KICK_WINDOW`) live in `MovementController._pitch_angle_calc()`, and so does the
  on-ground pitch auto-balance.
- Wheelie / stoppie are entered off `WHEELIE_PITCH_THRESHOLD_DEG` / `STOPPIE_PITCH_THRESHOLD_DEG`
  (consts here, shared with `MovementController`'s `in_wheelie` / `in_stoppie` checks). The bike
  definition's `max_wheelie_angle_deg` / `max_stoppie_angle_deg` are the *crash* limits instead —
  see `CrashController`.
- The trick-button variants (`WHEELIE_MOD` / `HIGH_CHAIR` / `HEEL_CLICKER` / `TWO_LEFT_FEET`) are
  picked by camera-stick direction while the trick button is held; `HIGH_CHAIR` latches until the
  button drops or the wheelie ends. `DRIFT` mirrors `MovementController.is_drifting`.
- Emits `trick_started`, `trick_ended` signals
- Scoring lives in `TrickManager` (see below)

### Trick Manager

> Full breakdown + every tunable: [ComboAndBoost.md](./ComboAndBoost.md)

Earn, spend and bank have three separate owners, and the split is **not** optional:

- **Per-tick accrual → `TrickController._accrue_combo()`** (rollback). The combo vars and `BoostController.boost_amount` are netfox state properties, and `RollbackSynchronizer._before_tick()` re-applies every state property from history each tick. A manager writing them from `_process()` is overwritten before anything accumulates — this was a real bug, don't reintroduce it. Tuning lives in consts (`BOOST_PER_SEC`, `COMBO_GRACE_SECS`, `COMBO_MULT_THRESHOLDS`), not `@export`s, so every peer simulates identically.
  - Any trick accrues; the multiplier steps at `COMBO_MULT_THRESHOLDS` seconds of unbroken trick time; dropping every trick starts the grace window so chains survive. A crash freezes accrual (the rollback tick bails on `is_crashed`) and the respawn's `do_reset()` clears the combo.
- **Scoring → `TrickManager`** (`managers/trick_manager.gd`, server-only `_process()`). Watches those synced values and banks a score the frame `combo_time` returns to zero: `duration × points_per_second × peak_multiplier`. Banking on the combo-end edge keeps scoring out of the rollback path entirely, so resimulation can't double-count it.
  - **Crashing voids the run** — no partial credit. Checked before the `combo_time` test, because a crash freezes `combo_time` and only zeroes it at the respawn; without that ordering a crashed run would bank on the way down like a clean finish.
  - Gamemode-agnostic: gamemodes call `get_score(peer_id)` and `reset_peer(peer_id)`. Signals: `combo_banked(peer_id, points, duration, multiplier)`, `combo_voided(peer_id, lost_duration, lost_points)`.
- **Spending → `BoostController`** (rollback), which owns the meter vars — see [PlayerController.md](./PlayerController.md).

#### CrashController

Runs after physics each rollback tick and tests, in order: air-trick landing, drift
spinout/highside, then the ground checks. Every threshold is an `@export` on the controller or a
limit on `BikeSkinDefinition` — read the values there, not here.

- **Killbox** contact — always crashes, whatever the speed or angle
- **Pitch** past the bike definition's `max_wheelie_angle_deg` / `max_stoppie_angle_deg`
- **Stalled on a grade** too steep to climb (`MovementController.is_stalled_on_steep_slope()`)
- **Lean** past `crash_lean_threshold_deg`, tightened on unstable ground by
  `unstable_lean_threshold_reduction_deg` × `get_unstable_factor()`
- **Unstable lowside** — front brake while steering on gravel/sand
  (`unstable_lowside_brake_threshold` + `unstable_lowside_steer_threshold_deg`)
- **Brake grab** while turning (`brake_grab_rate_threshold`, gamepad only)
- **Upside-down landing** — checked separately, because an inverted `up_direction` breaks
  `is_on_floor()`; skipped on steep surfaces where being inverted is expected (loops)
- **Head-on obstacle collision** above a min speed
- **Drift** — over-rotation past `drift_spinout_angle_deg`, or a highside when grip returns
  (`drift_highside_*`, launched with `highside_launch_force`)

`trigger_crash()` sets `is_crashed = true`, starts the ragdoll, forces the TPS camera and emits
`crashed`. It does **not** schedule a respawn — the running gamemode owns the delay and the
destination (see [Gamemode Manager](#gamemode-manager)), which is how free roam can drop you at
the crash site while a race puts you back on your last checkpoint.

#### AnimationController

Rider states are the `RiderState` enum in `animation_controller.gd`. A `TRICK` state is commented
out there — skeleton trick anims aren't wired into the pose pipeline yet, so tricks currently
render purely procedurally.

- **Procedural animation**: Smooths visual_lean, visual_pitch, visual_yaw each frame
  - `visual_root.rotation.x` = pitch (wheelie/stoppie)
  - `visual_root.rotation.z` = lean (turning)
  - Chest rotates with lean for rider weight shift
- **IK**: `IKController` handles hand/foot/head positions via markers on BikeSkinDefinition
- **Ragdoll**: `RagdollController` creates skeleton bodies for crash physics

#### Skin System

See [Skins.md](./Skins.md)

### Pause System

User stories:

- In SP or MP, hitting **PAUSE** should:
  - Open the pause menu
  - Show the Mouse / allow gamepad to control menus
  - Allow you to change settings
  - Allow you to go to the main menu
  - Customize your character (progression depends on mode)
- In Singleplayer, hitting **PAUSE** should:
  - Freeze the gameplay & pause whole world
  - Allow you to save game
  - Allow you to load game
- In Multiplayer, hitting **PAUSE** should:
  - Freeze your character? Turn half-invisible w/o hitbox
  - Allow you to invite friends to server
  - Allow you to change servers

#### Input & Pause Interaction

The `PauseManager` (`managers/pause_manager.gd`) coordinates InputManager, MenuManager, and LevelManager:

- **Pause** (`pause_requested`): Sets state to `IN_GAME_PAUSED`, shows pause menu, enables MenuManager processing, disables LevelManager processing
- **Unpause** (`unpause_requested`): Sets state to `IN_GAME`, hides menus, disables MenuManager processing, enables LevelManager processing

The same "pause" action triggers different behavior based on `InputState`.

### Audio Manager

- `AudioManager` (`managers/audio_manager.gd`) - custom Godot audio middleware (replaced FMOD, web-export friendly). See [AudioMiddleware.md](./AudioMiddleware.md)
- Maps settings keys to audio bus volumes (e.g. `"master_vol"` → `Master` bus)
- `update_ninja500_rpm(rpm_ratio)` - sets RPM parameter for seamless engine sound looping
- Listens to `SettingsManager.setting_updated` / `all_settings_changed` to sync bus volumes

### Settings Manager

- `SettingsManager` (`managers/settings_manager.gd`) - JSON persistence to `user://settings.json`
- The key list is the `default_settings` dict in that file — read it there
- **Settings are device/UI preferences only.** Username, skins and progression live in save data
  (`SaveManager`), not here. New player-identity fields go there, not in settings
- Signals: `setting_updated(key, value)`, `all_settings_changed(dict)`
- Consumers: `AudioManager` (bus volumes), `ConnectionManager` (signal relay host)

### Gamemode Manager

- `GamemodeManager` (`managers/gamemodes/gamemode_manager.gd`) - manages match state, coordinates level/spawn. Runs a **state machine of gamemodes**.
- **Gamemode states** (extend base `GameModeType`, whose `Kind` enum is the canonical id, live under `managers/gamemodes/types/`):
  - `FreeRoamGameMode` - open play, event circles trigger mode switches, respawn on crash. Crash respawns return you to the crash site (upright, same heading) — unless the site is steep or void, in which case you go to your last flat-ground breadcrumb (the server samples one per player on gentle ground; the ground check excludes the bike's own collider and ragdoll bones)
  - `RoadRaceGameMode` - lap-based race built on the task/runner system (see [GamemodeSystem.md](./GamemodeSystem.md)). Bots keep racing through the results countdown; result rows refresh live until the timer ends (human rows are snapshotted before the runner stops — `TaskRunner.stop()` clears its per-player state)
  - `StreetRaceGameMode` - the same race run through live ambient traffic (duplicated file, not a subclass)
  - `TutorialGameMode` - step-by-step progression with countdown + trick detection
  - `ChallengeGameMode` - lightweight in-world trick challenges (no countdown/results)
  - The `Kind` enum runs ahead of the implementation — it carries reserved entries with no
    gamemode file and no state node in `main_game.tscn`. A `Kind` value is not evidence the mode
    exists; check for the type under `types/` and the node in `main_game.tscn`.
- Events run via a composable **task/runner system** (`GameModeTask` leaves + `SequentialTaskRunner` / `ConcurrentTaskRunner`), authored in level scenes. See [GamemodeSystem.md](./GamemodeSystem.md)
- Context passed between gamemode states via `GamemodeStateContext`
- RPC guards (signatures: grep `@rpc` in `gamemode_manager.gd`):
  - `start_game` - server calls on all peers; ignores anything sent by a client
  - `_sync_game_to_late_joiner` - authority-mode RPC, server → one peer
  - `_request_late_spawn` - a peer may only request its own spawn
- **`change_gamemode()` is the single entry point for transitions.** It is the only thing that calls the `_rpc_transition_gamemode` broadcast — gamemodes returning to free roam go through it too, so every transition passes the same guards. Calling the broadcast directly bypasses them.
- **Late-join contract**: `GameModeType.is_late_joinable()` (default false, true on `FreeRoamGameMode`). A peer joining mid-race is synced into free roam on the same level instead of the live race — races need mid-match context (start circle, runner state) the joiner has no way to reconstruct, and dropping them straight in crashed the client on a null `event_start_circle`. They still spawn and ride; when the race ends, everyone transitions to free roam and the joiner's same-state transition is a harmless no-op.
- While a non-late-joinable mode is running, `change_gamemode()` accepts only a return to `FREE_ROAM`. That stops a free-roaming late joiner from driving into an event circle and restarting the mode out from under a live race.

### Save Manager

- `SaveManager` (`managers/save_manager.gd`) - JSON persistence of player save data with version tracking
- Owns the local `PlayerDefinition` (username, bike/character skins, progression)
- Distinct from `SettingsManager` (which handles device/UI settings)

### Spawn Manager

`SpawnManager` (`managers/spawn_manager.gd`) owns player spawn/despawn/respawn. Grep `@rpc` there
for the current surface. The distinctions that aren't obvious from the signatures:

- **Respawn and crash are broadcasts, not server-side teleports.** Every peer sets `rb_do_respawn`
  / `rb_do_crash` on its local player so the handler runs everywhere — clients have ragdoll and
  visual state that a synced transform alone won't reset. `crash_player` is sent by whoever rammed
  the victim, because slide collisions only report what *you* moved into.
- **Three respawn flavors, differing only in what they do to the persistent point**: teleport and
  store it, teleport with a one-shot and leave it (free-roam crash), or update/clear it without
  teleporting (race checkpoints, entering free roam). Picking the wrong one is silent — you find
  out when a later respawn lands somewhere stale.
- **`request_respawn()` is the only client-callable entry point.** The server derives the target
  from the RPC sender, so a client can never respawn anyone but itself.
- **Sender guards**: broadcasts stay `any_peer` only because the server has to `call_local` them,
  and each rejects any sender that isn't the server. This relies on a subtle mechanic — during
  `call_local` the sender id is the *local* peer's own id, so it reads as 1 on the host and as the
  client's own id (correctly rejected) on a client. **Any new client-side caller needs a
  `request_*` entry point, never a direct broadcast.**

### NPC Race Manager

- `NPCRaceManager` (`managers/npc_race_manager.gd`) - owns AI race riders (`NPCRiderEntity`) on a negative-id roster (ids from -1) with spawn/despawn RPCs mirroring `SpawnManager`. The race gamemodes drive its lifecycle; the server-only AI tick points each NPC at its next checkpoint from `RaceTask`.
- Late joiners get every live bot re-sent at its current transform via `sync_npcs_to_peer(peer_id)` (called from the race gamemodes' `_on_player_latejoined`) — without it the newcomer has no bot nodes and takes a MultiplayerSynchronizer error per packet per bot.

### NPC Traffic Manager

- `NPCTrafficManager` (`managers/npc_traffic_manager.gd`) - ambient traffic riders/cars (ids counting down from its `FIRST_ID` const, far enough below the race roster to guarantee the two id spaces never collide). Builds a `TrafficRouteGraph` from the level's road network; count, car/bike mix, cruise speed and vehicle rosters are per-map via `LevelDefinition.traffic_settings` (a `TrafficSettings` resource). `FreeRoamGameMode` and `StreetRaceGameMode` start/stop it, server-only.
- **Spawn sync contract** (this is the fix for "traffic only loads for host"):
  - The server broadcasts `rpc_spawn_npc`, but clients only *accept* spawns after their own gamemode `Enter()` runs (level guaranteed loaded) — earlier broadcasts would parent riders under the outgoing level and be freed with it.
  - On `Enter()`, non-server peers call `request_traffic_sync()` to pull everything they missed (covers both the fresh-start timing race and late join); `Exit()` calls `reset_local_traffic()`.
  - Spawn/despawn RPCs are idempotent (dedupe on npc id / tolerant of missing ids), so broadcast + resync can overlap safely.
- Crashed riders recover onto a clear lane spot after a randomized delay; a rider that rams a player crashes them via `SpawnManager.crash_player`.
- Vehicle skins ship as `res://` paths, deliberately not `PlayerDefinition.to_dict()` — that round-trips through `BikeSkinDefinition.from_dict()`, which writes a `.tres` into `user://skins/` per rider per peer (open issue).

### Animal Spawn Manager

- `AnimalSpawnManager` (`managers/animal_spawn_manager.gd`) — server authority for the animals a level authored (`NPCAnimalEntity`). It **does not spawn them**: they are hand-placed in the level scene. Hooked from `GamemodeManager` on level load (`_bind_level_animals`), so it applies to every gamemode rather than one.
- **The parent decides the behavior.** An animal under a `Path3D` walks that curve; one parked anywhere else stands and plays `Idle`. Several animals can share a path — they space themselves evenly around it by child order, so only *which* Path3D they hang under matters, not where along it they were dropped. (Seeding from the authored position was tried and is wrong: an animal placed beside the spline gets clamped by `get_closest_offset()` to the nearest end of it, so a whole herd stacks on one point.) Re-routing a herd is a drag in the scene tree, no code and no manager wiring.
- **The walk is deliberately unsynced.** Every peer loads the same level, so it has the same curve, the same `move_speed` and the same index-derived start offset — it just walks it. Only the two things a peer cannot decide alone are broadcast: the kill and the respawn.
- Animals are addressed by **NodePath under the level**, which ships inside the level scene and is therefore identical on every peer. That removes the id roster, the spawn broadcast and the client accept gate that `NPCTrafficManager` needs. A late joiner's level brings every animal in alive, so `request_animal_sync()` only has to fetch the set that is currently dead.
- **Animals are hit volumes, not obstacles.** `NPCAnimalEntity` is an `Area3D` on no collision layer at all (nothing can hit it), masking only `crash_collision` — the layer racers carry alongside the default world layer. A racer rides straight *through* one: the animal plays `Death` and holds the last frame, the rider keeps their line. That is why it isn't an `AnimatableBody3D` — a solid body would deflect a bike at speed no matter how fast the death registered.
  - The mask is only a pre-filter, **not** a racer test — `_on_body_entered` still checks the `Racers` group. It masks `crash_collision` rather than the default world layer because the asphalt road surface is on that default layer: an animal walking a roadside path would otherwise fire against the ground under its own feet. Layer names live in `project.godot`.
- Only the server acts on the overlap (`hit_by_racer` → `rpc_kill_animal`), so no peer ever kills an animal locally. The corpse lies there for `respawn_delay_min..max`, then gets up where it fell and walks on.
- Mesh and hit volume are built from `AnimalSkinDefinition` exactly as `PlayerEntity` builds itself from `BikeSkinDefinition` — see [Skins.md](./Skins.md). Clip names are consts on the entity, not definition fields: the Animated Animal Pack ships one identical clip set (`Walk` / `Idle` / `Death`) for every animal in it.

#### NPC transform sync + render smoothing

Shared by both NPC managers, implemented on `NPCRiderEntity`. NPCs use a plain `MultiplayerSynchronizer` (server authority) with **no** netfox rollback or TickInterpolator.

- The replicated property is `sync_transform`, not the node's raw transform. The server writes it at the end of every movement tick (all three behavior states route through `apply_gravity_and_move()`) and on `teleport_to()`.
- Nothing renders straight off it. A body that only moves on the tick reads as stepping at render rate — the player bike doesn't, because netfox's TickInterpolator smooths it, and that gap is what this closes for NPCs. Both peers ease toward `sync_transform` in `_process()`, with different math because they know different things:
  - **Server** knows both ends of the step, so it interpolates exactly between the last two authoritative poses by the physics interpolation fraction. One tick of visual latency and no more, so what you see still lines up with what you collide with.
  - **Client** only ever knows the latest pose, arriving at replication rate on irregular timing, so it eases toward it exponentially. Jumps past a snap threshold (teleport / crash recovery) snap instead of sliding across the map.
- The server puts the body back on `sync_transform` in its own `_physics_process` before the behavior states run, so steering and `move_and_slide()` never see a smoothed pose. That restore has to land first, which is why the entity sets a negative `process_physics_priority` rather than relying on parent-before-child order alone.
- Clients never simulate: `_ready` disables the behavior state machine's physics on non-server peers.

### Unlocks / progression

#### WIP NOTES

- Singleplayer unlocks mods / cosmetics (aka 100% skin), and that unlocks skins for SP and MP
- Bikes unlock per SP/MP

- Playing SP unlocks bikes for MP?
- Playing MP unlocks skins for SP, but not bikes

### Customizing

- Have an in-world garage like LS Customs
- Pause menu btn teleports you to the garage

## Multiplayer Networking Architecture

### Authority Model: Client-Predicted, Server-Authoritative

Each client captures input locally and predicts off it immediately. netfox's
`RollbackSynchronizer` ships that input to the server, which runs the authoritative physics and
broadcasts the resulting state properties back; clients resimulate from the corrected state on
mismatch. There is no hand-written input RPC — netfox owns the whole path.

### Authority Summary

| Component                   | Runs On                | Authority                  |
| --------------------------- | ---------------------- | -------------------------- |
| `InputController` (capture) | Local client only      | Client                     |
| `InputController` (sync)    | Local client -> Server | Client sends, netfox syncs |
| `MovementController`        | Server only            | Server                     |
| `GearingController`         | Server only            | Server                     |
| `TrickController`           | Server only            | Server                     |
| `CrashController`           | Server only            | Server                     |
| `AnimationController`       | Local client only      | Client (visual only)       |
| `CameraController`          | Local client only      | Client                     |
| Position/Rotation           | Server broadcasts      | Server                     |
| Lobby state                 | Server broadcasts      | Server                     |

### Terrain

Terrain is `zylann.hterrain`. Its collision is static and identical on every peer, so server-authoritative physics needs nothing special from it. (Terrain3D was removed — it built collision around a single tracked camera, so the server had to force a full-collision mode or remote players fell through the map.)

### Connection Modes

All modes are **server-authoritative** — the host runs physics, clients predict + reconcile. Mode only affects transport.

- **WEBRTC** *(default)*: WebRTC peer connections via a custom signaling server (`signal_relay_host`), works for both native and browser clients. Handled by `MultiplayerWebRTC`. See [LobbyGameFlowMP.md](./LobbyGameFlowMP.md)
- **IP_PORT**: Direct IP/ENet connection on `UtilsConstants.PORT`. Handled by `MultiplayerIPPort`.
  - Fetches public IP via ipify.org API (or private IP in debug)

Like `GameModeType.Kind`, `ConnectionMode` carries entries with no handler behind them. The
`match` in `connection_manager.gd` is the real list of supported modes, not the enum.

### RPC Signatures

**InputController** - Client -> Server (synced via RollbackSynchronizer):

Input is gathered locally by `InputController._gather()` and synced automatically by netfox's `RollbackSynchronizer`. No manual RPC needed - netfox handles input sync and rollback.

**LobbyManager** RPCs:

- `update_player_metadata(peer_id, player_def_dict)` - client sends PlayerDefinition to server
- `_sync_lobby_players(players_dict)` - server broadcasts full lobby dict

**GamemodeManager** RPCs:

- `start_game(level_name)` - server calls on all peers
- `_sync_game_to_late_joiner(level_name, gamemode, ...)` - sync level to late-joining client
- `_request_late_spawn(peer_id)` - late-joiner requests their player spawn

See the [Gamemode Manager](#gamemode-manager) section for the sender guards, the late-join contract, and why `change_gamemode()` is the only way to start a transition.

**SpawnManager** RPCs: see the [Spawn Manager](#spawn-manager) section for the full list (spawn/despawn broadcasts plus the respawn/crash/respawn-point family) and the server-sender guard rule.

### Deployment / builds

- Godot 4.7 is required (see `config/features` in `project.godot`)
- Audio uses a custom Godot middleware — no FMOD dependency (see [AudioMiddleware.md](./AudioMiddleware.md))
- Deploying new version
  - Run `./deploy-version.sh` (any OS) to create a new version tag & push to github to run CI
  - See [build.yml](../../.github/workflows/build.yml)
