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
- Don't remove DebugUtils.DebugMsg() debug statements
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

`PlayerEntity` (CharacterBody3D) uses composition via `@export` component references:
`InputController`, `MovementController`, `GearingController`, `TrickController`, `CrashController`, `CameraController`, `AnimationController`, `HUDController`, plus `BikeSkinDefinition` / `CharacterSkinDefinition` resources. `IKController` / `RagdollController` live under `player/characters/scripts/`.

Controllers are called sequentially from `PlayerEntity._rollback_tick()` via their `on_movement_rollback_tick()` methods. See `planning_docs/Architecture.md` for synced state vars and detailed subsystem docs.

#### Netfox + RPC Pattern

For actions needing rollback sync on `PlayerEntity`:

1. **Setter var**: `rb_<action>` (e.g. `rb_do_respawn`) — external systems set it
2. **Handler func**: `on_<action>()` — does the work
3. In `_rollback_tick()`: check setter, call handler, reset setter

### Skin System

See `planning_docs/Skins.md` for details.

### Audio & Settings

- `AudioManager` - FMOD integration, VCA volume mapping, engine sound RPM parameter
- `SettingsManager` - JSON persistence to `user://settings.json`, emits `setting_updated` / `all_settings_changed`

### Gamemode System

- `GamemodeManager` - match state, late-joiner sync, runs a state machine of gamemodes (base `GameMode` → `FreeRoamGameMode`, `StreetRaceGameMode`, `TutorialGameMode`)
- `SpawnManager` - spawn/despawn RPCs + local player instantiation
- `SaveManager` - JSON persistence of `PlayerDefinition` (username, skins, etc.)

### Multiplayer / Netcode

**Server-authoritative** using **netfox** (RollbackSynchronizer + TickInterpolator). Clients predict locally and reconcile. `ConnectionManager` supports three modes: **WebRTC** (preferred), **Noray**, and direct **IP/Port**. `LobbyManager`, `GamemodeManager`, and `SpawnManager` handle the lobby/match/spawn layers.

See `Architecture.md` for diagrams and RPC signatures.

## Project Structure

- `main_game.tscn` - root scene, composes all managers
- `managers/` - all managers (`network/`, `gamemodes/` subdirs)
- `player/` - PlayerEntity + `controllers/`
- `menus/` - menu states (main, splash, play, lobby, customize, settings, pause, help)
- `levels/` - all levels extend `LevelDefinition`
- `resources/` - `BikeSkinDefinition` / `CharacterSkinDefinition` `.tres` files
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
