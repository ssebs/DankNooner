# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DankNooner is a multiplayer motorcycle stunt game built in Godot 4.6 (GDScript). The project is in active development with Claude assisting on planning and implementation.

**Source of Truth**: Always review `./planning_docs/Architecture.md` for current system designs and implementation details. The TODO.md in the same folder tracks active work.

## Working Style

- Don't always jump to coding first - help plan and design systems before implementation
- Be concise in responses
- Don't take the folder structure too seriously - it's flexible
- Use spatial comments (debug notes in levels) for in-world documentation
- Don't remove TODO comments unless you're implementing the whole system.

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

`InputManager` routes input based on `InputState` enum (IN_MENU, IN_GAME, IN_GAME_PAUSED, DISABLED).

### Player Entity

Uses composition - `PlayerEntity` has `@export` component references:

- `CameraController` - camera follow/control
- `MovementController` - handles physics-based movement
- `BikeDefinition` - resource with mesh/collision data
- `MeshComponent` - renders the bike mesh

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

### Multiplayer / Netcode

Uses **netfox** addon with **Noray** for NAT traversal:

- **Server-authoritative**: Physics runs on server, clients predict locally
- **RollbackSynchronizer**: Per-entity sync with client-side prediction and automatic reconciliation
- **TickInterpolator**: Smooths remote player visuals between network ticks
- **Noray**: NAT punch-through with relay fallback for peer connections
- `MultiplayerManager` handles ENet peer connections via Noray
- `LevelManager.spawn_players()` spawns player entities when level loads
- Input flows: Client captures → RPC to server → Server applies → Broadcasts state

See `Architecture.md` for detailed diagrams and RPC signatures.

## Code Style

- Use `@tool` for editor scripts
- Use `@export` for inspector wiring between managers/states
- Use `@onready var x: Type = %UniqueName` for internal node refs
- Use `_get_configuration_warnings()` to validate required exports
- Group constants in `utils/constants.gd`
- Localization strings in `localization/localization.csv`, access via `tr("KEY")`
- Use context clues in the file you're working on if possible
