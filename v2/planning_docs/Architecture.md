# Architecture / Design

> How the game works under the hood

## High Level

### Tips for me:

- [ ] Think about how to use composition in game, like x has a y. Think golang struct has a struct. I.e. dog has age/walk anim/collider handler/etc components. When something spawns in, it has a popanim component that plays,
- [ ] I don't have to write code the godot way, e.g. load/save my own files without nodes. Use until funcs
- [ ] hand write the code & plan structure. Don't import moto-poc, but re-create it using better systems
- Use spatial comments (debug notes in the level itself)

#### Debug levels

- See @level_manager's Console cmd
  - \` then `dbg_gym` to load that test level right from the main menu

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

- **LevelManager** (`managers/level_manager.gd`)
  - `LevelName` enum - defines all available levels
  - `possible_levels` - Dictionary mapping `LevelName` -> preloaded `PackedScene`
  - `level_name_map` - Dictionary mapping `LevelName` -> localization key string
  - `@export spawn_node` - Node3D where levels are instantiated

> Note - Level enum idx 0 is `LEVEL_SELECT_LABEL` (not a real level, used for dropdown default)

- **LobbyMenuState** (`menus/lobby_menu/`) - Level selection UI
  - `LevelSelectBtn` (OptionButton) - Dropdown for level selection
  - `StartBtn` - Triggers level spawn

#### Adding a New Level

1. Create level scene extending `LevelDefinition` (no need to wire `level_manager` export - it's set automatically on spawn)
2. Add entry to `LevelName` enum in `level_manager.gd`
3. Add entry to `level_name_map` (enum -> localization key)
4. Add entry to `possible_levels` (enum -> `preload("res://path/to/level.tscn")`)

### Input System

The `InputStateManager` (`managers/input_state_manager.gd`) is a centralized input handler that routes input based on the current game context.

#### Input States

```gdscript
enum InputState {
    IN_MENU,           # Player is in a menu, ESC navigates menus
    IN_GAME,           # Player is playing, ESC triggers pause
    IN_GAME_PAUSED,    # Game is paused, ESC resumes game
    DISABLED,          # All input is disabled
}
```

#### Input Routing

The InputStateManager uses `_unhandled_input()` to process events based on `current_input_state`:

- **IN_GAME**: "pause" action -> emits `pause_requested` signal
- **IN_GAME_PAUSED**: "pause" action -> emits `unpause_requested` signal
- **IN_MENU**: "ui_cancel" action -> delegates to current MenuState's `on_cancel_key_pressed()`
- **DISABLED**: Ignores all input

#### Mouse Cursor Control

Mouse visibility is managed based on input state:

- **IN_MENU** or **IN_GAME_PAUSED**: Mouse visible (`MOUSE_MODE_VISIBLE`)
- **IN_GAME** or **DISABLED**: Mouse captured (`MOUSE_MODE_CAPTURED`)

#### Signals

- `input_state_changed(new_state: InputState)` - Fired when state changes
- `pause_requested` - Fired when player wants to pause (IN_GAME + pause action)
- `unpause_requested` - Fired when player wants to resume (IN_GAME_PAUSED + pause action)

### Player Entity

`PlayerEntity` is a `CharacterBody3D` using composition with `@export` component references. All controllers are called sequentially from `_rollback_tick()` via their `on_movement_rollback_tick()` methods.

For detailed design docs see:

- [PlayerController.md](./PlayerController.md) - movement, gearing, tricks, crash subsystems
- [AnimationController.md](./AnimationController.md) - procedural animation, IK, ragdoll

#### Component Controllers

| Controller            | File                                  | Purpose                                                 |
| --------------------- | ------------------------------------- | ------------------------------------------------------- |
| `InputController`     | `controllers/input_controller.gd`     | Gathers input, syncs via RollbackSynchronizer           |
| `MovementController`  | `controllers/movement_controller.gd`  | Physics-based movement, speed, steering, lean, velocity |
| `GearingController`   | `controllers/gearing_controller.gd`   | Clutch engagement, RPM blending, power output           |
| `TrickController`     | `controllers/trick_controller.gd`     | Detects wheelie/stoppie, updates pitch_angle            |
| `CrashController`     | `controllers/crash_controller.gd`     | Brake grab detection, crash detection, auto-respawn     |
| `CameraController`    | `controllers/camera_controller.gd`    | FPS/TPS camera switching                                |
| `AnimationController` | `controllers/animation_controller.gd` | Procedural animation blending, IK, ragdoll              |

#### Synced State (via RollbackSynchronizer)

- **Physics**: `speed`, `lean_angle`, `pitch_angle`, `fishtail_angle`, `ground_pitch`
- **Gearing**: `current_gear`, `current_rpm`, `clutch_value`, `rpm_ratio`
- **Tricks**: `is_boosting`, `boost_count`
- **Crashes**: `is_crashed`
- **Discrete actions**: `rb_do_respawn`, `rb_gear_up`, `rb_gear_down` (uses rollback pattern)

#### GearingController

- Tracks clutch engagement (0-1), blends between throttle-driven and wheel-driven RPM
- Gear shifts via `rb_gear_up` / `rb_gear_down` discrete actions on PlayerEntity
- Power output = throttle x power_curve x torque_multiplier x engagement
- Gear ratios, max_rpm, idle_rpm, stall_rpm are defined in `BikeSkinDefinition`

#### TrickController

```gdscript
enum TrickState { NONE, WHEELIE_SITTING, WHEELIE_MOD, STOPPIE }
```

- Detects tricks via `pitch_angle` threshold checks against bike definition limits
- Wheelie: RPM + throttle + lean detection + clutch-kick window (0.4s)
- Stoppie: Front brake + forward lean
- Emits `trick_started`, `trick_ended` signals
- Auto-balances pitch on ground with `move_toward()` smoothing

#### CrashController

Monitors for crash conditions:

- Lean angle > 80 degrees
- Pitch angle > max_wheelie_angle_deg or < -max_stoppie_angle_deg
- Brake grab while turning (rapid brake engage + lean > 15 degrees)

`trigger_crash()` sets `is_crashed = true`, starts ragdoll, 3s auto-respawn timer.

#### AnimationController

```gdscript
enum RiderState { RIDING, IDLE, TRICK, RAGDOLL }
```

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

- `AudioManager` (`managers/audio_manager.gd`) - FMOD integration
- Maps settings keys to VCA paths (e.g. `"master_vol"` → `"MASTER"`)
- `update_ninja500_rpm(rpm_ratio)` - sets RPM parameter for seamless engine sound looping
- Listens to `SettingsManager.setting_updated` to sync VCA volumes

### Settings Manager

- `SettingsManager` (`managers/settings_manager.gd`) - JSON persistence to `user://settings.json`
- Default settings: username, noray_relay_host, resolution, fullscreen_mode, master_vol, music_vol, menu_vol, sfx_vol, bike_skin, character_skin
- Signals: `setting_updated(key, value)`, `all_settings_changed(dict)`
- Used by AudioManager (volume), ConnectionManager (noray host), CustomizeMenuState (skins)

