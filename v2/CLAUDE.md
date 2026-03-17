# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DankNooner is a multiplayer motorcycle stunt game built in Godot 4.6 (GDScript). The project is in active development with Claude assisting on planning and implementation.

**Source of Truth**: Always review `./planning_docs/Architecture.md` for current system designs and implementation details. The TODO.md in the same folder tracks active work.

Use haiku subagents when searching files

## Working Style

- Don't always jump to coding first - help plan and design systems before implementation
- Be concise in responses
- Don't take the folder structure too seriously - it's flexible
- Use spatial comments (debug notes in levels) for in-world documentation
- Don't remove TODO comments unless you're implementing the whole system.
- Don't remove print() debug statements
- Don't run `gh` or `git` commands

## Running the Project

- Only have the human run the project

## Core Architecture

### Manager Pattern

All systems use a **Manager + State Machine** pattern:

- `ManagerManager` - root node, wires signals between all managers
- Managers extend `BaseManager`, belong to "Managers" group
- Each manager can have a `StateMachine` with child `State` nodes

### State Machine

- States emit `transitioned` signal or call `request_state_change()` to transition
- Pass typed data via `StateContext` subclasses (see `lobby_state_context.gd`)
- Connect signals in `Enter()`, disconnect in `Exit()`

### Menu System

MenuStates extend `State` and must have a `%UI` Control node (unique name).

Pattern: `@export` navigation targets and managers, wire in inspector.

### Level System

- `LevelManager` has `LevelName` enum, `possible_levels` dict (enum → PackedScene), `level_name_map` dict (enum → localization key)
- Levels extend `LevelDefinition`
- Adding a level: add to enum, both dicts, create scene

### Input System

`InputStateManager` routes input based on `InputState` enum (IN_MENU, IN_GAME, IN_GAME_PAUSED, DISABLED).

### Player Entity

Uses composition - `PlayerEntity` (CharacterBody3D) has `@export` component references:

- `InputController` - gathers input, syncs via RollbackSynchronizer
- `MovementController` - physics-based movement, speed, steering, lean
- `GearingController` - clutch engagement, RPM blending, power output
- `TrickController` - detects wheelie/stoppie, updates pitch_angle
- `CrashController` - brake grab detection, crash detection, auto-respawn
- `CameraController` - FPS/TPS camera switching
- `AnimationController` - procedural animation blending, IK, ragdoll
- `BikeSkinDefinition` - resource with mesh/collision/gearing/physics data
- `CharacterSkinDefinition` - resource with character mesh/colors

All controllers are called sequentially from `PlayerEntity._rollback_tick()` via their `on_movement_rollback_tick()` methods.

#### Netfox + RPC Pattern

For actions that need rollback sync (called via RPC), use this pattern in `PlayerEntity`:

1. **Setter var**: `var rb_<action>: bool = false` (e.g., `rb_do_respawn`)
2. **Handler func**: `func on_<action>():` containing the actual logic
3. **In `_rollback_tick()`**: Check the setter, call handler, reset setter

```gdscript
# Setter var
var rb_do_respawn: bool = false

# Handler in _rollback_tick
func _rollback_tick(_delta: float, _tick: int, _is_fresh: bool):
    if rb_do_respawn:
        on_respawn()
        rb_do_respawn = false

# Handler func
func on_respawn():
    global_transform = get_parent().global_transform
    velocity = Vector3.ZERO
    # ... reset other state
```

External systems set the `rb_*` var; netfox handles sync and rollback automatically.

### Skin System

See `planning_docs/Skins.md` for details.

### Audio & Settings

- `AudioManager` - FMOD integration, VCA volume mapping, engine sound RPM parameter
- `SettingsManager` - JSON persistence to `user://settings.json`, emits `setting_updated` / `all_settings_changed`

### Gamemode System

- `GamemodeManager` - manages match state, late-joiner sync, coordinates level/spawn
- `SpawnManager` - spawn/despawn RPCs + local player instantiation

### Multiplayer / Netcode

Uses **netfox** addon with **Noray** for NAT traversal:

- **Server-authoritative**: Physics runs on server, clients predict locally
- **RollbackSynchronizer**: Per-entity sync with client-side prediction and automatic reconciliation
- **TickInterpolator**: Smooths remote player visuals between network ticks
- **Noray**: NAT punch-through with relay fallback for peer connections
- **IP/Port mode**: Direct connection alternative to Noray (port 42068)
- `ConnectionManager` handles ENet peer connections via Noray or IP/Port
- `LobbyManager` handles lobby_players dict and PlayerDefinition sync
- `GamemodeManager` coordinates match state and late-joiner sync
- `SpawnManager` handles player spawning/despawning via RPCs
- Input flows: Client captures → RPC to server → Server applies → Broadcasts state

See `Architecture.md` for detailed diagrams and RPC signatures.

## Project Structure

- `main_game.tscn` - root scene, composes all managers
- `managers/` - all managers (`network/`, `gamemodes/` subdirs)
- `entities/player/` - PlayerEntity + `controllers/`
- `menus/out_of_game/` - pre-game menus (lobby, customize, settings)
- `menus/in_game/` - in-game overlays (pause, respawn)
- `levels/` - all levels extend `LevelDefinition`
- `resources/entities/` - `BikeSkinDefinition` / `CharacterSkinDefinition` `.tres` files
- `utils/state_machine/` - base `State`, `StateMachine`, `StateContext` classes
- `utils/constants.gd` - global constants/enums
- `planning_docs/` - `Architecture.md` (source of truth), `TODO.md`

## Code Style

- Use `@tool` for editor scripts
- Use `@export` for inspector wiring between managers/states
- Use `@onready var x: Type = %UniqueName` for internal node refs
- Use `_get_configuration_warnings()` to validate required exports — if the file already has it, add your checks there
- Group constants in `utils/constants.gd`
- Localization strings in `localization/localization.csv`, access via `tr("KEY")`
- Use context clues in the file you're working on if possible
- Reuse existing code, signals, and patterns before adding new ones. Check what's already available in the codebase — new methods, exports, or helpers should be a  
  last resort.

### Fail Loudly — No Silent Null Returns

**Do not guard against null with early returns.** Code like this hides bugs:

```gdscript
# BAD - silently does nothing if player is missing
var player := _get_player_by_peer_id(peer_id)
if player == null:
    return
player.do_thing()
```

Instead, call directly and let Godot crash with a real error:

```gdscript
# GOOD - crashes immediately with a clear null reference error
_get_player_by_peer_id(peer_id).do_thing()
```

If null is truly expected/valid, add a comment explaining why:

```gdscript
# Player may not be spawned yet during late-join sync — skip is intentional
var player := _get_player_by_peer_id(peer_id)
if player == null:
    return
```
