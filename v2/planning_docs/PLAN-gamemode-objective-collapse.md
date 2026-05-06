# PLAN — Collapse Objective + GameModeLesson into GameModeObjective

## Why

`tutorial_gamemode.gd` is bloated and only 1 of ~4 tutorials exists. The current shape (Resource `Objective` + Node `GameModeLesson` + special-cased RPCs in the gamemode) is too coupled to scale to race / trick modes.

Root cause: `Objective` is a `Resource`, so it can't host RPCs. Anything peer-local (open a help menu, push UI on one peer, ack back to server) leaks into the gamemode. `CloseHelpObjective` is the proof — its logic lives across three files.

Goal: each step is a single self-contained Node. Drop it under an `EventStartCircle`, the gamemode walks children. No special cases.

## The shape

One base, typed subclasses per mechanic.

```
GameModeObjective (Node)            ← base contract
├─ CloseHelpTutorialStep            ← owns its RPC + UI hookup
├─ SpeedAboveTutorialStep
├─ WheelieDurationTutorialStep
├─ StoppieDurationTutorialStep
├─ ChangeGearTutorialStep
│
├─ RaceLapCheckpoint                ← future
├─ RaceFinishLine                   ← future
└─ TrickTargetObjective             ← future
```

Authoring:

```
Tutorial01EventStartCircle (EventStartCircle)
├─ start_marker = ../Tut01StartMarker
├─ CloseHelpTutorialStep
├─ SpeedAboveTutorialStep      (min_speed = 2.0)
├─ SpeedAboveTutorialStep      (min_speed = 30.0)
├─ WheelieDurationTutorialStep (duration = 3.0)
├─ ChangeGearTutorialStep
└─ StoppieDurationTutorialStep (duration = 1.0)
```

No `Objective` resource picker. No `GameModeLesson` wrapper. The Node *is* the step.

## Base contract

```gdscript
@tool
class_name GameModeObjective extends Node

enum EvalWhen { ALWAYS, ON_ENTER, WHILE_INSIDE }

@export var eval_when: EvalWhen = EvalWhen.ALWAYS
@export var trigger: GameModeObject  # required for ON_ENTER / WHILE_INSIDE

func on_enter(_player: PlayerEntity, _state: Dictionary) -> void: pass
func check(_player: PlayerEntity, _delta: float, _state: Dictionary) -> bool: return false
func on_exit(_player: PlayerEntity, _state: Dictionary) -> void: pass
func get_progress(_state: Dictionary) -> String: return ""
func get_objective_text() -> String: return ""
func get_hint_text() -> String: return ""
```

That's the whole API. Same hooks as today, just on a Node so subclasses can `@rpc` and `@export` managers directly.

## State ownership stays with the gamemode

Per-peer `lesson_state: Dictionary` lives in `tutorial_gamemode._player_states[peer]`. Cleared on advance and on crash. **Objective Nodes are shared across all players** — they hold no per-peer state.

## How `CloseHelpTutorialStep` becomes self-contained

It's a Node, so it can hold its own RPCs and `@export` the managers it needs.

```gdscript
@tool
class_name CloseHelpTutorialStep extends GameModeObjective

@export var input_state_manager: InputStateManager
@export var menu_manager: MenuManager
@export var help_menu_state: HelpMenuState
@export var spawn_manager: SpawnManager

func on_enter(_player, state):
    state["closed"] = false
    var peer_id := int(_player.name)
    _rpc_show_help.rpc_id(peer_id)

func check(_player, _delta, state) -> bool:
    return state.get("closed", false)

@rpc("call_local", "reliable")
func _rpc_show_help(): ...                   # local UI work

func _on_help_closed(): ...                  # local cleanup, then ack server
    _rpc_help_closed.rpc_id(1, multiplayer.get_unique_id())

@rpc("any_peer", "reliable")
func _rpc_help_closed(peer_id: int):
    # tells the gamemode to set state["closed"] = true for that peer's lesson_state
```

