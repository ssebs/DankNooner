# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

DankNooner is a multiplayer motorcycle stunt game built in Godot 4.7 (GDScript). The project is in active development with Claude assisting on planning and implementation.

**Source of Truth**: Always review `./planning_docs/Architecture.md` for current system designs and implementation details. The TODO.md in the same folder tracks active work. Other .md files in planning_docs/ will explain how various systems work.

**Intent**: This project is a portfolio-quality highlight of my SWE work. Code quality is a
deliverable, not overhead. "AI slop" — code I can't read or didn't write — is a velocity
problem, not just a pride problem: prioritize it accordingly. Reducing scope is always a valid
answer. Prefer deleting over adding.

## Working Style

- Don't always jump to coding first - help plan and design systems before implementation
- Be CONCISE in responses
- Don't take the folder structure too seriously - it's flexible
- Use spatial comments (debug notes in levels) for in-world documentation
- Don't remove TODO comments unless you're implementing the whole system.
- Use `DebugUtils.DebugMsg()` for debug/print statements
- Don't run `gh` or `git` commands
- Follow existing patterns, do not add duplicate logic that is found in another file / controller.
- Do NOT GUESS, VERIFY BY READING EXISTING CODE.
- Verify TODO/doc claims against the code before acting on them — many are stale.
- Answer the question that was asked. "How would you X" means propose, then stop.
- Don't produce artifacts — new files, rewritten docs, full plans — unless asked.
- One question at a time when checking direction, not a batch.

### planning_docs/TODO.md

- The user owns this file. Don't edit without an explicit instruction to.
- The fat `## Done ✅` section stays. It's history, not clutter.
- Tight lists throughout — no blank lines between items or before nested children.
- Links to plan docs are often stale (several point at deleted files). Verify before citing.

## Running the Project

- Only have the human run the project
- After completing changes with any `.gd` files, verify it lints clean against `.gdlintrc` before reporting done. Fix any reported problems (e.g. class-definitions-order)

## Patterns

> Conventions for writing new code. **System inventories belong in `planning_docs/`, not here** —
> a fact duplicated in both files is a fact that will disagree with itself.

### Manager Pattern

All systems use a **Manager + State Machine** pattern:

- `ManagerManager` - root node, wires signals between all managers
- Managers extend `BaseManager`
- Each manager can have a `StateMachine` with child `State` nodes

### State Machine

- States emit `transitioned` signal or call `request_state_change()` to transition
- Pass typed data via `StateContext` subclasses (ex: `lobby_state_context.gd`)
- Connect signals in `Enter()`, disconnect in `Exit()`

### Menu System

MenuStates extend `State` and must have a `%UI` Control node (unique name).

Pattern: `@export` navigation targets and managers, wire in inspector.

### Level System

Levels extend `LevelDefinition`. Adding one: add to `LevelManager`'s `LevelName` enum, then to
both dicts (`possible_levels`, `level_name_map`), then create the scene.

### Player Entity

`PlayerEntity` (CharacterBody3D) is composed of controllers wired in `player_entity.tscn`.
Simulation controllers implement `on_movement_rollback_tick()` and run in `_rollback_tick()`
(order is load-bearing); visual/local ones run in `_process()` and must never write simulation
state. See [Architecture — Player Entity](./planning_docs/Architecture.md#player-entity).

#### Netfox + RPC Pattern

For actions needing rollback sync on `PlayerEntity`:

1. **Setter var**: `rb_<action>` (e.g. `rb_do_respawn`) — external systems set it
2. **Handler func**: `on_<action>()` — does the work
3. In `_rollback_tick()`: check setter, call handler, reset setter

### Gamemodes

Gamemodes are `State`s extending `GameModeType`, run by `GamemodeManager`'s state machine.
In-mode events are composed from `GameModeTask` leaves under a `TaskRunner`, authored in the
level scene rather than in code. See [GamemodeSystem](./planning_docs/GamemodeSystem.md).

### Multiplayer / Netcode

**Server-authoritative** via **netfox** — the host simulates, clients predict and reconcile.
Never hand-roll an input RPC; register the property on the `RollbackSynchronizer` instead. Every
var mutated inside the rollback tick that affects simulation **must** be a state property —
resimulation cannot rewind what netfox doesn't record.

Client-callable RPCs get a `request_*` entry point that derives the target from the sender.
Broadcast RPCs are server-only and must reject non-server senders. See
[Architecture — Multiplayer Networking](./planning_docs/Architecture.md#multiplayer-networking-architecture).

## Planning Docs

`planning_docs/` is the source of truth for how systems actually work. Files prefixed `__` are
archived — ignore them.

- [Architecture](./planning_docs/Architecture.md) — **start here**; every system, how they wire together
- [TODO](./planning_docs/TODO.md) — active work (user owns this file, see rules above)
- [Goals4Game](./planning_docs/Goals4Game.md) — MVP scope and requirements
- [PlayerController](./planning_docs/PlayerController.md) — physics, gearbox, crash, tricks, rollback
- [AnimationController](./planning_docs/AnimationController.md) — pose pipeline, procedural animation, IK, ragdoll
- [ComboAndBoost](./planning_docs/ComboAndBoost.md) — trick combos, boost economy, scoring, tunables
- [GamemodeSystem](./planning_docs/GamemodeSystem.md) — gamemode taxonomy, task/runner system
- [LobbyGameFlowMP](./planning_docs/LobbyGameFlowMP.md) — host/join through game start
- [Skins](./planning_docs/Skins.md) — slot-based color customization, bike/character definitions
- [AudioMiddleware](./planning_docs/AudioMiddleware.md) — the FMOD replacement, buses, engine sound
- [Levels](./planning_docs/Levels.md) — stub
- [Debugging](./planning_docs/Debugging.md) — VSCode integration
- [Story](./planning_docs/Story.md) / [Marketing](./planning_docs/Marketing.md) — narrative and launch notes

## Project Structure

- `main_game.tscn` - root scene, composes all managers
- `managers/` - all managers (`network/`, `gamemodes/` subdirs)
- `player/` - PlayerEntity + `controllers/`
- `menus/` - menu states (main, splash, play, lobby, customize, settings, pause, help, loading)
- `levels/` - all levels extend `LevelDefinition`
- `entities/` - non-player entities (`NPCRiderEntity` + its state machine, `NPCAnimalEntity`, `NPCAnimationController`, `TrafficRouteGraph`, `vehicles/`, `vfx/`)
- `resources/` - `BikeSkinDefinition` / `CharacterSkinDefinition` `.tres` files
- `utils/state_machine/` - base `State`, `StateMachine`, `StateContext` classes
- `utils/constants.gd` - global constants/enums
- `planning_docs/` - Many relevant docs

## Code Style

- Use `@tool` for editor scripts
- Use `@export` for inspector wiring between managers/states, esp in composed nodes
- Use `@onready var x: Type = %UniqueName` for internal node refs
- Use `_get_configuration_warnings()` to validate required exports — if the file already has it, add your checks there
- Group constants in `utils/constants.gd`
- Localization strings in `localization/localization.csv`, access via `tr("KEY")`
- Use context clues in the file you're working on if possible
- IMPORTANT:
  - Reuse existing code, signals, and patterns before adding new ones
  - Check what's already available in the codebase
  - New methods, exports, or helpers should be a last resort

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

# Always Apply

Behavioral guidelines to reduce common LLM coding mistakes. These are not optional — see
**Intent** above. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
