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

- No level-loading command is registered. `level_manager.gd` has one commented-out
  `Console.add_command` (`dbg_gym`, marked broken — its handler no longer exists) beside the live
  `dbg_traffic`. Re-add one there to load a level straight from the main menu (\` opens the
  console).

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

### Terrain & Roads

Terrain is `zylann.hterrain`; roads are TheDuckCow's `godot-road-generator`. Both are addons and
both are authored per level as scene nodes — an `HTerrain` node beside a `RoadManager` holding
`RoadContainer`s of `RoadPoint`s. There is no code that builds either; the level scene *is* the
data.

This is the third attempt. Hand-built `StaticBody3D` road pieces and Terrain3D both lost.

What the plugins don't give you:

- **AI lanes nobody uses.** No game code reads the addon's lanes: race bots ride a navmesh racing
  line (see [NPC Race Manager](#npc-race-manager)) and traffic its own baked network
  (see [Traffic Network](#traffic-network)).
- **A road/off-road distinction.** Road mesh and terrain both sit on the default world layer.
  Surface feel comes from the separately authored unstable-surface layer
  (see [CrashController](#crashcontroller)), not from being on a `RoadContainer`. The `road` layer
  exists only for the traffic bake's height snap.

**Minimap layer.** The minimap camera draws only render layer 2 (`minimap`), so it skips
traffic, riders and props. Anything that should show on the map needs layers 1+2: the
`GrayBoxStaticBody` mesh (which covers the building props), the farm glbs and the race/bridge wall
CSGs have it in their scenes, but each level's
`RoadContainer`s (`render_layers`) and terrain meshes have to be tagged by hand.

### Input System

The `InputStateManager` (`managers/input_state_manager.gd`) is a centralized input handler that routes input based on the current game context.

#### Input Routing

`_unhandled_input()` dispatches on `current_input_state` — read the `InputState` enum and the
match in `input_state_manager.gd` for the current set.

The design points behind it:

- **The same physical "pause" press means different things per state**, resolved here rather than
  by the presser. IN_GAME emits `pause_requested`; IN_GAME_PAUSED emits `unpause_requested`.
  Nothing downstream has to know which is appropriate.
- **Menu cancel delegates rather than dispatches** — IN_MENU (and IN_GAME_PAUSED, while a menu is
  visible) routes `ui_cancel` (and tab keys) to the current
  MenuState's `on_cancel_key_pressed()`, so back-navigation lives with the screen that knows where
  "back" goes.
- **Mouse capture is derived from input state, never set ad hoc.** Menu and paused states show the
  cursor; in-game and disabled capture it. Setting `mouse_mode` anywhere else will fight this.

### Player Entity

`PlayerEntity` is a `CharacterBody3D` using composition. Most components are `@export` node
references wired in `player_entity.tscn`; `SkidmarkController` hangs under `AnimationController`
rather than off the entity. The HUD is no longer a component — it's the global `HUDManager`
(see [HUD Manager](#hud-manager)), injected onto the entity by `SpawnManager`; on spawn the local
player registers itself as `hud_manager.local_player` and flips it to the riding HUD.

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
- **Everything else is local/visual** and runs off `_process()` — camera, animation, skidmarks.
  None of it may write simulation state. (The HUD and minimap moved out of the entity into
  `HUDManager` — see [HUD Manager](#hud-manager).)

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
- **Private `_prev_*` / cached vars count too.** Anything carried from one tick into the next
  (`_is_on_floor`, `air_pitch_total`, CrashController's `_prev_*`) must be registered. Unsynced,
  they kept the client's own values through a resim, so landings mispredicted — a flashed crash
  HUD on a clean land, or a server-side crash on a flip that looked landed.
- **`is_drifting` is deliberately absent.** It's re-derived each tick from synced inputs plus
  `slip_angle`, so syncing it would be redundant state that can disagree with its own inputs.

**Discrete actions** (the `rb_` pattern — external systems set the flag, `_rollback_tick()` runs the handler and clears it):

- `rb_do_respawn` → `do_respawn()`, and `rb_do_crash` → `on_crash()`
- `rb_respawn_transform` (persistent point) / `rb_respawn_transform_oneshot` (consumed on use) carry the target; `_pick_respawn_target()` prefers the one-shot.
- The respawn tick is remembered in `_respawn_tick` so a **resimulation** of it re-applies the synced-state half via `_apply_respawn_state()`, skipping one-time cosmetics (mesh/IK/audio). Without that, the resim undoes the teleport — the flag was already consumed on the first pass.
- Any `rb_` flag that writes synced state needs the same protection: boost grants (`_boost_grant_tick`) and freezes (`rb_lock_movement` / `rb_unlock_movement` → `_lock_tick`) re-apply their result on a resim of their tick. An unprotected unlock gets undone and leaves the rider frozen for good — most often a laggy (web) client, whose ticks the server is still predicting.
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
  (consts here, shared with `MovementController`'s `in_wheelie` / `in_stoppie` checks). A wheelie
  only ends once pitch stays under the lower `WHEELIE_EXIT_PITCH_DEG` for `WHEELIE_EXIT_DELAY`, so
  bobbing across the threshold doesn't restart the trick; `wheelie_setting_down()` marks that tick (the set-down wobble trigger). The bike
  definition's `max_wheelie_angle_deg` / `max_stoppie_angle_deg` are the *crash* limits instead —
  see `CrashController`.
- The trick-button variants (`WHEELIE_MOD` / `HIGH_CHAIR` / `HEEL_CLICKER` / `TWO_LEFT_FEET`) are
  picked by camera-stick direction while the trick button is held; `HIGH_CHAIR` latches until the
  button drops or the wheelie ends. `DRIFT` mirrors `MovementController.is_drifting`.
- Stick tricks work in any ground wheelie. Outside the balance point they pump a speed wobble
  (`WobbleController.trick_feed()`, rate `WOBBLE_TRICK_FEED`) toward a swing sized by how far
  off the window pitch is (crash-sized at `WOBBLE_TRICK_CRASH_MISS_DEG`). It keeps the wheelie up
  (`wobble_from_trick`); closing in on the balance point shrinks it, reaching it settles it.
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
  - **Bonus tricks** (`set_bonus_tricks`, from a race's suggested-tricks challenge) count twice: each frame's `combo_score` growth is attributed to the trick being held. Still observe-only — nothing in the rollback path changes. Kept outside the per-peer scoring row because `reset_peer` fires on every spawn.
- **Spending → `BoostController`** (rollback), which owns the meter vars — see [PlayerController.md](./PlayerController.md).

#### CrashController

Runs after physics each rollback tick and tests, in order: air-trick landing, drift
spinout/highside, then the ground checks. Every threshold is an `@export` on the controller or a
limit on `BikeSkinDefinition` — read the values there, not here.

- **Killbox** contact — always crashes, whatever the speed or angle
- **Pitch** past the bike definition's `max_wheelie_angle_deg` / `max_stoppie_angle_deg`
- **Stalled on a grade** too steep to climb (`MovementController.is_stalled_on_steep_slope()`)
- **Lean** past `CRASH_LEAN_THRESHOLD_DEG`, tightened on unstable ground by
  `UNSTABLE_LEAN_THRESHOLD_REDUCTION_DEG` × `get_unstable_factor()`
- **Unstable lowside** — front brake while steering on gravel/sand
  (`UNSTABLE_LOWSIDE_BRAKE_THRESHOLD` + `UNSTABLE_LOWSIDE_STEER_THRESHOLD_DEG`)
- **Brake grab** while turning (`BRAKE_GRAB_RATE_THRESHOLD`, gamepad only)
- **Upside-down landing** — checked separately, because an inverted `up_direction` breaks
  `is_on_floor()`; skipped on steep surfaces where being inverted is expected (loops)
- **Head-on obstacle collision** above a min speed
- **Drift** — over-rotation past `DRIFT_SPINOUT_ANGLE_DEG`, or a highside when grip returns
  (`DRIFT_HIGHSIDE_*`, launched with `HIGHSIDE_LAUNCH_FORCE`)

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

### HUD Manager

`HUDManager` (`managers/hud/hud_manager.gd`) runs a **state machine of `HUDState`s** (all under
`managers/hud/`). `RidingHUDState` is the gameplay HUD — on spawn the local `PlayerEntity` sets
`hud_manager.local_player` and calls `go_to_riding_hud()`, and the state polls that player's
controllers in its own `Physics_Update()` rather than the entity's `_process()`, so it owns no
simulation state. `LevelManager` flips back to `NullHUDState` when leaving gameplay for a menu.

- **The overlay HUDs are parked states their gamemode drives directly, not transitioned to** —
  `ResultsHUDState` and `GamemodeEventHUDState` sit under the same state
  machine but are shown/hidden by their owning gamemode via `@rpc` calls (grep the gamemode for the
  `rpc_*` entry points). They never become the machine's `current_state`.
- **Riding HUD layout is one job per corner, no panels** — FPS + event pane top-left, money/XP +
  progress line top-centre, leaderboard + trick feed top-right, held item + minimap bottom-left, speed/gear/RPM + vertical boost gauge
  bottom-right, trick prompt mid-left. Labels read over the world via the outline/shadow in
  `resources/themes/hud.tres`, set on the HUD's `MarginContainer`.
- **Button prompts are `InputPrompt`s** (`player/hud_elements/`) — the glyph an action is bound to
  on the rider's current device (`InputController.is_gamepad`), resolved through `ControlBindings`
  (shared with Settings > Controls). `RidingHUDState` re-glyphs them on a device switch and on every
  `show_ui()`, so a remap from the pause menu shows on unpause. While the trick button is held, the
  mid-left trick prompt lists every stick trick bound in the current `TrickState`, above the pinned
  tricks.
- **Event text lives in `RidingHUDState`'s event pane** (title, step, objective, progress, warning)
  and the live leaderboard sits top-right — every runner event pushes to them server-side via
  `push_event_*` / `push_leaderboard`. See [GamemodeSystem — Event pane](./GamemodeSystem.md#event-pane-riding-hud).
- **`RidingHUDState.push_checkpoint_marker()`** is how the race gamemodes mark each racer's next
  checkpoint on that peer's minimap: the state is a single node at a shared path on every peer, so
  the server can `rpc_id` the owning client's minimap through it. Pre-race it carries the current
  step's trigger instead (`is_guide`). `TargetCompass` points at the same target from above the
  minimap: always for guide targets, for race checkpoints only on easy difficulty. While a
  guide target is on screen it pins over it instead, and the distance shows under the arrow or pin.
  It hides near the target, where the server's pass lags the predicted rider and the bearing
  would spin.
- Pause hides the current HUD in place (`set_hud_hidden`) instead of transitioning, so unpause
  restores it without a state change.

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
- **Remappable controls**: defaults are the project Input Map; `"controls"` stores only overrides
  per action slot (kbm / gamepad / addl). `ControlBindings` (`utils/control_bindings.gd`) resolves
  and applies them to `InputMap` from `MainGame` on `all_settings_changed`. Which actions are
  remappable, and their categories (duplicates only conflict within one), is
  `UtilsConstants.CONTROL_CATEGORIES`. Edited in `SettingsMenuState`'s Controls tab (`ControlsTab`)

### Gamemode Manager

- `GamemodeManager` (`managers/gamemodes/gamemode_manager.gd`) - manages match state, coordinates level/spawn. Runs a **state machine of gamemodes**.
- **Gamemode states** (extend base `GameModeType`, whose `Kind` enum is the canonical id, live under `managers/gamemodes/types/`):
  - `FreeRoamGameMode` - open play, event circles trigger mode switches, respawn on crash. Crash respawns return you to the crash site (upright, same heading) — unless the site is steep or void, in which case you go to your last flat-ground breadcrumb (the server samples one per player on gentle ground; the ground check excludes the bike's own collider and ragdoll bones). Crashing again right after each in-place respawn `CRASH_LOOP_LIMIT` times in a row means the site itself is deadly, so the next one is a full respawn
  - Every event mode extends `RunnerGameMode` — the shared runner plumbing (chaining, dep injection, crash respawn, late-join, disconnect, results countdown). Results are built in `_on_last_runner_completed`, **before** the runner stops — `TaskRunner.stop()` clears its per-player state.
  - `RaceGameMode` - every checkpoint race; `race_type` (`RACE` / `STUNT_RACE` / `TIME_ATTACK`) fixes the standing, and everything else is a `RaceComponent` child (NPCs, traffic, scoring, challenges, pickups, time attack, leaderboard). One node per `race_type` in `main_game.tscn`. Bots keep racing through the results countdown; result rows refresh live until the timer ends
  - `TutorialGameMode` - step-by-step progression with countdown + trick detection
  - `StuntChallengeGameMode` - race through a fixed sequence of `PerformTrickTask`s, ranked by completion time
  - `LongJumpGameMode` - timed `LongJumpTask` attempts off one jump, ranked by best attempt's trick score
  - `TrickBattleGameMode` - timed free trick session, ranked by total trick score (open combo at the buzzer counts). Shares the session clock / cancel / results with Long Jump via `TimedScoreGameMode`
  - `FuelUpGameMode` - pre-race step for events with `fuel_up_first`. Each rider is teleported to a pump (`FuelUpMinigame`) in the circle's `gas_station`, assigned by sorted peer id so every peer agrees without an RPC, and frozen. Each client then plays its own pump locally: pump camera, `IN_MINIGAME` input state, `FuelUpHUDState` in place of the riding HUD. It reports its fill and spill whenever the rider ends it, and gets boost for the fill (spill shrinks the tank), plus a stunt-race bonus for a clean full tank. When every rider has reported, it hands the same event to `target_gamemode` — the one non-free-roam transition `change_gamemode()` allows out of a running mode
    - The minigame starts on the rider's `respawned` signal, not in `Enter`: the teleport's `do_respawn` flips the HUD back to riding. The pump camera is re-asserted every frame, because respawn resims re-run `CameraController.do_reset()`
    - Pump pick areas sit on their own `interactable` physics layer so the cursor ray never hits the rider's own areas
    - The pump (`FuelUpMinigame.begin()` / `end()`) owns the local session. It's also a `FreeRoamActivity`, so free roam runs it per rider from its own small start circle. See [GamemodeSystem](./GamemodeSystem.md)
  - The `Kind` enum runs ahead of the implementation — it carries reserved entries with no
    gamemode file and no state node in `main_game.tscn`. A `Kind` value is not evidence the mode
    exists; check for the type under `types/` and the node in `main_game.tscn`.
- Events run via a composable **task/runner system** (`GameModeTask` leaves + `SequentialTaskRunner` / `ConcurrentTaskRunner`), authored in level scenes as `GameModeEvent`s under an `EventStartCircle`, linking the circle's `Props` / `Spawns` / `Checkpoints` groups. See [GamemodeSystem.md](./GamemodeSystem.md)
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

### Steam Manager

- `SteamManager` (`managers/steam_manager.gd`) - GodotSteam init; the game must run without Steam (offline, Web)
- `is_logged_in()` is the gate for Steam features; each feature decides its own fallback when false
- Username: `SaveManager` swaps the placeholder username for the Steam name once at load; after that the save's username wins
- Avatars: `PlayerDefinition.steam_id` (set per session, synced as a string) lets each viewer fetch lobby-list avatars from its own Steam client. No Steam, or a non-friend → default icon
- Never reference `Steam` statically — Web uses stock templates, so it's a parse error there. Go through `steam_manager.steam`
- No `restartAppIfNecessary()`: it forces a relaunch through Steam and blocks offline play
- Lobbies: `SteamManager` owns create/join/leave (`host_lobby()` / `join_lobby()` await the Steam callback; `leave_lobby()` mid-await leaves the late lobby)
- Invites (plan A1 in `_STEAM_WORKSHOP.md`): a non-solo, logged-in host has a friends-only Steam lobby whose `game_id` data is the game code (`ConnectionManager.start_server`), left in `stop_server`. `join_requested` / `+connect_lobby` only reads the code into `pending_game_id`; main menu routes to the play menu, which joins through the normal code path. Only the STEAM transport actually joins the lobby
- Free ride hosts like Host does, but always on the Host dropdown's default transport, and the lobby menu shows no player list, so the host never waits there. Friends late-join into free roam, invited from the pause menu. Only if hosting fails does it fall back to a solo local server (`is_solo`, no lobby)

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

- `NPCRaceManager` (`managers/npc_race_manager.gd`) - owns AI race riders (`NPCRiderEntity`) on a negative-id roster (ids from -1) with spawn/despawn RPCs mirroring `SpawnManager`. `RaceGameMode`'s `NPCRacersComponent` drives its lifecycle; the server-only AI tick sets `npc.driving` while `RaceTask` has a target checkpoint for it (not on the grid, countdown or after finishing).
- Late joiners get every live bot re-sent at its current transform via `sync_npcs_to_peer(peer_id)` (from `RaceGameMode._on_player_latejoined` via `NPCRacersComponent.sync_to_peer`) — without it the newcomer has no bot nodes and takes a MultiplayerSynchronizer error per packet per bot.
- **Navmesh: two regions per race level** (`NPCNavRegion`, `levels/components/npc_nav_region.gd`). The road region (`LevelDefinition.npc_nav_region`, nav layer `UtilsConstants.NAV_LAYER_ROAD`) parses the default + `crash_collision` layers, so walls cut it. Its `exclude_layers` drops anything on `unstable_collision`: grass carries the default layer on some maps, and the parser only has an include mask, so Bake hides excluded colliders from it for the parse. The grass region (`NPCNavGrassRegion`, `NAV_LAYER_GRASS`) is the rest, with a travel cost so paths prefer road. The two regions are eroded apart, so the project's nav edge-connection margin is set wide enough to join them. Bake is a button on each region; re-bake after moving road, walls or grass.
- **Racing line** (`NPCRacingLine`). Built once per race on the server by `bake_racing_line`, called from `NPCRacersComponent.race_start`. It waits until the nav map has synced (a level loaded this frame returns empty paths), then bakes on a `WorkerThreadPool` task (about a second of navmesh queries), and a generation counter bumped on despawn drops a bake that lands after its race ended. Road-only navmesh paths are chained through the checkpoints (closed on lap routes, `RaceTask.is_lap_route`; point-to-point routes start from the grid centre, since their first checkpoint can be far up the road), Laplacian-smoothed with every point clamped back onto the road, then fit with a `Curve3D`. The navmesh's own erosion is the edge margin. Each sample keeps curvature, the corner speed that implies (`corner_grip`), and the road room either side. An unreachable checkpoint `push_error`s and is bridged straight. `dbg_racing_line` draws it.
- **Braking is per bot.** The line stores only corner speeds; each `NPCRaceState` runs `braking_profile` with its own `npc.braking` × style, so there's no shared braking knob and no two bots brake identically.
- **Driving** (`NPCRaceState`). Speed, acceleration and braking come from the bot's `bike_definition` (set at spawn). Steer at a point `steer_lookahead()` ahead on the line, shortened through bends so chasing it cuts inside by at most `max_corner_cut`, offset sideways by `_lateral` and clamped onto the whole nav map: grass allowed, walls not. Progress `_s` is tracked in a local window (`track_offset`), so a line passing near itself can't make a bot jump to the other pass. The global search runs only after a teleport (`reset_line_progress`). A bot further than `rejoin_distance` from its spot paths back over road + grass. Stuck detection → `crash_npc` as before. Lean is the existing yaw-rate lean, which is speed × curvature, so it needs nothing from the bake.
- **Anti-train** (hard requirement: the last navmesh attempt rode nose to tail):
  - **Wander.** A per-bot lateral from two seeded sines, a share (`wander_fraction`) of the road room. Wavelengths are rounded to fit the lap so there's no jump at the seam.
  - **Style.** Corner carry, braking and steering reaction rolled per bot (`style_spread`), scaled by `Difficulty`.
  - **Overtaking.** A throttled forward box scan (`intersect_shape` on `crash_collision`, areas included, because traffic only has a `ContactArea`) finds the slower rider in our offset band. The bot then commits to whichever side no other scanned rider holds, for `overtake_commit_time`, or tucks in at its speed.
  - **Mistakes.** A late brake or running wide every `mistake_interval` or so, more often on EASY.
- Accepted gap: traffic beyond `NPCTrafficManager.near_radius` of every player has its `ContactArea` off, so scans can't see it. Nobody can see that encounter either.

### Traffic Network

Ambient traffic drives a hand-placed network baked in the editor, not the road addon's lanes.
Code: `levels/components/traffic/`, plus `TrafficLaneFollower` and `JunctionState` in `entities/npc/`.

- **Why not the road addon.** Roads will change (new map, non-addon road meshes), so traffic never
  reads `RoadManager` / `RoadLane`. What counts as road is the `road` collision layer, used only by
  the bake's height snap. Authoring is placeable nodes because the Godot curve editor is the thing
  being avoided.
- **Authoring.** One `TrafficNetwork` per level parents `TrafficRoad`s and `TrafficIntersection`s.
  A road's child points in tree order are its path; `lane_count` is the total over both directions,
  so it must be even. Intersections link roads through N/E/S/W slots in their own basis
  (north = −Z, so rotating the node works), and whichever road end is nearest connects. Roads never
  link back: one source of truth. A one-slot intersection is a cul-de-sac (U-turns only, control
  ignored). A road's `traffic_weight` sets its traffic per metre relative to other roads; there are
  no one-way roads, so a quiet road is just a low weight.
- **Every problem is visible in the editor.** Config warnings on all three node types; Bake refuses
  while any exist, and after building rejects lanes clipped away or with no way out. A stale bake
  is flagged by `source_hash`. Editor drawing (debug_draw_3d) redraws only on change via
  `TrafficNetwork.request_redraw()`, never per frame — a per-frame version tanked editor FPS.
  Known bug, left alone: the preview vanishes while nothing is moving.
- **Bake** (`TrafficNetworkBaker`) saves `<level>_traffic.tres` beside the level scene; runtime reads
  only that. Lanes are offset right of travel per direction (keep right), corners rounded by
  sampling, and clipped at each intersection's box, which is the stop line. Lane-count changes
  taper the outer lanes into their neighbours. Each road lane stores its same-direction `neighbors` where it ends, for lane changes. Turn lanes are sampled beziers from stop line to
  exit, with no U-turns outside cul-de-sacs. Conflicts are marked from the horizontal proximity of
  sampled paths, except pairs sharing an entry lane (same queue); if cars clip mid-junction, raise
  the baker's vehicle width and rebake. Lane samples snap to the `road` layer with a single
  down-ray, so stacked roads (overpasses) would need a closer start height.

### NPC Traffic Manager

- `NPCTrafficManager` (`managers/npc_traffic_manager.gd`) - ambient traffic riders/cars on the level's baked `TrafficNetwork` (no node or no bake = no traffic). Ids count down from its `FIRST_ID` const, far enough below the race roster to guarantee the two id spaces never collide. Count, car/bike mix, cruise speed and vehicle rosters are per-map via `LevelDefinition.traffic_settings` (a `TrafficSettings` resource). The host's `traffic_density` setting (Settings > Gameplay) multiplies free-roam `traffic_count`; races keep `race_traffic_amount`. Saving a new density mid-session respawns traffic. Linked into free roam and both race `TrafficComponent`s; races only run it for events with `enable_traffic`. Traffic has no physics collision, so it rides through event barriers.
- **Spawn sync contract** (this is the fix for "traffic only loads for host"):
  - The server broadcasts `rpc_spawn_npc`, but clients only *accept* spawns after their own gamemode `Enter()` runs (level guaranteed loaded) — earlier broadcasts would parent riders under the outgoing level and be freed with it.
  - On `Enter()`, non-server peers call `request_traffic_sync()` to pull everything they missed (covers both the fresh-start timing race and late join); `Exit()` calls `reset_local_traffic()`.
  - Spawn/despawn RPCs are idempotent (dedupe on npc id / tolerant of missing ids), so broadcast + resync can overlap safely.
- **Rails, no physics.** The rider's `TrafficLaneFollower` is its authoritative position: `NPCTrafficState` picks a speed, the follower advances, `ride_to` places the rider. `move_and_slide` was most of the traffic cost, so traffic has no body collision at all: `collision_layer` / `mask` are zeroed on every peer (a predicting client would otherwise bump a body the server rides through), and the `ContactArea` reports hits server-side. A player has no body to bump off, so any touch from a player crashes both; rider-to-rider contact needs a relative-speed threshold so queues don't wipe out. Side effect: traffic no longer kills animals, which only listen for `body_entered`.
- **Behavior.** Corner speed, capped to stop a gap behind whatever is ahead, capped again by the junction gate. "Ahead" means on the rider's own lane path, not a forward cone, so a racer beside the lane doesn't stop it. Traffic ahead comes from a per-lane rider index (each `NPCTrafficState` moves itself between lists as its follower changes lane), walked along the latched path, so no rider sweeps the pack. Players and race bots are checked separately against the path (within the baker's vehicle width), from a non-traffic racer list the LOD pass refreshes. A rider on a merging turn lane isn't seen until it's on our lane. The follow cap assumes the rider ahead may stop dead, so a rider can always halt a queue's spacing (`EXIT_CLEARANCE`: both half lengths plus `QUEUE_GAP`) behind it. Assuming it brakes like us (v² = its v² + 2·braking·gap) let riders tailgate at any gap at matched speed, and a wreck, which stops instantly, then chain-crashed the whole queue. Forks pick a turn weighted by the exit road's `traffic_weight` (baked onto each turn lane), latched until the rider leaves that lane, so busy roads keep their traffic instead of shedding half of it at every crossroads. No go-around: a stopped player just gets queued behind (go-around was dropped; it doesn't fit rails). **Lane changes:** a blocked rider (checked on the `lane_speed` throttle) moves to a baked neighbour lane offering the same turn at the next junction when that lane's nearest rider ahead (the same `_rider_ahead`, run on the neighbour's path) is further off, nothing is beside it, and every rider behind there can still stop. The follower jumps lanes; `_lane_shift` eases the body across as it drives on. So straight-through traffic fills every lane at a light, while turns still come from the lane that offers them.
- **Junction gate** (`_gate`). Only the rider the stop line is actually slowing asks, and it claims the junction on grant, so two riders can't both see it empty (the server ticks riders sequentially). Every rider held at a green or unlit line joins `JunctionState`'s arrival queue (a red takes it out, so it can't hold up the cross street, and so does finding a rider ahead of it, or a queue member that isn't at the line deadlocks the junction). A red, an occupied conflicting turn lane, or an earlier arrival waiting on one always holds — first come first served, so a stream can't starve a crossing turn. Except right on red (amber too): after a full stop, a right turn goes if no conflicting turn is occupied or waited on by anyone; it never joins the queue, so it yields to the green rather than holding it up. Past that, `junction_timeout` breaks deadlocks the gate can't see; STOP needs only a full stop (still for `full_stop_time`), since the gate's order already lets non-conflicting turns go together; a stopped racer just past the exit waits (a spatial check instead of a lane-occupancy table).
- **Lights** are a pure function of `NetworkTime.time` (`TrafficJunctionData.light`): no Timer and no sync, every peer agrees, and far riders on coarse ticks still obey them. North/south are green together, then east/west; amber counts as stop. The `TrafficLight` prop and LevelManager's `dbg_traffic` console command read the same function. A slot's light is for traffic coming *from* that side.
- **LOD + network culling.** One radius, `near_radius`: a rider within it of any player is near. The manager ticks every rider itself (each rider's own state machine and pose restore are off): near ones every tick, far ones round-robin every `far_tick_interval`-th tick with their accumulated time, which rails make safe. An interval LOD pass applies only what changed: ContactArea, per-peer `set_visibility_for` (traffic synchronizers are private with update mode none), and host drawing. Clients spawn every rider hidden, show it on first sync and hide it when stale, so there's no client distance math and nothing renders where the server stopped updating. Every peer still spawns every rider; only the sync stream is culled. Pop-in at the edge is accepted. This came from Steam lag: GodotSteam maps unreliable to reliable, so full-rate transform sync showed up as ever-growing lag rather than drops.
- **Spawn spots + density near players.** Start-up lays spots every `SPOT_SPACING` along the road lanes; spawns and recycles pick one weighted by its lane's baked `traffic_weight`, so share is weight × length. Weighted forks alone can't hold that share: a junction's outflow equals its inflow, so the road layout evens densities out within a minute. So every LOD pass also **rebalances**: the far rider on the road lane furthest over its share (riders per metre per unit weight, against `_npcs.size() / _weighted_length`) moves to a weighted spot out of every player's view — races included, since it's invisible. Both moves pick that same worst far rider. In free roam, each LOD pass also recycles at most one far rider toward the player furthest under `TrafficSettings.near_target`: onto a clear spot within `recycle_band` beyond `near_radius` of that player, outside `near_radius` of every player, on a lane heading their way, at cruise speed. Assigning a rider's `follower` drops its junction claim and arrival, or a recycled rider leaves a ghost arrival that blocks every conflicting turn at its old junction forever. Recycled riders are already undrawn and unsynced everywhere, so they arrive by driving in — the same edge pop-in as any rider. `traffic_count` stays the total; the rest drive wherever they are. Races keep the even weighted spread. The spot filter is a linear scan per pass; swap for a grid if a network gets large.
- Crashed riders recover onto a clear lane spot after a randomized delay; while down, a bike falls on its side and a car flips onto its roof (`NPCAnimationController`, cosmetic off the synced `npc_state`); a rider that rams a player crashes them via `SpawnManager.crash_player`. No stuck recovery: riders on rails can't wedge. Known gap: recovery's random-lane fallback can still drop a rider inside a player's view; it could reuse the recycle spot filter.
- Vehicle skins ship as `res://` paths, deliberately not `PlayerDefinition.to_dict()` — that round-trips every loadout through `BikeSkinDefinition.from_dict()` per rider per peer.
- Still O(n) per call over the Racers group: `_exit_clear` (every tick while a rider waits at a stop line) and the LOD pass's racer refresh (once per interval).

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

- The replicated pose is `sync_position` + `sync_yaw`, not the node's raw transform: riders only ever turn about Y, and `teleport_to()` flattens a tilted checkpoint to yaw so server and clients agree. `sync_yaw` is listed first in the synchronizer so a packet's yaw has landed by the time the `sync_position` setter runs. The server writes the pose at the end of every movement tick (`apply_gravity_and_move()` for idle / race, `ride_to()` for traffic, which is traffic's single transform write) and on `teleport_to()`.
- Nothing renders straight off it. A body that only moves on the tick reads as stepping at render rate — the player bike doesn't, because netfox's TickInterpolator smooths it, and that gap is what this closes for NPCs. Both peers ease toward the synced pose in `_process()`, with different math because they know different things:
  - **Server** knows both ends of the step, so it interpolates exactly between the last two authoritative poses by the physics interpolation fraction. One tick of visual latency and no more, so what you see still lines up with what you collide with.
  - **Client** only ever knows the latest pose, arriving at replication rate on irregular timing, so it eases toward it exponentially. Jumps past a snap threshold (teleport / crash recovery) snap instead of sliding across the map.
- The server puts the body back on the synced pose in its own `_physics_process` before the behavior states run, so steering and `move_and_slide()` never see a smoothed pose. That restore has to land first, which is why the entity sets a negative `process_physics_priority` rather than relying on parent-before-child order alone. Traffic turns the restore off: its follower, not the node, is its position, so its reads of other racers may see a pose up to a tick behind (accepted, those scans are throttled anyway).
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

**Local netfox patch** (`addons/netfox/network-time.gd`, `_loop`, marked `DankNooner patch` —
re-apply on addon upgrade): if the tick falls more than `stall_threshold` behind the synced
clock, it snaps to it like a pause. Stock netfox only snaps on a single frame longer than
`stall_threshold`; otherwise it catches up via clock stretch and `max_ticks_per_frame`, both
slow. A late joiner whose clock sync corrects by seconds after its level load (or a run of
shorter hitches) stays behind long enough that its inputs fall out of the host's history — the
host never simulates it, never sends it state, and it resimulates the full history every frame
forever.

### Authority Summary

| Component                   | Runs On                | Authority                  |
| --------------------------- | ---------------------- | -------------------------- |
| `InputController` (capture) | Local client only      | Client                     |
| `InputController` (sync)    | Local client -> Server | Client sends, netfox syncs |
| `MovementController`        | Server only            | Server                     |
| `WobbleController`          | Server only            | Server                     |
| `GearingController`         | Server only            | Server                     |
| `TrickController`           | Server only            | Server                     |
| `CrashController`           | Server only            | Server                     |
| `AnimationController`       | Local client only      | Client (visual only)       |
| `CameraController`          | Local client only      | Client                     |
| Position/Rotation           | Server broadcasts      | Server                     |
| Lobby state                 | Server broadcasts      | Server                     |

### Terrain

Ground collision is static and identical on every peer, so it needs nothing special from the
netcode — see [Terrain & Roads](#terrain--roads) for why that constraint picked the plugin.

### Connection Modes

All modes are **server-authoritative** — the host runs physics, clients predict + reconcile. Mode only affects transport.

- **WEBRTC** *(default)*: WebRTC peer connections via a custom signaling server (`signal_relay_host`), works for both native and browser clients. Handled by `MultiplayerWebRTC`. See [LobbyGameFlowMP.md](./LobbyGameFlowMP.md)
- **IP_PORT**: Direct IP/ENet connection on `UtilsConstants.PORT`. Handled by `MultiplayerIPPort`.
  - Fetches public IP via ipify.org API (or private IP in debug)
- **STEAM**: `SteamMultiplayerPeer` over Steam's relay — no signaling or TURN server. Handled by `MultiplayerSteam`. The game code is the host's Steam lobby ID; joiners join that lobby, then connect to its owner. Steam-only: web / non-Steam players can't join a Steam host
  - Instantiated via `ClassDB` — a static `SteamMultiplayerPeer` ref won't parse on Web

The host picks the mode in the play menu (`HostModeOpt`; Steam listed first, as the default, when logged in). Joining auto-detects it from the code's format; Steam codes only validate when logged in. Free roam ignores the picker (lobby menu forces local ENet, WebRTC on web).

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
