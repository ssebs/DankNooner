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

Uses composition - `PlayerEntity` (RigidBody3D) has `@export` component references:
- `CameraController`
- `MovementController`
- `BikeDefinition` (resource with mesh/collision data)

### Multiplayer / Netcode

Uses **netfox** addon for rollback-based networking:

- **Server-authoritative**: Physics runs on server, clients predict locally
- **RollbackSynchronizer**: Per-entity sync with client-side prediction and automatic reconciliation
- **TickInterpolator**: Smooths remote player visuals between network ticks
- `MultiplayerManager` handles ENet peer connections and player spawning
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