The objective writes back into the gamemode's per-peer state via a small callback the gamemode hands to active objectives, OR the gamemode keeps a thin `mark_event(peer_id, key, value)` helper. Either works. Pick whichever reads cleaner during impl — bias to whichever needs *fewer* lines.

What `tutorial_gamemode.gd` loses:
- `if objective is CloseHelpObjective` special case.
- `input_state_manager`, `menu_manager`, `help_menu_state` exports.
- Entire `#region Help menu (per-player)` (~40 lines).

## Reuse across gamemodes — composition, not inheritance

Mechanic detection (wheelie, stoppie, speed gates) goes into **static helpers** in `utils/` or `gameplay/detectors/`:

```gdscript
class_name WheelieDetector
static func tick(player, state, duration) -> bool: ...
```

`WheelieDurationTutorialStep` and a future `WheelieRaceGate` both call `WheelieDetector.tick(...)`. Shared rule, no shared parent. This is what we *thought* we wanted from reusable Resource Objectives — composition via helpers gets us there with less surface area.

## Trigger wiring stays on the gamemode (for now)

The existing `_wire_lesson_signals` / `_on_trigger_entered/exited` loop still works — just iterates `_objectives` instead of `_lessons`. Each objective with `eval_when != ALWAYS` declares its `trigger`; the gamemode connects once and routes by peer. Don't pull this into the objective until a non-tutorial mode actually forces it.

## How the gamemode loops differ per mode

The base contract is the same; the **gamemode** decides traversal:
- Tutorial: linear, advance per peer when `check()` returns true. (current behavior)
- Race: loop the checkpoint sequence N times per peer, finish line ends the run.
- Trick combo: any-order completion, score-based end condition.

EventStartCircle just hands the gamemode `get_objectives()` (children in tree order). Interpretation is the gamemode's job. Don't generalize this until we have a second consumer.

## Migration steps

1. Create `levels/components/game_mode_objective.gd` (Node base). Move `eval_when` enum + `trigger` export here.
2. Port each existing `*_objective.gd` (Resource) into a `*_tutorial_step.gd` (Node extends `GameModeObjective`).
3. Move help-menu RPCs and exports out of `tutorial_gamemode.gd` into `CloseHelpTutorialStep`. Add a tiny `mark_objective_state(peer_id, key, value)` helper on the gamemode for the ack path (or pass a Callable into `on_enter` — choose during impl).
4. Update `EventStartCircle.get_lessons()` → `get_objectives()`. Return `Array[GameModeObjective]` of children in tree order.
5. Update `tutorial_gamemode.gd`:
   - Rename `_lessons` → `_objectives`, `lesson` local vars likewise.
   - Drop `objective.X` indirection — call directly on the node.
   - Delete `is CloseHelpObjective` branch and the help-menu region.
6. Update `Tutorial01EventStartCircle2` in `levels/test_levels/test_city_01/test_city_01.tscn`:
   - Replace `GameModeLesson` children with the new typed step nodes.
   - Wire help-menu exports on the `CloseHelpTutorialStep` instance.
7. Delete:
   - `levels/components/objective.gd`
   - `levels/components/game_mode_lesson.gd`
   - `managers/gamemodes/tutorial/objectives/` (whole folder)
8. Replace `planning_docs/GamemodeEventAndGameModeLessonAndTutorial.md` with the new (shorter) doc reflecting the collapsed shape.

## Non-goals

- Don't generalize the gamemode's child-traversal until race forces it.
- Don't move trigger wiring onto objectives until something actually needs it.
- Don't introduce a registry, factory, or enum of step types. Tree-order children are enough.
- Don't add per-mode base classes (`TutorialObjective`, `RaceObjective`). Subclass `GameModeObjective` directly.

## Success check

- `tutorial_gamemode.gd` is shorter (target: < 350 lines, currently ~488).
- Adding a new tutorial step = one new `.gd` file + drop-in node. No registration, no enum, no special case in the gamemode.
- `CloseHelpTutorialStep` is a single file containing all of its behavior.
