# GameModeEvent / EventStartCircle / GameModeObjective

How tutorials (and future per-mode courses like races) are authored.

## The shape

Three pieces, all simple:

| Piece               | Type          | Role                                                                                                           |
| ------------------- | ------------- | -------------------------------------------------------------------------------------------------------------- |
| `GameModeEvent`     | Resource      | Metadata only — name, description, target gamemode. No logic.                                                  |
| `EventStartCircle`  | Node (Area3D) | World trigger that offers the event in free roam. **Also the course root** — its child nodes are the steps.    |
| `GameModeObjective` | Node          | One step. Self-contained: own `check`/`on_enter`/`on_exit`, own RPCs, own `@export`s. Subclassed per mechanic. |

The previous split (`Objective` Resource + `GameModeLesson` Node wrapper) is gone. The objective *is* the node, so subclasses can `@rpc` and `@export` whatever they need without leaking logic into the gamemode.

## Authoring a course

Drop typed objective nodes under an `EventStartCircle` in tree order. That's it — no registration, no enum, no factory.

```
Tutorial01EventStartCircle (EventStartCircle)
├─ gamemode_event = "Moto 101"   (GameModeEvent resource, target=TUTORIAL)
├─ start_marker   = ../Tut01StartMarker
│
├─ Countdown                 (CountdownTutorialStep, seconds=3.0)
├─ CloseHelp_ShowHelp        (CloseHelpTutorialStep)
├─ SpeedAbove_PressRT        (SpeedAboveTutorialStep, min_speed=2.0)
├─ SpeedAbove_ReachSpeed     (SpeedAboveTutorialStep, min_speed=30.0)
├─ WheelieDuration_Wheelie   (WheelieDurationTutorialStep, duration=3.0)
├─ ChangeGear                (ChangeGearTutorialStep)
└─ StoppieDuration_Stoppie   (StoppieDurationTutorialStep, duration=1.0)
```

Some objectives (`CountdownTutorialStep`, `TeleportTutorialStep`) are mode-agnostic — usable from race / trick courses too. The `*TutorialStep` class-name suffix is historical, not a constraint, and should be cleaned up.

## Adding a new step type

1. New file in `managers/gamemodes/gamemode_objectives/` (named `*_obj.gd`) extending `GameModeObjective`.
2. Override the hooks you need (`on_enter`, `check`, `on_exit`, `get_progress`, `get_objective_text`, `get_hint_text`).
3. Drop the node into an `EventStartCircle` in tree order.

No registration, no enum, no special case in the gamemode.

## Base contract

`managers/gamemodes/gamemode_objectives/gamemode_objective.gd`:

```gdscript
class_name GameModeObjective extends Node

enum EvalWhen { ALWAYS, ON_ENTER, WHILE_INSIDE }

@export var eval_when: EvalWhen = EvalWhen.ALWAYS
@export var trigger: GameModeObject  # required for ON_ENTER / WHILE_INSIDE

var _gamemode: GameMode  # injected by the gamemode on Enter

func on_enter(player, state) -> void
func check(player, delta, state) -> bool   # true = advance
func on_exit(player, state) -> void
func get_progress(state) -> String
func get_objective_text() -> String
func get_hint_text() -> String
```

`eval_when` controls when the gamemode evaluates the step:
- `ALWAYS` — every tick (default).
- `ON_ENTER` — one-shot, fires when the player enters `trigger`.
- `WHILE_INSIDE` — only while the player is inside `trigger`.

## Flow

1. Player drives into an `EventStartCircle` in free roam → confirm HUD pops up.
2. Player confirms → `TutorialGameMode` starts with the circle in `GamemodeStateContext`.
3. Gamemode reads `start_circle.start_marker` (teleport target) and `start_circle.get_objectives()` (children, in tree order).
4. Gamemode injects `_gamemode = self` on each objective so steps can call back.
5. Per peer, walks objectives sequentially. For each: `on_enter` → tick `check` per `eval_when` rules → `on_exit` → advance.
6. All peers done → results screen.

## Per-peer state

Objective Nodes are **shared across all players** — they hold no per-peer state. The scratchpad lives in `tutorial_gamemode._player_states[peer].lesson_state` and is passed into each hook as `state`. Cleared on advance and on crash.

Steps that need to ack from a client RPC back to server state call `_gamemode.mark_objective_state(peer_id, key, value)` (e.g. `CloseHelpTutorialStep`).

## Cross-scene wiring

Steps live in the level scene; managers (input, menu, help) live in `main_game.tscn`. NodePath `@export`s can't bridge the two, so steps that need managers cast `_gamemode` to `TutorialGameMode` and pull from there. The gamemode keeps the manager `@export`s.

## Reuse across gamemodes

Same base contract; the **gamemode** decides traversal:
- Tutorial: linear, advance per peer when `check()` returns true.
- Race (future): loop the checkpoint sequence N times, finish line ends the run.
- Trick combo (future): any-order completion, score-based end.

Mechanic detection (wheelie, stoppie, speed gates) lives in the step itself for now. Once a second consumer appears (e.g. a race gate that needs the same wheelie detection), pull it into a static helper in `utils/` or `gameplay/detectors/`. Don't preemptively extract.

## Where things live

- Base + all objective subclasses: `managers/gamemodes/gamemode_objectives/`
- Course root / world trigger: `managers/gamemodes/components/event_start_circle.gd`
- Event metadata resource: `resources/events/gamemode_event.gd`
- Tutorial gamemode (state machine, traversal, results): `managers/gamemodes/tutorial/tutorial_gamemode.gd`

## What this bought us

- `tutorial_gamemode.gd` no longer special-cases `CloseHelpObjective` — help-menu RPCs and exports live entirely on `CloseHelpTutorialStep`.
- Adding a new step = one `.gd` file + drop-in node. No registration, no enum, no special case.
- Mode-agnostic objectives (countdown, teleport) drop straight into future race / trick courses unchanged.