### Gamemode Manager

- `GamemodeManager` (`managers/gamemodes/gamemode_manager.gd`) - manages match state, coordinates level/spawn
- RPCs for multiplayer sync:
  - `start_game(level_name)` - server calls on all peers
  - `_sync_game_to_late_joiner(level_name)` - sync level to late-joining client
  - `_request_late_spawn(peer_id)` - late-joiner requests their player spawn

### Spawn Manager

- `SpawnManager` (`managers/spawn_manager.gd`) - player spawning/despawning
- RPCs:
  - `rpc_spawn_player(peer_id, player_def_dict)` - spawn broadcast
  - `rpc_despawn_player(peer_id)` - despawn broadcast
  - `respawn_player(peer_id)` - server respawns a specific player
- Local helpers: `add_player_locally()`, `remove_player_locally()`, `spawn_all_players()`

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

```mermaid
sequenceDiagram
    participant C as Client (Local)
    participant S as Server (Host)
    participant O as Other Clients

    Note over C: Frame N
    C->>C: Capture input locally
    C->>C: Apply input (prediction)
    C->>S: send_input.rpc_id(1, input_state)

    Note over S: Server processes
    S->>S: Receive input for player
    S->>S: Apply input to player entity
    S->>S: Run physics (authoritative)

    Note over S,O: Broadcast state
    S-->>C: Position/rotation sync
    S-->>O: Position/rotation sync

    Note over C: Reconciliation
    C->>C: Compare server state vs prediction
    C->>C: Correct if mismatch (netfox rollback)
```

### What Runs Where

```mermaid
flowchart LR
    subgraph Client["Client (Each Player)"]
        IC[InputController]
        Predict[Local Prediction]
        Cam[CameraController]
    end

    subgraph Server["Server (Host)"]
        MC[MovementController]
        Physics[Authoritative Physics]
        Sync[State Broadcast]
    end

    IC -->|"send_input.rpc_id(1)"| MC
    IC --> Predict
    MC --> Physics
    Physics --> Sync
    Sync -->|"MultiplayerSynchronizer"| Client
```

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

### Connection Modes

- **NORAY**: Uses netfox.noray addon for NAT punch-through + relay fallback
  - `Noray.connect_to_host()`, `Noray.register_host()`, `Noray.register_remote()`
  - OID = Object ID (21-char string) used as invite code
- **IP_PORT**: Direct IP connection to port 42068
  - Fetches public IP via ipify.org API (or private IP in debug)

### RPC Signatures

**InputController** - Client -> Server (synced via RollbackSynchronizer):

Input is gathered locally by `InputController._gather()` and synced automatically by netfox's `RollbackSynchronizer`. No manual RPC needed - netfox handles input sync and rollback.

**LobbyManager** RPCs:

- `update_player_metadata(peer_id, player_def_dict)` - client sends PlayerDefinition to server
- `_sync_lobby_players(players_dict)` - server broadcasts full lobby dict

**GamemodeManager** RPCs:

- `start_game(level_name)` - server calls on all peers
- `_sync_game_to_late_joiner(level_name)` - sync level to late-joining client
- `_request_late_spawn(peer_id)` - late-joiner requests their player spawn

**SpawnManager** RPCs:

- `rpc_spawn_player(peer_id, player_def_dict)` - spawn broadcast
- `rpc_despawn_player(peer_id)` - despawn broadcast
- `respawn_player(peer_id)` - server respawns a specific player

### Deployment / builds

- Godot 4.6+ is required
- FMOD is required
  - Use File > build before it can be used in game
- Deploying new version
  - Run `./deploy-version.sh` (any OS) to create a new version tag & push to github to run CI
  - See [build.yml](../../.github/workflows/build.yml)
