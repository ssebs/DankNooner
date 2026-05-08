# GameModeEvent / EventStartCircle / GameModeObjective

How tutorials (and future per-mode courses like races) are authored.

## The three pieces

| Piece | Type | What it is |
| ----- | ---- | ---------- |
| `GameModeEvent` | Resource | Metadata for the event: name, description, target gamemode, countdown. No logic. |
| `EventStartCircle` | Node (Area3D) | Trigger in the world. When a player drives in, free roam offers them this event. **Also acts as the course root** — its child objectives are the steps. |
| `GameModeObjective` | Node | One step. Self-contained: holds its own `check`/`on_enter`/`on_exit`/RPCs. Subclassed per mechanic (e.g. `WheelieDurationTutorialStep`, future `RaceLapCheckpoint`). |

The previous `GameModeLesson` (Node) + `Objective` (Resource) split has been collapsed: the objective *is* the node. Subclasses can `@rpc` and `@export` whatever they need.

## Flow

1. Player enters an `EventStartCircle` in free roam → confirm HUD pops up.
2. Player confirms → `TutorialGameMode` starts, receives the start circle via `GamemodeStateContext`.
3. Tutorial reads `start_circle.start_marker` (teleport target) and `start_circle.get_objectives()` (children, in tree order).
4. Tutorial sets `_gamemode = self` on each objective (so steps can call back).
5. Per peer, walks objectives. For each: calls `objective.check(player, delta, state)` according to `eval_when`. On true → advance.
6. All peers done → results screen.

## Authoring a tutorial — `Tutorial01EventStartCircle2` example

This is the "Moto 101" course, 6 steps.

```
Tutorial01EventStartCircle2 (EventStartCircle)
├─ gamemode_event   = Resource_asds5  ("Tutorial: Moto 101", target=TUTORIAL)
├─ start_marker     = ../Stuff/Tut01Location/Tutorial01StartMarker
│
├─ CloseHelp_ShowHelp        (CloseHelpTutorialStep)
├─ SpeedAbove_PressRT        (SpeedAboveTutorialStep, min_speed=2.0)
├─ SpeedAbove_ReachSpeed     (SpeedAboveTutorialStep, min_speed=30.0 default)
├─ WheelieDuration_Wheelie   (WheelieDurationTutorialStep, duration=3.0)
├─ ChangeGear                (ChangeGearTutorialStep)
└─ StoppieDuration_Stoppie   (StoppieDurationTutorialStep, duration=1.0)
```

No `Objective` resource picker, no `GameModeLesson` wrapper. Drop a typed step node under the circle and it just works.

## Adding a new step type

1. New file in `managers/gamemodes/tutorial/steps/` extending `GameModeObjective`.
2. Override the hooks you need (`on_enter`, `check`, `on_exit`, `get_progress`, `get_objective_text`, `get_hint_text`).
3. Drop the node into a `EventStartCircle` in tree order.

That's it. No registration, no enum, no special case in the gamemode.

## Base contract

```gdscript
class_name GameModeObjective extends Node

enum EvalWhen { ALWAYS, ON_ENTER, WHILE_INSIDE }

@export var eval_when: EvalWhen = EvalWhen.ALWAYS
@export var trigger: GameModeObject  # required for ON_ENTER / WHILE_INSIDE

var _gamemode: GameMode  # injected by the gamemode on Enter

func on_enter(_player, _state) -> void
func check(_player, _delta, _state) -> bool
func on_exit(_player, _state) -> void
func get_progress(_state) -> String
func get_objective_text() -> String
func get_hint_text() -> String
```

`eval_when` controls when the gamemode evaluates the step:
- `ALWAYS` — every tick (default).
- `ON_ENTER` — one-shot, fires when the player enters `trigger`.
- `WHILE_INSIDE` — only while the player is inside `trigger`.

## Per-peer state

Per-peer scratchpad lives in `tutorial_gamemode._player_states[peer].lesson_state`. Cleared on advance and on crash. **Objective Nodes are shared across all players** — they hold no per-peer state.

Steps that need to ack from a client RPC back to the server (e.g. `CloseHelpTutorialStep`) call `_gamemode.mark_objective_state(peer_id, key, value)`.

## Cross-scene wiring

Steps live in the level scene; managers (input, menu, help) live in `main_game.tscn`. NodePath @exports can't bridge the two, so steps that need managers (`CloseHelpTutorialStep`) cast `_gamemode` to `TutorialGameMode` and pull from there. The gamemode keeps the manager `@export`s.

## Reuse across gamemodes — composition

Mechanic detection (wheelie, stoppie, speed gates) lives in the step itself for now. Once a second consumer appears (a race gate that needs the same wheelie detection), pull it into a static helper in `utils/` or `gameplay/detectors/`. Don't preemptively extract.

## How the gamemode loops differ per mode

Same base contract; the **gamemode** decides traversal:
- Tutorial: linear, advance per peer when `check()` returns true.
- Race (future): loop the checkpoint sequence N times, finish line ends the run.
- Trick combo (future): any-order completion, score-based end.
